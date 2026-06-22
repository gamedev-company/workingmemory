"""okfmem — OKF working-memory ⇄ Postgres recall index.

Source of truth is the markdown vault; this package maintains a derived Postgres
projection (embeddings + full-text + freshness contract) and serves recall over MCP.
"""
__version__ = "0.3.0"
