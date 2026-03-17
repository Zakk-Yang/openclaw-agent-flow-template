# OpenClaw Agent Flow Template

A simple starter for people who want two AI agents working inside one project.

This repo gives you:

- a place to describe your project
- a place to describe what each agent should do
- scripts to start and check the workflow
- a background loop that can wake up and send work automatically

You can copy this repo into a real project and edit it there.

If you want one copy-paste instruction for Codex or another coding agent, use [prompt.txt](./prompt.txt).

If you want one machine-wide command that creates new projects from this template, see [docs/global-setup.md](./docs/global-setup.md).

## In Plain English

This template follows a simple idea:

1. OpenClaw runs on your machine.
2. This repo keeps the project rules and agent roles.
3. A background loop checks the project every 5 minutes.
4. If nothing changed for 5 minutes, it can send work to one agent.
5. If the project changed, it waits.

The default rule is `diff-only`, which means the workflow reacts to project file changes, not just agent chatter.

## Fast Start

1. Copy this repo or create a new repo from it.
2. Edit [AGENTS.md](./AGENTS.md) to describe the project rules.
3. Edit [.openclaw/project.json](./.openclaw/project.json) to set the project name and timing.
4. Edit the two role files:
   - [.openclaw/roles/agent-a.md](./.openclaw/roles/agent-a.md)
   - [.openclaw/roles/agent-b.md](./.openclaw/roles/agent-b.md)
5. Run these commands:

```bash
bash scripts/openclaw/setup-project-agents.sh
bash scripts/openclaw/start-supervisor-tmux.sh
```

If you want to send work manually:

```bash
bash scripts/openclaw/dispatch-primary.sh "Review the repo and take the next safe task."
bash scripts/openclaw/dispatch-secondary.sh "Improve the next clear part of the product."
```

## Useful Commands

```bash
npm run agents:setup
npm run agents:primary
npm run agents:secondary
npm run agents:supervisor:start
npm run agents:supervisor:status
npm run agents:supervisor:stop
```

## Global Bootstrap

This repo also includes an optional global setup step.

Use it if you want one reusable command that creates new project folders from this template.

Install it once:

```bash
bash scripts/bootstrap/install-global.sh
```

Then you can create a new project with:

```bash
new-agent-flow my-project
```

## Folder Guide

- [.openclaw/project.json](./.openclaw/project.json): the main project settings
- [.openclaw/roles/](./.openclaw/roles): what each agent is supposed to do
- [scripts/openclaw/](./scripts/openclaw): the main workflow scripts
- [scripts/bootstrap/](./scripts/bootstrap): optional machine-wide setup scripts
- [docs/](./docs): guides and examples
