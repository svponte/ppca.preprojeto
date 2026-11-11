-- =====================================================================
-- 05_aiops.sql — Operação orientada a eventos e autonomia graduada
-- Base ragdb. Executar após 01–03. Docs: 13 (eventos/autonomia), 14 (logs).
-- ADR-013 (fila), ADR-014 (autonomia + executor), ADR-015 (verificação/auditoria).
-- Senhas NÃO ficam aqui: credenciais dinâmicas do Vault
-- (aiops_orchestrator.vault, aiops_executor.vault, aiops_logproc.vault).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Papéis-grupo (NOLOGIN); usuários LOGIN criados pelo Vault (TTL curto)
-- ---------------------------------------------------------------------
CREATE ROLE aiops_orchestrator NOLOGIN;   -- event-orchestrator
CREATE ROLE aiops_executor     NOLOGIN;   -- action-executor (só resultado da execução)
CREATE ROLE aiops_logproc      NOLOGIN;   -- log-processor (só publica eventos)

-- ---------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------
CREATE TYPE ops.event_status AS ENUM ('NOVO', 'EM_PROCESSAMENTO', 'TRIADO', 'TRATADO', 'DESCARTADO', 'ERRO');
CREATE TYPE ops.event_source AS ENUM ('zabbix', 'log', 'assistente', 'manual');
CREATE TYPE ops.run_status   AS ENUM (
    'INFORMADO',             -- nível 0 (ou nível 3 / negado): só notificação
    'AGUARDANDO_APROVACAO',  -- nível 2
    'APROVADO', 'NEGADO', 'EXPIRADO',
    'EXECUTANDO', 'SUCESSO', 'FALHA_EXECUCAO', 'FALHA_VERIFICACAO',
    'BLOQUEADO'              -- disjuntor aberto, kill switch ou limite atingido
);

-- ---------------------------------------------------------------------
-- Fila de eventos (consumida com FOR UPDATE SKIP LOCKED)
-- ---------------------------------------------------------------------
CREATE TABLE ops.event_queue (
    event_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source        ops.event_source NOT NULL,
    external_ref  text,                                  -- id do evento no Zabbix, fingerprint do log...
    server_id     bigint REFERENCES catalog.server,
    environment   catalog.environment NOT NULL,
    kind          text NOT NULL,                         -- trigger | padrao_log_novo | taxa_anomala | solicitacao
    title         text NOT NULL,
    payload       jsonb NOT NULL DEFAULT '{}'::jsonb,    -- já mascarado na origem (doc 14)
    dedup_key     text NOT NULL,                         -- ex.: PG-HML01:idle_in_tx
    status        ops.event_status NOT NULL DEFAULT 'NOVO',
    attempts      smallint NOT NULL DEFAULT 0,
    triage        jsonb,                                 -- saída validada do modelo (categoria, severidade, resumo, confianca)
    triage_model  text,                                  -- modelo + digest
    incident_id   bigint REFERENCES ops.incident,
    received_at   timestamptz NOT NULL DEFAULT now(),
    locked_at     timestamptz,
    processed_at  timestamptz,
    classification kb.classification NOT NULL DEFAULT 'CONFIDENCIAL',
    CONSTRAINT triage_categoria CHECK (triage IS NULL OR triage ? 'categoria')
);
-- No máximo um evento "aberto" por dedup_key: repetições incrementam o existente
CREATE UNIQUE INDEX event_queue_dedup_open ON ops.event_queue (dedup_key)
    WHERE status IN ('NOVO', 'EM_PROCESSAMENTO', 'TRIADO');
CREATE INDEX event_queue_pending ON ops.event_queue (received_at) WHERE status = 'NOVO';

-- Publicação com deduplicação: devolve o event_id (novo ou existente)
CREATE OR REPLACE FUNCTION ops.publish_event(
    p_source ops.event_source, p_environment catalog.environment, p_kind text,
    p_title text, p_dedup_key text, p_payload jsonb DEFAULT '{}'::jsonb,
    p_server_id bigint DEFAULT NULL, p_external_ref text DEFAULT NULL)
RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, ops AS
$$
    INSERT INTO ops.event_queue (source, environment, kind, title, dedup_key, payload, server_id, external_ref)
    VALUES (p_source, p_environment, p_kind, p_title, p_dedup_key, p_payload, p_server_id, p_external_ref)
    ON CONFLICT (dedup_key) WHERE status IN ('NOVO', 'EM_PROCESSAMENTO', 'TRIADO')
    DO UPDATE SET payload = ops.event_queue.payload
                         || jsonb_build_object('repeticoes',
                                coalesce((ops.event_queue.payload->>'repeticoes')::int, 1) + 1)
    RETURNING event_id;
$$;

