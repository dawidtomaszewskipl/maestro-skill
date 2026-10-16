# Troubleshooting

Every entry below happened in a real route run between 2026-08-16 and 2026-09-30.

## Codex sits at `Reading additional input from stdin...` for an hour

Every confirmed Codex "hang" in twenty runs was this — three separate sessions, three separate
diagnoses, 19 to 75 minutes lost each. The `codex exec` call was inside a shell command that also
contained a heredoc, stdin stayed open, and Codex waited for it (its help says so: piped stdin is
appended to the prompt). Nothing was written to disk, so the restart is clean.

The line is printed on healthy runs too. The hang signal is that line **with no `thread.started`
event in the `.jsonl`**. Fix: `< /dev/null` on the command line — it is on every canonical line.

## `codex exec resume` rejects `-s` / `--color`

`error: unexpected argument '-s' found`. The resume subcommand has a different flag set — on
0.159.2 it takes `--ignore-user-config`, `--image` and `--output-schema` but not `-s`, `--color`,
`-C`, `--add-dir` or `--approve-for-me` (the full list is in `docs/workers.md`). Sandbox goes
through `-c 'sandbox_mode="workspace-write"'`. Two 8–10-minute sampling windows were wasted per
session on this before the working form was found.

## `Error loading config.toml: invalid transport in mcp_servers.<name>`

`codex exec` exits 1 before any model turn. The line combined `--ignore-user-config` with the old
`-c mcp_servers.perplexity.enabled=false`: with the user config skipped, that override creates a
server entry with no command, and the configuration no longer parses (2026-09-30). Isolated lines
carry no MCP overrides — the servers are already gone; the overrides belong to pinned mode only.

## `--worktree cannot be combined with --ignore-user-config`

Codex's managed worktrees refuse isolated mode (0.159.2, 2026-09-30). Route creates the worktree
itself (`git worktree add --detach`) and passes it with `-C`; `docs/commands.md`, "Parallel Codex
workers".

## A resumed worktree worker ran in the checkout

`codex exec resume` has no `-C` and runs in the shell's current directory — the thread does not
remember its worktree. Started from the checkout, a resume works on the checkout (observed with a
read-only probe turn on 2026-09-30, before any edit). Start every resume of a worktree worker from
its worktree (`cd <worktree> && codex exec resume …`), and let the effective-config check confirm
the write root.

## `No prompt provided via stdin` right after attaching a screenshot

`-i <file>` takes several values, so in `-i shot.png "Fix the modal"` the prompt was read as a second
image and Codex fell back to stdin, which was closed: exit 1 (2026-09-30). Attach with
`--image=shot.png[,other.png]`, or put `--image <file>` before the other flags.

## Codex finished long ago and the director noticed only when asked "how is it going?"

The worker was launched as `setsid nohup run.sh … & disown` inside the Bash command, with the
tool's `run_in_background` left unset. The tool returned after the `sleep 15` that followed, no
harness task was registered, and the completion notification that would have woken the director
never existed. The director ended its turn ("second batch starting") and waited for something that
could not arrive. Across two sessions this was 34 of 36 launches — idle gaps of 0.7 to 127 minutes,
every one ended by the user typing. The same runs launched with `run_in_background: true` were
resumed by the director 6–10 s after the worker exited, with no human in between.

Fix: the Bash tool's background mode is the *only* background mechanism — no `&`, `nohup`,
`setsid`, `disown` in the command. If a process must outlive the shell, the same background
command waits for its PID so the task ends when the worker does. Never end a turn with a live
worker and no task for it. The Codex plugin's `--background` rescue does the same detach
(`spawn(detached) + unref()`) and is polled through `/codex:status`, so it does not fix this.

## The director's own `timeout 900` was cut at 10 minutes

The Bash tool caps foreground commands at 600 s and sends SIGTERM; the longer value you wrote is
silently ignored. Anything that can take more than a few minutes — every model call, every test run
— goes to the background.

## A healthy 417-second test was killed as a hang

The test emitted nothing for its entire run; two silent samples of 20–25 s "proved" it stuck. The
silence rule now has a floor — `max(15 min, 2 × T_slow)` of *continuous* silence, with `T_slow`
recorded at stage 0 — and is never applied to test runs at all.

## Every test run blocks forever with no output

