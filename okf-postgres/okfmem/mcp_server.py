"""okf-memory MCP server — exposes the recall index as MCP tools so any model
(local qwen via mcphost, or Claude Code) can query persistent codebase memory
instead of re-reading files. Speaks MCP over stdio.

Run:  OKF_REPO=/path/to/repo .venv/bin/python -m okfmem.mcp_server
"""
from __future__ import annotations
from mcp.server.fastmcp import FastMCP
from . import recall, db, config
from .enrich import git_sha

mcp = FastMCP("okf-memory")


@mcp.tool()
def memory_recall(query: str, k: int = 6, type: str | None = None) -> list[dict]:
    """Recall codebase knowledge cards by meaning + keywords. Use this BEFORE
    reading source files — it returns a compact map (what a folder/feature does,
    which files, gotchas) so you avoid re-exploring. Each result includes a
    `freshness` verdict: if `stale` is true, the underlying code has changed
    since the card was written — treat the card as a hint and verify, or call
    memory_stale_cards to see what drifted.

    Args:
        query: natural-language question, e.g. "how does auth refresh work".
        k: number of cards to return (default 6).
        type: optional filter, e.g. "feature-card".
    """
    hits = recall.search(query, k=k, type_filter=type)
    return [
        {
            "title": h["title"],
            "description": h["description"],
            "resource": h["resource"],     # the code path this card describes
            "card_path": h["path"],
            "tags": h["tags"],
            "map": h["body"],              # the responsibility→file map + gotchas
            "freshness": h["freshness"],   # {stale, drifted:[...], covered:N}
        }
        for h in hits
    ]


@mcp.tool()
def memory_get_card(card_path: str) -> dict:
    """Fetch one knowledge card in full by its vault path (as returned by
    memory_recall's `card_path`)."""
    with db.connect() as conn:
        row = conn.execute(
            """SELECT path, type, title, description, tags, resource, body
               FROM documents WHERE path=%s""", (card_path,)).fetchone()
    return dict(row) if row else {"error": f"no card at {card_path}"}


@mcp.tool()
def memory_stale_cards() -> list[dict]:
    """List cards whose covered code has drifted since enrichment. Use this to
    decide what needs re-enriching, or to gauge how much to trust recall."""
    with db.connect() as conn:
        rows = db.stale_sources(conn)
    by_card: dict[str, list[str]] = {}
    for r in rows:
        p = config.REPO / r["source_path"]
        if not p.exists() or git_sha(p) != r["source_sha"]:
            by_card.setdefault(r["card_path"], []).append(r["source_path"])
    return [{"card_path": c, "drifted": d} for c, d in by_card.items()]


def main():
    mcp.run()   # stdio transport


if __name__ == "__main__":
    main()
