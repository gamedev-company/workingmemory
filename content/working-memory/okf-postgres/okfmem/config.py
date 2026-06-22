"""Environment-driven configuration. Everything is local by default."""
from __future__ import annotations
import hashlib
import os
import re
from pathlib import Path

# The code repository we are building a knowledge map of.
REPO = Path(os.environ.get("OKF_REPO", ".")).resolve()

# Where OKF markdown cards live (the vault). Default: <repo>/working-memory.
VAULT = Path(os.environ.get("OKF_VAULT", str(REPO / "working-memory"))).resolve()


def _db_slug(name: str) -> str:
    """A safe, readable Postgres-identifier fragment from a repo name."""
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")[:30] or "repo"


def derive_db_name(repo: Path) -> str:
    """Stable, collision-resistant database name for a repo: ``okf_<slug>_<hash8>``.

    Derived from the repo's ABSOLUTE path, so distinct checkouts get distinct
    databases and we never land on a user's pre-existing database by accident.
    Override with OKF_DB_NAME (a bare name) or OKF_DB_DSN (a full DSN)."""
    digest = hashlib.sha256(str(repo).encode()).hexdigest()[:8]
    return f"okf_{_db_slug(repo.name)}_{digest}"


# Database resolution (precedence): a full DSN wins; else an explicit bare name;
# else a derived per-repo name. Postgres.app uses trust auth on localhost.
_explicit_dsn = os.environ.get("OKF_DB_DSN")
if _explicit_dsn:
    DB_DSN = _explicit_dsn
    DB_NAME = _explicit_dsn.rstrip("/").split("/")[-1].split("?")[0] or derive_db_name(REPO)
else:
    DB_NAME = os.environ.get("OKF_DB_NAME") or derive_db_name(REPO)
    DB_DSN = f"postgresql://localhost/{DB_NAME}"

# Local Ollama.
OLLAMA = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")

# Models: a cheap local embedder, and a small local model for the "massaging".
EMBED_MODEL = os.environ.get("OKF_EMBED_MODEL", "nomic-embed-text")
EMBED_DIM = int(os.environ.get("OKF_EMBED_DIM", "768"))   # must match schema vector(N)
ENRICH_MODEL = os.environ.get("OKF_ENRICH_MODEL", "qwen3.6:27b")

# Folders we never card (noise / not ours). Extend per-project with
# OKF_IGNORE_EXTRA="dir1,dir2" (comma-separated).
# NOTE: do NOT ignore Phoenix `priv/` — it holds Ecto migrations
# (priv/repo/migrations/*.exs) and seeds (priv/repo/seeds.exs), which are exactly
# the schema-change files that most need cards + freshness tracking.
IGNORE_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".obsidian",
               "dist", "build", "target", ".next", ".cache", "working-memory",
               "_build", "deps", "_archive", "logs", ".claude"}
IGNORE_DIRS |= {d.strip() for d in os.environ.get("OKF_IGNORE_EXTRA", "").split(",") if d.strip()}
# Extensions worth reading into a card prompt. Extend per-project with
# OKF_EXTS_EXTRA=".astro,.zig" (comma-separated; leading dot optional).
CODE_EXTS = {".py", ".ts", ".tsx", ".js", ".jsx", ".ex", ".exs", ".heex", ".eex",
             ".go", ".rs", ".rb", ".java", ".kt", ".swift", ".c", ".h", ".cpp",
             ".sql", ".sh", ".css", ".scss", ".html", ".vue", ".svelte", ".md",
             ".toml", ".yaml", ".yml"}
CODE_EXTS |= {("" if e.strip().startswith(".") else ".") + e.strip()
              for e in os.environ.get("OKF_EXTS_EXTRA", "").split(",") if e.strip()}
