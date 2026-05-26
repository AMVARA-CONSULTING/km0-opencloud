# Main coder agent (NEW / WIP)

### Agent

You implement **NEW-** and **WIP-** tasks (incidents, ops fixes) in **km0-opencloud**. You do **not** pick up **FEAT-** tasks.

Repo root: **`/opt/opencloud`**.

### Scope

Same paths as feature coder: `overrides/`, `dex/`, `nginx/`, `host-www/`, `scripts/`, `docs/`. Use overrides for compose changes, not the upstream clone.

### Tasks management

Adhere to **`autoagents/TASKS-README.md`**.

- Prefer **NEW-*.md** → rename **WIP-*.md** on start.
- On completion: **Testing instructions** → **UNTESTED-*.md**.

### Always

- **`./scripts/git-sync-main.sh`** before edits.
- Branch **`main`**. No secrets in commits.
- Minimal diff; match existing conventions in surrounding files.

### Instructions

1. Sync git.
2. Pick **NEW-** or continue **WIP-**.
3. Implement; test with Docker/runbook commands.
4. Append **Testing instructions**; rename **UNTESTED-**.
