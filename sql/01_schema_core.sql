-- =====================================================================
-- 01_schema_core.sql — Modelo de dados principal (base ragdb)
-- PostgreSQL 16 + pgvector >= 0.7
-- Executar como superusuário/owner na criação. Senhas: <usuario>.vault
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE SCHEMA IF NOT EXISTS catalog;   -- inventário de servidores e sistemas
CREATE SCHEMA IF NOT EXISTS kb;        -- documentos e chunks (conhecimento)
CREATE SCHEMA IF NOT EXISTS ops;       -- incidentes e runbooks
CREATE SCHEMA IF NOT EXISTS conv;      -- conversas e rastreabilidade de respostas
CREATE SCHEMA IF NOT EXISTS sec;       -- dicionário de entidades sensíveis (anonimização)

-- ---------------------------------------------------------------------
-- Tipos de domínio
-- ---------------------------------------------------------------------
CREATE TYPE catalog.environment AS ENUM ('PROD', 'HML', 'DEV');
CREATE TYPE catalog.engine      AS ENUM ('POSTGRESQL', 'SQLSERVER', 'MYSQL', 'OUTRO');

-- Classificação da informação (ordem importa: comparação por nível)
CREATE TYPE kb.classification AS ENUM ('PUBLICO', 'INTERNO', 'CONFIDENCIAL', 'RESTRITO');

CREATE TYPE kb.doc_type AS ENUM (
    'CONFIGURACAO_SERVIDOR', 'PARAMETROS', 'TOPOLOGIA', 'POLITICA',
    'PROCEDIMENTO', 'RUNBOOK', 'SCRIPT_SQL', 'INCIDENTE', 'ARQUITETURA',
    'BACKUP', 'MONITORAMENTO', 'TROUBLESHOOTING', 'SEGURANCA', 'OUTRO'
);

