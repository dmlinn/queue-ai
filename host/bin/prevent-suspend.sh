#!/usr/bin/env bash
# Keep an always-on runner host from sleeping (or re-enable sleep later).
#
#   bash ~/desktop-runner/bin/prevent-suspend.sh          # KDE PowerDevil only
#   bash ~/desktop-runner/bin/prevent-suspend.sh --system # also mask systemd sleep (sudo)
set -euo pipefail

SYSTEM=0
for arg in "$@"; do
  case "$arg" in
    --system|-s) SYSTEM=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
  esac
done

echo "== 1/2 desktop environment: never auto-suspend =="
if command -v kwriteconfig6 >/dev/null 2>&1; then
  KW=kwriteconfig6
elif command -v kwriteconfig5 >/dev/null 2>&1; then
  KW=kwriteconfig5
else
  KW=""
  echo "   (no kwriteconfig — skip KDE profile; use --system or DE settings)"
fi

if [ -n "$KW" ]; then
  mkdir -p "$HOME/.config"
  if [ -f "$HOME/.config/powerdevilrc" ]; then
    cp -a "$HOME/.config/powerdevilrc" \
      "$HOME/.config/powerdevilrc.bak.$(date +%Y%m%d%H%M%S)"
  fi
  for profile in AC Battery LowBattery; do
    $KW --file powerdevilrc --group "$profile" --group SuspendAndShutdown \
      --key AutoSuspendAction 0
    $KW --file powerdevilrc --group "$profile" --group SuspendAndShutdown \
      --key AutoSuspendIdleTimeoutSec 0
    $KW --file powerdevilrc --group "$profile" --group SuspendAndShutdown \
      --key LidAction 0
  done
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
  command -v qdbus6 >/dev/null 2>&1 && \
    qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement \
      org.kde.Solid.PowerManagement.reparseConfiguration 2>/dev/null || true
  systemctl --user try-restart plasma-powerdevil.service 2>/dev/null || true
  echo "   PowerDevil: AutoSuspendAction=0"
fi

if [ "$SYSTEM" -eq 1 ]; then
  echo "== 2/2 systemd: mask sleep targets (sudo) =="
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
  sudo mkdir -p /etc/systemd/logind.conf.d
  sudo tee /etc/systemd/logind.conf.d/desktop-runner-no-suspend.conf >/dev/null <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
  sudo systemctl restart systemd-logind
  echo "   masked. Unmask later: sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target"
else
  echo "== 2/2 systemd mask skipped (pass --system; needs sudo) =="
fi

echo "DONE. Screen blanking can remain; sleep is blocked (if --system)."
