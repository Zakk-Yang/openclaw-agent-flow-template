# Quickstart

This is the shortest reliable path from clone to first automatic dispatch.

The template starts with a two-agent example, but the supervisor will read any number of agents from `.openclaw/project.json`.

## 30-Second Version

```bash
$EDITOR AGENTS.md \
  .openclaw/project.json \
  .openclaw/roles/agent-a.md \
  .openclaw/roles/agent-b.md

bash scripts/openclaw/setup-project-agents.sh
bash scripts/openclaw/dispatch-primary.sh "State your role in one short sentence."
bash scripts/openclaw/dispatch-secondary.sh "State your role in one short sentence."
bash scripts/openclaw/start-supervisor-tmux.sh
bash scripts/openclaw/supervisor-status.sh
```

## 1. Edit The Template

Update these files for your real project:

- [AGENTS.md](../AGENTS.md)
- [.openclaw/project.json](../.openclaw/project.json)
- [.openclaw/roles/agent-a.md](../.openclaw/roles/agent-a.md)
- [.openclaw/roles/agent-b.md](../.openclaw/roles/agent-b.md)

Minimal checklist:

- replace the example project name and slug
- describe what the project is actually trying to achieve
- give each starter agent a clear job
- define where each agent is allowed to work
- keep the first version simple

## 2. Register The Agents

```bash
bash scripts/openclaw/setup-project-agents.sh
```

This creates or refreshes the project-local OpenClaw agents.

## 3. Test Manual Dispatch

Before you start the background loop, make sure the starter agents respond correctly:

```bash
bash scripts/openclaw/dispatch-primary.sh "State your role in one short sentence."
bash scripts/openclaw/dispatch-secondary.sh "State your role in one short sentence."
```

If you add more agents later, use the generic dispatcher:

```bash
bash scripts/openclaw/dispatch-agent.sh <agent-key> "State your role in one short sentence."
```

## 4. Start The Heartbeat Loop

```bash
bash scripts/openclaw/start-supervisor-tmux.sh
```

This starts the supervisor in tmux so it can keep checking the repo on a repeating interval.

## 5. Inspect State

```bash
bash scripts/openclaw/supervisor-status.sh
```

Runtime files live under `.openclaw/runtime/`.

Important ones:

- `supervisor-state.json`
- `supervisor.log`
- `dispatch-history.jsonl`

## 6. Confirm The Intended Flow

The first real test is simple:

1. let the repo go idle
2. wait for the configured stall window
3. check that one agent was dispatched
4. make a repo change
5. confirm dispatch pauses until the repo is idle again

That is the core behavior this template is trying to give you.

## Add A Third Agent Later

When you want to move beyond the starter pair, the same supervisor keeps working:

1. create another role brief, for example `.openclaw/roles/agent-c.md`
2. add another agent entry to `.openclaw/project.json`
3. rerun `bash scripts/openclaw/setup-project-agents.sh`
4. manually test it with `bash scripts/openclaw/dispatch-agent.sh <agent-key> "..."`

For a realistic example split, see [docs/examples/three-agent-product.md](./examples/three-agent-product.md).