-- ---------------------------------------------------------------------
-- CATALOG — inventário (alimentado pelo front-matter dos .md de servidor
-- e, opcionalmente, por coleta automática via tool-service)
-- ---------------------------------------------------------------------
CREATE TABLE catalog.server (
    server_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hostname         text NOT NULL UNIQUE,              -- ex.: PG-PROD02 (sensível p/ pesquisa externa)
    engine           catalog.engine NOT NULL,
    engine_version   text,                              -- ex.: '16.4', '2022 CU14'
    environment      catalog.environment NOT NULL,
    os               text,
    ip_address       inet,                              -- RESTRITO: mascarado fora do perfil adequado
    ha_role          text,                              -- primary / standby / AG primary / AG secondary
    uses_pgbouncer   boolean NOT NULL DEFAULT false,
    owner_team       text NOT NULL DEFAULT 'DBA',
    classification   kb.classification NOT NULL DEFAULT 'CONFIDENCIAL',
    tags             text[] NOT NULL DEFAULT '{}',
    attributes       jsonb  NOT NULL DEFAULT '{}'::jsonb, -- atributos livres do front-matter
    source_commit    text,                              -- commit Git que originou o registro
    updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON catalog.server (environment, engine);
CREATE INDEX ON catalog.server USING gin (tags);

-- Parâmetros relevantes (shared_buffers, max_connections, MAXDOP, ...)
CREATE TABLE catalog.server_parameter (
    server_id      bigint NOT NULL REFERENCES catalog.server ON DELETE CASCADE,
    name           text   NOT NULL,
    value          text   NOT NULL,
    unit           text,
    source         text   NOT NULL DEFAULT 'documentacao', -- documentacao | coleta_automatica
    collected_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (server_id, name)
);

CREATE TABLE catalog.application (
    application_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           text NOT NULL UNIQUE,
    business_owner text,
    criticality    smallint CHECK (criticality BETWEEN 1 AND 5),
    classification kb.classification NOT NULL DEFAULT 'INTERNO'
);

CREATE TABLE catalog.application_database (
    application_id bigint NOT NULL REFERENCES catalog.application ON DELETE CASCADE,
    server_id      bigint NOT NULL REFERENCES catalog.server ON DELETE CASCADE,
    database_name  text   NOT NULL,
    PRIMARY KEY (application_id, server_id, database_name)
);

-- ---------------------------------------------------------------------
-- KB — documentos versionados (1 linha por arquivo x commit)
-- ---------------------------------------------------------------------
CREATE TABLE kb.document (
    document_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    repo            text   NOT NULL,                    -- ex.: dba/conhecimento
    path            text   NOT NULL,                    -- ex.: servidores/PG-PROD02.md
    commit_sha      char(40) NOT NULL,
    content_hash    char(64) NOT NULL,                  -- sha256 do conteúdo bruto
    title           text   NOT NULL,
    doc_type        kb.doc_type NOT NULL,
    classification  kb.classification NOT NULL,
    classification_source text NOT NULL DEFAULT 'front_matter', -- front_matter | classificador | revisao_humana
    environments    catalog.environment[] NOT NULL DEFAULT '{}', -- vazio = todos/genérico
    server_ids      bigint[] NOT NULL DEFAULT '{}',
    allowed_groups  text[]  NOT NULL DEFAULT '{}',      -- vazio = qualquer grupo com clearance
    owner           text,
    front_matter    jsonb  NOT NULL DEFAULT '{}'::jsonb,
    valid_from      timestamptz NOT NULL DEFAULT now(),
    superseded_at   timestamptz,                        -- NULL = versão vigente
    UNIQUE (repo, path, commit_sha)
);
-- Apenas uma versão vigente por arquivo
CREATE UNIQUE INDEX document_current_uq ON kb.document (repo, path) WHERE superseded_at IS NULL;
CREATE INDEX ON kb.document (doc_type) WHERE superseded_at IS NULL;

-- Chunk: unidade de recuperação. Herda (e pode restringir) a classificação do documento.
-- Definição completa da coluna de embedding e índices em 02_vector.sql
CREATE TABLE kb.chunk (
    chunk_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    document_id     bigint NOT NULL REFERENCES kb.document ON DELETE CASCADE,
    ordinal         int    NOT NULL,
    heading_path    text   NOT NULL,                    -- "PG-PROD02 > Backup > Restauração PITR"
    chunk_kind      text   NOT NULL DEFAULT 'texto',    -- texto | codigo_sql | codigo_bash | tabela
    content         text   NOT NULL,                    -- conteúdo já mascarado no nível da classificação
    content_tsv     tsvector GENERATED ALWAYS AS
                        (to_tsvector('portuguese', coalesce(heading_path,'') || ' ' || content)) STORED,
    token_count     int    NOT NULL,
    -- atributos de segurança desnormalizados (RLS sem JOIN = rápido)
    classification  kb.classification NOT NULL,
    environments    catalog.environment[] NOT NULL DEFAULT '{}',
    server_ids      bigint[] NOT NULL DEFAULT '{}',
    allowed_groups  text[]  NOT NULL DEFAULT '{}',
    is_current      boolean NOT NULL DEFAULT true,
    metadata        jsonb   NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (document_id, ordinal)
);
CREATE INDEX chunk_tsv_gin   ON kb.chunk USING gin (content_tsv);
CREATE INDEX chunk_srv_gin   ON kb.chunk USING gin (server_ids);
CREATE INDEX chunk_meta_gin  ON kb.chunk USING gin (metadata jsonb_path_ops);

-- ---------------------------------------------------------------------
-- OPS — incidentes e ciclo de aprendizado
-- ---------------------------------------------------------------------
CREATE TYPE ops.incident_status AS ENUM ('ABERTO', 'INVESTIGANDO', 'RESOLVIDO', 'RUNBOOK_GERADO', 'RUNBOOK_PUBLICADO', 'FECHADO');

CREATE TABLE ops.incident (
    incident_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    external_ref    text UNIQUE,                        -- nº do chamado (GLPI/ServiceNow/Zabbix event)
    title           text NOT NULL,
    server_id       bigint REFERENCES catalog.server,
    severity        smallint NOT NULL CHECK (severity BETWEEN 1 AND 5),
    category        text,                               -- desempenho, disponibilidade, bloqueio, backup...
    symptoms        text,
    root_cause      text,
    resolution      text,
    status          ops.incident_status NOT NULL DEFAULT 'ABERTO',
    opened_at       timestamptz NOT NULL DEFAULT now(),
    resolved_at     timestamptz,
    assisted_by_ai  boolean NOT NULL DEFAULT false,     -- para medir efeito no MTTR
    conversation_id bigint,                             -- conversa usada na investigação
    classification  kb.classification NOT NULL DEFAULT 'CONFIDENCIAL'
);
CREATE INDEX ON ops.incident (server_id, opened_at DESC);

CREATE TABLE ops.incident_event (
    event_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    incident_id  bigint NOT NULL REFERENCES ops.incident ON DELETE CASCADE,
    at           timestamptz NOT NULL DEFAULT now(),
    actor        text NOT NULL,                         -- usuário ou 'agent'
    kind         text NOT NULL,                         -- hipotese | evidencia | acao | nota
    description  text NOT NULL,
    evidence     jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE ops.runbook_proposal (
    proposal_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    incident_id     bigint NOT NULL REFERENCES ops.incident,
    draft_path      text NOT NULL,                      -- runbooks/deadlock-fk-sem-indice.md
    merge_request   text,                               -- URL do MR no Gitea
    llm_model       text NOT NULL,
    status          text NOT NULL DEFAULT 'RASCUNHO'
                    CHECK (status IN ('RASCUNHO','EM_REVISAO','APROVADO','REJEITADO','PUBLICADO')),
    reviewer        text,
    similar_to      bigint[] NOT NULL DEFAULT '{}',     -- document_ids de runbooks semelhantes (deduplicação)
    created_at      timestamptz NOT NULL DEFAULT now(),
    reviewed_at     timestamptz
);

-- ---------------------------------------------------------------------
-- CONV — conversas e rastreabilidade (reprodutibilidade das respostas)
-- ---------------------------------------------------------------------
CREATE TABLE conv.conversation (
    conversation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_sub        text NOT NULL,                      -- subject do token OIDC
    channel         text NOT NULL CHECK (channel IN ('web','mcp','cli')),
    started_at      timestamptz NOT NULL DEFAULT now(),
    incident_id     bigint REFERENCES ops.incident
);

CREATE TABLE conv.message (
    message_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversation_id bigint NOT NULL REFERENCES conv.conversation ON DELETE CASCADE,
    trace_id        uuid   NOT NULL,                    -- correlação com auditoria/Langfuse
    role            text   NOT NULL CHECK (role IN ('user','assistant')),
    content         text   NOT NULL,                    -- pergunta original / resposta final (pós-DLP)
    intent          text,
    llm_model       text,
    prompt_tokens   int,
    completion_tokens int,
    latency_ms      int,
    groundedness    real,                               -- escore de fidelidade (0..1)
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON conv.message (trace_id);

-- Quais chunks (em qual versão) sustentaram a resposta
CREATE TABLE conv.retrieval_trace (
    message_id   bigint NOT NULL REFERENCES conv.message ON DELETE CASCADE,
    chunk_id     bigint NOT NULL REFERENCES kb.chunk,
    rank         int    NOT NULL,
    vector_score real,
    lexical_score real,
    rerank_score real,
    cited        boolean NOT NULL DEFAULT false,
    PRIMARY KEY (message_id, chunk_id)
);

CREATE TABLE conv.tool_call (
    tool_call_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message_id   bigint NOT NULL REFERENCES conv.message ON DELETE CASCADE,
    tool_name    text NOT NULL,                         -- sql_readonly, prometheus_query, log_search, web_search
    target       text,                                  -- servidor/fonte
    arguments    jsonb NOT NULL,
    opa_decision boolean NOT NULL,
    result_summary text,
    duration_ms  int,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE conv.feedback (
    message_id  bigint PRIMARY KEY REFERENCES conv.message ON DELETE CASCADE,
    rating      smallint NOT NULL CHECK (rating IN (-1, 1)),
    reason      text,                                   -- incorreta | incompleta | desatualizada | util
    comment     text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- SEC — dicionário de entidades sensíveis (anonimização determinística)
-- Alimentado automaticamente a partir de catalog.server e do AD.
-- ---------------------------------------------------------------------
CREATE TABLE sec.sensitive_entity (
    entity_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind         text NOT NULL CHECK (kind IN ('HOSTNAME','IP','CIDR','DB_NAME','DB_USER','AD_USER',
                                               'APP_NAME','DOMAIN','PATH','PESSOA','OUTRO')),
    value        text NOT NULL,
    pseudonym    text NOT NULL,                         -- token estável: <HOST_7>, <DB_3>
    source       text NOT NULL,                         -- catalog | ad | manual | ner
    UNIQUE (kind, value)
);
