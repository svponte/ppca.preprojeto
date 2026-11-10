-- =====================================================================
-- 03_rls_roles.sql — Papéis e Row-Level Security (base ragdb)
-- Princípio: autorização aplicada no DADO. Falha fechada (fail-closed):
-- sem variáveis de sessão, nenhuma linha classificada é retornada.
-- Senhas NÃO ficam aqui: credenciais emitidas dinamicamente pelo Vault
-- (database secrets engine). Referência: rag_retrieval.vault etc.
-- =====================================================================

-- Papéis-grupo (NOLOGIN). Os usuários LOGIN são criados pelo Vault com
-- validade curta (TTL) e herdam destes papéis.
CREATE ROLE rag_owner      NOLOGIN;                -- dono dos objetos (migrações)
CREATE ROLE rag_retrieval  NOLOGIN;                -- retrieval-service (somente leitura, sujeito a RLS)
CREATE ROLE rag_ingestion  NOLOGIN;                -- ingestion-worker (escrita em kb/catalog)
CREATE ROLE rag_agent      NOLOGIN;                -- agent-service (conv/ops)
CREATE ROLE rag_anonymizer NOLOGIN;                -- ext-search-gateway (lê sec.sensitive_entity)
CREATE ROLE rag_kwriter    NOLOGIN;                -- knowledge-writer (ops.runbook_proposal)

-- Nenhum papel de aplicação tem BYPASSRLS.
ALTER SCHEMA catalog OWNER TO rag_owner;
ALTER SCHEMA kb      OWNER TO rag_owner;
ALTER SCHEMA ops     OWNER TO rag_owner;
ALTER SCHEMA conv    OWNER TO rag_owner;
ALTER SCHEMA sec     OWNER TO rag_owner;

REVOKE ALL ON SCHEMA catalog, kb, ops, conv, sec FROM PUBLIC;

GRANT USAGE ON SCHEMA kb, catalog TO rag_retrieval, rag_ingestion, rag_agent;
GRANT USAGE ON SCHEMA ops, conv   TO rag_agent, rag_kwriter;
GRANT USAGE ON SCHEMA sec         TO rag_anonymizer, rag_ingestion;

GRANT SELECT ON ALL TABLES IN SCHEMA kb      TO rag_retrieval;
GRANT SELECT ON ALL TABLES IN SCHEMA catalog TO rag_retrieval, rag_agent;
GRANT EXECUTE ON FUNCTION kb.hybrid_search   TO rag_retrieval;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA kb, catalog TO rag_ingestion;
GRANT SELECT, INSERT          ON sec.sensitive_entity           TO rag_ingestion;
GRANT SELECT                  ON sec.sensitive_entity           TO rag_anonymizer;

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA conv, ops TO rag_agent;
GRANT SELECT, INSERT, UPDATE ON ops.runbook_proposal, ops.incident TO rag_kwriter;
GRANT SELECT ON ops.incident_event TO rag_kwriter;

-- ---------------------------------------------------------------------
-- Contexto de segurança da sessão
-- O retrieval-service executa, no início de CADA transação:
--   SET LOCAL app.user_sub     = '<sub do JWT>';
--   SET LOCAL app.clearance    = 'CONFIDENCIAL';
--   SET LOCAL app.groups       = 'dba-pg,dba-senior';
--   SET LOCAL app.environments = 'PROD,HML,DEV';
-- Valores derivados do JWT validado + decisão do OPA (nunca da pergunta).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION kb.session_clearance() RETURNS kb.classification
LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('app.clearance', true), '')::kb.classification $$;

CREATE OR REPLACE FUNCTION kb.session_groups() RETURNS text[]
LANGUAGE sql STABLE AS
$$ SELECT string_to_array(nullif(current_setting('app.groups', true), ''), ',') $$;

CREATE OR REPLACE FUNCTION kb.session_environments() RETURNS catalog.environment[]
LANGUAGE sql STABLE AS
$$ SELECT string_to_array(nullif(current_setting('app.environments', true), ''), ',')::catalog.environment[] $$;

GRANT EXECUTE ON FUNCTION kb.session_clearance(), kb.session_groups(), kb.session_environments()
      TO rag_retrieval, rag_agent;

-- ---------------------------------------------------------------------
-- Políticas RLS
-- ---------------------------------------------------------------------
ALTER TABLE kb.chunk    ENABLE ROW LEVEL SECURITY;
ALTER TABLE kb.document ENABLE ROW LEVEL SECURITY;
ALTER TABLE kb.chunk    FORCE ROW LEVEL SECURITY;
ALTER TABLE kb.document FORCE ROW LEVEL SECURITY;

-- Leitura: classificação <= clearance  E  ambiente permitido  E  grupo permitido
CREATE POLICY chunk_read ON kb.chunk
    FOR SELECT TO rag_retrieval, rag_agent
    USING (
        classification <= kb.session_clearance()
        AND (cardinality(environments)  = 0 OR environments  && kb.session_environments())
        AND (cardinality(allowed_groups) = 0 OR allowed_groups && kb.session_groups())
    );

CREATE POLICY document_read ON kb.document
    FOR SELECT TO rag_retrieval, rag_agent
    USING (
        classification <= kb.session_clearance()
        AND (cardinality(environments)  = 0 OR environments  && kb.session_environments())
        AND (cardinality(allowed_groups) = 0 OR allowed_groups && kb.session_groups())
    );

-- Ingestão escreve tudo (não lê por RLS de usuário)
CREATE POLICY chunk_ingest    ON kb.chunk    FOR ALL TO rag_ingestion USING (true) WITH CHECK (true);
CREATE POLICY document_ingest ON kb.document FOR ALL TO rag_ingestion USING (true) WITH CHECK (true);

-- Conversas: cada usuário só vê as próprias (o agent-service define app.user_sub)
ALTER TABLE conv.conversation ENABLE ROW LEVEL SECURITY;
ALTER TABLE conv.conversation FORCE ROW LEVEL SECURITY;
CREATE POLICY conversation_owner ON conv.conversation
    FOR ALL TO rag_agent
    USING (user_sub = current_setting('app.user_sub', true))
    WITH CHECK (user_sub = current_setting('app.user_sub', true));

-- ---------------------------------------------------------------------
-- Visão de inventário com mascaramento de IP (ABAC por clearance)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW catalog.server_v
WITH (security_barrier = true) AS
SELECT server_id, hostname, engine, engine_version, environment, os, ha_role,
       uses_pgbouncer, owner_team, tags,
       CASE WHEN kb.session_clearance() >= 'RESTRITO' THEN host(ip_address)
            ELSE '***.***.***.***' END AS ip_address
FROM catalog.server
WHERE classification <= kb.session_clearance()
  AND (environment = ANY (kb.session_environments()));

REVOKE SELECT ON catalog.server FROM rag_retrieval, rag_agent;
GRANT  SELECT ON catalog.server_v TO rag_retrieval, rag_agent;
