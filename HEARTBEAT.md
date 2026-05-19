# Heartbeat checklist

Every heartbeat, work through this in order:

1. Read `workspace/state/active-jobs.jsonl` (or `workspace/state/active-jobs.json` if you prefer one-file form). This is the canonical record of long-running subprocesses you have launched. If the file does not exist, create it next time you launch a job.

2. For each entry in active-jobs, verify the process is still alive (`ps -p <pid>` or `kill -0 <pid>`), inspect its current state (most recent lines of its log file, GPU utilisation if relevant), and decide whether it is: progressing normally, finished cleanly, failed, or stuck. Record an updated status back in active-jobs.

3. For every job that is failed or stuck: kill it, write a one-line incident summary to `workspace/notes/incidents/<date>-<jobname>.md`, and queue the next sensible action (retry with different parameters, escalate to Slack, mark blocked).

4. Check the Slack channel (`#dr-clankenstein`) for new messages from the principal. Their instructions override anything else in flight.

5. Check `workspace/notes/` for active plans. If GPUs are idle and the latest plan has work remaining, launch the next experiment.

6. Reply with a short progress summary to Slack only if there is something substantive (new failure, milestone hit, blocker, idle GPU with nothing queued). Otherwise stay quiet.

**HEARTBEAT_OK rules:**

Reply `HEARTBEAT_OK` ONLY when every one of the following is true:

- `workspace/state/active-jobs.jsonl` is empty or every entry is marked done.
- No OS-level processes you launched are still running (`ps`/`kill -0` confirm).
- GPUs are idle and no plan has next steps queued.
- Slack has no unread messages from the principal.
- The runs repo is clean and pushed.

If any one of those is false, do not `HEARTBEAT_OK`. Do the work or post a status. Routine "nothing to do" replies waste tokens; one-line "still running, no change" replies are also unnecessary — only post when there is signal.

**If something is unclear:**

First check `workspace/notes/` (active plans), `workspace/state/` (running jobs and recent decisions), `dr-clankenstein-runs` git history (recent commits), and any `thread-dump-*.md` in `workspace/notes/`. Ask the principal in Slack only after those four sources have been checked and the next action genuinely cannot be inferred. Missing Slack history is not by itself a blocker if workspace state shows an active plan; continue the plan.
