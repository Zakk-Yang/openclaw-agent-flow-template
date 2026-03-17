# Customization

## Rename The Project

Edit [.openclaw/project.json](../.openclaw/project.json):

- `project.slug`
- `project.name`
- `project.tmux_session`

## Change Agent Roles

Edit:

- [.openclaw/roles/agent-a.md](../.openclaw/roles/agent-a.md)
- [.openclaw/roles/agent-b.md](../.openclaw/roles/agent-b.md)

Then update their config entries:

- `identity_name`
- `role_label`
- `focus_paths`
- `idle_prompt`

## Add A Third Agent Or More

This template is meant to support `n` specialized agents, not only the starter pair.

The supervisor and status scripts read the `agents` array dynamically, so adding more lanes is a configuration change, not a script rewrite.

To add another agent:

1. create a new role file under `.openclaw/roles/`
2. add another object to the `agents` array in `.openclaw/project.json`
3. give it a unique `key` and `agent_id_suffix`
4. set a clear `role_label`, `focus_paths`, and `idle_prompt`
5. rerun `bash scripts/openclaw/setup-project-agents.sh`

Manual test command:

```bash
bash scripts/openclaw/dispatch-agent.sh <agent-key> "Take the next safe task for your role."
```

For a concrete example, see [docs/examples/three-agent-product.md](./examples/three-agent-product.md).

## Change Timing

Project defaults live in `.openclaw/project.json`:

- `heartbeat_interval_seconds`
- `stall_seconds`
- `dispatch_cooldown_seconds`

Temporary overrides can be passed as env vars:

- `SUPERVISOR_INTERVAL_SECONDS`
- `SUPERVISOR_STALL_SECONDS`
- `SUPERVISOR_DISPATCH_COOLDOWN_SECONDS`

## Recommended First Real Use

A good first real split is:

- primary: product or data lane
- secondary: docs, support systems, or frontend lane

If the repo is busy enough, add a third lane for quality, ops, or release work.
