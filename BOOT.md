# Startup State

This file is source-controlled in `dr-clankenstein` and bind-mounted into the agent workspace at runtime.

On startup:

1. Read `AGENTS.md` and `HEARTBEAT.md`.
2. Read `USER.md`.
3. Read `notes/CURRENT_TASK.md`.
4. Read `state/next-actions.jsonl`.
5. Read `state/active-jobs.jsonl` and verify live jobs with `/proc` before assuming anything is running or stopped.
6. Check `dr-clankenstein-runs` status if it is present.

Do not infer the current research direction from this file. Current work should come from Preben's latest instruction, `notes/CURRENT_TASK.md`, `state/next-actions.jsonl`, and the current state of `dr-clankenstein-runs`.

Historical files under `dr-clankenstein-runs/ops/` document incidents and prior handoffs. Treat them as historical unless current workspace state explicitly names one as active.
