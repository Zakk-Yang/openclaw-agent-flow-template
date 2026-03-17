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

## Why This Shape

- easy to inspect
- easy to version
- avoids hidden machine behavior
- avoids cron if you want the snapshot-style loop
