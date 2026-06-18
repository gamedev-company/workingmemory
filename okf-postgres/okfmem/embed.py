"""Local embeddings + chat via the Ollama HTTP API. Nothing leaves the machine."""
from __future__ import annotations
import httpx
from . import config


def embed(text: str) -> list[float]:
    """Embed text with the local embedding model. Returns a 768-dim vector."""
    # Ollama's modern endpoint is /api/embed (batched). Falls back to /api/embeddings.
    with httpx.Client(timeout=120) as c:
        r = c.post(f"{config.OLLAMA}/api/embed",
                   json={"model": config.EMBED_MODEL, "input": text})
        if r.status_code == 404:
            r = c.post(f"{config.OLLAMA}/api/embeddings",
                       json={"model": config.EMBED_MODEL, "prompt": text})
            r.raise_for_status()
            return r.json()["embedding"]
        r.raise_for_status()
        return r.json()["embeddings"][0]


def chat(prompt: str, *, system: str | None = None, think: bool = False,
         format_json: bool = False) -> str:
    """One-shot chat with the local enrichment model.

    think=False suppresses qwen3.6's reasoning trace — we want terse card text,
    not a chain-of-thought, for routine summarization.
    """
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    payload = {
        "model": config.ENRICH_MODEL,
        "messages": messages,
        "stream": False,
        "think": think,
        "keep_alive": "10m",   # stay resident across a folder sweep
        "options": {"temperature": 0.2, "num_ctx": 16384, "num_predict": 2048},
    }
    if format_json:
        payload["format"] = "json"
    with httpx.Client(timeout=600) as c:
        r = c.post(f"{config.OLLAMA}/api/chat", json=payload)
        r.raise_for_status()
        return r.json()["message"]["content"]
