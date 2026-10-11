# Hosts

route2 runs as the director inside four agent hosts. They differ in four things the loop depends
on: how the director starts a Claude worker, how it waits for a long command, how it asks the
user, and what its own shell may do. Stage 0 detects the host and every later step uses the row of
this file that belongs to it.

Everything marked **measured** was observed on this machine on 2026-10-11 with Claude Code
2.1.296, Codex CLI 0.162.1, agy 1.3.3 and Cursor agent 2026.10.01; anything else is marked
**documented** (with the source) or **unverified**.

## Detection

`bin/route2-host` prints one JSON line: `{host, interactive, session_key, host_pid,
host_pid_starttime, director_family, director_model, director_line, evidence[]}`.

**Child processes inherit host markers** (measured: a `codex exec` launched from Claude Code still
has `CLAUDECODE=1`; so does `agent -p`). A marker therefore says "this host is somewhere above
you", not "this host is your parent". The rules:

1. **Ancestry.** Walk up from the shell's parent through `/proc/<pid>/stat` and match each process
   by `readlink /proc/<pid>/exe` and `argv[0..1]` from `/proc/<pid>/cmdline` — never by `comm`,
   which Linux truncates to 15 bytes. Host executables (measured):

   | Host | Executable | argv |
   | --- | --- | --- |
   | Claude Code | `~/.local/share/claude/versions/<v>` (a single ELF) | `claude …` (also `claude daemon run`, `claude bg-spare …` for background sessions) |
   | Codex | `~/.codex/packages/standalone/releases/<v>/bin/codex` | `codex …`, `codex exec …` |
   | Cursor | `~/.local/share/cursor-agent/versions/<v>/node` | `argv[0]` = the `agent` launcher path, `argv[1]` = `…/cursor-agent/versions/<v>/index.js` |
   | agy | `~/.local/bin/agy` (a single ELF) | `agy …` |

   The **nearest** match is the host. Outer hosts' markers are expected and are not a conflict.
2. **Marker confirmation** (measured):

   | Host | Marker | Session key |
   | --- | --- | --- |
   | Claude Code | `CLAUDECODE=1` | `CLAUDE_CODE_SESSION_ID` |
   | Codex | `CODEX_THREAD_ID` (also `CODEX_CI=1`, `CODEX_VERSION`) | `CODEX_THREAD_ID` |
   | Cursor | `CURSOR_AGENT=1` + `CURSOR_CONVERSATION_ID` (also `CURSOR_INVOKED_AS`, `CURSOR_SANDBOX=native` inside its sandbox) | `CURSOR_CONVERSATION_ID` |
   | agy | `ANTIGRAVITY_AGENT=1` + `ANTIGRAVITY_CONVERSATION_ID` (also `ANTIGRAVITY_TRAJECTORY_ID`, `ANTIGRAVITY_LS_VERSION`) | `ANTIGRAVITY_CONVERSATION_ID` |

   The nearest host's marker must be present, else `unknown`.
3. **Hidden hosts.** A sandbox can hide part of the chain. Measured: inside Cursor's sandbox the
   Cursor process is invisible and the nearest visible host was the Claude Code daemon that had
   launched Cursor — a wrong answer if trusted. Inside Codex's sandbox the whole ancestry is
   invisible (a pid namespace). So: **if a host's marker is present but that host is not in the
   visible ancestry, the ancestry is not trusted** and the markers-only rule decides.
4. **Markers only:** exactly one host's markers present → that host (evidence `markers-only`);
   two or more → `unknown` (the nesting order cannot be read from inherited markers); none →
   `unknown`.
5. `unknown` → attended: ask which host; `--unattended`: row 2 stop. `--host=` overrides the name
   only — never capabilities, never lock liveness.

A director started by the user in a terminal has only its own host's markers, so even the
markers-only path is unambiguous there. Nesting (a director host launched from another host) is a
test setup; launch it through `bin/route2-env` and the outer markers are gone.

**Interactive or headless** is read from the host's command line: Claude Code `-p`/`--print`,
Codex the `exec` subcommand, Cursor `-p`/`--print`, agy `-p`. **A headless director requires
`--unattended`**, and **agy cannot direct in print mode at all** — it auto-denies every shell
command (`docs/workers.md`).

## Director identity

`{family, model_line, model_id}`, resolved at stage 0 and re-checked before every dispatch:

