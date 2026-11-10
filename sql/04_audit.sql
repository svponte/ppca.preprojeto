-- =====================================================================
-- 04_audit.sql — Banco de Auditoria (base auditdb, separada de ragdb)
-- Requisitos: imutável (append-only), encadeado por hash (detecção de
-- adulteração), retenção conforme política LGPD, envio ao Wazuh.
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS audit;

CREATE ROLE audit_owner  NOLOGIN;
CREATE ROLE audit_writer NOLOGIN;   -- serviços: apenas INSERT
CREATE ROLE audit_reader NOLOGIN;   -- equipe de segurança / auditor: apenas SELECT

CREATE TABLE audit.event (
    event_id     bigint GENERATED ALWAYS AS IDENTITY,
    occurred_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
    trace_id     uuid        NOT NULL,
    service      text        NOT NULL,     -- api-gateway, agent, tools, ext-search, ingestion...
    actor_sub    text        NOT NULL,     -- usuário (sub OIDC) ou conta de serviço
    actor_ip     inet,
    action       text        NOT NULL,     -- query.ask, retrieval.search, tool.sql, ext.search.request,
                                           -- ext.search.approve, dlp.block, authz.deny, kb.ingest ...
    resource     text,                     -- servidor, documento, ferramenta
    decision     text        NOT NULL CHECK (decision IN ('ALLOW','DENY','MASKED','BLOCKED','INFO')),
    policy_id    text,                     -- regra OPA/DLP que decidiu
    details      jsonb       NOT NULL DEFAULT '{}'::jsonb,  -- NUNCA conteúdo sensível em claro
    prev_hash    bytea,
    row_hash     bytea       NOT NULL,
    PRIMARY KEY (event_id, occurred_at)
) PARTITION BY RANGE (occurred_at);

-- Partições mensais (criar via pg_partman ou job agendado)
CREATE TABLE audit.event_2026_11 PARTITION OF audit.event
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE audit.event_2026_12 PARTITION OF audit.event
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE INDEX ON audit.event (trace_id);
CREATE INDEX ON audit.event (actor_sub, occurred_at DESC);
CREATE INDEX ON audit.event (action, decision, occurred_at DESC);

-- Encadeamento por hash: row_hash = sha256(prev_hash || campos canônicos)
-- SECURITY DEFINER: audit_writer só tem INSERT; a leitura do último hash
-- é feita com os privilégios do owner da função.
CREATE OR REPLACE FUNCTION audit.chain_hash() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = audit, public AS $$
DECLARE
    v_prev bytea;
BEGIN
    -- serializa a cadeia (volume esperado de auditoria comporta o lock)
    PERFORM pg_advisory_xact_lock(hashtext('audit.event.chain'));
    SELECT row_hash INTO v_prev
      FROM audit.event
     ORDER BY occurred_at DESC, event_id DESC
     LIMIT 1;
    NEW.prev_hash := v_prev;
    NEW.row_hash  := digest(
        coalesce(encode(v_prev, 'hex'), 'GENESIS') || '|' ||
        NEW.occurred_at::text || '|' || NEW.trace_id::text || '|' ||
        NEW.service || '|' || NEW.actor_sub || '|' || NEW.action || '|' ||
        coalesce(NEW.resource, '') || '|' || NEW.decision || '|' ||
        NEW.details::text,
        'sha256');
    RETURN NEW;
END $$;

CREATE TRIGGER event_chain BEFORE INSERT ON audit.event
    FOR EACH ROW EXECUTE FUNCTION audit.chain_hash();

-- Bloqueio de alteração/remoção mesmo para o owner (apenas superusuário
-- via procedimento formal de expurgo por retenção pode remover partições)
CREATE OR REPLACE FUNCTION audit.deny_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit.event é append-only (operação % negada)', TG_OP;
END $$;

CREATE TRIGGER event_no_update BEFORE UPDATE OR DELETE ON audit.event
    FOR EACH ROW EXECUTE FUNCTION audit.deny_mutation();

-- Registro específico de pesquisas externas (prova de anonimização)
CREATE TABLE audit.external_search (
    search_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    trace_id          uuid NOT NULL,
    requested_by      text NOT NULL,
    approved_by       text,                    -- o próprio usuário (ou supervisor, se política exigir)
    approved_at       timestamptz,
    original_sha256   bytea NOT NULL,          -- hash do texto original (o texto não é guardado aqui)
    anonymized_query  text NOT NULL,           -- exatamente o que saiu da organização
    entities_removed  jsonb NOT NULL,          -- {"HOSTNAME":2,"IP":1,"DB_USER":1}
    dlp_score         real NOT NULL,           -- risco residual (0..1) estimado pelo verificador
    providers         text[] NOT NULL,         -- ['postgresql.org','learn.microsoft.com']
    status            text NOT NULL CHECK (status IN ('PENDENTE','APROVADA','NEGADA','BLOQUEADA_DLP','EXECUTADA')),
    created_at        timestamptz NOT NULL DEFAULT now()
);

-- Verificação de integridade da cadeia (auditor executa periodicamente)
CREATE OR REPLACE FUNCTION audit.verify_chain(p_from timestamptz, p_to timestamptz)
RETURNS TABLE (event_id bigint, ok boolean)
LANGUAGE sql STABLE AS $$
    SELECT e.event_id,
           e.prev_hash IS NOT DISTINCT FROM lag(e.row_hash) OVER w AS ok
    FROM audit.event e
    WHERE e.occurred_at BETWEEN p_from AND p_to
    WINDOW w AS (ORDER BY e.occurred_at, e.event_id);
$$;

REVOKE ALL ON SCHEMA audit FROM PUBLIC;
GRANT USAGE  ON SCHEMA audit TO audit_writer, audit_reader;
GRANT INSERT ON audit.event, audit.external_search TO audit_writer;
GRANT UPDATE (approved_by, approved_at, status) ON audit.external_search TO audit_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO audit_reader;
GRANT EXECUTE ON FUNCTION audit.verify_chain TO audit_reader;
