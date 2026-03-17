# Example: Product + Frontend + Quality

This is a practical three-agent split for a normal software product repo.

Use it when the project has enough surface area that two agents feel cramped, but you still want the flow to stay easy to understand.

## Project Goal

Ship product changes continuously without letting frontend polish, quality work, and support systems fall through the cracks.

## Recommended Split

### 1. Product / Backend Agent

Owns:

- backend features
- domain logic
- API handlers
- schemas and migrations
- integration points between systems

Typical focus paths:

- `src/server`
- `src/lib`
- `api`
- `prisma`
- `docs`

Should avoid:

- broad UI rewrites
- unrelated styling work
- deployment changes unless the task clearly needs them

### 2. Frontend / UX Agent

Owns:

- page flows
- components
- styling
- copy clarity
- user-facing docs and screenshots

Typical focus paths:

- `src/app`
- `src/components`
- `src/styles`
- `public`
- `docs`

Should avoid:

- database or infra changes
- backend refactors unless needed for a specific UI task

### 3. Quality / Ops Agent

Owns:

- tests
- CI and support scripts
- observability helpers
- release notes
- guardrails that keep the project healthy

Typical focus paths:

- `tests`
- `scripts`
- `.github`
- `docs`
- `package.json`

Should avoid:

- feature rewrites that belong to the product or frontend lanes
- large visual changes unless they are required to unblock verification

## Why This Split Works

It gives each agent a lane that is easy to understand:

- one pushes the product forward
- one improves the user-facing experience
- one keeps quality and delivery from rotting

That usually maps better to real repos than a generic "primary vs secondary" split.

## Example `agents` Entry

Add a third role file such as `.openclaw/roles/agent-c.md`, then extend `.openclaw/project.json` like this:

```json
{
  "key": "quality",
  "agent_id_suffix": "quality",
  "identity_name": "Example Quality Agent",
  "role_label": "quality agent",
  "role_file": ".openclaw/roles/agent-c.md",
  "focus_paths": [
    "tests",
    "scripts",
    ".github",
    "docs"
  ],
  "idle_prompt": "Repository heartbeat: the repo looks idle. Review AGENTS.md, current repo status, and your role brief. Pick the next safe quality task, execute it carefully, verify it, and explain what changed or what blocker prevented changes."
}
```

Then rerun:

```bash
bash scripts/openclaw/setup-project-agents.sh
```

Manual test:

```bash
bash scripts/openclaw/dispatch-agent.sh quality "State your role in one short sentence."
```

## Good First Tasks For Each Lane

- product: tighten one backend workflow or remove one obvious blocker
- frontend: improve one weak screen, empty state, or docs flow
- quality: add one missing test, CI check, or verification script

Keep the first few tasks small. The orchestration loop matters more than heroic first prompts.
