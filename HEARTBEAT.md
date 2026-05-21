# Intended Canonical Heartbeat Checklist

This is the intended canonical heartbeat runbook after the 2026-05-20
queue-stall incident. In this container the workspace root `HEARTBEAT.md` is
mounted read-only from the source repo, so the live mitigation is an OpenClaw
config prompt override plus `HEARTBEAT_AUTOPILOT.md`. For the next container,
copy this content into the actual injected workspace `HEARTBEAT.md` if that file
is writable.

## Research Mission Lock

**HOW CAN WE TRAIN A NEURAL NET WITH DISCRETE WEIGHTS - E.G. RATIONAL WEIGHTS - USING SOME FORM OF BACKPROP OR A SCALABLE ADJACENT SCHEME SUCH AS MCMC SAMPLING FROM A BAYESIAN NEURAL NET POSTERIOR?**

**REPLICATING OR EVEN GETTING CLOSE TO LAN ET AL. WITH BACKPROP WOULD BE A GREAT RESULT, BUT IT WILL NOT BE ACHIEVED IN A DAY. IT REQUIRES CAREFUL THINKING, DEEP LITERATURE READING, AND METICULOUS EXPERIMENTAL DESIGN.**

Do not use heartbeat queue pressure to drift into CIFAR/compression, generic
rational-MDL projection, or GA-only work. Next work must be grounded in the
method-selection plan, the discrete-weight backprop survey, and the restart
handoff in `ops/2026-05-20-container-restart-discrete-backprop-mission.md`.

## First Rule

Every heartbeat must end in one of these states:

- useful work is running and recorded in `state/active-jobs.jsonl`;
- a result was harvested, written to `dr-clankenstein-runs`, committed, pushed,
  and the next action was queued;
- a real blocker was reported to Preben in Slack and recorded in
  `state/next-actions.jsonl` as `blocked`.

Do not reply `HEARTBEAT_OK` while `state/next-actions.jsonl` has any `pending`
item or while `notes/CURRENT_TASK.md` names remaining actionable work.

## Required Orientation

On every heartbeat, read these exact workspace-relative files first:

1. `state/active-jobs.jsonl`
2. `state/next-actions.jsonl`
3. `state/experiment-queue.jsonl`
4. `notes/CURRENT_TASK.md`
5. `HEARTBEAT_AUTOPILOT.md`
6. latest `dr-clankenstein-runs` git status and log

Then read these plan anchors before launching or interpreting research work:

1. `dr-clankenstein-runs/2026-05-19-lan-backprop/method-selection-plan.md`
2. `dr-clankenstein-runs/2026-05-19-lane2-discrete-weight-backprop-survey.md`
3. `dr-clankenstein-runs/2026-05-19-lan-backprop/current-status-and-guardrail.md`

## Queue Discipline

`state/next-actions.jsonl` is the live research queue. Keep
`state/experiment-queue.jsonl` either aligned with it or explicitly marked
deprecated; do not leave stale pending items in one queue while another queue
has moved on.

When marking a queue item `done`, add the next `pending` item in the same edit.
If blocked, write the missing decision as a `blocked` queue item and ask Preben
once in Slack.

Current project focus: Lan/Abudy-style rational or discrete-weight
formal-language networks trained with backprop-compatible methods. Do not revive
CIFAR, MNIST compression, generic rational-MDL compression, or old mechanistic
sweeps unless Preben explicitly asks.

## Active Jobs

For every nontrivial subprocess or run session:

- record it in `state/active-jobs.jsonl` with command, cwd, log path, purpose,
  expected duration, PID/session id if available, and `status`;
- reconcile recorded jobs using `/proc/<pid>` when available, not only `ps`;
- check GPU state with:

```bash
export LD_LIBRARY_PATH=/.singularity.d/libs:${LD_LIBRARY_PATH:-}
nvidia-smi
```

For runs longer than a few minutes, prefer OpenClaw `sessions_spawn mode=run`
over detached shell/nohup children.

## Heartbeat Failure Check

If the last substantive artifact or Slack update is more than 40 minutes old:

1. inspect `/home/node/.openclaw/logs/openclaw.log` for heartbeat starts,
   liveness warnings, queue-depth warnings, and `requests-in-flight`;
2. inspect `/home/node/.openclaw/agents/main/sessions/sessions.json` for stale
   `pendingFinalDelivery`, timed-out, or aborted sessions;
3. record the diagnosis under `notes/incidents/`;
4. if the gateway main queue appears wedged, report it in Slack and continue by
   writing persistent handoff/queue files so the next container can recover.

## HEARTBEAT_OK Rules

Reply `HEARTBEAT_OK` only when all are true:

- no running, stuck, or unhandled failed entries exist in
  `state/active-jobs.jsonl`;
- no launched OS process is alive under `/proc/<pid>`;
- GPUs are idle;
- `state/next-actions.jsonl` has no `pending` item;
- `notes/CURRENT_TASK.md` has no actionable next step;
- Slack has no unread principal instruction;
- `dr-clankenstein-runs` is clean and pushed.

If any condition is false, do the work, queue the next action, or report the
blocker. Do not send routine "still running" updates.
