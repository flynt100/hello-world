#!/usr/bin/env python3
"""Merge OpenClaw desktop routing configuration into ~/.openclaw/openclaw.json."""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Configure OpenClaw routing and providers")
    parser.add_argument("--venice-key", required=True, help="Venice API key (vapi_...)")
    parser.add_argument("--telegram-token", required=True, help="Telegram bot token")
    parser.add_argument(
        "--config-path",
        default=str(Path.home() / ".openclaw" / "openclaw.json"),
        help="Path to openclaw.json",
    )
    parser.add_argument(
        "--skip-ollama-provider",
        action="store_true",
        help="Do not add/update models.providers.ollama",
    )
    return parser.parse_args()


def ensure_dict(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        value = {}
        parent[key] = value
    return value


def load_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError(f"Top-level JSON in {path} must be an object")
    return data


def backup_config(path: Path) -> None:
    if not path.exists():
        return
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = path.with_suffix(path.suffix + f".{stamp}.bak")
    shutil.copy2(path, backup)
    print(f"Backup created: {backup}")


def upsert_ollama_models(provider: dict[str, Any]) -> None:
    provider["baseUrl"] = "http://127.0.0.1:11434"
    provider["api"] = "ollama"

    desired_models = [
        {
            "id": "phi3:3.8b",
            "name": "Phi-3 Mini",
            "contextWindow": 4096,
            "maxTokens": 2048,
        },
        {
            "id": "llama3:8b",
            "name": "Llama 3 8B",
            "contextWindow": 8192,
            "maxTokens": 4096,
        },
    ]

    existing = provider.get("models")
    if not isinstance(existing, list):
        existing = []

    index: dict[str, dict[str, Any]] = {}
    for item in existing:
        if isinstance(item, dict) and isinstance(item.get("id"), str):
            index[item["id"]] = item

    for model in desired_models:
        model_id = model["id"]
        if model_id in index:
            index[model_id].update(model)
        else:
            existing.append(model)

    provider["models"] = existing


def merge_config(cfg: dict[str, Any], venice_key: str, telegram_token: str, skip_ollama_provider: bool) -> dict[str, Any]:
    env = ensure_dict(cfg, "env")
    env["VENICE_API_KEY"] = venice_key
    env["TELEGRAM_BOT_TOKEN"] = telegram_token

    agents = ensure_dict(cfg, "agents")
    defaults = ensure_dict(agents, "defaults")
    model = ensure_dict(defaults, "model")

    model["primary"] = "venice/llama-3.3-70b"
    model["fallbacks"] = ["venice/claude-sonnet-4-5", "ollama/llama3:8b"]
    model["heartbeatModel"] = "ollama/phi3:3.8b"
    model["subAgentModel"] = "ollama/llama3:8b"

    if not skip_ollama_provider:
        models = ensure_dict(cfg, "models")
        providers = ensure_dict(models, "providers")
        ollama = ensure_dict(providers, "ollama")
        upsert_ollama_models(ollama)

    return cfg


def write_config(path: Path, cfg: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
    tmp.replace(path)


def main() -> None:
    args = parse_args()

    if not args.venice_key.startswith("vapi_"):
        raise SystemExit("--venice-key must start with 'vapi_'")
    if ":" not in args.telegram_token:
        raise SystemExit("--telegram-token must contain ':'")

    path = Path(args.config_path).expanduser()
    current = load_config(path)
    backup_config(path)
    merged = merge_config(current, args.venice_key, args.telegram_token, args.skip_ollama_provider)
    write_config(path, merged)
    print(f"Wrote configuration: {path}")


if __name__ == "__main__":
    main()
