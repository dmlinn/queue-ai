#!/usr/bin/env bash
# desktop-runner — drain queued jobs serially on the host.
#
# Each ~/desktop-runner/queue/*.job is sourced as shell (use printf %q when writing).
# Required: PROMPT  (or PROMPT_FILE relative to REPO_DIR)
# Optional: BASE (branch), TITLE (PR title fragment), PLAN (label for logs/PRs)
#
# Pipeline: checkout base → optional PREPARE_CMD → Claude implement → commit →
#           Claude review (annotate-only) → optional VALIDATE_CMD → push → draft PR
#
# Usage artifacts:
#   logs/<job>.implement.json | .review.json
#   ledger.jsonl
#
# total_cost_usd in Claude JSON is an API-equivalent estimate, not subscription billing.
set -uo pipefail

ROOT="${HOME}/desktop-runner"
# shellcheck source=/dev/null
[ -f "$ROOT/config.env" ] && source "$ROOT/config.env"

REPO="${REPO_DIR:-$HOME/desktop-runner/repo}"
DEFAULT_BASE="${BASE_BRANCH:-main}"
NTFY_URL="${NTFY_URL:-}"
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-sonnet-5}"
CLAUDE_REVIEW_MODEL="${CLAUDE_REVIEW_MODEL:-claude-opus-4-8}"
CLAUDE_REVIEW="${CLAUDE_REVIEW:-1}"
PREPARE_CMD="${PREPARE_CMD:-}"
VALIDATE_CMD="${VALIDATE_CMD:-}"

QUEUE="$ROOT/queue"; RUNNING="$ROOT/running"; DONE="$ROOT/done"; FAILED="$ROOT/failed"; LOGS="$ROOT/logs"
LEDGER="$ROOT/ledger.jsonl"
mkdir -p "$QUEUE" "$RUNNING" "$DONE" "$FAILED" "$LOGS"

JOB_USAGE_PREFIX=""

unset ANTHROPIC_API_KEY

export PATH="${HOME}/.nvm/versions/node/v20.19.5/bin:${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
# also pick up any default nvm node
if [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
  # shellcheck source=/dev/null
  . "${NVM_DIR:-$HOME/.nvm}/nvm.sh" 2>/dev/null || true
fi

notify() {
  [ -n "$NTFY_URL" ] || return 0
  curl -fsS -H "Title: $1" -d "$2" "$NTFY_URL" >/dev/null 2>&1 || true
}

run_claude() {
  local model="$1"; shift
  local prompt="$1"; shift
  local role="$1"; shift
  local -a args=(-p "$prompt" --dangerously-skip-permissions --output-format json)
  [ -n "$model" ] && args+=(--model "$model")
  args+=("$@")

  local raw rc=0
  raw="$(claude "${args[@]}")" || rc=$?

  if [ -n "${JOB_USAGE_PREFIX:-}" ]; then
    printf '%s\n' "$raw" >"${JOB_USAGE_PREFIX}.${role}.json"
  fi

  if [ "$rc" -ne 0 ]; then
    echo "claude ${role} failed rc=${rc}" >&2
    [ -n "$raw" ] && printf '%s\n' "$raw" | head -c 4000 >&2
    return "$rc"
  fi

  node -e '
    const fs = require("fs");
    const role = process.argv[1];
    const raw = fs.readFileSync(0, "utf8");
    let j;
    try { j = JSON.parse(raw); } catch {
      process.stdout.write(raw);
      process.exit(0);
    }
    const u = j.usage || {};
    const models = Object.keys(j.modelUsage || {});
    const ms = j.duration_ms ?? j.duration_api_ms ?? "?";
    const cost = j.total_cost_usd;
    const costS = (typeof cost === "number") ? cost.toFixed(4) : "?";
    const wallMin = (typeof j.duration_ms === "number")
      ? (j.duration_ms / 60000).toFixed(2) : "?";
    console.error(
      `usage[${role}]: models=${models.join(",") || "?"} ` +
      `wall_min=${wallMin} wall_ms=${ms} api_ms=${j.duration_api_ms ?? "?"} ` +
      `cost_usd_est=${costS} in=${u.input_tokens ?? "?"} out=${u.output_tokens ?? "?"}`
    );
    process.stdout.write(j.result != null ? String(j.result) : raw);
  ' "$role" <<<"$raw"
}

usage_markdown() {
  local prefix="$1"
  node -e '
    const fs = require("fs");
    const prefix = process.argv[1];
    function load(role) {
      const p = prefix + "." + role + ".json";
      if (!fs.existsSync(p)) return null;
      try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return null; }
    }
    function row(label, j) {
      if (!j) return `| ${label} | — | — | — | — | — |`;
      const u = j.usage || {};
      const model = Object.keys(j.modelUsage || {})[0] || "?";
      const wallMin = (typeof j.duration_ms === "number")
        ? (j.duration_ms / 60000).toFixed(2) : "?";
      const cost = (typeof j.total_cost_usd === "number")
        ? "$" + j.total_cost_usd.toFixed(4) : "?";
      return `| ${label} | \`${model}\` | ${wallMin} | ${cost} | ${u.input_tokens ?? "?"} | ${u.output_tokens ?? "?"} |`;
    }
    const impl = load("implement");
    const rev = load("review");
    let totalCost = 0, totalMs = 0, n = 0;
    for (const j of [impl, rev]) {
      if (!j) continue;
      n++;
      if (typeof j.total_cost_usd === "number") totalCost += j.total_cost_usd;
      if (typeof j.duration_ms === "number") totalMs += j.duration_ms;
    }
    const totalMin = n ? (totalMs / 60000).toFixed(2) : "—";
    const totalCostS = n ? "$" + totalCost.toFixed(4) : "—";
    process.stdout.write([
      "### Usage (API-equivalent estimate — not subscription invoice)",
      "",
      "| Pass | Model | Wall min | Est. cost | Input tok | Output tok |",
      "|------|-------|----------|-----------|-----------|------------|",
      row("Implement", impl),
      row("Review", rev),
      `| **Total** | | **${totalMin}** | **${totalCostS}** | | |`,
      "",
    ].join("\n"));
  ' "$prefix"
}

