-- okf-postgres schema — derived recall index for an OKF working-memory vault.
--
-- Source of truth = the markdown vault (git-tracked, OKF-compliant). This database
-- is a DERIVED, rebuildable projection: embeddings + full-text + the freshness
-- contract that lets a consumer know whether a card still matches the code.
--
-- Embedding model: nomic-embed-text via Ollama → 768 dims. If you switch embedders,
-- change vector(768) below and re-embed everything (dims must match exactly).

CREATE EXTENSION IF NOT EXISTS vector;

-- ─────────────────────────────────────────────────────────────────────────────
-- documents — one row per OKF markdown doc in the vault (any tier).
-- A "feature-card" (type='feature-card') is the per-folder code map; other rows
-- mirror the durable tiers (ref/design/plan/…) and journals.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS documents (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  path          TEXT        NOT NULL UNIQUE,          -- vault-relative md path = OKF concept identity
  type          TEXT        NOT NULL,                 -- OKF required field: feature-card|ref|design|plan|journal|…
  tier          TEXT,                                 -- vault tier dir (core/ref/schema/senses/design/plan/…)
  title         TEXT,
  description   TEXT,
  tags          TEXT[]      NOT NULL DEFAULT '{}',
  resource      TEXT,                                 -- OKF resource: the code path/URL this doc describes
  status        TEXT,                                 -- type-specific (draft/approved/open/resolved/…)
  project       TEXT,
  body          TEXT        NOT NULL DEFAULT '',      -- markdown body (frontmatter stripped)
  content_hash  TEXT        NOT NULL,                 -- hash of the md FILE itself (detects card edits)
  doc_timestamp TIMESTAMPTZ,                          -- OKF timestamp from frontmatter
  embedding     vector(768),                          -- nomic-embed-text of (title + description + body)
  tsv           tsvector
                GENERATED ALWAYS AS (
                  setweight(to_tsvector('english', coalesce(title,'')),       'A') ||
                  setweight(to_tsvector('english', coalesce(description,'')), 'B') ||
                  setweight(to_tsvector('english', coalesce(body,'')),        'C')
                ) STORED,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- card_sources — THE FRESHNESS CONTRACT.
-- For each feature-card, the code files it "covers" and the git blob sha we
-- summarized at. The daemon: changed path → look up covering cards → if current
-- sha != stored sha (or path vanished), the card is stale and gets re-enriched.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS card_sources (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  document_id  BIGINT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  source_path  TEXT   NOT NULL,                        -- repo-relative code path the card covers
  source_sha   TEXT   NOT NULL,                        -- git blob sha at last enrichment
  enriched_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (document_id, source_path)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- links — knowledge-graph edges from [[wikilinks]] and [md](path) links.
-- dst_document_id is filled in when the target resolves to a known doc; otherwise
-- the edge dangles (dst_path kept) so we can resolve it later as the vault grows.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS links (
  src_document_id BIGINT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  dst_path        TEXT   NOT NULL,
  dst_document_id BIGINT REFERENCES documents(id) ON DELETE SET NULL,
  kind            TEXT   NOT NULL DEFAULT 'wikilink',  -- 'wikilink' | 'mdlink'
  PRIMARY KEY (src_document_id, dst_path)
);

-- ── Indexes ────────────────────────────────────────────────────────────────────
-- HNSW for fast approximate nearest-neighbor semantic recall (cosine distance).
CREATE INDEX IF NOT EXISTS documents_embedding_hnsw
  ON documents USING hnsw (embedding vector_cosine_ops);
-- GIN for keyword/full-text recall (the other half of hybrid search).
CREATE INDEX IF NOT EXISTS documents_tsv_gin ON documents USING gin (tsv);
-- GIN on tags for tag-filtered recall.
CREATE INDEX IF NOT EXISTS documents_tags_gin ON documents USING gin (tags);
CREATE INDEX IF NOT EXISTS documents_type_idx  ON documents (type);
CREATE INDEX IF NOT EXISTS documents_tier_idx  ON documents (tier);
-- Reverse lookup: changed code file → which cards cover it (the daemon's hot path).
CREATE INDEX IF NOT EXISTS card_sources_path_idx ON card_sources (source_path);
CREATE INDEX IF NOT EXISTS card_sources_doc_idx  ON card_sources (document_id);

-- ── Convenience view: per-card coverage summary (for stale detection in SQL) ────
CREATE OR REPLACE VIEW card_coverage AS
SELECT d.id, d.path, d.type, d.resource,
       count(cs.id)            AS covered_files,
       max(cs.enriched_at)     AS last_enriched
FROM documents d
LEFT JOIN card_sources cs ON cs.document_id = d.id
WHERE d.type = 'feature-card'
GROUP BY d.id;
