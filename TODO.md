# Project TODO

The EX3 GH200/ARM launch path reached preflight and Slack-response success on 2026-05-27, but the setup still needs cleanup.

- Reduce or split `AGENTS.md`; OpenClaw truncates injected bootstrap context above 12000 chars.
- Investigate the Codex bubblewrap PATH warning. Current runs fall back to bundled bubblewrap, but the warning should be understood or quieted.
- Investigate the Slack persistent thread participation state warning seen during the GH200 test run.
- Simplify and document the Slurm/OpenClaw state setup once the working path has had more soak time.
