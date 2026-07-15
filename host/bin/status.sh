#!/usr/bin/env bash
# Snapshot of queue-ai state (host-local or via console: qai status).
ROOT="${HOME}/queue-ai"
LOGS="$ROOT/logs"

section() {
  local title="$1" dir="$2"
  echo "== $title =="
  if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
    echo "  (empty)"
    return
  fi
  ls -1t "$dir" 2>/dev/null | head -5 | sed 's/^/  /'
}

section "queue (pending)" "$ROOT/queue"
section "running (in flight)" "$ROOT/running"
section "last 5 done" "$ROOT/done"
section "last 5 failed" "$ROOT/failed"

echo "== service =="
path_st="$(systemctl --user is-active qai-runner.path 2>/dev/null || true)"
svc_st="$(systemctl --user is-active qai-runner.service 2>/dev/null || true)"
linger="$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || echo "?")"
echo "  path unit:     ${path_st:-unknown}"
echo "  drain service: ${svc_st:-unknown}   (active only while a job runs)"
echo "  linger:        ${linger}"
echo -n "  mem_sleep:     "; cat /sys/power/mem_sleep 2>/dev/null || echo "?"

echo "== last job log =="
latest="$(ls -1t "$LOGS"/*.log 2>/dev/null | head -1 || true)"
if [ -z "$latest" ]; then
  echo "  (no logs yet)"
else
  echo "  file: $(basename "$latest")"
  end_line="$(grep -E ' end ' "$latest" 2>/dev/null | tail -1 || true)"
  [ -n "$end_line" ] && echo "  $end_line"
  pr="$(grep -oiE 'https://github\.com/[^ ]+/pull/[0-9]+' "$latest" 2>/dev/null | tail -1 || true)"
  [ -n "$pr" ] && echo "  PR: $pr"
  echo "  tail:"
  tail -5 "$latest" 2>/dev/null | sed 's/^/    /'
fi

echo "== usage ledger (last 3) =="
LEDGER="$ROOT/ledger.jsonl"
if [ ! -f "$LEDGER" ] || [ ! -s "$LEDGER" ]; then
  echo "  (empty)"
else
  tail -3 "$LEDGER" | while IFS= read -r line; do
    node -e '
      const r=JSON.parse(process.argv[1]);
      const t=r.totals||{};
      const i=r.implement||{};
      const v=r.review||{};
      console.log(
        "  " + (r.ts||"?").slice(0,19) +
        "  " + (r.job||"?") +
        "  wall=" + (t.wall_min ?? "?") + "m" +
        "  est=$" + (t.cost_usd_est ?? "?") +
        "  impl=" + (i.model||"—") +
        "  rev=" + (v.model||"—") +
        (r.pr ? "  " + r.pr : "")
      );
    ' "$line" 2>/dev/null || echo "  (unparsed row)"
  done
  echo "  full: $LEDGER"
fi
