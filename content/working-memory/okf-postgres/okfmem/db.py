"""Postgres access — connection + upsert/query helpers for the recall index."""
from __future__ import annotations
from contextlib import contextmanager
from typing import Iterable, Sequence
import psycopg
from psycopg.rows import dict_row
from pgvector.psycopg import register_vector
from . import config


@contextmanager
def connect():
    """Yield a connection with the pgvector adapter registered."""
    with psycopg.connect(config.DB_DSN, row_factory=dict_row) as conn:
        register_vector(conn)
        yield conn


def upsert_document(conn, *, path: str, type: str, tier: str | None, title: str | None,
                    description: str | None, tags: Sequence[str], resource: str | None,
                    status: str | None, project: str | None, body: str,
                    content_hash: str, doc_timestamp, embedding) -> int:
    """Insert or update a document by its unique vault path. Returns its id."""
    row = conn.execute(
        """
        INSERT INTO documents (path, type, tier, title, description, tags, resource,
                               status, project, body, content_hash, doc_timestamp, embedding)
        VALUES (%(path)s, %(type)s, %(tier)s, %(title)s, %(description)s, %(tags)s,
                %(resource)s, %(status)s, %(project)s, %(body)s, %(content_hash)s,
                %(doc_timestamp)s, %(embedding)s)
        ON CONFLICT (path) DO UPDATE SET
            type=EXCLUDED.type, tier=EXCLUDED.tier, title=EXCLUDED.title,
            description=EXCLUDED.description, tags=EXCLUDED.tags, resource=EXCLUDED.resource,
            status=EXCLUDED.status, project=EXCLUDED.project, body=EXCLUDED.body,
            content_hash=EXCLUDED.content_hash, doc_timestamp=EXCLUDED.doc_timestamp,
            embedding=EXCLUDED.embedding, updated_at=now()
        RETURNING id
        """,
        dict(path=path, type=type, tier=tier, title=title, description=description,
             tags=list(tags), resource=resource, status=status, project=project,
             body=body, content_hash=content_hash, doc_timestamp=doc_timestamp,
             embedding=embedding),
    ).fetchone()
    return row["id"]


def replace_card_sources(conn, document_id: int, sources: Iterable[tuple[str, str]]) -> None:
    """Replace the freshness contract for a card: [(source_path, source_sha), ...]."""
    conn.execute("DELETE FROM card_sources WHERE document_id=%s", (document_id,))
    for source_path, source_sha in sources:
        conn.execute(
            """INSERT INTO card_sources (document_id, source_path, source_sha)
               VALUES (%s, %s, %s)
               ON CONFLICT (document_id, source_path)
               DO UPDATE SET source_sha=EXCLUDED.source_sha, enriched_at=now()""",
            (document_id, source_path, source_sha),
        )


def cards_covering(conn, source_path: str) -> list[dict]:
    """All feature-cards whose freshness contract includes this code path."""
    return conn.execute(
        """SELECT d.id, d.path, cs.source_sha
           FROM card_sources cs JOIN documents d ON d.id = cs.document_id
           WHERE cs.source_path = %s""",
        (source_path,),
    ).fetchall()


def stale_sources(conn) -> list[dict]:
    """Every (card, source_path, stored_sha) pair — caller compares to current git sha."""
    return conn.execute(
        """SELECT d.path AS card_path, cs.source_path, cs.source_sha
           FROM card_sources cs JOIN documents d ON d.id = cs.document_id
           ORDER BY d.path, cs.source_path"""
    ).fetchall()
