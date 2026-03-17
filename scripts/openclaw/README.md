# openclaw scripts

This folder contains the working shell scripts for the agent flow.

Main pieces:

- `setup-project-agents.sh`: register or refresh project agents
- `dispatch-agent.sh`: shared dispatch wrapper
- `dispatch-primary.sh` and `dispatch-secondary.sh`: sample manual entrypoints
- `supervisor.sh`: one-shot decision engine
- `heartbeat-loop.sh`: repeating loop that calls the supervisor
- `start-supervisor-tmux.sh`, `stop-supervisor-tmux.sh`, `supervisor-status.sh`: runtime controls
- `config.cjs`: reads `.openclaw/project.json`

If you want to change orchestration behavior, this is the first folder to inspect.
