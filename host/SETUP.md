# Host setup (Linux runner)

Order matters. Do these on the always-on box (or over SSH).

## 0. Prerequisites

- Linux with systemd user units (Fedora, Nobara, Ubuntu, etc.)
- `git`, `curl`, `gh` (GitHub CLI), `claude` (Claude Code CLI)
- Node optional unless your `PREPARE_CMD` / project needs it (see `bootstrap.sh`)

## 1. Land the kit

From the laptop (after SSH works):

```bash
rsync -av host/ desktop:~/desktop-runner/
ssh desktop 'chmod +x ~/desktop-runner/bin/*.sh ~/desktop-runner/bootstrap.sh'
cp ~/desktop-runner/config.env.example ~/desktop-runner/config.env
# edit REPO_DIR, models, etc.
```

## 2. Dedicated repo clone

The runner **hard-resets** its checkout between jobs:

```bash
git clone git@github.com:YOU/YOUR_REPO.git ~/desktop-runner/repo
# install project deps as needed
```

Or run `bash ~/desktop-runner/bootstrap.sh` after `gh auth login` (clones if missing, enables linger).

## 3. Auth (subscription, not API key)

```bash
claude setup-token    # or normal claude login — subscription OAuth
gh auth login         # account that can push and open draft PRs
env | grep ANTHROPIC || echo "clean (good)"
```

**Critical:** do not put `ANTHROPIC_API_KEY` in the environment. An API key forces metered billing. The runner also `unset`s it defensively.

Set git author on the runner clone only:

```bash
git -C ~/desktop-runner/repo config user.name "Your Name"
git -C ~/desktop-runner/repo config user.email "you@example.com"
```

## 4. Prevent accidental idle sleep (overnight)

```bash
bash ~/desktop-runner/bin/prevent-suspend.sh          # user PowerDevil (KDE)
bash ~/desktop-runner/bin/prevent-suspend.sh --system # mask systemd sleep (sudo)
```

For quiet sleep when idle is *desired*, use **deep** sleep (not s2idle):

```bash
cat /sys/power/mem_sleep          # want: s2idle [deep]
# session:
echo deep | sudo tee /sys/power/mem_sleep
# permanent (example):
# sudo grubby --update-kernel=DEFAULT --args='mem_sleep_default=deep'
```

## 5. systemd user units

```bash
mkdir -p ~/.config/systemd/user
cp ~/desktop-runner/systemd/desktop-runner.{path,service} ~/.config/systemd/user/
# edit PATH in the service if your node/claude live elsewhere
systemctl --user daemon-reload
systemctl --user enable --now desktop-runner.path
loginctl enable-linger "$USER"   # fire with no graphical login
```

## 6. Smoke test

From the laptop:

```bash
desktop dispatch smoke main <<'EOF'
PROMPT=Create or update a file named DESKTOP_RUNNER_SMOKE.md in the repo root with a single line: ok. Do not change any other files.
EOF
desktop status
desktop logs
```

Expect a **draft** PR. Review and merge (or close) manually.

## 7. Remote sleep / wake

```bash
desktop sleep --setup   # once: polkit allow suspend without password
desktop sleep
desktop wake            # magic packet only — not random LAN traffic
```
