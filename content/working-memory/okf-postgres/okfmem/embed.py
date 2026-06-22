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
         schema: dict | None = None, temperature: float = 0.2) -> str:
    """One-shot chat with the local enrichment model.

    think=False suppresses qwen3.6's reasoning trace — we want terse card text,
    not a chain-of-thought, for routine summarization.

    schema: an Ollama structured-output JSON Schema. When set, the decoder is
    constrained to emit valid JSON conforming to it — far more reliable than the
    plain "json" format mode, which only nudges the model.
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
        "options": {"temperature": temperature, "num_ctx": 16384, "num_predict": 2048},
    }
    if schema is not None:
        payload["format"] = schema
    with httpx.Client(timeout=600) as c:
        r = c.post(f"{config.OLLAMA}/api/chat", json=payload)
        r.raise_for_status()
        return r.json()["message"]["content"]