append_ledger() {
  local label="$1" rc="$2" pr="$3" prefix="$4"
  node -e '
    const fs = require("fs");
    const [label, rcS, pr, prefix, ledgerPath] = process.argv.slice(1);
    const rc = Number(rcS);
    function load(role) {
      const p = prefix + "." + role + ".json";
      if (!fs.existsSync(p)) return null;
      try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return null; }
    }
    function slice(j, role) {
      if (!j) return null;
      const u = j.usage || {};
      const models = j.modelUsage || {};
      return {
        role,
        model: Object.keys(models)[0] || null,
        duration_ms: j.duration_ms ?? null,
        duration_api_ms: j.duration_api_ms ?? null,
        wall_min: typeof j.duration_ms === "number" ? Math.round(j.duration_ms / 600) / 100 : null,
        total_cost_usd_est: j.total_cost_usd ?? null,
        input_tokens: u.input_tokens ?? null,
        output_tokens: u.output_tokens ?? null,
        modelUsage: models,
      };
    }
    const implement = slice(load("implement"), "implement");
    const review = slice(load("review"), "review");
    let cost = 0, wall = 0;
    for (const p of [implement, review]) {
      if (!p) continue;
      if (typeof p.total_cost_usd_est === "number") cost += p.total_cost_usd_est;
      if (typeof p.duration_ms === "number") wall += p.duration_ms;
    }
    const row = {
      ts: new Date().toISOString(),
      job: label,
      rc,
      pr: pr || null,
      implement,
      review,
      totals: {
        wall_ms: wall,
        wall_min: Math.round(wall / 600) / 100,
        cost_usd_est: Math.round(cost * 1e6) / 1e6,
      },
    };
    fs.appendFileSync(ledgerPath, JSON.stringify(row) + "\n");
    console.log(
      "ledger: job=" + label +
      " wall_min=" + row.totals.wall_min +
      " cost_usd_est=" + row.totals.cost_usd_est +
      " pr=" + (pr || "—")
    );
  ' "$label" "$rc" "${pr:-}" "$prefix" "$LEDGER"
}

