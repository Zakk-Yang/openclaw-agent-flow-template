# Quickstart

## 1. Edit The Template

Update:

- [AGENTS.md](../AGENTS.md)
- [.openclaw/project.json](../.openclaw/project.json)
- [.openclaw/roles/agent-a.md](../.openclaw/roles/agent-a.md)
- [.openclaw/roles/agent-b.md](../.openclaw/roles/agent-b.md)

## 2. Register The Agents

```bash
bash scripts/openclaw/setup-project-agents.sh
```

## 3. Test Manual Dispatch

```bash
bash scripts/openclaw/dispatch-primary.sh "State your role in one short sentence."
bash scripts/openclaw/dispatch-secondary.sh "State your role in one short sentence."
```

## 4. Start The Heartbeat Loop

```bash
bash scripts/openclaw/start-supervisor-tmux.sh
```

## 5. Inspect State

```bash
bash scripts/openclaw/supervisor-status.sh
```

Runtime files live under `.openclaw/runtime/`.
