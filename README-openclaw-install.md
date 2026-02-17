# OpenClaw Desktop Installer (Ubuntu/Debian)

This repository includes a draft installer and configurator for setting up OpenClaw on a Linux desktop with:

- OpenClaw CLI + gateway daemon
- Venice as primary model provider
- Telegram token injection
- Ollama for local fallback and routing
- Tailscale for secure remote access

## Files

- `scripts/install_openclaw.sh` - system installer/orchestrator
- `scripts/configure_openclaw.py` - safe JSON config merge for `~/.openclaw/openclaw.json`
- `scripts/openclaw.env.example` - environment variable template

## Prerequisites

- Ubuntu/Debian-based system
- `sudo` privileges
- Internet access
- Collected credentials:
  - `VENICE_API_KEY` (`vapi_...`)
  - `TELEGRAM_BOT_TOKEN` (`123456789:...`)

## Quick start

```bash
chmod +x scripts/install_openclaw.sh scripts/configure_openclaw.py
./scripts/install_openclaw.sh --venice-key "vapi_..." --telegram-token "123456789:..."
```

## Non-interactive mode

```bash
export VENICE_API_KEY="vapi_..."
export TELEGRAM_BOT_TOKEN="123456789:..."
./scripts/install_openclaw.sh --non-interactive
```

## Optional flags

- `--skip-onboard`: skip `openclaw onboard --install-daemon`
- `--skip-tailscale`: skip Tailscale install/setup
- `--skip-ollama`: skip Ollama install + model pulls
- `--dry-run`: print commands without executing

## What the Python configurator writes

The configurator merges these defaults into `~/.openclaw/openclaw.json`:

- `env.VENICE_API_KEY`
- `env.TELEGRAM_BOT_TOKEN`
- `agents.defaults.model.primary = venice/llama-3.3-70b`
- `agents.defaults.model.fallbacks = [venice/claude-sonnet-4-5, ollama/llama3:8b]`
- `agents.defaults.model.heartbeatModel = ollama/phi3:3.8b`
- `agents.defaults.model.subAgentModel = ollama/llama3:8b`
- `models.providers.ollama` with base URL and starter models

Existing config keys not touched by the installer are preserved. If a config file already exists, a timestamped backup is created.

## Verification commands

```bash
sudo systemctl status openclaw-gateway
tailscale status
systemctl status ollama
openclaw models list
journalctl -u openclaw-gateway -n 100 --no-pager
```

Dashboard:

- Local: `http://127.0.0.1:18789/`
- Remote: `http://<tailscale-ip>:18789/`

## Notes

- `tailscale up` may require browser authorization.
- Ollama model pulls can be several GB.
- If OpenClaw onboarding prompts are required, run without `--skip-onboard` in an interactive terminal.
