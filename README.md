# Queue AI

Console CLI + always-on Linux **host** that runs **headless [Claude Code](https://claude.com/claude-code)** from a job queue (overnight or while you work), then opens a **draft pull request** for review.

```
console:  qai dispatch …   --ssh-->   host queue (~/queue-ai/queue/*.job)
host:     systemd path unit --> runner drains serially:
            git branch → Claude implement → Claude review (annotate-only)
            → commit → push → gh pr create --draft
console:  qai status / logs / usage / sleep / wake
```

Nothing auto-merges. The draft PR is the human gate.

## Why

- Use a **flat Claude subscription** on a machine you already leave on (or Wake-on-LAN).
- **Two-pass models**: cheaper implement + stronger annotate-only review.
- **Git is the queue** — no second backlog system.
- Serial jobs stay under subscription rate limits.

## Layout

```
console/bin/qai                 # CLI — type `qai` for help
console/bin/qai-completion.bash
console/ssh_config.snippet
host/                           # lands at ~/queue-ai on the runner host
  bootstrap.sh
  config.env.example
  SETUP.md
  bin/runner.sh
  bin/status.sh
  bin/prevent-suspend.sh
  systemd/qai-runner.{path,service}
```

## Terminology

| Term | Meaning |
|------|---------|
| **Host** | Always-on Linux machine (queue, Claude, draft PRs) |
| **Console** | Machine where you run `qai` (laptop, workstation, …) |
| **`qai`** | CLI command |

## Quick start

### Console

```bash
cp console/bin/qai ~/bin/
chmod +x ~/bin/qai
# optional tab completion
echo 'source /path/to/queue-ai/console/bin/qai-completion.bash' >> ~/.zshrc

# SSH: copy console/ssh_config.snippet into ~/.ssh/config and fill in HostName / User / key
ssh qai 'echo ok'
```

### Host

See [host/SETUP.md](host/SETUP.md). Summary:

1. Copy `host/` → `~/queue-ai/`
2. Authenticate `claude` on a **subscription** (do **not** set `ANTHROPIC_API_KEY`)
3. `gh auth login` + `bash ~/queue-ai/bootstrap.sh`
4. Enable user systemd units + linger
5. Optional: `qai sleep --setup` once for passwordless remote suspend

### Queue a job

```bash
qai dispatch fix-typos main --prompt 'Fix obvious typos in README.md only. Touch no other files.'
```

Or:

```bash
qai dispatch fix-typos main <<'EOF'
PROMPT=Fix obvious typos in README.md only. Touch no other files.
EOF
```

Watch:

```bash
qai status
qai logs
qai usage --sum
```

## Power

| Command | Purpose |
|---------|---------|
| `qai sleep` | Suspend host (prefer kernel **deep** sleep, not s2idle) |
| `qai wake` | Magic-packet Wake-on-LAN |
| `qai doctor` | SSH, sleep mode, runner, GPU snapshot |

Fans spinning while “asleep” usually means `mem_sleep` is `s2idle`. Prefer `deep` (see SETUP.md).

Set WoL before wake:

```bash
export QAI_MAC='aa:bb:cc:dd:ee:ff'
export QAI_BCAST='255.255.255.255'   # optional; use your LAN broadcast if needed
```


## Usage ledger

Each Claude pass uses `--output-format json`. The host appends rows to `~/queue-ai/ledger.jsonl` with wall minutes, tokens, and **API-equivalent** cost estimates (relative efficiency, not subscription billing).

```bash
qai usage
qai usage --sum
```

## Security notes

- Never commit API keys, OAuth tokens, or `~/.claude` credentials.
- `config.env` is local to the host; only `config.env.example` is in git.
- Draft PRs use whatever `gh` account is logged in on the host.
- Review pass denies write tools and discards unexpected dirty trees.

## License

MIT
