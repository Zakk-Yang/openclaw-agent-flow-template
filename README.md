# OpenClaw Agent Flow Template

A small, public starter repo for running a two-agent OpenClaw workflow with:

- project-local agent briefs
- `tmux` heartbeat supervision
- diff-only auto-dispatch
- simple shell scripts
- GSD-friendly structure

This template is meant to be copied into a real project, then edited in place.

If you want one copy-paste prompt for Codex or another coding agent, use [prompt.txt](./prompt.txt).

If you want a machine-level bootstrap command for creating new projects from this template, see [docs/global-setup.md](./docs/global-setup.md).

## What It Gives You

- one place to define your project goal and agent roles
- one idempotent setup script for registering project agents
- one shared dispatch wrapper plus two sample dispatch commands
- one heartbeat supervisor that dispatches only when the repo is idle
- one clear runtime state/log location

## How It Works

1. OpenClaw stays installed globally on your machine.
2. This repo keeps agent roles, prompts, and orchestration scripts project-local.
3. A `tmux` session runs a heartbeat loop.
4. Every 5 minutes the supervisor checks repo diff/status.
5. If the repo has stayed unchanged for 5 minutes, it dispatches one agent.
6. If the repo changed, it does nothing.

The default mode is `diff-only`. Agent session timestamp noise does not block dispatch.

## Quickstart

1. Copy this repo or use it as a template.
2. Edit [AGENTS.md](./AGENTS.md).
3. Edit [.openclaw/project.json](./.openclaw/project.json).
4. Edit the role briefs:
   - [.openclaw/roles/agent-a.md](./.openclaw/roles/agent-a.md)
   - [.openclaw/roles/agent-b.md](./.openclaw/roles/agent-b.md)
5. Run:

```bash
bash scripts/openclaw/setup-project-agents.sh
bash scripts/openclaw/start-supervisor-tmux.sh
```

Manual dispatch:

```bash
bash scripts/openclaw/dispatch-primary.sh "Review the repo and take the next safe task."
bash scripts/openclaw/dispatch-secondary.sh "Improve the next clear part of the product."
```

## Operating Commands

```bash
npm run agents:setup
npm run agents:primary
npm run agents:secondary
npm run agents:supervisor:start
npm run agents:supervisor:status
npm run agents:supervisor:stop
```

## Global Bootstrap

This repo also includes an optional global bootstrap layer.

Use it when you want one reusable command that creates new repos from this template while keeping actual agent behavior local to each project.

Install it:

```bash
bash scripts/bootstrap/install-global.sh
```

Then create a new project:

```bash
new-agent-flow my-project
```

## File Map

- [.openclaw/project.json](./.openclaw/project.json): project and agent config
- [.openclaw/roles/](./.openclaw/roles): role briefs
- [scripts/bootstrap/](./scripts/bootstrap): optional machine-level bootstrap layer
- [scripts/openclaw/](./scripts/openclaw): setup, dispatch, and supervisor scripts
- [docs/quickstart.md](./docs/quickstart.md): practical setup guide
- [docs/global-setup.md](./docs/global-setup.md): how to install the global bootstrap layer
- [docs/customization.md](./docs/customization.md): how to adapt for a real repo
- [docs/architecture.md](./docs/architecture.md): runtime design
