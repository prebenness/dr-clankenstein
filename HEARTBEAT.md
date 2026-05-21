# Heartbeat checklist

A heartbeat is a work-continuation trigger, not a status check. The default is to keep advancing useful research until the container ends.

Do not reply `HEARTBEAT_OK` merely because the current command finished, the repo is clean, the process list is empty, the queue is empty, or Slack context is missing.

## Prime directive

On every heartbeat, find the next useful unit of work and do it.

Useful work must be connected to the current research plan, a live instruction from Preben, an unharvested result, an active job, or the construction of the next research plan. Do not fill time with easy experiments or unrelated subtasks just because the allocation is live.

`HEARTBEAT_OK` is a last resort. It is allowed only when all are true:

- Preben explicitly told you to stop or wait, or no useful action remains after orienting from workspace state;
- there is no running, failed, or stale job to inspect;
- there is no active plan, pending queue item, unharvested result, unfinished writeup, or unread instruction from Preben;
- no low-cost useful work remains, including literature review, experiment design, result synthesis, note cleanup, or preparation of the next plan;
- the workspace contains a clear handoff explaining why no further useful action exists.

In normal operation, do not send `HEARTBEAT_OK`.

## Orient

Reconstruct state from the workspace before deciding what to do. Read enough of these to know the active research frame:

1. `AGENTS.md`
2. recent Slack messages from Preben, if available
3. `state/active-jobs.jsonl`, if present
4. `state/next-actions.jsonl`, if present
5. `state/experiment-queue.jsonl`, if present
6. `notes/CURRENT_TASK.md`, if present
7. recent plans, handoffs, notes, logs, and result files under the workspace
8. `dr-clankenstein-runs` git status, recent commits, and relevant open files, if cloned

Missing Slack context or missing optional files is not a blocker. Use the state that exists.

## Work order

Follow this order on each heartbeat.

1. Reconcile active jobs. Check process or session status, logs, output files, and elapsed time. Update `state/active-jobs.jsonl`.
2. Harvest completed results. Interpret them, write down what they mean, commit and push publishable outputs, and record the next action.
3. Handle failed or stale jobs. Diagnose the failure and decide whether to fix, run a smaller sanity check, revise the plan, or ask Preben.
4. Continue the next queued action if it still fits the current plan.
5. If a plan exists but no queue item exists, create the next concrete action from the plan and begin it.
6. If no agreed plan exists, do plan-building work: review literature, map methods, identify baselines, sketch experiments, and prepare a plan for discussion with Preben.
7. If genuinely blocked on Preben, ask a narrow question, record the blocker, and do any non-conflicting useful background work.

Do not launch substantial GPU work from a vague idea alone. First build or recover the plan.

## Anti-drift check

Before launching a new experiment, state why it matters. It should answer a question in the current plan, validate code, reproduce a baseline, test an assumption, or inform a decision.

Do not pivot to easier lower-value work because the hard path is slow, messy, or producing weak results. Diagnose, tighten the experiment, update the plan, or ask Preben whether to change direction.

Do not leave contradictory queues or stale pending items behind. If a queue item is obsolete, mark it obsolete with a short reason.

## Active jobs

Every nontrivial subprocess or run session should be recorded in `state/active-jobs.jsonl` with id, command or task, cwd, log path, purpose, expected duration, and status.

Trust durable workspace state over session-local process memory. Do not launch duplicate jobs just because a process is invisible to the current OpenClaw session.

For GPU checks, use:

```bash
export LD_LIBRARY_PATH=/.singularity.d/libs:${LD_LIBRARY_PATH:-}
nvidia-smi
```

## Reporting

Send Slack messages for meaningful results, blockers, plan changes, or surprising failures. Do not send routine "still running" messages when logs and state already show that.

After producing publishable output, commit and push it to `dr-clankenstein-runs` before claiming completion.

## Plumbing checks

Do not spend heartbeat time debugging OpenClaw plumbing unless there is evidence of a runtime problem: missed wakes, repeated empty turns, stale jobs despite elapsed time, queue warnings, or lost session state.

If there is a runtime problem, inspect OpenClaw logs and session state, preserve the research queue in workspace files, record the diagnosis under `notes/incidents/`, and report the operational blocker to Preben.
