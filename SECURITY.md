# Security

## What this project never stores in git

- Claude / Anthropic OAuth tokens or API keys
- GitHub tokens (`gh` keyring on the host only)
- `host/config.env` (local only; use `config.env.example`)
- `ledger.jsonl` and runner logs
- Private SSH keys

## Host hardening checklist

1. Do **not** export `ANTHROPIC_API_KEY` on the runner host (forces metered API billing and is a secret).
2. Use a dedicated SSH key for console → host; `IdentitiesOnly yes` in SSH config.
3. Runner clone is hard-reset between jobs — never put secrets only in that working tree.
4. Draft PRs use the `gh` identity on the host; treat that account as production.
5. Review pass is annotate-only; still read every draft PR before merge.

## Reporting

Open a private security advisory on the GitHub repo if you find a vulnerability.
