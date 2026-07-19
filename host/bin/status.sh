#!/usr/bin/env bash
# Snapshot of queue-ai state (host-local or via console: qai status).
# Colorized, laid out to use terminal width. Pass --watch on the console
# (qai status --watch) for a live-refreshing display.
#
# Color: on by default. Disabled if NO_COLOR is set or --no-color is passed.
ROOT="${HOME}/queue-ai"
LOGS="$ROOT/logs"
# shellcheck source=/dev/null
[ -f "$ROOT/config.env" ] && source "$ROOT/config.env"
IMPL_MODEL="${CLAUDE_MODEL:-claude-sonnet-5}"
REVIEW_MODEL="${CLAUDE_REVIEW_MODEL:-claude-opus-4-8}"

# ---- color -----------------------------------------------------------------
USE_COLOR=1
[ -n "${NO_COLOR:-}" ] && USE_COLOR=0
for a in "$@"; do [ "$a" = "--no-color" ] && USE_COLOR=0; done

if [ "$USE_COLOR" = "1" ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RST=$'\033[0m'
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
  BLU=$'\033[34m'; MAG=$'\033[35m'; CYN=$'\033[36m'; GRY=$'\033[90m'
else
  BOLD=""; DIM=""; RST=""; RED=""; GRN=""; YEL=""; BLU=""; MAG=""; CYN=""; GRY=""
fi

# terminal width (fall back to 72)
COLS="${COLUMNS:-0}"
[ "$COLS" -gt 0 ] 2>/dev/null || COLS="$(tput cols 2>/dev/null || echo 72)"
[ "$COLS" -gt 40 ] 2>/dev/null || COLS=72
RULE_W=$((COLS < 78 ? COLS : 78))

rule() { printf '%s' "$GRY"; printf '%.0s─' $(seq 1 "$RULE_W"); printf '%s\n' "$RST"; }

hdr() { # section header
  printf '\n%s%s %s%s\n' "$BOLD" "$BLU" "$1" "$RST"
}

# grep -c always prints a number (0 on no match); its exit 1 is harmless here.
count() { ls -A "$1" 2>/dev/null | grep -c .; }

# ---- header ----------------------------------------------------------------
now="$(date '+%Y-%m-%d %H:%M:%S')"
printf '%s%s  Queue AI%s   %s%s%s\n' "$BOLD" "$CYN" "$RST" "$DIM" "$now" "$RST"
rule

# ---- current activity / phase ----------------------------------------------
nq="$(count "$ROOT/queue")"
nr="$(count "$ROOT/running")"
nd="$(count "$ROOT/done")"
nf="$(count "$ROOT/failed")"

running_job="$(ls -1t "$ROOT/running"/*.job 2>/dev/null | head -1 || true)"
if [ -n "$running_job" ]; then
  rname="$(basename "$running_job" .job)"
  jlog="$(ls -1t "$LOGS/${rname}"-*.log 2>/dev/null | head -1 || true)"

  phase="STARTING"; pcolor="$YEL"; pmodel=""; picon="◔"
  if [ -n "$jlog" ]; then
    marker="$(grep -aE '^(packet:|implement: model=|review: model=|validate:)' "$jlog" 2>/dev/null | tail -1 || true)"
    case "$marker" in
      review:*)    phase="REVIEW";   pcolor="$MAG"; pmodel="$REVIEW_MODEL"; picon="●" ;;
      implement:*) phase="DEV";      pcolor="$CYN"; pmodel="$IMPL_MODEL";   picon="●" ;;
      validate:*)  phase="VALIDATE"; pcolor="$YEL"; pmodel="";              picon="◕" ;;
      packet:*)    phase="PACKET";   pcolor="$YEL"; pmodel="";              picon="◔" ;;
    esac
    # elapsed since the job's start line
    start_iso="$(grep -aE ' start job=' "$jlog" 2>/dev/null | tail -1 | awk '{print $1}')"
    if [ -n "$start_iso" ]; then
      s="$(date -d "$start_iso" +%s 2>/dev/null || echo 0)"
      if [ "$s" -gt 0 ]; then
        e=$(( $(date +%s) - s ))
        if [ "$e" -ge 3600 ]; then elapsed="$((e/3600))h$(( (e%3600)/60 ))m"
        elif [ "$e" -ge 60 ]; then elapsed="$((e/60))m$((e%60))s"
        else elapsed="${e}s"; fi
      fi
    fi
  fi

  printf '  %s%s %-8s%s' "$BOLD$pcolor" "$picon" "$phase" "$RST"
  [ -n "$pmodel" ] && printf ' %s%s%s' "$pcolor" "$pmodel" "$RST"
  printf '   %sjob%s %s' "$DIM" "$RST" "$rname"
  [ -n "${elapsed:-}" ] && printf '   %s⏱ %s%s' "$DIM" "$elapsed" "$RST"
  printf '\n'
  [ "$nq" -gt 0 ] && printf '  %s%s more queued behind it%s\n' "$DIM" "$nq" "$RST"
else
  printf '  %s%s◍ IDLE%s   %sno job in flight%s\n' "$BOLD" "$GRN" "$RST" "$DIM" "$RST"
fi

