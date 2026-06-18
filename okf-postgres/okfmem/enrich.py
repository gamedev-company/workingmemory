"""Folder → knowledge card. The procedural + small-LLM pipeline that keeps the
premium agent out of routine codebase summarization."""
from __future__ import annotations
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
import frontmatter
from . import config, db, embed

PER_FILE_CHARS = 2500     # how much of each file to show the model
TOTAL_CHARS = 24000       # cap on the whole prompt's code payload

SYSTEM = (
    "You are a codebase cartographer. Given the files directly inside ONE folder, "
    "produce a terse, durable map of what the folder does. Be concrete: name files, "
    "responsibilities, and non-obvious gotchas. No marketing voice. You are writing "
    "for another engineer (or AI agent) who wants to AVOID reading the raw files."
)


def _as_bullets(val) -> str:
    """Normalize a model field that may be a markdown string OR a list of items
    into a clean markdown bullet list."""
    if val is None:
        return ""
    if isinstance(val, str):
        return val.strip()
    items = []
    for item in val:
        line = str(item).strip().lstrip("-").strip()
        items.append(f"- {line}")
    return "\n".join(items)


def _parse_json(raw: str) -> dict:
    """Tolerant JSON extraction: handle code fences, leading prose, empty replies."""
    s = (raw or "").strip()
    if not s:
        raise ValueError("enrichment model returned empty content")
    if s.startswith("```"):
        s = s.strip("`")
        s = s[s.find("\n") + 1:] if "\n" in s else s
    start, end = s.find("{"), s.rfind("}")
    if start == -1 or end == -1:
        raise ValueError(f"no JSON object in model reply: {raw[:200]!r}")
    return json.loads(s[start:end + 1])


def git_sha(path: Path) -> str:
    """Git blob sha of a working-tree file; sha256 fallback if not in a git repo."""
    try:
        out = subprocess.run(
            ["git", "-C", str(config.REPO), "hash-object", str(path)],
            capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()[:40]


def folder_files(folder: Path) -> list[Path]:
    """Direct (non-recursive) code/text files in a folder — subfolders get own cards."""
    return sorted(
        p for p in folder.iterdir()
        if p.is_file() and p.suffix in config.CODE_EXTS and not p.name.startswith(".")
    )


def card_path_for(folder: Path) -> Path:
    """Vault location for a folder's card, mirroring the repo tree under cards/."""
    rel = folder.resolve().relative_to(config.REPO)
    sub = "_root" if str(rel) == "." else str(rel)
    return config.VAULT / "cards" / sub / "index.md"


def _build_prompt(folder: Path, files: list[Path]) -> str:
    rel = folder.resolve().relative_to(config.REPO)
    parts = [f"Folder: {rel}\nFiles in this folder: {[f.name for f in files]}\n"]
    budget = TOTAL_CHARS
    for f in files:
        if budget <= 0:
            break
        try:
            text = f.read_text(errors="replace")[:PER_FILE_CHARS]
        except Exception:
            continue
        budget -= len(text)
        parts.append(f"\n=== {f.name} ===\n{text}")
    parts.append(
        "\n\nReturn STRICT JSON with keys: "
        '"title" (short), "description" (one sentence), "tags" (array of lowercase '
        'keywords), "map" (markdown bullet list: responsibility → `file`), '
        '"gotchas" (markdown bullets of non-obvious facts, or empty string).'
    )
    return "".join(parts)


def enrich_folder(folder: Path, *, project: str | None = None) -> dict:
    """Summarize one folder into an OKF card, write markdown, upsert Postgres."""
    folder = folder.resolve()
    files = folder_files(folder)
    if not files:
        return {"skipped": str(folder.relative_to(config.REPO)), "reason": "no code files"}

    raw = embed.chat(_build_prompt(folder, files), system=SYSTEM, think=False, format_json=True)
    data = _parse_json(raw)

    rel = folder.relative_to(config.REPO)
    sources = [(str(f.relative_to(config.REPO)), git_sha(f)) for f in files]
    body = f"# {data.get('title', rel.name)}\n\n## Map\n{_as_bullets(data.get('map'))}\n"
    if data.get("gotchas"):
        body += f"\n## Gotchas\n{_as_bullets(data['gotchas'])}\n"

    post = frontmatter.Post(
        body,
        type="feature-card",
        title=data.get("title", str(rel)),
        description=data.get("description", ""),
        tags=data.get("tags", []),
        resource=str(rel),
        project=project,
        timestamp=datetime.now(timezone.utc).isoformat(),
        covers=[{"path": p, "sha": s} for p, s in sources],
    )
    card_file = card_path_for(folder)
    card_file.parent.mkdir(parents=True, exist_ok=True)
    md = frontmatter.dumps(post)
    card_file.write_text(md)

    vector = embed.embed(f"{post['title']}\n{post['description']}\n{body}")
    content_hash = hashlib.sha256(md.encode()).hexdigest()[:40]
    with db.connect() as conn:
        doc_id = db.upsert_document(
            conn, path=str(card_file.relative_to(config.VAULT)), type="feature-card",
            tier="cards", title=post["title"], description=post["description"],
            tags=post["tags"], resource=str(rel), status=None, project=project,
            body=body, content_hash=content_hash, doc_timestamp=post["timestamp"],
            embedding=vector,
        )
        db.replace_card_sources(conn, doc_id, sources)
        conn.commit()
    return {"card": str(card_file.relative_to(config.VAULT)), "files": len(files), "id": doc_id}
