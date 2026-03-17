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

- primary: product or data lane
- secondary: docs, support systems, or frontend lane
