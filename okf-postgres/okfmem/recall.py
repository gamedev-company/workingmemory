"""Hybrid recall: semantic (pgvector) + full-text (tsvector), fused with RRF,
with each result annotated by whether its underlying code has drifted (staleness)."""
from __future__ import annotations
from pathlib import Path
from pgvector import Vector
from . import config, db, embed
from .enrich import git_sha

RRF_K = 60  # standard Reciprocal Rank Fusion constant; dampens the tail


def _semantic(conn, query_vec, limit: int, type_filter: str | None) -> list[int]:
    sql = """SELECT id FROM documents
             WHERE embedding IS NOT NULL {tf}
             ORDER BY embedding <=> %(v)s LIMIT %(lim)s"""
    tf = "AND type = %(type)s" if type_filter else ""
    rows = conn.execute(sql.format(tf=tf),
                        {"v": Vector(query_vec), "lim": limit, "type": type_filter}).fetchall()
    return [r["id"] for r in rows]


def _fulltext(conn, query: str, limit: int, type_filter: str | None) -> list[int]:
    sql = """SELECT id FROM documents
             WHERE tsv @@ plainto_tsquery('english', %(q)s) {tf}
             ORDER BY ts_rank(tsv, plainto_tsquery('english', %(q)s)) DESC
             LIMIT %(lim)s"""
    tf = "AND type = %(type)s" if type_filter else ""
    rows = conn.execute(sql.format(tf=tf),
                        {"q": query, "lim": limit, "type": type_filter}).fetchall()
    return [r["id"] for r in rows]


def _rrf(*rankings: list[int]) -> list[int]:
    """Reciprocal Rank Fusion: blend ranked id-lists without needing comparable scores."""
    scores: dict[int, float] = {}
    for ranking in rankings:
        for rank, doc_id in enumerate(ranking):
            scores[doc_id] = scores.get(doc_id, 0.0) + 1.0 / (RRF_K + rank)
    return sorted(scores, key=scores.get, reverse=True)


def _staleness(conn, doc_id: int) -> dict:
    """Compare a card's stored source shas to the current working tree."""
    rows = conn.execute(
        "SELECT source_path, source_sha FROM card_sources WHERE document_id=%s",
        (doc_id,)).fetchall()
    if not rows:
        return {"stale": False, "drifted": [], "covered": 0}
    drifted = []
    for r in rows:
        p = config.REPO / r["source_path"]
        if not p.exists() or git_sha(p) != r["source_sha"]:
            drifted.append(r["source_path"])
    return {"stale": bool(drifted), "drifted": drifted, "covered": len(rows)}


def search(query: str, *, k: int = 6, type_filter: str | None = None,
           pool: int = 25) -> list[dict]:
    """Top-k hybrid recall. Each hit carries a freshness verdict so the caller
    knows whether to trust the card or trigger a re-enrich first."""
    with db.connect() as conn:
        qvec = embed.embed(query)
        sem = _semantic(conn, qvec, pool, type_filter)
        fts = _fulltext(conn, query, pool, type_filter)
        order = _rrf(sem, fts)[:k]
        if not order:
            return []
        rows = {r["id"]: r for r in conn.execute(
            """SELECT id, path, type, title, description, tags, resource, body
               FROM documents WHERE id = ANY(%s)""", (order,)).fetchall()}
        out = []
        for doc_id in order:
            r = rows.get(doc_id)
            if not r:
                continue
            r["freshness"] = _staleness(conn, doc_id)
            out.append(r)
        return out
