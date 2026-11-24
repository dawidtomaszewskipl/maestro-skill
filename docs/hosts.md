# Host: Claude Code

> **What this page is for.** How the director runs inside Claude Code, interactive or headless: how it confirms the host, launches and waits for long jobs, asks you, and locks the repository. The plain overview is in [the guide](guide/setup-and-hosts.md).

Since 2.0.0 maestro directs only from Claude Code. Codex (`codex exec`) and agy are worker
transports, never directors. Claude Code runs the director in one of two modes, and the loop uses
the column of the adapter table below that belongs to it. Measurement history lives in
`docs/evidence.md`.

## Detection

`bin/maestro-host` prints one JSON line: `{host, interactive, session_key, host_pid,
host_pid_starttime, director_family, evidence[]}` with `host` one of:

| `host` | Meaning | What you do |
| --- | --- | --- |
| `claude-code` | the nearest agent CLI above this shell is Claude Code and `CLAUDECODE=1` is set | continue |
| `unsupported` | the nearest agent CLI is another one (`codex`, `agy` or another agent CLI): it is directing | stop: maestro runs only in Claude Code |
| `unknown` | no agent CLI in the visible ancestry and the markers do not settle it | attended: ask the user to start `/maestro` from Claude Code; unattended: row 2 stop |

The rules behind it:

1. **Ancestry.** It walks up from the shell's parent through `/proc/<pid>/stat` and matches each
   process by `readlink /proc/<pid>/exe` and `argv[0..1]`, never by `comm` (Linux truncates it to
   15 bytes). Claude Code is `~/.local/share/claude/versions/<v>` (one ELF, argv `claude …`, also
   `claude daemon run`). The **nearest** agent CLI wins. Child processes inherit markers (measured:
   a `codex exec` launched from Claude Code still has `CLAUDECODE=1`), so an outer CLI's marker is
   no conflict: `claude -p` started from a Codex shell is `claude-code`.
2. **Hidden chain.** A sandbox can hide the CLI that really runs the shell. When another CLI's
   marker is set (`CODEX_THREAD_ID`, `ANTIGRAVITY_AGENT`…) but that CLI is not in the visible
   ancestry, the ancestry is not trusted: `unknown`.
3. **Markers only** (no visible ancestry): `CLAUDECODE=1` alone gives `claude-code`. Any other
   CLI's marker gives `unknown`.

**Interactive or headless** is read from Claude Code's command line: `-p`/`--print` means headless.
**A headless director requires `--unattended`**, because nobody can answer there.

## Director identity

You know your own model: the system prompt names it. `director_family` is `claude`. Pass your model
line (`opus`, `fable`, `sonnet`, `haiku`) as `director_line` to `maestro-roles` for `self`. If your
model changes between dispatches (a `/model` switch), re-validate `self` and the degraded-mode
roles. An assignment that became illegal → ask (unattended: row 2).

## Adapters

| Concern | Interactive Claude Code | Headless `claude -p` |
| --- | --- | --- |
| Invoke the skill | `/maestro` | `/maestro --unattended …` in the prompt |
| Claude worker | `Agent` tool with an explicit `model`, default `subagent_type` (`fork` ignores `model`); `claude -p` for a pinned native id | `claude -p` |
| Long command | a job (below): `maestro-run`, foreground, returns at once | the same |
| Waiting for it | one Bash call with `run_in_background: true`: `maestro-wait <job> --until-done`; its completion notification wakes you | `maestro-wait <job> --max 540` in a foreground loop, each call with `timeout: 600000` (the default 100 fits the 120 s default cap) |
| Foreground cap | 600 s, cut silently | the Bash tool's: 120 s by default, 600 s at most |
| Ask the user | `AskUserQuestion`, only while no worker is running | nobody: `--unattended` only |
| Progress sampling | every 5 min (a background `sleep 300` or `Monitor`): `maestro-wait <job> --peek` or `maestro-status` | the `maestro-wait` loop (`last_progress_at` persists) |

A Bash permission prompt that is denied is a stop (unattended: row 2), never a hang.

## Capability checks (stage 0 step 3a)

`"$MAESTRO/bin/maestro-preflight" --gen N --interactive <true|false> [--api] [--no-codex]
[--no-agy] [--worktree] [--skills] [--resume]` runs, without a model turn and inside the fence
where it writes:

- **step 2:** creates `.maestro/`, adds `.maestro/` to `info/exclude` (never `.gitignore`), copies
  `docs/schemas/*.json`, checks for a clean tree and leftover `maestro-draft-*` stashes;
- **state and git:** a probe file in `.maestro/`, `git hash-object -w`, a throwaway
  `GIT_INDEX_FILE` `read-tree`, a throwaway ref, with `--worktree` also `git worktree add/remove`.
  Every name is unique and removed by a trap;
