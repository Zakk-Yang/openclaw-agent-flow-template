# Master Prompt

```text
Set up this repository to use OpenClaw as a project-local orchestrator with GSD discipline.

Project context:
- Project name: <PROJECT_NAME>
- Repo root: <REPO_PATH>
- Main goal: <PROJECT_GOAL>
- Success outcome: <WHAT_SUCCESS_LOOKS_LIKE>

Agents to create:
- Agent 1 name: <AGENT_1_NAME>
- Agent 1 mission: <AGENT_1_MISSION>
- Agent 1 allowed areas: <PATHS_AGENT_1_CAN_TOUCH>
- Agent 1 should avoid: <PATHS_AGENT_1_MUST_NOT_TOUCH>

- Agent 2 name: <AGENT_2_NAME>
- Agent 2 mission: <AGENT_2_MISSION>
- Agent 2 allowed areas: <PATHS_AGENT_2_CAN_TOUCH>
- Agent 2 should avoid: <PATHS_AGENT_2_MUST_NOT_TOUCH>

System requirements:
- Use OpenClaw as the orchestrator.
- Use exactly these project-local agents.
- Use heartbeat + tmux + shell scripts + GSD only.
- Do not use cron.
- Keep OpenClaw global, but keep agent definitions, setup scripts, dispatch scripts, and orchestration docs inside this repo.
- Make setup idempotent and safe to run multiple times.
- Do not revert unrelated working tree changes.

Dispatch policy:
- Heartbeat interval: 5 minutes.
- Supervisor loop must run in tmux.
- Use diff-only dispatch logic.
- If repo diff/status has not changed for 5 minutes, dispatch work.
- If repo diff/status changed, do not dispatch.
- Do not use agent session timestamp changes as a reason to suppress dispatch.
- Prefer dispatching one agent per cycle unless there is a clear reason to do otherwise.
- Choose or alternate agents pragmatically based on repo state.
```
