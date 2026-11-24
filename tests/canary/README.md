# Canaries (live, cost model turns)

End-to-end runs of `/maestro` on a scratch repository — release gate V11 (`docs/hosts.md`,
"End-to-end canaries"). None of this runs in `tests/run.sh`; every run spends real model turns.

| Script | What it does |
| --- | --- |
| `mkcanary.sh <name>` | creates `$MAESTRO_CANARY_ROOT/<name>` (default `~/maestro-canaries`): a bash string library (`lib/str.sh` with `upper`) and its test (`bash tests/test_str.sh`), one commit, maestro installed into the project |
| `build-interrupt-resume.sh <repo> <evidence-dir>` | a full `--unattended` build with a `claude -p` director; kills the director as soon as a build job exists, then runs `/maestro --resume --unattended` and shows the commit and the tests |
| `shim/claude` | the transport-switch fault: put its directory first on `PATH` (with `MAESTRO_SHIM_STATE` set) for a `claude -p` director; the first builder call runs for real until its `init` and first edit, then is killed with Claude Code's quota message |
| `v2b.sh <repo>` | the director's git capabilities (objects, index file, refs, worktree, commit) — run from inside Claude Code's shell |

Since 2.0.0 Claude Code is the only director host. The headless invocation (from inside the
canary repository):

```bash
maestro-env -- claude -p --model sonnet --permission-mode acceptEdits --allowedTools "Bash Read Write Edit Glob Grep Skill" \
  --output-format stream-json --verbose "/maestro --plan-only --unattended --model=sonnet --critic=sol --rounds=1 <task>"
```

The interactive path is a plain `/maestro …` typed into Claude Code in the canary repository.

The task used: *add a function slugify to lib/str.sh: lowercase the text, turn spaces and
underscores into dashes, drop every other character that is not a letter, digit or dash; with
tests in tests/test_str.sh* (it reliably provokes a real locale finding from the critics).