- **step 3:** `claude auth status` (warns when `loginExpiresAt` is less than 24 h away),
  `codex login status`, `codex doctor --summary`, `agy models`, `maestro-sdk --check` with `--api`;
- **the Codex config mode** (`isolated`, or `pinned` with the keys that forced it) and **step 7**,
  the project `.codex/config.toml` warnings;
- with `--skills` **step 6**: agy's workspace skills (`agy -p "/skills" --mode plan`).

It answers `{tree, git, transports, codex_config, skills, warnings, stops}`. Every entry in
`stops` is a stop with the remedy in its text (attended: tell the user; unattended: row 2). A git
write that fails names the likely cause: since Claude Code 2.1.323 the Bash sandbox makes `git
worktree add/remove` and commits in a worktree read-only, so allow the repository's `.git` or run
without the sandbox. Exit 4 = the fence refused: you were superseded, stop at once.

Two checks stay yours:

- **Tests** (not under `--skip-tests`): the cheap check of the tests, run by you.
- **Visual** (a user-facing layout change only): the screenshot tool starts and writes one file
  under `.maestro/evidence/`, and you read it back (measured: Claude Code and `claude -p` read a
  Playwright screenshot correctly, `docs/evidence.md`).

## Jobs

Every external worker (`codex exec`, agy, `claude -p`, `maestro-sdk`) and every test run is a job,
in both modes. Only the wait differs: an interactive director is woken by the completion
notification of one background `maestro-wait --until-done`; a headless one has no notification, so
it loops `maestro-wait` in the foreground. A Claude worker on the `Agent` tool (interactive,
`native`) is not a job: the harness owns it. maestro passes it a `model` and no effort. (Upstream fact only, recorded
2026-11-24: the Agent tool has an `effort` parameter, which Claude Code 2.1.329 fixed to be honored
for named teammates in agent teams — vendor, `CHANGELOG.md`. maestro does not use it; the effort
of an Agent-tool worker is recorded as the model's default, `docs/workers.md`.) Headless, a
background subagent of `claude -p` would share one 10-minute wait ceiling since 2.1.328
(`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`, with `CLAUDE_CODE_FORK_SUBAGENT=0`); maestro's `-p`
workers start no subagents.

- `bin/maestro-run --gen N --job <id> --run <run_id> --role <role> [--kind test]
  [--test-cmd "<cmd>"]… [--test-runner <path>]… -- <command…>` launches the command in its own
  session and process group (`setsid`), stdin `/dev/null`, every descriptor above 2 closed (so it
  never holds the lock), stdout and stderr in `.maestro/jobs/<id>/out` and `err`. It writes
  `meta.json` inside the fence and returns at once. Job ids are `<run_id>.<role>.r<round>.a<attempt>`,
  hold only `[A-Za-z0-9._:-]` (no `..`) and are never reused.
- A wrapper records every process of the job's tree in `members.jsonl` (one poll right after the
  spawn, then every second): pid, start time, **original** parent, process group, argv, cwd. A
  process that `setsid`s or is re-parented later stays a member. A process that was never a
  descendant is never a member, whatever its command line.
- `bin/maestro-wait <id> [--max S] [--peek | --until-done] [--also <file>]` prints `{state, code,
  leader_alive, elapsed, last_progress_at, idle_s, progress_source, live_members, unowned}`:

  | state | meaning |
  | --- | --- |
  | `running` | the leader (or the wrapper finishing it) is alive |
  | `exited` | `exit` written and no member left: terminated; success only for code `0` (`signal:<n>` and `launch-failed` are failures) |
  | `lingering` | `exit` written but members remain (a writer left a background process): **not** terminated |
  | `orphaned` | leader gone, no `exit`, members remain |
  | `lost` | leader gone, no `exit`, no member left: terminated, outcome unknown |
  | `uncertain` | `/proc`, the leader or a member unreadable. It outranks a live leader (`leader_alive` says whether the leader still runs), is never counted as terminated, and `maestro-wait` blocks on it like `running` while the leader lives |

  Progress = new bytes on stdout (the `--json`/`stream-json` event streams of codex and `claude
  -p`, thinking deltas included), or new stderr/`--also` bytes whose last line differs from the
  previous one (a repeated identical error line is not progress). `--also` is the agy run's own
  log (`--log-file "$J/agy.log"`), since agy writes its envelope only at exit. `unowned` lists
  processes in the job's directory whose **full command line** equals the job's recorded command or
  a recorded test command but that were never members. They are reported, never signalled; for a
  writer you do not integrate or relaunch until they are settled.