run_review() {
  local base="$1" out_file="$2"
  local diff_block review_prompt
  diff_block="$(git diff "origin/${base}...HEAD" 2>/dev/null | head -c 200000)"
  if [ -z "$diff_block" ]; then
    diff_block="$(git show --stat --patch --format=fuller HEAD | head -c 200000)"
  fi

  review_prompt="$(cat <<EOF
You are a senior code reviewer for an automated runner. ANNOTATE ONLY.

Do NOT edit, create, delete, or rename any files.
Do NOT run git commit, git push, or open a PR.
Do NOT implement fixes — only review.

--- git diff origin/${base}...HEAD (may be truncated) ---
${diff_block}
--- end diff ---

Respond in GitHub-flavored markdown with exactly these sections:

## Verdict
One of: **ship-as-draft** | **needs-human** | **blocking**

## Summary
2–5 sentences on what changed and quality.

## Blocking
Bullet list, or "None."

## Non-blocking
Bullet list, or "None."

## Scope
Any unexpected files or risky surfaces?
EOF
)"

  echo "review: model=${CLAUDE_REVIEW_MODEL} (annotate-only)"
  if ! run_claude "$CLAUDE_REVIEW_MODEL" "$review_prompt" review \
      --disallowedTools "Edit" "Write" "NotebookEdit" "MultiEdit" \
      >"$out_file" 2>"${out_file}.err"; then
    {
      echo "## Verdict"
      echo "**needs-human**"
      echo
      echo "## Summary"
      echo "Automated review pass failed."
      echo
      echo "## Blocking"
      echo "None."
      echo
      echo "## Non-blocking"
      echo "None."
      echo
      echo "## Scope"
      echo "Reviewer did not complete."
    } >"$out_file"
    cat "${out_file}.err" >&2 2>/dev/null || true
    return 0
  fi
  [ -s "${out_file}.err" ] && cat "${out_file}.err" >&2 || true
  if [ -n "$(git status --porcelain)" ]; then
    echo "review: discarding unexpected working-tree changes" >&2
    git checkout -- . >/dev/null 2>&1 || true
    git clean -fd >/dev/null 2>&1 || true
  fi
  return 0
}

# Return: 0 PR+ok, 2 no changes, 3 PR but validate failed, 1 hard fail
process_job() {
  local LABEL="$1" BASE="$2" branch="$3" PROMPT_TEXT="$4" TITLE_FRAG="$5"
  cd "$REPO" || return 1
  if [ -z "$(git config user.email 2>/dev/null)" ]; then
    echo "git user.email unset in $REPO" >&2
    return 1
  fi
  git fetch origin --prune || return 1
  git checkout -B "$branch" "origin/${BASE}" || return 1
  git reset --hard "origin/${BASE}" || return 1
  git clean -fd || return 1

  if [ -n "$PREPARE_CMD" ]; then
    echo "prepare: $PREPARE_CMD"
    bash -lc "$PREPARE_CMD" || return 1
  fi

  local prompt
  prompt="$(cat <<EOF
${PROMPT_TEXT}

---
Make only the file changes required. Stay minimal.
Do NOT run git commit, git push, or open a PR — the runner handles git.
EOF
)"

  echo "implement: model=${CLAUDE_MODEL:-<default>}"
  run_claude "$CLAUDE_MODEL" "$prompt" implement || return 1

  [ -n "$(git status --porcelain)" ] || return 2

  git add -A || return 1
  git commit -m "auto(${LABEL}): desktop-runner" \
    -m "Implement-Model: ${CLAUDE_MODEL:-default}" || return 1

  local review_file review_body review_note usage_block
  review_file="$(mktemp "${TMPDIR:-/tmp}/desktop-runner-review.XXXXXX.md")"
  review_body=""
  review_note="skipped"
  if [ "$CLAUDE_REVIEW" = "1" ] && [ -n "$CLAUDE_REVIEW_MODEL" ]; then
    run_review "$BASE" "$review_file" || true
    review_body="$(cat "$review_file" 2>/dev/null || true)"
    review_note="model=${CLAUDE_REVIEW_MODEL}"
  else
    review_body="## Verdict
**needs-human**

## Summary
Review pass disabled.

## Blocking
None.

## Non-blocking
None.