A killed parallel test runner (`timeout`, `pkill`) orphans its workers, which keep their test
databases and a metadata lock (`Waiting for table metadata lock`). Every subsequent run then waits
on that lock and looks exactly like a frozen model. Recovery that worked: find the blocking
connection id in the database, kill *that* connection by id, leave the others alone. Prevention:
never wrap tests in `timeout`, never `pkill` them, never run two of the same suite at once.

## `pkill -f` returned 144 and killed the wrong thing

`pkill -f "codex exec"` and `pkill -f 'artisan test'` matched the director's own shell — four
sessions, always exit 144. Kill by PID (`ps -eo pid,etime,cmd | grep '[c]odex exec'`, then
`kill <PID>`) or by the harness task id.

## agy: exit 0, `status:"CANCELED"`, empty response

The worker tried a tool action that headless mode cannot prompt for (usually `RunCommand`) and the
turn was cancelled: `denied_actions:[{"action":"command","display_name":"RunCommand"}]`. Fix the
brief (edits-only for builders; every fact inline for critics) or add `permissions.allow` rules —
never retry identically, and never resume that conversation.

## agy: exit 0, `status:"SUCCESS"`, empty response, `denied_actions:[{"action":"mcp"}]`

A different signature from the `CANCELED` case above, and a nastier one: the status says
**SUCCESS**, so a check that reads only `status` concludes the critique passed and moves on with
nothing. The worker reached for an MCP tool the project configures (Laravel Boost, Perplexity,
Playwright), headless mode auto-denied it because it cannot prompt, and the turn ended with no
answer. stderr names it exactly:

```
jetski: no output produced — a tool required the "mcp" permission that headless mode cannot
prompt for, so it was auto-denied.
```

Usage still shows thousands of output and thinking tokens — the model did the work and then threw
it away reaching for a tool. This is why the envelope check is three conditions, not one:
`status == "SUCCESS"` **and** `response != ""` **and** `denied_actions == []`.

Fix in the brief, not in the user's global config: open a critic brief with an explicit
prohibition — *"This brief is self-contained. Do NOT call any tools: do not read files, do not run
commands, do not call MCP, do not search the repository. Answer from the text below alone."* — and
make sure every fact the critic needs really is inline. `--dangerously-skip-permissions` also
clears it but grants far more than a read-only critic should have, and `agy mcp disable` mutates
the user's setup for every project. Start a new conversation; the one that produced no answer has
nothing to resume.

Measured on agy 1.1.28: same brief, same model, same effort — 37 s and no answer with the
prohibition absent, 202 s and a full verdict with it present.

maestro (agy 1.3.3, 2026-10-12) narrows the prohibition instead of forbidding every tool: file
reads **inside** `--add-dir` are allowed and work in print mode (four critiques out of four, no
denial, `.maestro/` in `info/exclude` included); commands, MCP and paths outside the workspace stay
forbidden, because each of those is auto-denied and empties the answer. A denial still means a new
conversation, now with the inline variant (`docs/workers.md`).

## agy: exit 1, `status:"ERROR"`, `error:"timeout waiting for response"`

`--print-timeout` expired (5 minutes by default up to agy 1.1.x; 1.2.8 defaults to no limit, so a
missing value hangs instead — route always sets it). There is no `TIMEOUT` status. Start a new
conversation with a larger timeout and the current `git diff` embedded; do not `--conversation`
into the expired one.

## agy: `flag needs an argument: -p` / `Argument list too long`

`-p` does not read stdin, and the OS caps a single argument at ~128 KB. The pointer stub
(`Read .maestro/brief-build.md … execute it exactly`) sidesteps both. The old "prompts over 4 KB
return `status:"ERROR"`" belief did not reproduce on 1.1.27 — a 34 KB prompt ran normally.

## Gemini "did the work" but ran no tests and saw no skills

Two different causes. Headless `agy` cannot run commands (see `CANCELED` above) — the director runs
the tests. And print mode does not treat cwd as the workspace: without `--add-dir "$REPO"` the
worker sees only the built-in skills and none of the project's `.agents/skills`. Stage 0's
`agy --add-dir "$REPO" -p "/skills"` probe shows exactly what the worker will see.

## The schema verdict will not parse

Three layers: agy's envelope wraps the verdict in the `response` *string*; the model may wrap the
JSON in Markdown fences; agy adds `toolAction`/`toolSummary` keys the schema does not declare. Strip
fences, drop those two keys, parse, validate — then act. Codex's `-o` file is the bare verdict.

