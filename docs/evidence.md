# Evidence

> **What this page is for.** The measurements behind the rules in `docs/hosts.md`: what was run, on which versions, and what came out. The director does not need this page at run time.

Until 1.4.0 maestro could direct from four hosts, and the release gates measured each of them. 2.0.0
keeps only Claude Code as the director, so only its rows are kept here. The rows for the other
directors are in git history (tag `v1.4.0`, `docs/hosts.md`).

Unless a row says otherwise, everything was measured on this machine on 2026-10-11 with Claude Code
2.1.296.

## Detection

- Child processes inherit markers: a `codex exec` launched from Claude Code still has
  `CLAUDECODE=1`. A marker says "Claude Code is somewhere above you", not "Claude Code is your
  parent". That is why `maestro-host` decides by the nearest agent CLI in the ancestry.
- A sandbox can hide part of the process chain. A worker CLI's own sandbox hid that CLI, and the
  nearest visible process was the Claude Code daemon that had launched it, which is a wrong answer
  if trusted. Codex's sandbox hides the whole ancestry (a pid namespace). Hence the rule that a set
  marker of a CLI absent from the visible ancestry makes the ancestry untrusted.
- Claude Code's executable is a single ELF under `~/.local/share/claude/versions/<v>`; background
  sessions run as `claude daemon run` and `claude bg-spare …`.

## Git capabilities (V2b)

`tests/canary/v2b.sh` (objects, a throwaway index file, refs, a worktree, a commit) passed from
Claude Code's shell, interactive and `claude -p`. Since Claude Code 2.1.323 a Bash sandbox makes
`git worktree add/remove` and worktree commits read-only (changelog); `maestro-preflight --worktree`
reports that as a stop.

## Job survival (V9)

In a `claude -p` director (haiku, `--tools Bash`, `dontAsk`), `maestro-lock acquire`, `maestro-run …
-- sleep 900` and `maestro-wait --peek` ran as separate commands. The job was `running` in the third
command and still `running` after the director process was gone. A second check 11 minutes after
the director session ended found it still `running` (elapsed 672 s). Since 2.1 interactive jobs are
`maestro-run` jobs too: a background `maestro-wait --until-done` stopped with TaskStop left the job
`running` (`leader_alive: true`), and `maestro-kill` then ended it (`signalled` → `done`).

## Screenshots (V14)

A Playwright screenshot of a test page was read back correctly ("ZEBRA 42", purple) by Claude Code
and by `claude -p`. Codex (`gpt-6-luna`) and agy (`gemini-3.8-flash-low`, print mode) read it too,
so a Codex builder can be sent screenshots as `--image=` attachments in a fix round, and an agy
worker their paths.

## End-to-end canaries (V11)

Real `/maestro` runs on a scratch repository (a bash string library and its test script, built by
`tests/canary/mkcanary.sh`), all `--unattended`, with a `claude -p` Sonnet director:

| Run | Outcome |
| --- | --- |
| `--plan-only --model=sonnet --rounds=1` with a cross-family critic | `needs-decision` row 3 at the cap: the critic found a real locale bug (`[a-z]` keeps Polish letters under `pl_PL.UTF-8`). The resume refused a checkpoint the director had written without `maestro-state` (row 2); after the user's `adopt` the resume ran round 2, the critic found a second locale issue, `needs-decision` again |
| full build `--model=sonnet` with a `claude` shim that fails after the builder's first edit with Claude Code's quota message | the director kept the partial edit after reading it, switched `sonnet` to agy (`claude-sonnet-5-5`), the agy session finished, the director ran the tests and committed; ledger row `transport-switch (quota)` |
| full build, the director killed while the build job ran, then `/maestro --resume --unattended` (`tests/canary/build-interrupt-resume.sh`) | the job survived; the resume reconciled the finished build, ran the tests and committed |

The canaries showed these weak spots:
- A Sonnet director wrote ledger rows without `stage`, `cli`, `model_requested` or tokens. Rows now
  come only from `maestro-ledger`, which reads the job's own output.
- One director wrote the checkpoint directly, and the audit caught it.
- A director that dismissed a fingerprint alarm as a false positive led to the rule that it never
  overrules `changed`.

