# Canaries (live, cost model turns)

End-to-end runs of `/route2` on a scratch repository — release gate V11 (`docs/hosts.md`,
"End-to-end canaries"). None of this runs in `tests/run.sh`; every run spends real model turns.

| Script | What it does |
| --- | --- |
| `mkcanary.sh <name>` | creates `$ROUTE2_CANARY_ROOT/<name>` (default `~/route2-canaries`): a bash string library (`lib/str.sh` with `upper`) and its test (`bash tests/test_str.sh`), one commit, route2 installed into the project |
| `build-interrupt-resume.sh <repo> <evidence-dir>` | a full `--unattended` build with a `claude -p` director; kills the director as soon as a build job exists, then runs `/route2 --resume --unattended` and shows the commit and the tests |
| `shim/claude` | the transport-switch fault: put its directory first on `PATH` (with `ROUTE2_SHIM_STATE` set) for a `claude -p` director; the first builder call runs for real until its `init` and first edit, then is killed with Claude Code's quota message |
| `agy-approver.sh <tmux-session> <log> [idle-s]` | answers an interactive agy director's command and file-write prompts in tmux, refusing dangerous commands and logging every decision |
| `v2b.sh <repo>` | the director's git capabilities (objects, index file, refs, worktree, commit) — run from inside a host's shell |

The invocations used on 2026-10-11 (each from inside the canary repository):

```bash
# Claude Code, headless
route2-env -- claude -p --model sonnet --permission-mode acceptEdits --allowedTools "Bash Read Write Edit Glob Grep Skill" \
  --output-format stream-json --verbose "/route2 --plan-only --unattended --model=sonnet --critic=grok --rounds=1 <task>"
# Codex
route2-env -- codex exec -m gpt-6.1-sol -s danger-full-access --json --ignore-user-config -c model_reasoning_effort=medium \
  -C "$PWD" -o answer.txt '$route2 --plan-only --unattended --model=sonnet --critic=grok --rounds=1 <task>'
# Cursor — with .cursor/cli.json as in docs/hosts.md ("Cursor's allowlist"), never --force
route2-env -- agent -p --trust --model grok-4.7-high --output-format stream-json --workspace "$PWD" \
  "/route2 --plan-only --unattended --model=sonnet --critic=sol --rounds=1 <task>"
# agy — interactive in tmux, with agy-approver.sh answering the prompts
tmux new-session -d -s r2canary "route2-env -- agy --model gemini-3.8-flash-high"
tmux send-keys -t r2canary -l "/route2 --plan-only --unattended --model=sonnet --critic=grok --rounds=1 <task>"; tmux send-keys -t r2canary Enter
```

The task used: *add a function slugify to lib/str.sh: lowercase the text, turn spaces and
underscores into dashes, drop every other character that is not a letter, digit or dash; with
tests in tests/test_str.sh* (it reliably provokes a real locale finding from the critics).