## The progress monitor raised an alarm on a healthy Codex run

The Codex `.jsonl` carried `{"type":"error", …}` lines about a stream reconnect (HTTP 503) in the
middle of a build that finished normally. Codex retries its stream by itself; the event is a
notice. The director's own monitor treated every `"type":"error"` as a failure (2026-09-09). A
failure is `turn.failed`, or the process exiting without `turn.completed` — check for those.

## The ledger showed a resumed Codex thread costing twice what it did

`codex exec resume` reports `turn.completed.usage` **cumulatively for the thread**, not for the new
turn. Summing the rows of a thread counted the first call again on every resume (2026-09-20). The
ledger keeps the raw counters in `raw_cumulative` and records `raw[n] − raw[n−1]` as the row's
tokens — computed from the raw counters, not from the previous row's delta (that shortcut breaks on
the second resume: 100, 150, 180 becomes 100, 50, 130). `docs/ledger.md` has the rule.

## Tests failed with missing tables in the middle of a run

Another Claude Code session on the same machine ran its own tests against the shared `testing`
database and dropped tables under the route run — false reds with no relation to the diff
(2026-09-09 in one project, 2026-09-20 in another). Before diagnosing a red that makes no sense,
check for another live test run (`ps -eo pid,etime,cmd | grep '[a]rtisan test'`); wait for it to end
rather than killing it. Never start a second run of the same suite while one is live.

## The cascade draft was right in shape and wrong in finish