- `bin/maestro-wait <id> --until-done [--max S] [--also <file>]` blocks, with no cap, until the
  job needs you, and prints that one snapshot:

  | state seen | `--until-done` |
  | --- | --- |
  | `running`; `uncertain` with `leader_alive: true` | keeps waiting |
  | `exited`, `lost` | returns: terminated |
  | `lingering`, `orphaned` | returns: nothing ends them but `maestro-kill`, so waiting would never end |
  | `uncertain` without a live leader | returns: read the job's files and `--peek` again |

  Exit 0 with the snapshot in every returning case. An explicit `--max S` caps the wait: still
  waiting at the deadline → the snapshot and exit 3. It writes the progress record every 2 s, so
  give it the job's `--also`; `--peek` beside it then shows a true `idle_s`.
- `bin/maestro-kill <id> --gen N [--grace S]` stops a job **without ever signalling a test**, one
  step per call (call it again until `done` or `blocked`):
  - **Protected:** a test root and everything under it. A test root is a member whose recorded
    *or current* command line equals a recorded test command, or holds a recorded runner path such
    as `vendor/bin/pest` (never a bare interpreter name like `php`). Every descendant of a test
    root and every shell wrapper between the leader and it is protected too. A member that later
    `exec`s into the runner is a test root from then on.
  - **Proven safe to signal:**
    - the leader;
    - a member whose recorded ancestry reaches the wrapper;
    - a member the recorder never saw (found in the job's process group), only if its *current*
      ancestry reaches a recorded member or the wrapper;
    - a recorded member whose parent is unknown (re-parented before the first poll), only when the
      job has no tests at all.

    Anything else → `blocked` (fail closed).
  - **Steps:**
    - `waiting-tests` while anything is protected: nothing is signalled, the lock is not held.
    - Otherwise, **inside the fence**, the whole classification runs again. Only if it still finds
      nothing protected or unknown does SIGTERM go to each member individually, and `kill.state`
      advances in the same fenced section (`signalled`).
    - After the grace period the same happens with SIGKILL (`killed`).
    - Then `done`, or `blocked` for members that survive SIGKILL or are `uncertain`.
    - Test jobs (`--kind test`) are refused outright.
- The wrapper's own children (its poll `sleep`, its last member scan) are infrastructure and never
  members. An unreadable leader or member makes the state `uncertain` even while the leader is
  alive, so `maestro-kill` never classifies an incomplete live set.

**Never end your turn while a job is `running`, `lingering`, `orphaned`, or `uncertain` with
`leader_alive: true`**, and ask nothing meanwhile.

- **Interactive:** every such job has one background `maestro-wait <job> --until-done` task. That
  task is the only thing that wakes you: a job without one (the task was stopped, the turn was
  interrupted, a `--resume` adopted the job) gets it re-armed before anything else. When it
  returns:
  - `exited`/`lost` → read the job;
  - `lingering`/`orphaned` → act in the same turn (`--peek`, then `maestro-kill`); re-arming
    would return at once. `maestro-kill` → `waiting-tests` (or `refused`, a test job): wait on the
    sampler and `--peek` again;
  - `uncertain` → `--peek` again; with a live leader re-arm, otherwise `maestro-kill` answers
    `blocked`;
  - exit 3 (you passed `--max`) → still running: re-arm.
- **Headless:** loop `maestro-wait --max 540` (Bash `timeout: 600000`) and sample progress.

`maestro-run` is the one sanctioned detach. The director's own commands never use `&`, `nohup`,
`setsid` or `disown`: a process detached by hand has no task, so nothing would wake you
(`docs/troubleshooting.md`).

A hang is no progress for max(15 min, 2 × T_slow): read the job's files, then `maestro-kill`.
A test never counts as hung.

**`blocked`** is the one outcome on which you may end your turn with a job unresolved:
- report the members (pid, argv, cwd);
- keep the job evidence and **keep the lock**, so the checkout stays reserved;
- launch nothing.

A later `--resume` of the same run reconciles: members gone → dirty-exit and continue; still there →
`blocked` again. It is a state to clear, not a decision, and the same under `--unattended`.

A `maestro-run` job survives separate director commands and the end of the director's session
(measured, `docs/evidence.md`), which is what `--resume` relies on. The job belongs to the
wrapper's own session and process group, not to a Bash task: stopping the background
`--until-done` task stops only the waiter (measured 2026-11-14 in a Claude Code session:
`maestro-run … -- sleep 45`, the waiter stopped with `TaskStop`, `--peek` still `running`,
`maestro-kill` → `done`). So when the user interrupts the director, the job keeps running:

- back in the same session → `--peek`, then re-arm `--until-done` or `maestro-kill`;
- session gone → `--resume` adopts the job;
- to stop a job, always `maestro-kill`, never the harness task.

## Lock

One director per checkout. `.maestro/lock` holds `{run_id, token, generation, fence_sha, host,
session_key, liveness}` and changes only under `flock -w 30` on `.maestro/lock.flock`.

- **Liveness**: `{kind: pid, pid, starttime}` when `maestro-host` found the Claude Code process,
  else `{kind: heartbeat}`. Every fenced call touches `.maestro/lock.heartbeat`, and the owner is
  live while it is younger than `MAESTRO_HEARTBEAT_WINDOW` (default 1800 s; set it to at least 2 ×
  T_slow).
- **Fencing.**
  - Every acquire or takeover:
    - increments the generation (it never goes back, even after a release);
    - publishes the new owner's liveness in the same flock section;
    - returns a **fence** `<generation>.<secret>` to that owner alone.
  - The lock stores only `sha256(fence)`, so neither the readable generation nor the run's token
    lets a contender mutate. Re-entry needs the fence (`acquire … --fence F`).
  - Every mutation runs as `maestro-lock exec --gen F -- <command>`, which checks the fence and
    runs the command **while still holding the flock** (`flock -o`: the command and its children
    hold no lock descriptor). No takeover can fall between the check and the mutation.
  - A helper given `--gen` fences itself: `maestro-run`, `maestro-state`, `maestro-kill`,
    `maestro-ledger`, `maestro-preflight`, `maestro-catalog refresh|record-probe|record-resolved`.
    Call it directly. A nested `maestro-lock exec` runs directly while the enclosing holder is
    alive and the fence is current, and is refused once that holder is gone.
  - Workers and jobs never inherit the fence variables (`maestro-env`, `maestro-run`).
  - A stale generation means you were superseded: stop without touching anything.
- **Re-entrant** only for the holder of the current fence. A second `/maestro` in the same session,
  or a second resume of the same run, is a different owner.
- **Takeover.** A **live** owner keeps the lock against everyone, including a `--resume` of its own
  run. `--resume` takes over only a **stale** owner (pid dead or restarted, heartbeat expired) and
  then adopts the run's jobs. When two resumes start at once, the first takes over and publishes
  its liveness, and the second finds a live owner (tested in T8).
- **Another run** takes over a stale lock only when no job of the old run is `running`,
  `lingering`, `orphaned` or `uncertain`. Otherwise the result is `blocked`.
- Released at the report and at every stop; **kept** on `blocked`.

## Transport switch

When a Claude slot's transport fails with quota or unavailability (never a safety stop, an
authority question, a decline or a bad verdict) and the slot has another eligible transport serving
**the same model id**, the switch is one transaction:

