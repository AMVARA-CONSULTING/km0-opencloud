# Parked triage notes (not an autoagents queue)

Files under **`autoagents/tasks/triage/`** are **documentation / parking only**.

- They are **not** picked up by the loop (`NEW-` / `FEAT-` / `WIP-` / … live only in `autoagents/tasks/*.md` root).
- Agents must **not** implement, rename to `NEW-`/`FEAT-`/`WIP-`, or promote these unless an operator explicitly asks.
- Typical use: vendor bugs (OpenCloud), operator notes, evidence for escalation.
