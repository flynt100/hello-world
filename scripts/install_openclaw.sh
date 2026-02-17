#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SCRIPT="$SCRIPT_DIR/configure_openclaw.py"
LOG_FILE="${OPENCLAW_INSTALL_LOG:-$HOME/openclaw-install.log}"

DRY_RUN=false
NON_INTERACTIVE=false
SKIP_TAILSCALE=false
SKIP_OLLAMA=false
SKIP_ONBOARD=false
VENICE_API_KEY="${VENICE_API_KEY:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

usage() {
  cat <<USAGE
OpenClaw Desktop Installer (Ubuntu/Debian)

Usage:
  $0 [options]

Options:
  --venice-key <key>         Venice API key (or set VENICE_API_KEY)
  --telegram-token <token>   Telegram bot token (or set TELEGRAM_BOT_TOKEN)
  --non-interactive          Fail if required input is missing and avoid prompts
  --skip-tailscale           Skip Tailscale installation and setup
  --skip-ollama              Skip Ollama installation and model pulls
  --skip-onboard             Skip 'openclaw onboard --install-daemon'
  --dry-run                  Print commands instead of executing
  -h, --help                 Show this help

Examples:
  $0 --venice-key vapi_xxx --telegram-token 123:abc
  VENICE_API_KEY=vapi_xxx TELEGRAM_BOT_TOKEN=123:abc $0 --non-interactive
USAGE
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] $*"
  else
    log "+ $*"
    eval "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --venice-key)
        VENICE_API_KEY="${2:-}"
        shift 2
        ;;
      --telegram-token)
        TELEGRAM_BOT_TOKEN="${2:-}"
        shift 2
        ;;
      --non-interactive)
        NON_INTERACTIVE=true
        shift
        ;;
      --skip-tailscale)
        SKIP_TAILSCALE=true
        shift
        ;;
      --skip-ollama)
        SKIP_OLLAMA=true
        shift
        ;;
      --skip-onboard)
        SKIP_ONBOARD=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

validate_input() {
  if [[ -z "$VENICE_API_KEY" ]]; then
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
      die "VENICE_API_KEY is required in --non-interactive mode"
    fi
    read -r -p "Enter Venice API key (vapi_...): " VENICE_API_KEY
  fi

  if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
      die "TELEGRAM_BOT_TOKEN is required in --non-interactive mode"
    fi
    read -r -p "Enter Telegram bot token: " TELEGRAM_BOT_TOKEN
  fi

  [[ "$VENICE_API_KEY" =~ ^vapi_ ]] || die "Venice API key must start with 'vapi_'"
  [[ "$TELEGRAM_BOT_TOKEN" == *:* ]] || die "Telegram bot token should contain ':'"
}

check_os() {
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect OS. /etc/os-release not found"
  fi
  . /etc/os-release
  case "${ID:-}" in
    ubuntu|debian) ;;
    *)
      if [[ "${ID_LIKE:-}" != *debian* ]]; then
        die "Unsupported distro: ${PRETTY_NAME:-unknown}. Expected Ubuntu/Debian-based."
      fi
      ;;
  esac
  log "Detected OS: ${PRETTY_NAME:-unknown}"
}

install_nodejs() {
  log "Installing Node.js 22.x"
  run_cmd "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
  run_cmd "sudo apt-get install -y nodejs"

  if [[ "$DRY_RUN" == "false" ]]; then
    require_command node
    local node_major
    node_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    [[ "$node_major" -ge 22 ]] || die "Node.js v22+ required, found $(node -v)"
    log "Node.js version OK: $(node -v)"
  fi
}

install_openclaw_cli() {
  log "Installing OpenClaw CLI"
  run_cmd "sudo npm install -g @openclaw/cli"
  if [[ "$DRY_RUN" == "false" ]]; then
    require_command openclaw
  fi
}

run_onboard() {
  if [[ "$SKIP_ONBOARD" == "true" ]]; then
    log "Skipping onboarding per flag"
    return
  fi

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    log "Running onboarding in non-interactive mode may still require terminal prompts."
  fi
  run_cmd "openclaw onboard --install-daemon"
}

install_tailscale() {
  [[ "$SKIP_TAILSCALE" == "true" ]] && { log "Skipping Tailscale"; return; }
  log "Installing Tailscale"
  run_cmd "curl -fsSL https://tailscale.com/install.sh | sh"
  run_cmd "sudo systemctl enable --now tailscaled"
  log "Running 'tailscale up' (may require browser authorization)"
  run_cmd "sudo tailscale up"
}

install_ollama() {
  [[ "$SKIP_OLLAMA" == "true" ]] && { log "Skipping Ollama"; return; }
  log "Installing Ollama"
  run_cmd "curl -fsSL https://ollama.com/install.sh | sh"
  run_cmd "sudo systemctl enable --now ollama"
  run_cmd "ollama pull phi3:3.8b"
  run_cmd "ollama pull llama3:8b"
}

configure_openclaw() {
  [[ -f "$CONFIG_SCRIPT" ]] || die "Configurator script not found: $CONFIG_SCRIPT"
  run_cmd "sudo systemctl stop openclaw-gateway || true"

  local args
  args=(
    "python3" "$CONFIG_SCRIPT"
    "--venice-key" "'$VENICE_API_KEY'"
    "--telegram-token" "'$TELEGRAM_BOT_TOKEN'"
  )
  if [[ "$SKIP_OLLAMA" == "true" ]]; then
    args+=("--skip-ollama-provider")
  fi
  run_cmd "${args[*]}"

  run_cmd "sudo systemctl enable --now openclaw-gateway"
}

print_summary() {
  cat <<EOF_SUMMARY | tee -a "$LOG_FILE"

Installation summary checks:
  sudo systemctl status openclaw-gateway
  tailscale status
  systemctl status ollama
  openclaw models list
  journalctl -u openclaw-gateway -n 100 --no-pager

Dashboard:
  Local:  http://127.0.0.1:18789/
  Remote: http://<tailscale-ip>:18789/
EOF_SUMMARY
}

main() {
  parse_args "$@"

  : > "$LOG_FILE"
  log "Starting OpenClaw install"

  require_command sudo
  require_command curl
  require_command python3

  check_os
  validate_input

  run_cmd "sudo apt-get update"
  run_cmd "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
  run_cmd "sudo apt-get install -y ca-certificates gnupg"

  install_nodejs
  install_openclaw_cli
  run_onboard
  install_tailscale
  install_ollama
  configure_openclaw
  print_summary

  log "OpenClaw install flow complete"
}

main "$@"
