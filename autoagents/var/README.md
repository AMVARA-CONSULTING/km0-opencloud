# Runtime files (gitignored)

Loop scratch data lives here instead of `/tmp/autoagents-loop/`:

- `loop/001-latest-context.txt` — 001 preflight digest (GitHub issues + Docker heuristics)
- `loop/gh-*-stderr.*` — transient gh stderr during preflight

Override path: `AGENT_LOOP_TMP` (default: `autoagents/var/loop`).