-- Consumo concorrente: cada orquestrador pega um lote sem bloquear os outros
CREATE OR REPLACE FUNCTION ops.claim_events(p_limit int DEFAULT 10)
RETURNS SETOF ops.event_queue
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, ops AS
$$
    UPDATE ops.event_queue q
       SET status = 'EM_PROCESSAMENTO', locked_at = now(), attempts = q.attempts + 1
     WHERE q.event_id IN (
           SELECT event_id FROM ops.event_queue
            WHERE status = 'NOVO'
            ORDER BY received_at
            LIMIT p_limit
            FOR UPDATE SKIP LOCKED)
    RETURNING q.*;
$$;

-- ---------------------------------------------------------------------
-- Catálogo de ações automatizáveis (derivado do bloco `automacao` dos
-- runbooks no Git; sincronizado pelo ingestion-worker)
-- ---------------------------------------------------------------------
CREATE TABLE ops.action_catalog (
    action_id      text PRIMARY KEY,                     -- encerrar_idle_in_transaction
    runbook_path   text NOT NULL,                        -- runbooks/pg/idle-in-transaction.md
    commit_sha     char(40) NOT NULL,                    -- versão revisada que autoriza a execução
    engine         catalog.engine NOT NULL,
    categories     text[] NOT NULL,                      -- categorias de triagem atendidas
    levels         jsonb NOT NULL,                       -- {"DEV":1,"HML":1,"PROD":2}
    reversible     boolean NOT NULL,
    idempotent     boolean NOT NULL,
    script_path    text NOT NULL,
    params_schema  jsonb NOT NULL DEFAULT '{}'::jsonb,   -- JSON Schema dos parâmetros
    success_check  text NOT NULL,                        -- condição de sucesso (consulta RO)
    timeout_s      int NOT NULL CHECK (timeout_s BETWEEN 1 AND 600),
    max_per_hour   int NOT NULL CHECK (max_per_hour BETWEEN 1 AND 20),
    credential_ref text NOT NULL DEFAULT 'aiops_executor.vault',
    enabled        boolean NOT NULL DEFAULT false,       -- liga só após revisão por DBA sênior
    reviewed_by    text,
    updated_at     timestamptz NOT NULL DEFAULT now(),
    -- ADR-014: nível 3 nunca entra no catálogo; só níveis 0–2 e só ambientes conhecidos
    CONSTRAINT levels_validos CHECK (
        jsonb_typeof(levels) = 'object'
        AND NOT jsonb_path_exists(levels, '$.* ? (@ < 0 || @ > 2)')
        AND (levels - 'DEV' - 'HML' - 'PROD') = '{}'::jsonb),
    -- ação irreversível nunca é automática (nível 1) em nenhum ambiente
    CONSTRAINT irreversivel_exige_aprovacao CHECK (
        reversible OR NOT jsonb_path_exists(levels, '$.* ? (@ == 1)')),
    CONSTRAINT habilitada_exige_revisor CHECK (NOT enabled OR reviewed_by IS NOT NULL),
    CONSTRAINT credencial_vault CHECK (credential_ref ~ '^[a-z0-9_]+\.vault$')
);

