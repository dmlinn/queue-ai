# Host setup (Queue AI runner)

Order matters. Do these on the always-on **host** (or over SSH).

## 0. Prerequisites

- Linux with systemd user units (Fedora/RHEL-family, Debian/Ubuntu, etc.)
- `git`, `curl`, `gh` (GitHub CLI), `claude` (Claude Code CLI)
- Node optional unless your `PREPARE_CMD` / project needs it (see `bootstrap.sh`)

## 1. Land the kit

From the console (after SSH works):

```bash
rsync -av host/ qai:~/queue-ai/
ssh qai 'chmod +x ~/queue-ai/bin/*.sh ~/queue-ai/bootstrap.sh'
cp ~/queue-ai/config.env.example ~/queue-ai/config.env
# edit REPO_DIR, models, etc.
```

## 2. Dedicated repo clone

The runner **hard-resets** its checkout between jobs:

```bash
git clone git@github.com:YOU/YOUR_REPO.git ~/queue-ai/repo
# install project deps as needed
```

Or run `bash ~/queue-ai/bootstrap.sh` after `gh auth login`.

## 3. Auth (subscription, not API key)

```bash
claude setup-token    # or normal claude login — subscription OAuth
gh auth login         # account that can push and open draft PRs
env | grep ANTHROPIC || echo "clean (good)"
```

**Critical:** do not put `ANTHROPIC_API_KEY` in the environment. An API key forces metered billing. The runner also `unset`s it defensively.

```bash
git -C ~/queue-ai/repo config user.name "Your Name"
git -C ~/queue-ai/repo config user.email "you@example.com"
```

## 4. Prevent accidental idle sleep (overnight)

```bash
bash ~/queue-ai/bin/prevent-suspend.sh          # user PowerDevil (KDE)
bash ~/queue-ai/bin/prevent-suspend.sh --system # mask systemd sleep (sudo)
```

For quiet sleep when idle is *desired*, use **deep** sleep (not s2idle):

```bash
cat /sys/power/mem_sleep          # want: s2idle [deep]
echo deep | sudo tee /sys/power/mem_sleep
# permanent (example):
# sudo grubby --update-kernel=DEFAULT --args='mem_sleep_default=deep'
```

## 5. systemd user units

```bash
mkdir -p ~/.config/systemd/user
cp ~/queue-ai/systemd/qai-runner.{path,service} ~/.config/systemd/user/
# edit PATH in the service if node/claude live elsewhere
systemctl --user daemon-reload
systemctl --user enable --now qai-runner.path
loginctl enable-linger "$USER"
```

## 6. Smoke test

From the console:

```bash
qai dispatch smoke main --prompt 'Create or update QAI_SMOKE.md in the repo root with a single line: ok. Touch no other files.'
qai status
qai logs
```

Expect a **draft** PR. Review and merge (or close) manually.

## 7. Remote sleep / wake

```bash
qai sleep --setup   # once: polkit allow suspend without password
qai sleep
qai wake            # magic packet only — not random LAN traffic
```