A Luna draft at effort `low` (2026-09-17) stayed inside its boundaries but packed code into very
long one-liners, left out two tests the plan listed and wrote one wrong Livewire assertion. The
Gemini gate asked for a revision (confidence 0.95, same diagnosis as the director's own probe); one
fix round was accepted. The drafter appendix now asks for the repository's formatting and for every
planned test; the gate still checks both.

## A worker hangs at startup with no output at all

No new session file under `~/.codex/sessions/` means the failure was before the session started.
`codex doctor --summary` shows the background `app-server`; an editor extension keeps its own
against the same `CODEX_HOME`. Once, the real cause was a global MCP server that shelled into a
container runtime that was not running — a 35-minute "hang" fixed by removing it from the global
config.

## A worker died mid-build (quota, API error, cancel)

Six quota events in three weeks; the protocol worked every time it was followed:

1. `git status` and `git diff` **before anything else** — remnants look finished.
2. Keep or reset them deliberately; write the checkpoint with `tree_state` and the blocker.
3. Resume rather than restart: Codex by thread UUID, agy by `conversation_id` (only after a
   `SUCCESS` turn), Claude subagents with the checkpoint's "to do on resume" section.
4. **Re-probe the limit before re-casting the roster.** The one time the director reasoned from a
   remembered limit ("resets 4:10am", at 8:48) it moved four batches off the right worker.

## The worker's green run disagrees with yours

770/770 reported, 769/770 measured. Sandbox differences, stale caches, a test the worker never ran.
A worker's green run is evidence, not a verdict — the commit waits for your own run.

## Playwright `fill()` never returns

A selector moved onto a custom element and `fill()` waited for it indefinitely instead of failing.
That is a red test that looks like a hang. Fix the selector; do not treat it as a watchdog case.

## Two projects served each other's assets

One project's Vite died; the other project's dev server took port 5173; the first silently loaded
the wrong CSS/JS for an hour and a half. Stale `public/hot` was the tell. Not route's fault — but
it is the kind of thing a browser check surfaces and a test suite does not.

## Leftover processes from an interrupted run

`until [ -s file ]` loops and dev servers from a run the director itself had interrupted survived
for hours. The checkpoint's `sessions` and the harness task ids are the inventory to clean up after
any interruption; `git stash list` shows leftover `route-draft-*` stashes from escalated cascades.

## maestro: a Cursor worker wrote outside the workspace and reached the network

`agent -p --force --sandbox enabled` (2026-10-11): the worker wrote into another directory under
`$HOME`, into `$HOME` itself, and fetched `https://example.com` — **`--force` turns Cursor's sandbox
off**, whatever `--sandbox` says. Without `--force` the same commands were denied (`Brak dostępu` /
`Permission denied`) and the network got `CONNECT tunnel failed, response 403`. maestro's Cursor lines
never carry `--force`; rung 4 is a per-run user approval (`docs/sandbox-and-preflight.md`).

## maestro: `maestro-host` said `claude-code` inside a Cursor run

A director check run by `agent -p --sandbox enabled` launched from a Claude Code session reported
`claude-code`: Cursor's sandbox hid the Cursor process, and the nearest visible host was the Claude
Code daemon that had launched Cursor (`CLAUDECODE=1` inherited). Fixed in `maestro-host`: when a
host's marker is present but that host is not in the visible ancestry, the ancestry is not trusted
and the markers-only rule decides — two hosts' markers → `unknown`. Launch nested hosts through
`maestro-env` (it strips the outer markers), and expect `unknown` from a `codex exec` read-only
sandbox started inside another host: Codex hides the whole ancestry there.

## maestro: a "read-only" `claude -p` critic loaded a plugin with hooks

`claude -p --setting-sources ""` still loaded a non-builtin plugin (with `hooks.json`): the
director's environment carried `CLAUDE_CODE_PLUGIN_DIRS`, inherited by the child. `maestro-env`
removes every `CLAUDE_*` variable except `CLAUDE_CONFIG_DIR` (it also removes `CLAUDE_EFFORT`, which
would override `--effort`), and the `init` check kills a session whose `plugins` hold anything not
`@builtin`.

## maestro: `claude -p` refused to write in a scratch repository

`"Claude requested permissions to edit … which is a sensitive file"` for a file under
`~/.claude/jobs/…`: Claude Code treats everything under `~/.claude/` as sensitive, in any permission
mode. Scratch repositories for tests and canaries live outside `~/.claude`.

## maestro: a Grok verdict "would not parse"

Grok opened two of seven critiques with a sentence before the JSON (`Porównam plan … {"verdict":…`),
in the user's language although the brief was English. `maestro-validate` allows leading prose and
still requires exactly one top-level object with nothing after it; briefs to Cursor say *"Answer in
English"* and *"Your final message must be the JSON object only."*

## maestro: agy cannot be the director in print mode

`agy -p` auto-denies every shell command (`docs/workers.md`), so a print-mode agy cannot run
`maestro-host`, the lock, git or the tests. agy directs only interactively, approving the commands
or with `permissions.allow` rules. `maestro-host` reports `interactive: false` for `agy -p` and stage 0
stops there.

## maestro: my own `pkill -f` killed my shell (exit 144)

During maestro's own build a cleanup `pkill -f "maestro-tests"` matched the very shell running it —
its command line contained the pattern. route's rule stands: never `pkill -f`; find the PIDs (`ps -eo
pid,args`, then `kill <pid>`) or let `maestro-kill` signal recorded members one by one.

## maestro: an `api` worker answered as an older Claude than the slot

`maestro-sdk --model haiku` served `claude-haiku-4-5-20251001` (SDK 0.3.286, 2026-10-15) while
native `claude -p --model haiku` served `claude-haiku-5-5`: the SDK's bundled Claude Code resolves
aliases from its own table. `maestro-sdk` now refuses aliases; the full id comes from the frozen
identity or from `maestro-sdk --resolve <slot>` (the Models API for the key).

## maestro: `api` probe fails with `Invalid API key`

`result.subtype: "success"` with `is_error: true` and `"Invalid API key · Fix external API key"`, or
`--resolve` exiting 3 with HTTP 401. The key file holds a revoked or mistyped key: create a new one
in the Console organisation linked to the Max plan and write it to
`~/.config/maestro/anthropic-api-key` (mode 600). An unavailability, not quota: no transport switch
onto it this run.

## maestro: the API credit did not go down, the prepaid balance did

The credit covers the Claude API and the Agent SDK, not Claude Code, and only in the Console
organisation linked under claude.ai → Settings → Billing. Check that the key belongs to that
organisation, and that the worker ran on `api` (ledger `cli: claude-sdk`), not as a director in
Claude Code started with an API key — that is Claude Code usage.

## maestro: `This API key is not scoped to a workspace`

HTTP 400 from `maestro-sdk --resolve` (measured 2026-10-15): an organisation-level key is accepted,
but each request must then name a workspace in an `anthropic-workspace-id` header, which neither
maestro nor Claude Code sends. Create the key inside a Console workspace instead. That also lets
you set the workspace's spend limit, maestro's hard stop beside `api.max_usd_per_run`.