1. **Confirm the old session ended.**
   - A job: `maestro-wait` → `exited`/`lost`, or `maestro-kill` → `done`. One that stays
     `lingering`/`orphaned` → `blocked`.
   - An Agent-tool subagent: its completion notification arrived, or `TaskStop` stopped it and the
     task list no longer shows it.
   - A recorded test still running → wait for it.

   Never start a second writer next to a live one.
2. Dirty-exit protocol; record `tree_state`.
3. Checkpoint (`sessions[].outcome: transport-switch`).
4. Resolve the same model id on the next eligible transport of the slot's order
   (`maestro-roles --transports`; the order comes from `bin/slots.json`: opus and sonnet native →
   agy → api, fable and haiku native → api). Denied and unavailable transports are skipped. Probe
   the target if no fresh probe exists. A transport without that version is not a switch target:
   the event is a swap.
5. Start a new session there with:
   - a brief **rewritten for its capabilities** (agy, `claude -p` and `api` are edits-only, so you
     run the tests);
   - the goal;
   - the current diff, tracked and untracked;
   - the open findings;
   - the effort re-mapped, marked `(clamped)` where needed.
6. Announce `transport: opus native→agy (quota; edits-only, director runs tests)`, and write a
   ledger row with `outcome: "transport-switch"` on the abandoned call.

The family does not change, so critics, reviewer and gate stand. A forced `@transport` never
switches.

**`api` is the last transport** of every Claude slot. It is a switch target only with `--sdk` or
policy `api.fallback = true`. Announced as `transport: opus native→api (quota; API credit, budget
$<left>; edits-only, director runs tests)`.

- Under `--sdk` the slot starts on `api` (a forced transport), so an `api` failure never falls back
  to the subscription.
- Fable has no agy transport, so a native quota hit on Fable without `api` is a swap.
- With no transport left, or only a different version, it is a swap (SKILL.md, "Time and the
  watchdog").
- Under `--unattended` the switch is automatic too (`docs/unattended.md` A16a, A17).

The `claude -p`-native path is exercised by the canary with a `claude` shim (`tests/canary/`).
The interactive Agent-tool path follows the same steps but no canary exercises it.
