# Architecture

This starter keeps the split clean:

- OpenClaw runtime: global on the machine
- role briefs and orchestration rules: local in the repo
- heartbeat loop: `tmux` + shell
- dispatch policy: diff-only by default

## Diff-Only Dispatch

The supervisor:

1. hashes repo status for each agent's focus paths
2. compares the current hash to the previous tick
3. dispatches only when the repo stayed unchanged for the stall window

It does not suppress dispatch just because an agent session timestamp changed.

## Dispatch History

Each dispatch also writes a small summary record to:

- `.openclaw/runtime/dispatch-history.jsonl`

That record is meant to answer:

- when was an agent dispatched
- which role was chosen
- whether the run exited cleanly
- which files changed in that role's scope
- what short summary came back from the run

This makes the system easier to evaluate without requiring a git commit on every heartbeat.

## Stop Conditions

Diff-only dispatch decides when a lane is eligible to run.

That is not the same as deciding whether a lane should keep running.

Best practice is to require every agent run to finish with one of:

- `continue`
- `done`
- `blocked`
- `defer`

Then the supervisor or operator can stop redispatching lanes that are already done, blocked, or not worth another cycle yet.

Without this, the loop can waste time on repeated no-op audits or repeated retries against the same blocker.

See [stop-conditions.md](./stop-conditions.md).

## Why This Shape

- easy to inspect
- easy to version
- avoids hidden machine behavior
- avoids cron if you want the snapshot-style loop
