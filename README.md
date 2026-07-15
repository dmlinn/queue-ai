# desktop-runner

Laptop cockpit + always-on Linux host that runs **headless [Claude Code](https://claude.com/claude-code)** overnight (or while you’re at work), then opens a **draft pull request** for you to review.

```
laptop:  desktop dispatch …   --ssh-->   host queue (~/desktop-runner/queue/*.job)
host:    systemd path unit --> runner drains serially:
           git branch → Claude implement → Claude review (annotate-only)
           → commit → push → gh pr create --draft
laptop:  desktop status / logs / usage / sleep / wake
```

Nothing auto-merges. The draft PR is the human gate.

## Why

- Use a **flat Claude subscription** on a machine you already leave on (or Wake-on-LAN).
- **Two-pass models**: cheaper implement + stronger annotate-only review (rate-limit / quality tradeoff).
- **Git is the queue** — no second backlog system.
- Serial jobs stay under subscription rate limits.

## Layout

```
laptop/bin/desktop          # single CLI (type `desktop` for help)
laptop/bin/desktop-completion.bash
laptop/ssh_config.snippet
host/                       # lands at ~/desktop-runner on the Linux box
  bootstrap.sh
  config.env.example
  SETUP.md
  bin/runner.sh
  bin/status.sh
  bin/prevent-suspend.sh
  systemd/*.path | *.service
```

## Quick start

### Laptop

```bash
cp laptop/bin/desktop ~/bin/
chmod +x ~/bin/desktop
# optional tab completion
echo 'source /path/to/desktop-runner/laptop/bin/desktop-completion.bash' >> ~/.zshrc

# SSH: copy laptop/ssh_config.snippet into ~/.ssh/config and fill in HostName / User / key
ssh desktop 'echo ok'
```

### Host (always-on Linux)

See [host/SETUP.md](host/SETUP.md). Summary:

1. Copy `host/` → `~/desktop-runner/`
2. `claude` authenticated on a **subscription** token (do **not** set `ANTHROPIC_API_KEY`)
3. `gh auth login` + `bash ~/desktop-runner/bootstrap.sh`
4. Enable user systemd path unit + linger
5. Optional: `desktop sleep --setup` once for passwordless remote suspend

### Queue a job

Jobs are simple env files. Minimal example:

```bash
desktop dispatch fix-typos main <<'EOF'
PROMPT=In this repo, fix obvious typos in README.md only. Do not change code.
EOF
```

Or use a prompt file already in the runner clone:

```bash
desktop dispatch my-task main --prompt-file docs/tasks/my-task.md
```

Watch:

```bash
desktop status
desktop logs
desktop usage --sum
```

## Power

| Command | Purpose |
|---------|---------|
| `desktop sleep` | Suspend host (prefer kernel **deep** sleep, not s2idle) |
| `desktop wake` | Magic-packet Wake-on-LAN |
| `desktop doctor` | SSH, sleep mode, runner, GPU snapshot |

Fans spinning while “asleep” usually means `mem_sleep` is `s2idle`. Prefer `deep` (see SETUP.md).

## Usage ledger

Each Claude pass uses `--output-format json`. The host appends rows to `~/desktop-runner/ledger.jsonl` with wall minutes, tokens, and **API-equivalent** cost estimates. That `$` is a relative efficiency signal, not subscription billing.

```bash
desktop usage
desktop usage --sum
```

## Security notes

- Never commit API keys, OAuth tokens, or `~/.claude` credentials.
- `config.env` is local to the host; only `config.env.example` is in git.
- Draft PRs use whatever `gh` account is logged in on the host — treat that identity as production.
- Review pass denies write tools and discards unexpected dirty trees.

## License

MIT