# ---- summary counts --------------------------------------------------------
printf '\n'
qc="$GRY"; [ "$nq" -gt 0 ] && qc="$YEL"
rc="$GRY"; [ "$nr" -gt 0 ] && rc="$CYN"
fc="$GRY"; [ "$nf" -gt 0 ] && fc="$RED"
printf '  %squeue%s %s%s%s    %srunning%s %s%s%s    %sdone%s %s%s%s    %sfailed%s %s%s%s\n' \
  "$DIM" "$RST" "$qc$BOLD" "$nq" "$RST" \
  "$DIM" "$RST" "$rc$BOLD" "$nr" "$RST" \
  "$DIM" "$RST" "$GRN$BOLD" "$nd" "$RST" \
  "$DIM" "$RST" "$fc$BOLD" "$nf" "$RST"

# ---- listings --------------------------------------------------------------
list_section() {
  local title="$1" dir="$2" color="$3" n
  n="$(count "$dir")"
  hdr "$title ($n)"
  if [ "$n" = "0" ]; then
    printf '  %s(empty)%s\n' "$DIM" "$RST"
    return
  fi
  ls -1t "$dir" 2>/dev/null | head -5 | while IFS= read -r f; do
    printf '  %s•%s %s\n' "$color" "$RST" "$f"
  done
}

list_section "queue (pending)" "$ROOT/queue" "$YEL"
list_section "last done"       "$ROOT/done"  "$GRN"
list_section "last failed"     "$ROOT/failed" "$RED"

# ---- service ---------------------------------------------------------------
hdr "service"
svc_line() { # label  value
  local label="$1" val="$2" c="$GRY"
  case "$val" in
    active) c="$GRN" ;;
    inactive|failed|dead) c="$RED" ;;
    yes) c="$GRN" ;;
    no) c="$YEL" ;;
  esac
  printf '  %-14s %s%s%s\n' "$label" "$c" "$val" "$RST"
}
svc_line "path unit:"     "$(systemctl --user is-active qai-runner.path 2>/dev/null || echo unknown)"
svc_line "drain service:" "$(systemctl --user is-active qai-runner.service 2>/dev/null || echo unknown)"
svc_line "linger:"        "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || echo '?')"
mem="$(cat /sys/power/mem_sleep 2>/dev/null || echo '?')"
memc="$GRY"; [[ "$mem" == *'[deep]'* ]] && memc="$GRN"; [[ "$mem" == *'[s2idle]'* ]] && memc="$YEL"
printf '  %-14s %s%s%s\n' "mem_sleep:" "$memc" "$mem" "$RST"

# ---- last job log ----------------------------------------------------------
hdr "last job log"
latest="$(ls -1t "$LOGS"/*.log 2>/dev/null | head -1 || true)"
if [ -z "$latest" ]; then
  printf '  %s(no logs yet)%s\n' "$DIM" "$RST"
else
  printf '  %sfile%s %s\n' "$DIM" "$RST" "$(basename "$latest")"
  end_line="$(grep -aE ' end ' "$latest" 2>/dev/null | tail -1 || true)"
  [ -n "$end_line" ] && printf '  %s\n' "$end_line"
  pr="$(grep -aoiE 'https://github\.com/[^ ]+/pull/[0-9]+' "$latest" 2>/dev/null | tail -1 || true)"
  [ -n "$pr" ] && printf '  %sPR%s %s%s%s\n' "$DIM" "$RST" "$BLU" "$pr" "$RST"
  printf '  %stail%s\n' "$DIM" "$RST"
  tail -5 "$latest" 2>/dev/null | sed "s/^/    ${DIM}/;s/\$/${RST}/"
fi

# ---- usage ledger ----------------------------------------------------------
hdr "usage ledger (last 3)"
LEDGER="$ROOT/ledger.jsonl"
if [ ! -f "$LEDGER" ] || [ ! -s "$LEDGER" ]; then
  printf '  %s(empty)%s\n' "$DIM" "$RST"
else
  tail -3 "$LEDGER" | while IFS= read -r line; do
    DIM="$DIM" RST="$RST" BOLD="$BOLD" CYN="$CYN" MAG="$MAG" GRN="$GRN" BLU="$BLU" \
    node -e '
      const r=JSON.parse(process.argv[1]);
      const t=r.totals||{}, i=r.implement||{}, v=r.review||{};
      const e=process.env;
      console.log(
        "  " + e.DIM + (r.ts||"?").slice(0,19) + e.RST +
        "  " + e.BOLD + (r.job||"?") + e.RST +
        "  " + e.DIM + "wall" + e.RST + "=" + (t.wall_min ?? "?") + "m" +
        "  " + e.DIM + "est" + e.RST + "=" + e.GRN + "$" + (t.cost_usd_est ?? "?") + e.RST +
        "  " + e.DIM + "dev" + e.RST + "=" + e.CYN + (i.model||"—") + e.RST +
        "  " + e.DIM + "rev" + e.RST + "=" + e.MAG + (v.model||"—") + e.RST +
        (r.pr ? "  " + e.BLU + r.pr + e.RST : "")
      );
    ' "$line" 2>/dev/null || printf '  %s(unparsed row)%s\n' "$DIM" "$RST"
  done
  printf '  %sfull: %s%s\n' "$DIM" "$LEDGER" "$RST"
fi
