#!/usr/bin/env bash
# One-time host bootstrap for desktop-runner (Fedora/RHEL-family or Debian/Ubuntu).
# Run on the host:  bash ~/desktop-runner/bootstrap.sh
# Idempotent. May prompt for sudo (gh install, linger).
set -euo pipefail

ROOT="${HOME}/desktop-runner"
# shellcheck source=/dev/null
[ -f "$ROOT/config.env" ] && source "$ROOT/config.env"
REPO_DIR="${REPO_DIR:-$HOME/desktop-runner/repo}"
# Optional: set REPO_URL in config.env before cloning
REPO_URL="${REPO_URL:-}"

echo "== 1/5 gh (GitHub CLI) =="
if ! command -v gh >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y gh
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y gh
  else
    echo "Install GitHub CLI (gh) manually, then re-run." >&2
    exit 1
  fi
fi

if ! gh auth status >/dev/null 2>&1; then
  echo
  echo ">> Authenticate GitHub, then re-run this script:"
  echo ">>   gh auth login"
  exit 1
fi
gh auth setup-git >/dev/null 2>&1 || true

echo "== 2/5 node (optional, via nvm if missing) =="
if ! command -v node >/dev/null 2>&1; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [ ! -d "$NVM_DIR" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  fi
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm alias default 'lts/*'
fi
echo "node $(node --version 2>/dev/null || echo missing)"

echo "== 3/5 runner clone =="
if [ ! -d "$REPO_DIR/.git" ]; then
  if [ -z "$REPO_URL" ]; then
    echo "Set REPO_URL in $ROOT/config.env (git clone URL), or clone manually to $REPO_DIR" >&2
    exit 1
  fi
  git clone "$REPO_URL" "$REPO_DIR"
fi
echo "repo: $REPO_DIR @ $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"

if [ -z "$(git -C "$REPO_DIR" config user.email 2>/dev/null || true)" ]; then
  echo ">> Set git author on the runner clone, e.g.:"
  echo ">>   git -C \"$REPO_DIR\" config user.name \"Your Name\""
  echo ">>   git -C \"$REPO_DIR\" config user.email \"you@example.com\""
fi

echo "== 4/5 directories =="
mkdir -p "$ROOT"/{queue,running,done,failed,logs}

echo "== 5/5 linger (jobs without GUI login) =="
loginctl enable-linger "$USER" 2>/dev/null || sudo loginctl enable-linger "$USER"

echo
echo "BOOTSTRAP COMPLETE."
echo "Next: enable systemd units (SETUP.md §5), then smoke-test from the laptop."