-- ---------------------------------------------------------------------
-- Execuções / decisões (uma linha por decisão, inclusive nível 0)
-- ---------------------------------------------------------------------
CREATE TABLE ops.action_run (
    run_id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trace_id         uuid NOT NULL,                      -- correlação com audit.event
    event_id         bigint NOT NULL REFERENCES ops.event_queue,
    action_id        text REFERENCES ops.action_catalog,  -- NULL = só informar
    action_commit    char(40),                            -- commit do catálogo no momento da decisão
    server_id        bigint REFERENCES catalog.server,
    environment      catalog.environment NOT NULL,
    autonomy_level   smallint NOT NULL CHECK (autonomy_level BETWEEN 0 AND 3),
    policy_version   text NOT NULL,                       -- revisão do bundle OPA
    policy_decision  jsonb NOT NULL,                      -- {"allow":..., "mode":..., "reasons":[...]}
    context_hash     bytea,                               -- hash do contexto enviado ao modelo
    params           jsonb NOT NULL DEFAULT '{}'::jsonb,  -- parâmetros validados
    dry_run          boolean NOT NULL DEFAULT false,
    status           ops.run_status NOT NULL,
    requested_by     text,                                -- sub do analista (solicitações via assistente)
    approved_by      text,
    approved_at      timestamptz,
    started_at       timestamptz,
    finished_at      timestamptz,
    result           jsonb,                               -- saída resumida e mascarada
    verified         boolean,                             -- condição de sucesso confirmada?
    created_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT nivel0_sem_acao   CHECK (autonomy_level > 0 OR action_id IS NULL),
    CONSTRAINT nivel3_nunca_exec CHECK (autonomy_level < 3 OR status IN ('INFORMADO', 'BLOQUEADO')),
    CONSTRAINT acao_tem_commit   CHECK (action_id IS NULL OR action_commit IS NOT NULL),
    CONSTRAINT nivel2_aprovado   CHECK (
        autonomy_level <> 2
        OR status IN ('AGUARDANDO_APROVACAO', 'NEGADO', 'EXPIRADO', 'BLOQUEADO', 'INFORMADO')
        OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
    CONSTRAINT sucesso_verificado CHECK (status <> 'SUCESSO' OR verified IS TRUE)
);
CREATE INDEX action_run_rate ON ops.action_run (action_id, server_id, started_at DESC);
CREATE INDEX action_run_event ON ops.action_run (event_id);

-- Execuções finalizadas são imutáveis (base da auditoria e da avaliação de H5)
CREATE OR REPLACE FUNCTION ops.action_run_final_immutable() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
    IF OLD.status IN ('SUCESSO', 'FALHA_EXECUCAO', 'FALHA_VERIFICACAO', 'NEGADO',
                      'EXPIRADO', 'INFORMADO', 'BLOQUEADO') THEN
        RAISE EXCEPTION 'action_run % já finalizada (status %)', OLD.run_id, OLD.status;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER action_run_immutable BEFORE UPDATE ON ops.action_run
    FOR EACH ROW EXECUTE FUNCTION ops.action_run_final_immutable();

CREATE OR REPLACE FUNCTION ops.action_run_no_delete() RETURNS trigger
LANGUAGE plpgsql AS
$$ BEGIN RAISE EXCEPTION 'ops.action_run é append-only'; END; $$;
CREATE TRIGGER action_run_no_delete BEFORE DELETE ON ops.action_run
    FOR EACH ROW EXECUTE FUNCTION ops.action_run_no_delete();

-- Disjuntor: execuções da mesma ação no mesmo servidor na última hora
CREATE OR REPLACE FUNCTION ops.recent_runs(p_action_id text, p_server_id bigint)
RETURNS int LANGUAGE sql STABLE AS
$$
    SELECT count(*)::int FROM ops.action_run
     WHERE action_id = p_action_id AND server_id = p_server_id
       AND started_at > now() - interval '1 hour'
       AND status IN ('EXECUTANDO', 'SUCESSO', 'FALHA_EXECUCAO', 'FALHA_VERIFICACAO');
$$;

-- ---------------------------------------------------------------------
-- Privilégios (menor privilégio por serviço)
-- ---------------------------------------------------------------------
ALTER TABLE ops.event_queue    OWNER TO rag_owner;
ALTER TABLE ops.action_catalog OWNER TO rag_owner;
ALTER TABLE ops.action_run     OWNER TO rag_owner;
ALTER FUNCTION ops.publish_event(ops.event_source, catalog.environment, text, text, text, jsonb, bigint, text) OWNER TO rag_owner;
ALTER FUNCTION ops.claim_events(int) OWNER TO rag_owner;

GRANT USAGE ON SCHEMA ops, catalog TO aiops_orchestrator, aiops_executor;
GRANT USAGE ON SCHEMA ops          TO aiops_logproc;
GRANT USAGE ON TYPE catalog.environment, ops.event_source TO aiops_logproc, rag_agent;

REVOKE ALL ON FUNCTION ops.publish_event(ops.event_source, catalog.environment, text, text, text, jsonb, bigint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION ops.claim_events(int) FROM PUBLIC;

-- log-processor e assistente (solicitações de nível 2): só publicam eventos
GRANT EXECUTE ON FUNCTION ops.publish_event(ops.event_source, catalog.environment, text, text, text, jsonb, bigint, text)
    TO aiops_logproc, aiops_orchestrator, rag_agent;

-- orquestrador: consome fila, lê catálogo, registra decisões e aprovações
GRANT EXECUTE ON FUNCTION ops.claim_events(int), ops.recent_runs(text, bigint) TO aiops_orchestrator;
GRANT SELECT ON ops.event_queue, ops.action_catalog, ops.incident TO aiops_orchestrator;
GRANT UPDATE (status, triage, triage_model, incident_id, processed_at) ON ops.event_queue TO aiops_orchestrator;
GRANT SELECT, INSERT ON ops.action_run TO aiops_orchestrator;
GRANT UPDATE (status, approved_by, approved_at) ON ops.action_run TO aiops_orchestrator;
GRANT SELECT ON catalog.server_v TO aiops_orchestrator;

-- executor: lê o que vai executar e grava SOMENTE o resultado
GRANT SELECT ON ops.action_catalog TO aiops_executor;
GRANT SELECT ON ops.action_run     TO aiops_executor;
GRANT EXECUTE ON FUNCTION ops.recent_runs(text, bigint) TO aiops_executor;
GRANT UPDATE (status, started_at, finished_at, result, verified) ON ops.action_run TO aiops_executor;

-- ingestion-worker sincroniza o catálogo a partir do Git (enabled/reviewed_by também vêm do MR revisado)
GRANT SELECT, INSERT, UPDATE ON ops.action_catalog TO rag_ingestion;
GRANT USAGE ON SCHEMA ops TO rag_ingestion;

-- assistente: consulta catálogo e histórico (para explicar e abrir solicitações)
GRANT SELECT ON ops.action_catalog, ops.action_run, ops.event_queue TO rag_agent;
