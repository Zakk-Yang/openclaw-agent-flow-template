# Stop Conditions

This is one of the most important best practices in an agent loop.

Without a stop condition, a heartbeat supervisor can keep dispatching forever even when:

- the work is already good enough
- the agent is blocked
- the next step is low value
- the repo needs a human decision first

## The Simple Rule

Every dispatched task should end with one of these statuses:

- `continue`
  Meaning: there is a clear next bounded step and another cycle would still be useful.

- `done`
  Meaning: this lane is complete for now and should stop until a new goal appears.

- `blocked`
  Meaning: the lane cannot move forward without a new source, credential, approval, schema change, or product decision.

- `defer`
  Meaning: more work is possible later, but another cycle right now is not worth the token cost or repo churn.

## Why This Matters

The supervisor already knows when the repo is idle.

That is not enough.

It also needs to know whether the agent should be asked again.

If the loop only checks:

- repo changed
- repo did not change

then it can get stuck in low-value patterns such as:

- repeated audit runs
- repeated "no new change" answers
- repeated attempts against the same upstream blocker

## Recommended Behavior

Best practice is:

1. The supervisor decides when a lane is eligible for dispatch.
2. The agent decides whether the lane should continue.
3. The repo stores that result in a small machine-readable summary.
4. The supervisor stops redispatching lanes that are `done`, `blocked`, or `defer` unless a new input resets them.

## Who Decides What

Use this split:

- **Prompts / role briefs** tell the agent how to report the result.
- **The agent** decides whether the lane is `continue`, `done`, `blocked`, or `defer`.
- **The supervisor** decides whether to dispatch the lane again.
- **Hooks** are optional helpers for side effects such as logging, notifications, memory snapshots, or writing status artifacts.

So hooks are useful, but they are not the main workflow brain.

The simplest reliable pattern is:

- prompts define the status contract
- the agent returns the status
- the supervisor enforces the stop condition
- hooks record or react to the event if you want extra automation

## Good Examples

### `continue`

- "The source is working and the next bounded step is to wire this series into daily scan."
- "The UI panel is improved, but the next contained step is to add a no-data state to the related table."

### `done`

- "This indicator is good enough for v1 and no further work is needed in this lane right now."
- "The panel is clear, verified, and does not need another frontend pass."

### `blocked`

- "The upstream source returns intermittent 405 errors, so deeper backfill is unsafe until the source path changes."
- "This build requires credentials or a schema decision that does not exist yet."

### `defer`

- "A cleaner implementation exists, but it is lower priority than the unresolved coverage gaps."
- "Backfilling this history would be nice, but it should wait until the main v1 indicators are stable."

## What To Put In Agent Prompts

Ask agents to finish every run with:

- what changed
- what was verified
- one short handoff sentence for the next fresh session
- one final status:
  - `continue`
  - `done`
  - `blocked`
  - `defer`
- one sentence explaining why

This prompt contract is what lets the supervisor make sane dispatch decisions later.

## Context Saturation

There is one more stop-related problem to solve in long-running loops:

- even a useful lane eventually fills its chat context

So a healthy loop should also:

1. keep the final report compact
2. store that report in a lane handoff file
3. rotate to a fresh session when the current thread gets too large
4. continue from the handoff instead of reusing the saturated session

This is how you keep the workflow automated without letting "100% context used" quietly break quality.

## Practical Outcome

This turns the workflow from:

- "dispatch forever while idle"

into:

- "dispatch while useful, then stop on purpose"