| Host | Source | Status |
| --- | --- | --- |
| Claude Code | you know your own model (the system prompt names it) | measured |
| Codex | the latest `turn_context.payload.model` in the rollout of `$CODEX_THREAD_ID` (`$CODEX_HOME/sessions/**/rollout-*-<id>.jsonl`), records of other threads ignored | measured (format: `docs/commands.md`, effective-config check) |
| Cursor | none found: the `init` event carries the model for `agent -p` sessions a director *launches*, but nothing exposes the director's own model to its shell | unverified → `unknown` |
| agy | none: `ANTIGRAVITY_SOURCE_METADATA` holds the conversation id, step and tool call, not the model | measured → `unknown` |

`family` or `model_line` unknown → `self` is not eligible as a builder (route2-roles stops on it),
and with `family` unknown `--review=self` is illegal (use `cross`). A stated model is not a source.
If your identity changes between dispatches (a model switch, even within a family), re-validate
`self` and degraded-mode roles; an assignment that became illegal → ask (unattended: row 2).

## Adapters

| Concern | Claude Code (interactive) | Claude Code `claude -p` | Codex | Cursor `agent` | agy (interactive only) |
| --- | --- | --- | --- | --- | --- |
| Invoke the skill | `/route2` | `/route2` in the prompt | `$route2` | `/route2` | `/route2` |
| Claude worker | `Agent` tool, default `subagent_type` (`fork` ignores `model`) | `claude -p` | `claude -p` | `claude -p` | `claude -p` |
| Long command | Bash `run_in_background` + completion notification | jobs (below) | jobs | jobs | jobs |
| Foreground cap | 600 s (silently cut) | the Bash tool's: 120 s default, 600 s max | ~30 s, then the command continues as a background terminal (documented: `yield_time_ms` max 30 000) | set by the model per call (measured: `timeout: 90000` on a `sleep 75`, which finished normally) | 10 s, then the command continues as a background task (measured: `WaitMsBeforeAsync: 10000`) |
| `route2-wait --max` | — (harness) | 25 | 25 | 25 | 8 |
| Ask the user | `AskUserQuestion` | nobody — `--unattended` only | `request_user_input` when the tool is listed, else a plain question and end the turn | a plain question and end the turn | `ask_question` (documented in agy's bundled skills) |
| Ask only when | no worker is running | — | no job is `running`, `lingering` or `orphaned` | same | same |
| Supported configuration | default | default | `codex --sandbox danger-full-access` — the director's own commands must reach the model APIs and run the tests; Codex's default sandbox blocks the network | a project `.cursor/cli.json` allowing exactly the commands below, **without `--force`** | approve command prompts **and file-write prompts** ("Allow creation of this file?" — measured: an interactive agy director asks before writing `.route2/PLAN.md` too), or `permissions.allow` rules in `~/.gemini/antigravity-cli/settings.json` |

**Cursor's allowlist** (`<project>/.cursor/cli.json`; documented: "Only permissions can be
configured at the project level"). Rules match the command's executable, and an absolute path
works (measured: `Shell(/…/bin/route2-run)` allowed exactly that script). A director needs:

- every helper by absolute path — `Shell(<R2>/bin/route2-host)`, `…/route2-lock`, `…/route2-run`,
  `…/route2-wait`, `…/route2-kill`, `…/route2-env`, `…/route2-catalog`, `…/route2-state`,
  `…/route2-fp`, `…/route2-validate`, `…/route2-roles`;
- the CLIs it checks directly in stage 0 — `Shell(codex)`, `Shell(agy)`, `Shell(agent)`,
  `Shell(claude)` (worker launches go through `route2-run`, which needs no further rule);
- `Shell(git)`, `Shell(jq)`, the project's test command, and the plain utilities a director reads
  and writes state with: `cat`, `ls`, `mkdir`, `printf`, `echo`, `grep`, `sed`, `head`, `tail`,
  `wc`, `date`, `sha256sum`, `readlink`, `dirname`, `command`, `test`;
- for UI runs the screenshot tool (`Shell(npx)` for Playwright).

`Shell(bash)` in that list makes it effectively broad — said plainly: a headless Cursor director
can run what `bash -c` can. Without it, directing works only interactively, approving each
command. Never `--force`: it turns Cursor's sandbox off entirely (measured).

## Capability checks (stage 0 step 3a)

Run from your own shell, for what the selected run needs; a failure is a stop with the remedy from
the "Supported configuration" row:

1. **State:** create and remove `.route2/probe-<id>`; take the lock.
2. **Git metadata** (what a commit needs, without touching the user's index or branch; measured
   to pass inside Codex `danger-full-access` and Cursor's allowlist, V2b):
   `git hash-object -w` of a throwaway blob; `GIT_INDEX_FILE=<git-dir>/route2-probe-<run>-<rand>
   git read-tree HEAD`, then remove that file; `git update-ref refs/route2/probe-<run>-<rand> HEAD`
   and `git update-ref -d` of it — unique names, removed by a trap on failure too. When a split is
   decided, also `git worktree add --detach .route2/worktrees/probe-<rand>` and `remove`.
3. **Model reach:** the free health check per family from this shell (`codex doctor --summary`,
   `agent status`, `agy models`, `claude auth status`); the stage 0 probes are the proof of API
   access. A DNS, connect, TLS or proxy error marks that transport ineligible for this host
   session, with the remedy printed.
4. **Tests** (not under `--skip-tests`): the reach probe's cheap check, run by you.
5. **Visual** (only for a user-facing layout change): the screenshot tool starts and writes one
   file under `.route2/evidence/`, and you can read an image on this host. Measured (V14,
   2026-10-11): a Playwright screenshot of a test page was read back correctly ("ZEBRA 42",
   purple) by Claude Code, `claude -p`, Codex (`gpt-6-luna`), Cursor (`grok-4.7-low`, plan mode)
   and agy (`gemini-3.8-flash-low`, print mode) — so every host can inspect screenshots, and a
   Cursor builder can be sent screenshot paths in a fix round (V12). The screenshot tool itself
   must be runnable from the director's shell (Cursor: `Shell(npx)`).
6. A host permission prompt that is denied → stop (unattended: row 2), never a hang.

## Jobs (every host except an interactive Claude Code)

An interactive Claude Code keeps route 3.4's mechanism: the Bash tool's background mode and its
completion notification. No other host has a notification that wakes the director when a command
finishes, so route2 brings its own:

- `bin/route2-run --gen N --job <id> --run <run_id> --role <role> [--kind test]
  [--test-cmd "<cmd>"]… [--test-runner <path>]… -- <command…>` launches the command in its own
  session and process group (`setsid`), stdin `/dev/null`, every descriptor above 2 closed — so it
  never holds the lock — with stdout and stderr in `.route2/jobs/<id>/out` and `err`. It writes
  `meta.json` inside the fence and returns at once. Job ids are `<run_id>.<role>.r<round>.a<attempt>`
  and never reused.
- A wrapper records every process of the job's tree in `members.jsonl` (one poll right after the
  spawn, then every second): pid, start time, **original** parent, process group, argv, cwd. A
  process that `setsid`s or is re-parented later stays a member. A process that was never a
  descendant is never a member, whatever its command line.
- `bin/route2-wait <id> [--max S] [--peek] [--also <file>]` prints `{state, code, elapsed,
  last_progress_at, idle_s, progress_source, live_members, unowned}`:

  | state | meaning |
  | --- | --- |
  | `running` | the leader (or the wrapper finishing it) is alive |
  | `exited` | `exit` written and no member left — terminated; success only for code `0` (`signal:<n>` and `launch-failed` are failures) |
  | `lingering` | `exit` written but members remain (a writer left a background process) — **not** terminated |
  | `orphaned` | leader gone, no `exit`, members remain |
  | `lost` | leader gone, no `exit`, no member left — terminated, outcome unknown |
  | `uncertain` | `/proc` unreadable — never counted as terminated |

  Progress = new bytes on stdout (the `--json`/`stream-json` event streams of codex, `claude -p`
  and Cursor, thinking deltas included), or new stderr/`--also` bytes whose last line differs from
  the previous one (a repeated identical error line is not progress). `--also` is agy's newest CLI
  log (`~/.gemini/antigravity-cli/log/cli-*.log`), since agy writes its envelope only at exit.
  `unowned` lists processes in the job's directory whose **full command line** equals the job's
  recorded command or a recorded test command but that were never members — reported, never
  signalled; for a writer you do not integrate or relaunch until they are settled.
- `bin/route2-kill <id> --gen N [--grace S]` stops a job **without ever signalling a test**, one
  step per call (call it again until `done` or `blocked`): `waiting-tests` while any protected
  process lives — a test root (a member whose full command line equals a recorded test command, or
  whose argv holds a recorded runner path such as `vendor/bin/pest` — never a bare interpreter name
  like `php`), every recorded descendant of it, and every shell wrapper between the leader and it;
  then `signalled` (SIGTERM to each remaining member individually, inside the fence), `killed`
  (SIGKILL after the grace period), `done`, or `blocked` (a member outside the recorded tree, a
  member surviving SIGKILL, or `uncertain`). Test jobs (`--kind test`) are refused outright.

**You never end your turn while a job is `running`, `lingering` or `orphaned`.** Loop
`route2-wait --max <n>` (the adapter row above: 25, agy 8), sample progress, and ask the user
nothing meanwhile. Hang = no progress for max(15 min,
2 × T_slow) → read the job's files → `route2-kill`; never for tests.

**`blocked`** is the one outcome on which you may end your turn with a job unresolved: report the
members (pid, argv, cwd), keep the job evidence and **keep the lock** (the checkout stays
reserved), launch nothing. A later `--resume` of the same run reconciles: members gone →
dirty-exit and continue; still there → `blocked` again. It is a state to clear, not a decision —
the same under `--unattended`.

### Survival (V9)

Whether a `route2-run` job survives across separate director commands and after the director's
session ends — measured per host in its supported configuration:

| Host | Across commands | After the session ends | Mode |
| --- | --- | --- | --- |
| Claude Code (interactive) | n/a (background tool) | n/a | harness |
| `claude -p` (haiku, `--tools Bash`, `dontAsk`) | yes | yes | detached |
| Codex (`codex exec -s danger-full-access`) | yes | yes | detached |
| Cursor (`agent -p`, project allowlist, no `--force`) | yes | yes | detached |
| agy (interactive, commands approved) | yes | yes (session killed, job still `running`) | detached |

Measured 2026-10-11 (V9): in each host a director ran `route2-lock acquire`, `route2-run … --
sleep 900` and `route2-wait --peek` as separate commands; the job was `running` in the third
command and still `running` after the host process was gone; `route2-kill` then ended it.

agy also has its own mechanism: a command still running after 10 s becomes a background task
(`/tasks`), and when it finishes **agy wakes the model with its output** (measured: a `sleep 130`
returned to the model at 01:57:56 without any prompt). route2 does not rely on it: agy uses the
same jobs as every other non-Claude-Code host, and the never-end-the-turn rule holds there too.

### End-to-end canaries (V11, 2026-10-11)

Real `/route2` runs on a scratch repository (a bash string library and its test script), each host
in its supported configuration, all `--unattended`:

| Host (director model) | Run | Outcome |
| --- | --- | --- |
| Codex (`gpt-6.1-sol`, `danger-full-access`) | `--plan-only --model=sonnet --critic=grok --rounds=1` | `result: plan-only`; Grok approved; checkpoint with `host: codex`, director identity from its rollout, frozen catalog; ledger; fingerprint around the critic; lock released |
| Claude Code `claude -p` (Sonnet) | same | `needs-decision` row 3 at the cap — Grok found a real locale bug (`[a-z]` keeps Polish letters under `pl_PL.UTF-8`); the resume refused a checkpoint the director had written without `route2-state` (row 2); after the user's `adopt` the resume ran round 2, Grok found a second locale issue, `needs-decision` again |
| Cursor (`grok-4.7-high`, project allowlist) | `--plan-only --model=sonnet --critic=sol --rounds=1` | `result: plan-only`; Sol approved; `director_family: unknown` → `self` excluded; audit consistent; lock released |
| agy (`gemini-3.8-flash-high`, interactive via tmux, commands and file writes approved) | `--plan-only --model=sonnet --critic=grok --rounds=1` | `needs-decision` row 3 (the same locale finding); Assign line and cost table complete; lock released |
| Codex (`gpt-6.1-sol`) | full build, `--model=sonnet --critic=grok` | `result: done`, commit; tests run by the director |
| Codex (`gpt-6.1-sol`) | full build split into two parallel Sonnet workers in worktrees | both parts integrated, worktrees removed, tests (51 checks) green, one commit |
| Claude Code `claude -p` (Sonnet) + a `claude` shim | full build, `--model=sonnet --critic=grok` | the shim killed the native builder after its first edit with a quota error → the director kept the partial edit after reading it, switched `sonnet` to agy (`claude-sonnet-5-5`), the agy session finished, the director ran the tests and committed; ledger row `transport-switch (quota)` |

Weak spots the canaries showed: a Sonnet director wrote ledger rows without `stage`, `cli`,
`model_requested` or tokens, and skipped a separate probe when the critique call itself showed the
model; one wrote the checkpoint directly (caught by the audit). A director that dismissed a
fingerprint alarm as a false positive led to the rule that it never overrules `changed`.

## Lock

One director per checkout. `.route2/lock` holds `{run_id, token, generation, host, session_key,
liveness}` and is changed only under `flock -w 30` on `.route2/lock.flock`.

- **Liveness**: `{kind: pid, pid, starttime}` when `route2-host` found the host process, else
  `{kind: heartbeat}` — every fenced call touches `.route2/lock.heartbeat`, and the owner is live
  while it is younger than `ROUTE2_HEARTBEAT_WINDOW` (default 1800 s; set it to at least 2 ×
  T_slow).
- **Generation fencing.** Every acquire or takeover increments the generation (it never goes back,
  even after a release) and publishes the new owner's liveness in the same flock section. Every
  mutation runs as `route2-lock exec --gen N -- <command>`, which checks `N` and runs the command
  **while still holding the flock** (`flock -o`: the command and its children hold no lock
  descriptor) — no takeover can fall between the check and the mutation. A nested `route2-lock
  exec` is refused instead of deadlocking. A stale generation → you were superseded; stop without
  touching anything.
- **Re-entrant** only for the same owner (token and liveness). A second `/route2` in the same host
  session is a different owner.
- A **live** owner keeps the lock against everyone, a `--resume` of its own run included. `--resume`
  takes over only a **stale** owner (pid dead or restarted, heartbeat expired) and then adopts the
  run's jobs. Two simultaneous resumes: the first takes over and publishes its liveness, the second
  finds a live owner (measured in T8).
- A **different run** takes over a stale lock only when no job of the old run is `running`,
  `lingering`, `orphaned` or `uncertain` — otherwise `blocked`.
- Released at the report and at every stop; **kept** on `blocked`.
- A concurrent `/route` (the older skill) cannot see this lock; do not run both in one checkout.

## Transport switch

When a Claude slot's transport fails with quota or unavailability (never a safety stop, an
authority question, a decline or a bad verdict) and the slot has another eligible transport serving
**the same model id**, the switch is one transaction:

1. **Confirm the old session ended.** A job: `route2-wait` → `exited`/`lost`, or `route2-kill` →
   `done`; `lingering`/`orphaned` that stays so → `blocked`. An Agent-tool subagent: its completion
   notification arrived, or `TaskStop` stopped it and the task list no longer shows it. A recorded
   test still running → wait for it. Never a second writer next to a live one.
2. Dirty-exit protocol; record `tree_state`.
3. Checkpoint (`sessions[].outcome: transport-switch`).
4. Resolve the same model id on the next eligible transport of the slot's order (skipping denied
   and unavailable ones); probe it if no fresh probe exists. A transport without that version is not
   a switch target — the event is a swap.
5. A new session there with a brief **rewritten for its capabilities** (agy and `claude -p`:
   edits-only, you run the tests; Cursor: sandboxed), the goal, the current diff (tracked and
   untracked), the open findings, the effort re-mapped and marked `(clamped)` where needed.
6. Announce `transport: opus native→agy (quota; edits-only, director runs tests)`; ledger row with
   `outcome: "transport-switch"` on the abandoned call.

The family does not change, so critics, reviewer and gate stand. A forced `@transport` never
switches. With no transport left, or a different version, it is a swap (SKILL.md). Under
`--unattended` the switch is automatic too (`docs/unattended.md` A16a, A17).

The `claude -p`-native path of this transaction is exercised by a canary with a `claude` shim that
fails after a real `init` and a first edit, with a `claude -p` director (whose shell keeps the
`PATH` it was started with). A Codex director cannot carry such a shim: its shell rebuilds `PATH`
from the login profile (measured: the shim directory was dropped and `~/.local/bin/claude` won).
The interactive Agent-tool path follows the same steps but is not exercised by a canary.

**Cursor leaves helper processes behind.** After an `agent -p` call exits, processes of its tree
can stay alive (measured in two canaries: the critic job ended `lingering`), and the director ended
them with `route2-kill`. That is the `lingering` state working as intended; a critic's lingering
members never block its verdict, but they are cleared before the next writer starts.

## Resume across hosts

`--resume` reads `run_id` and token from the checkpoint, takes the lock (stale owner only), then
re-detects the host and your identity. Same host, family and model line → continue. A different
host, family or line → attended: say what changes (adapter, `self` eligibility, every critic and
reviewer re-checked against the builder) and ask; unattended: row 2 stop. Recorded jobs are
reconciled before anything else.