## Codex rollouts

The `turn_context` fields `maestro-identity codex` checks (`model`, `effort`, `sandbox_policy`,
`approval_policy`, `approvals_reviewer`, `permission_profile`, `cyber_access_program`) were read
from real rollouts:
- On 0.159.2: read-only, rung 1, rung 3 on exec and resume, a worktree writer and its resumed fix,
  rung 4, and a resume at effort `medium` after a launch at the catalog default.
- On 0.166.0: the same fields, with `cyber_access_program: "standard"` new.
- On 0.169.0 (2026-11-14): a read-only probe (`gpt-6.1-sol`, effort low, `cli_version` 0.169.0) passed
  `maestro-identity codex` with `cyber_access_program: "standard"`.

Altered copies are in `tests/run.sh` T13: stale offset, wrong effort, a writer outside its root, a
non-standard cyber access program, truncated JSON, no record, and two rollouts for one id.

## 2.0.0 probes (2026-11-14)

On Claude Code 2.1.325, Codex 0.169.0 and agy 1.5.9:
- `claude -p --model fable` served `claude-fable-5-2` (`init.model` and `modelUsage`). The init event
  had `plugin_errors: null` and only `@builtin` plugins.
- `gemini-4-hydrogen-low` and `gemini-4-argon-low` on agy both answered `SUCCESS` "OK", with
  `finished_reason` null.
- `codex exec` with `gpt-6.1-sol` answered "OK".
- `agy --disable-slash-commands --mode plan` printed `warning: --mode plan has no effect while slash
  command expansion is disabled.` so the flag was not adopted.
- `maestro-identity claude` returned `OK` on the Fable probe; `maestro-identity codex` returned `OK` on
  the Sol probe's rollout.
- `maestro-sdk` (Agent SDK 0.3.325, bundled Claude Code 2.1.325) with `claude-fable-5-2`, `--tools ""`,
  budget 0.05 USD: `OK`, `apiKeySource: ANTHROPIC_API_KEY`, `total_cost_usd` 0.003552 (the SDK's
  estimate). `maestro-sdk --resolve fable` named `claude-fable-5-2`.
- `claude -p --restricted` (Haiku, `--tools "Read,Grep,Glob,Bash"`, `dontAsk`): a Read of
  `/etc/hostname` was denied — but it was denied without `--restricted` too (`dontAsk` refuses reads
  outside the working directories) — and Bash ran in both, because `--tools` names it. maestro's
  read-only lines already name no command tool and pass `--setting-sources ""`, so `--restricted`
  adds nothing measurable: not adopted.
- Live `maestro-catalog refresh`: codex sol 6.1/6/5.6, astra 6, luna 6/5.6, terra 6.1/5.6; agy argon 4,
  gemini 4 (Hydrogen) and 3.8 (Flash), opus 5.5, sonnet 5.5; `pick gemini agy --effort xhigh` →
  `gemini-4-hydrogen-xhigh`. `maestro-preflight` ran in about 2 s.
- Interactive Claude Code (this session): `maestro-host` → `claude-code`, `interactive: true`. A
  Sonnet builder through the `Agent` tool (explicit `model: sonnet`) stayed inside its two files;
  the director's own test run passed; `maestro-ledger --cli claude-agent` wrote the row and the
  commit went through `maestro-lock exec`. The completion reported tokens (40 180), tool uses (3)
  and duration, but **no model**: `--served` is optional since, and `model_served` is `null`.
- agy Argon critic with `--json-schema` (`gemini-4-argon-medium`, plan mode, brief by paths):
  `SUCCESS`, `structured_output` passed `maestro-validate --envelope agy` (verdict approve).
- Arbiter (2.1): `maestro-roles --arbiter` named `argon` for a Claude build whose finding Sol held;
  Argon (`gemini-4-argon-medium`, `arbiter-schema.json`) downgraded the int64 finding from the 2.0
  canary ("a state the system cannot reach"); `maestro-validate --decide arbiter --ids r3-m1` →
  approved.
- `maestro-limits` (2.1): Claude seven-day 0.77 from a probe's `rate_limit_event`, Codex 0.83 of
  its 168 h window from the newest rollout; agy unknown.
