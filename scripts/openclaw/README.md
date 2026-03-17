# openclaw scripts

This folder contains the main scripts for the agent workflow.

The most important files are:

- `setup-project-agents.sh`: creates or refreshes the agents
- `dispatch-agent.sh`: sends work to an agent
- `dispatch-primary.sh` and `dispatch-secondary.sh`: easy manual commands
- `supervisor.sh`: decides whether to send work
- `heartbeat-loop.sh`: repeats the check every few minutes
- `start-supervisor-tmux.sh`, `stop-supervisor-tmux.sh`, `supervisor-status.sh`: start, stop, and inspect the loop
- `config.cjs`: reads the project settings file

If you want to change how the workflow behaves, start here.

When the supervisor dispatches work, it also writes a small summary record under `.openclaw/runtime/dispatch-history.jsonl`.

It can also keep one small handoff file per lane under `.openclaw/runtime/` so a fresh session can continue without dragging the full old thread forward.

Best practice:

- do not let the loop run forever just because the repo is idle
- ask each agent run to end with a status like `continue`, `done`, `blocked`, or `defer`
- use that status to decide whether the same lane should be dispatched again
- ask each run to end with a compact report block the supervisor can parse
- roll a lane into a fresh session when the current thread gets too large
