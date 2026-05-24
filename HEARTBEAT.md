# Heartbeat checklist

A heartbeat is a work-continuation trigger, not a status check. The default is to keep advancing useful research until the container ends.

Do not reply `HEARTBEAT_OK` merely because the current command finished, the repo is clean, the process list is empty, the queue is empty, or Slack context is missing.

## Prime directive

On every heartbeat, find the next useful unit of work and do it.

Useful work must advance one of:

- the current research frame;
- a live instruction from Preben;
- an approved experiment ticket;
- an active or stale job;
- an unharvested result;
- a claim ledger;
- a result audit;
- the construction of the next research frame.

Do not fill time with easy experiments, unrelated subtasks, generic code cleanup, or broad sweeps just because the allocation is live.

`HEARTBEAT_OK` is a last resort. It is allowed only when all are true:

- Preben explicitly told you to stop or wait, or no useful action remains after orienting from workspace state;
- there is no running, failed, or stale job to inspect;
- there is no active research frame, pending action, experiment ticket, unharvested result, unresolved claim, unfinished audit, unfinished writeup, or unread instruction from Preben;
- no low-cost useful work remains, including literature review, experiment design, claim audit, result synthesis, note cleanup, or preparation of the next research frame;
- the workspace contains a clear handoff explaining why no further useful action exists.

In normal operation, do not send `HEARTBEAT_OK`.

## Orient

Reconstruct state from the workspace before deciding what to do. Read enough of these to know the active research frame:

1. `AGENTS.md`
2. recent Slack messages from Preben, if available
3. `notes/CURRENT_RESEARCH_FRAME.md`, if present
4. `claims.json`, if present
5. `state/slurm-job.json`, if present
6. `state/active-jobs.jsonl`, if present
7. `state/experiment-queue.jsonl`, if present
8. `state/next-actions.jsonl`, if present
9. `notes/CURRENT_TASK.md`, if present
10. recent plans, handoffs, notes, logs, metrics, audits, and result files under the workspace
11. `dr-clankenstein-runs` git status, recent commits, and relevant open files, if cloned

Missing Slack context or missing optional files is not a blocker. Use the durable state that exists.

## Slurm time budget

Read `state/slurm-job.json` if present. Use `ends_at_epoch` or `ends_at` to estimate remaining wall time.

When there is not enough wall time left for the next planned run plus result harvesting and handoff, stop launching long work. Prefer to:

- harvest completed or partial results;
- update active jobs and claim verdicts;
- commit and push useful outputs;
- write a handoff with current state, blockers, and next actions.

If the end time is missing or unclear, fall back to the job start note and visible Slurm or log state. Do not assume unlimited time.

## Work order

Follow this order on each heartbeat.

1. Reconcile active jobs. Check process or session status, logs, output files, elapsed time, and linked experiment tickets. Update `state/active-jobs.jsonl`.
2. Harvest completed results. Parse metrics, read logs, compare against the ticket, update claim verdicts, write interpretation, and commit/push publishable outputs.
3. Handle failed or stale jobs. Diagnose the failure and decide whether to fix, run a smaller sanity check, revise the ticket, mark the claim inconclusive, or ask Preben.
4. Continue the next approved experiment ticket if it still fits the current research frame.
5. If a research frame exists but no ticket exists, create the next concrete ticket from the frame and start it only if it is low-risk or already implied by the agreed plan.
6. If no agreed frame exists, do plan-building work: review literature, map methods, identify baselines, formulate claims, sketch experiments, and prepare a frame for discussion with Preben.
7. If a result summary or paper-facing note is pending, perform the audit before writing claims.
8. If genuinely blocked on Preben, ask a narrow question, record the blocker, and do any non-conflicting useful background work.

Do not launch substantial GPU work from a vague idea alone. First build or recover the research frame and experiment ticket.

## Research frame check

Before starting new work, identify the active frame:

- scientific question;
- target contribution;
- methods or approaches under consideration;
- baselines;
- claims or hypotheses;
- evidence needed;
- current next action.

If you cannot identify these from workspace state, your next useful work is to reconstruct or draft the frame, not to launch experiments.

## Claim check

Before launching or continuing an experiment, identify the linked claim, question, baseline reproduction, or diagnostic purpose.

Before reporting a result, update the claim ledger:

- `supported` only when evidence is direct and sufficient;
- `refuted` when evidence points against the claim;
- `inconclusive` when evidence is missing, weak, underpowered, partial, or contradictory;
- `blocked` when a missing dependency, access issue, runtime problem, or Preben decision prevents progress.

Do not make paper-facing claims from memory. Point to metrics, logs, configs, figures, or notes.

## Experiment ticket check

Every nontrivial run should have a ticket in `state/experiment-queue.jsonl` or the current equivalent. Before launching, confirm the ticket records:

- purpose;
- linked claim ids;
- method, baseline, and ablation coverage;
- dataset or data-generating process;
- metrics;
- seeds, folds, repetitions, or resamples;
- command or script path;
- expected runtime and GPU needs;
- success and failure criteria;
- output paths.

If the ticket is obsolete, mark it obsolete with a reason. Do not leave contradictory pending items behind.

## Anti-drift check

Before launching a new experiment, state why it matters. It should answer a question in the current frame, validate code, reproduce a baseline, test an assumption, support or refute a claim, or inform a decision.

Do not pivot to easier lower-value work because the hard path is slow, messy, or producing weak results. Diagnose, tighten the experiment, update the frame, or ask Preben whether to change direction.

Before a substantial pivot, write a pivot note with:

- original plan item;
- failure or change observed;
- evidence;
- proposed new direction;
- why it remains valuable;
- what is being abandoned.

Ask Preben before expensive or directional pivots. Tactical fixes inside an agreed plan can proceed.

## Result audit

Before writing a paper-facing result summary, audit the evidence:

- Did the code implement the named method?
- Were baselines, ablations, datasets, and seeds actually run?
- Do reported numbers exist in metrics files, logs, or result tables?
- Do claim verdicts match the data?
- Are failures and missing conditions counted?
- Are limitations explicit?
- Is the evidence strong enough for the claim?

If the audit fails, write the limitation and next action. Do not turn weak evidence into strong prose.

## Active jobs

Every nontrivial subprocess or run session should be recorded in `state/active-jobs.jsonl` with id, command or task, cwd, log path, purpose, linked ticket or claim id, expected duration, and status.

Trust durable workspace state over session-local process memory. Do not launch duplicate jobs just because a process is invisible to the current OpenClaw session.

For GPU checks, use:

```bash
export LD_LIBRARY_PATH=/.singularity.d/libs:${LD_LIBRARY_PATH:-}
nvidia-smi
```

## Reporting

Send Slack messages for meaningful results, blockers, plan changes, proposed pivots, surprising failures, or artifacts ready for Preben to inspect.

Slack messages should be short and decision-oriented:

- what was found;
- what it implies;
- what you are doing next;
- relevant path, commit, run id, or log.

Do not send routine "still running" messages when logs and state already show that.

After producing publishable output, commit and push it to `dr-clankenstein-runs` before claiming completion.

## Plumbing checks

Do not spend heartbeat time debugging OpenClaw plumbing unless there is evidence of a runtime problem: missed wakes, repeated empty turns, stale jobs despite elapsed time, queue warnings, or lost session state.

If there is a runtime problem, inspect OpenClaw logs and session state, preserve the research queue in workspace files, record the diagnosis under `notes/incidents/`, and report the operational blocker to Preben.
