# Global Setup

Use the global layer only for bootstrap.

Keep the actual project behavior local to each repo.

## Recommended Split

Global:

- OpenClaw install, auth, and gateway
- one reusable `new-agent-flow` command
- one reusable prompt file
- this template repo as the source of truth

Local:

- agent roles
- allowed file areas
- project slug and identity names
- supervisor state and logs
- `.planning/` and GSD history

This avoids cross-project collisions while still making new project creation fast.

## Install The Global Bootstrap

From the template repo:

```bash
bash scripts/bootstrap/install-global.sh
```

That installs:

- `~/.local/bin/new-agent-flow`
- `~/.config/openclaw-agent-flow/prompt.txt`
- `~/.config/openclaw-agent-flow/README.md`

## Create A New Project

```bash
new-agent-flow my-project
```

Or choose a target path and visible project name:

```bash
new-agent-flow my-project "$HOME/projects/_active/my-project" --name "My Project"
```

## What The Bootstrap Command Does

- copies or clones the template
- rewrites `.openclaw/project.json`
- removes the template git history
- initializes a fresh git repo on `main`
- creates an initial scaffold commit when git identity is configured

## After Bootstrap

Edit:

- `AGENTS.md`
- `.openclaw/project.json`
- `.openclaw/roles/agent-a.md`
- `.openclaw/roles/agent-b.md`

Then run:

```bash
bash scripts/openclaw/setup-project-agents.sh
bash scripts/openclaw/start-supervisor-tmux.sh
```

## Important Rule

Do not try to run one global supervisor for all projects.

Use the global layer to create projects.
Use the local repo to define how each project behaves.
