"""Environment-driven configuration. Everything is local by default."""
from __future__ import annotations
import os
from pathlib import Path

# Postgres.app: trust auth on localhost, db created earlier.
DB_DSN = os.environ.get("OKF_DB_DSN", "postgresql://localhost/okf_memory")

# The code repository we are building a knowledge map of.
REPO = Path(os.environ.get("OKF_REPO", ".")).resolve()

# Where OKF markdown cards live (the vault). Default: <repo>/working-memory.
VAULT = Path(os.environ.get("OKF_VAULT", str(REPO / "working-memory"))).resolve()

# Local Ollama.
OLLAMA = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")

# Models: a cheap local embedder, and a small local model for the "massaging".
EMBED_MODEL = os.environ.get("OKF_EMBED_MODEL", "nomic-embed-text")
EMBED_DIM = int(os.environ.get("OKF_EMBED_DIM", "768"))   # must match schema vector(N)
ENRICH_MODEL = os.environ.get("OKF_ENRICH_MODEL", "qwen3.6:27b")

# Folders we never card (noise / not ours). Extend per-project with
# OKF_IGNORE_EXTRA="dir1,dir2" (comma-separated).
IGNORE_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".obsidian",
               "dist", "build", "target", ".next", ".cache", "working-memory",
               "_build", "deps", "priv", "_archive", "logs", ".claude"}
IGNORE_DIRS |= {d.strip() for d in os.environ.get("OKF_IGNORE_EXTRA", "").split(",") if d.strip()}
# Extensions worth reading into a card prompt.
CODE_EXTS = {".py", ".ts", ".tsx", ".js", ".jsx", ".ex", ".exs", ".go", ".rs",
             ".rb", ".java", ".kt", ".swift", ".c", ".h", ".cpp", ".sql", ".sh",
             ".css", ".scss", ".html", ".vue", ".svelte", ".md", ".toml", ".yaml", ".yml"}
