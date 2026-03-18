# openclaw scripts

This folder contains the main scripts for the agent workflow.

The most important files are:

- `setup-project-agents.sh`: creates or refreshes the agents
- `dispatch-agent.sh`: sends work to any configured agent
- `dispatch-primary.sh` and `dispatch-secondary.sh`: easy manual commands for the starter pair
- `supervisor.sh`: decides whether to send work
- `heartbeat-loop.sh`: repeats the check every few minutes
- `start-supervisor-tmux.sh`, `stop-supervisor-tmux.sh`, `supervisor-status.sh`: start, stop, and inspect the loop
- `session-costs.sh` / `session-costs.cjs`: usage and cost breakdown by agent, for one repo or an `_active` folder
- `config.cjs`: reads the project settings file

If you want to change how the workflow behaves, start here.

If you want to inspect token / cost usage, run:

```bash
npm run agents:costs
npm run agents:costs -- --start 2026-03-01 --end 2026-03-31
npm run agents:costs:active
```

The cost script reads the configured agents from `.openclaw/project.json`, queries `sessions.usage`, and prints a per-agent breakdown. It also uses `contextWeight.workspaceDir`, so shared project-level sessions still count toward the repo totals even when the project is not strictly one-session-per-agent. The `_active` mode scans sibling repos under `~/projects/_active` that also have `.openclaw/project.json`.

The supervisor reads the full `agents` array from `.openclaw/project.json`.

That means:

- the starter repo still works as a simple two-agent example
- adding a third, fourth, or fifth agent only requires editing `project.json` plus a role file
- the generic `dispatch-agent.sh <agent-key> ...` path is the main manual entrypoint for larger setups

When the supervisor dispatches work, it also writes a small summary record under `.openclaw/runtime/dispatch-history.jsonl`.

Best practice:

- do not let the loop run forever just because the repo is idle
- ask each agent run to end with a status like `continue`, `done`, `blocked`, or `defer`
- use that status to decide whether the same lane should be dispatched again
- ask each run to end with a compact report block the supervisor can parse
- let OpenClaw handle long-thread compaction internally unless you have a proven reason to add custom rollover