## Scope
Not reviewed."
    review_note="disabled"
  fi
  rm -f "$review_file" "${review_file}.err" 2>/dev/null || true
  rm -f "${review_file}.err" 2>/dev/null || true

  usage_block=""
  [ -n "${JOB_USAGE_PREFIX:-}" ] && usage_block="$(usage_markdown "$JOB_USAGE_PREFIX" 2>/dev/null || true)"

  local conf="pass"
  if [ -n "$VALIDATE_CMD" ]; then
    echo "validate: $VALIDATE_CMD"
    bash -lc "$VALIDATE_CMD" || conf="FAIL"
  fi

  git push -u origin "$branch" || return 1

  local title
  if [ -n "$TITLE_FRAG" ]; then
    title="$TITLE_FRAG"
  else
    title="auto(${LABEL}): desktop-runner"
  fi
  [ "$conf" = "pass" ] || title="${title} [validate FAIL]"

  local pr_body
  pr_body="$(cat <<EOF
Automated **draft** from desktop-runner.

| Field | Value |
|-------|-------|
| Job | \`${LABEL}\` |
| Base | \`${BASE}\` |
| Implement | \`${CLAUDE_MODEL:-cli-default}\` |
| Review | \`${review_note}\` |
| Validate | **${conf}** |

Human gate: review and merge manually. Nothing auto-merges.

${usage_block}

---

${review_body}
EOF
)"

  gh pr create --draft --base "$BASE" --head "$branch" --title "$title" \
    --body "$pr_body" || return 1

  [ "$conf" = "pass" ] || return 3
  return 0
}

shopt -s nullglob
for job in "$QUEUE"/*.job; do
  name="$(basename "$job" .job)"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  logf="$LOGS/${name}-${ts}.log"
  JOB_USAGE_PREFIX="$LOGS/${name}-${ts}"
  mv "$job" "$RUNNING/${name}.job"; job="$RUNNING/${name}.job"

  PLAN=""; PROMPT=""; PROMPT_FILE=""; BASE="$DEFAULT_BASE"; TITLE=""
  # shellcheck source=/dev/null
  source "$job"
  local_label="${PLAN:-$name}"
  [ -n "$PROMPT" ] || {
    if [ -n "${PROMPT_FILE:-}" ] && [ -f "$REPO/$PROMPT_FILE" ]; then
      PROMPT="$(cat "$REPO/$PROMPT_FILE")"
    fi
  }
  if [ -z "${PROMPT:-}" ]; then
    echo "$(date -u +%FT%TZ) FAIL no PROMPT or PROMPT_FILE in job" >>"$logf"
    mv "$job" "$FAILED/${name}.job"
    continue
  fi

  branch="auto/${local_label}-${ts}"
  # sanitize branch name lightly
  branch="$(echo "$branch" | tr -c 'A-Za-z0-9._/-' '-' | sed 's/--*/-/g')"

  echo "$(date -u +%FT%TZ) start job=$local_label base=$BASE branch=$branch" >>"$logf"
  process_job "$local_label" "$BASE" "$branch" "$PROMPT" "$TITLE" >>"$logf" 2>&1
  rc=$?
  url="$(grep -oiE 'https://github\.com/[^ ]+/pull/[0-9]+' "$logf" | tail -n1)"

  append_ledger "$local_label" "$rc" "${url:-}" "$JOB_USAGE_PREFIX" >>"$logf" 2>&1 || true

  case "$rc" in
    0) mv "$job" "$DONE/${name}.job";   notify "runner OK ${local_label}" "draft PR: ${url}";;
    2) mv "$job" "$DONE/${name}.job";   notify "runner -- ${local_label}" "no changes";;
    3) mv "$job" "$FAILED/${name}.job"; notify "runner WARN ${local_label}" "validate failed; PR: ${url}";;
    *) mv "$job" "$FAILED/${name}.job"; notify "runner FAIL ${local_label}" "rc=$rc log=$logf";;
  esac

  cd "$REPO" && git checkout "$DEFAULT_BASE" >/dev/null 2>&1 || true
  echo "$(date -u +%FT%TZ) end job=$local_label rc=$rc" >>"$logf"
done
