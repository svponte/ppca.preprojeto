-- =====================================================================
-- 02_vector.sql — Modelo do banco vetorial (pgvector)
-- Modelo de embedding de referência: bge-m3 (1024 dimensões, multilíngue,
-- bom desempenho em português e em trechos técnicos/código).
-- Se trocar o modelo, criar NOVA coluna/tabela e reindexar (ver doc 04 §6).
-- =====================================================================

-- Embedding desacoplado do chunk: permite manter dois modelos em paralelo
-- durante migração e testar modelos no experimento (doc 10).
CREATE TABLE kb.embedding_model (
    model_id     smallint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         text NOT NULL UNIQUE,      -- 'bge-m3'
    dimensions   int  NOT NULL,
    distance     text NOT NULL DEFAULT 'cosine',
    digest       text NOT NULL,             -- hash do modelo no Ollama (reprodutibilidade)
    active       boolean NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE kb.chunk_embedding_bge_m3 (
    chunk_id     bigint PRIMARY KEY REFERENCES kb.chunk ON DELETE CASCADE,
    model_id     smallint NOT NULL REFERENCES kb.embedding_model,
    embedding    vector(1024) NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- HNSW: melhor relação recall/latência para consultas interativas;
-- não exige treinamento prévio (diferente do IVFFlat) — adequado a base
-- que cresce continuamente com novos runbooks.
CREATE INDEX chunk_emb_bge_m3_hnsw
    ON kb.chunk_embedding_bge_m3
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 128);

-- ---------------------------------------------------------------------
-- Busca híbrida com Reciprocal Rank Fusion (RRF)
-- SECURITY INVOKER: executa com o papel/variáveis da sessão do usuário,
-- portanto as políticas RLS de kb.chunk (04_rls.sql) são aplicadas
-- ANTES de qualquer resultado chegar ao serviço de recuperação.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION kb.hybrid_search(
    p_query_text      text,
    p_query_embedding vector(1024),
    p_k               int     DEFAULT 20,
    p_server_ids      bigint[] DEFAULT NULL,         -- filtro opcional por servidor
    p_doc_types       kb.doc_type[] DEFAULT NULL,    -- filtro opcional por tipo
    p_rrf_k           int     DEFAULT 60
)
RETURNS TABLE (
    chunk_id      bigint,
    document_id   bigint,
    heading_path  text,
    content       text,
    vector_rank   int,
    lexical_rank  int,
    rrf_score     double precision
)
LANGUAGE sql STABLE SECURITY INVOKER
AS $$
WITH
-- Os filtros ficam DENTRO de cada ramo para que o planejador use o índice
-- HNSW (ORDER BY distância + LIMIT) com pós-filtragem; RLS de kb.chunk
-- é aplicada automaticamente ao JOIN.
vec_raw AS (
    SELECT e.chunk_id, e.embedding <=> p_query_embedding AS dist
    FROM kb.chunk_embedding_bge_m3 e
    JOIN kb.chunk c    ON c.chunk_id = e.chunk_id
    JOIN kb.document d ON d.document_id = c.document_id
    WHERE c.is_current
      AND (p_server_ids IS NULL OR c.server_ids && p_server_ids)
      AND (p_doc_types  IS NULL OR d.doc_type = ANY (p_doc_types))
    ORDER BY e.embedding <=> p_query_embedding
    LIMIT p_k * 4
),
vec AS (
    SELECT chunk_id, row_number() OVER (ORDER BY dist) AS rnk FROM vec_raw
),
lex_raw AS (
    SELECT c.chunk_id, ts_rank_cd(c.content_tsv, q) AS score
    FROM kb.chunk c
    JOIN kb.document d ON d.document_id = c.document_id,
         websearch_to_tsquery('portuguese', p_query_text) q
    WHERE c.is_current
      AND c.content_tsv @@ q
      AND (p_server_ids IS NULL OR c.server_ids && p_server_ids)
      AND (p_doc_types  IS NULL OR d.doc_type = ANY (p_doc_types))
    ORDER BY score DESC
    LIMIT p_k * 4
),
lex AS (
    SELECT chunk_id, row_number() OVER (ORDER BY score DESC) AS rnk FROM lex_raw
),
fused AS (
    SELECT coalesce(v.chunk_id, l.chunk_id) AS chunk_id,
           v.rnk::int AS vector_rank,
           l.rnk::int AS lexical_rank,
           coalesce(1.0 / (p_rrf_k + v.rnk), 0) + coalesce(1.0 / (p_rrf_k + l.rnk), 0) AS rrf_score
    FROM vec v
    FULL OUTER JOIN lex l USING (chunk_id)
)
SELECT c.chunk_id, c.document_id, c.heading_path, c.content,
       f.vector_rank, f.lexical_rank, f.rrf_score
FROM fused f
JOIN kb.chunk c USING (chunk_id)
ORDER BY f.rrf_score DESC
LIMIT p_k;
$$;

COMMENT ON FUNCTION kb.hybrid_search IS
 'Busca híbrida (vetorial + full-text) com RRF. Respeita RLS do chamador. '
 'Para filtros muito seletivos, ajustar hnsw.ef_search e usar hnsw.iterative_scan (pgvector >= 0.8).';
