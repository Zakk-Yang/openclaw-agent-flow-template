# Safety

Keep the default posture conservative:

- diff-only dispatch
- one dispatch per cycle
- explicit allowed file areas per agent
- no auto-commit by default
- no destructive git commands

Before using this on a real repo:

- confirm each agent's focus paths are correct
- keep prompts plain and bounded
- inspect supervisor logs after the first auto-dispatch
