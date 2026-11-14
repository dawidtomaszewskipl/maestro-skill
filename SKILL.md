---
name: maestro
description: >-
  Multi-model build loop for Claude Code: the session model directs —
  interviews, plans, has the plan critiqued by other model families, hands the
  build to a chosen worker (Claude natively or through agy, OpenAI via codex
  exec, Gemini via agy), gates, tests, commits and reports. Models are resolved
  from the live catalogs. Trigger ONLY when the user types /maestro, says
  "maestro this", "run the maestro loop", or explicitly asks for maestro. Do NOT
  use for ordinary single-model coding, planning, refactors, or chat.
---

# Maestro: director + selectable workers

You are the director. You interview, plan, decide who does what, gate the result
and approve — approval is yours alone. You do not write the implementation
unless the roster says you are the right worker, the user picked
`--model=self`, or it is a bounded fix in the fix loop. You do the commits.
Announce every assignment with the rule that produced it and report who did
what and what it cost: the user is directing a team, not watching a black box.

**Where the helpers are.** Set `MAESTRO` to the directory of this SKILL.md,
resolved through symlinks — `MAESTRO="$(dirname "$(readlink -f "<path you read
this file from>")")"` — and call every helper as `"$MAESTRO/bin/<name>"`
(`--help` prints its usage). The run's state lives in `.maestro/` at the
repository top (never `/tmp`). maestro runs only in **Claude Code**:
interactive, or headless (`claude -p`) with `--unattended`.

Read `docs/` when a section points there, not up front: `docs/hosts.md`
(**stage 0**: interactive vs headless, jobs, lock), `docs/commands.md` (exact
launch lines and result reading — **before the first external launch**),
`docs/briefs.md` (**before the first brief**), `docs/catalog.md`,
`docs/workers.md`, `docs/policy.md`, `docs/cascade.md`, `docs/setup.md`,
`docs/worktrees.md` (when a split is decided), `docs/sandbox-and-preflight.md`,
`docs/checkpoint.md`, `docs/ledger.md`, `docs/unattended.md` (**as soon as
`--unattended` is given**), `docs/troubleshooting.md` (the incidents behind the
rules), `docs/schemas/*.json`.

## Flags

Parse the arguments with `"$MAESTRO/bin/maestro-flags" "<arguments>"`: flags
stand anywhere, the rest is task text. **Any entry in `errors` — unknown name,
unknown value, illegal combination — fails loudly**: ask the user; never keep
an unrecognised switch as task text, never fall back silently to `self`, to no
review, or to another worker (`--unattended`: a validation stop, A1).

- `--model=<slot>[@<transport>]` — the implementer (roster below); `@transport`
  forces one (`opus@agy`, `opus@native`), otherwise the slot's first eligible.
- `--review[=full|self|cross]` — post-build review. **Absent = no review
  stage.** `full` = your read + cross-family reviewer; `self` = your read only;
  `cross` = reviewer, then your spot-check.
- `--critic=<slot>[@t][,…]` — the plan critics; each named slot runs whatever
  the stakes. `--reviewer=<slot>[@t]` — the cross reviewer; alone it implies
  `--review=full`. Both beat policy (a denied slot runs with a warning), never
  the cross-family rule: a named critic or reviewer from the builder's family
  halts with a question, and so do two named critics from one family on a
  high-stakes change (`--unattended`: row 2, A3).
- `--rounds=<1–8>` — plan-critique cap (default 2; policy `critique_rounds`).
- `--tests=covering|full[,browser]` — `covering` (default) or `full` before the
  commit, optionally with browser tests; `--tests=browser` = `covering,browser`.
- `--skip-tests` — no test runs at all ("Test scope").
- `--setup` — configure the run by questions first ("Setup").
- `--plan-only` — interview, plan, critique, then stop: hand over PLAN.md, the
  unresolved findings and the decisions left. `--model` and `--tests` are
  recorded for the later build.
- `--cascade[=luna|haiku|gemini]` — a cheap drafter first, a gate accepts or
  escalates (`docs/cascade.md`). Default `luna`.
- `--resume` — continue the run in `.maestro/CHECKPOINT.md` with its recorded
  configuration; the task text is the answer to a recorded decision.
- `--unattended` — nobody answers: a gap becomes a recorded assumption, a
  question of authority stops the run with `result: needs-decision`
  (`docs/unattended.md` overrides "ask", "halt with a question" and "hand
  over" everywhere). **A headless director (`claude -p`) requires it.**
- `--sdk` — every Claude slot runs on the `api` transport (the Agent SDK on an
  API key, `bin/maestro-sdk`, billed to the Max plan's API credit) — for when
  the subscription's limits are spent. An explicit `@transport` still wins.
  Spend is capped per run (policy `api.max_usd_per_run`). Without it, policy
  `api: {fallback: true}` makes `api` the last transport a Claude slot switches
  to on quota (`docs/workers.md`).

`maestro-flags` rejects the illegal combinations: `--plan-only` with
`--cascade`/`--review`/`--reviewer`; `--reviewer` with `--review=self`;
`--tests` with two scopes or with `--skip-tests`; `--cascade` with
`--model=luna|haiku`, drafter == implementer, or `--skip-tests`; `--setup` with
`--unattended`; `--sdk` with a forced `@native`; `--resume` with any flag but
`--unattended` (to change the configuration, start again or answer a recorded
decision whose option changes it).

**Plain words are flags too.** "Krytykuj astrą", "review gemini", "bez fable",
"astra implementuje", "opus przez agy", "więcej rund krytyki", "bez testów
przeglądarkowych", "zbuduj tylko plan", "zapytaj o konfigurację", "na kredycie
API" map to `--critic`, `--reviewer`, a per-run deny, `--model[@t]`,
`--rounds`, `--tests`, `--plan-only`, `--setup`, `--sdk`. Echo the mapping in
the Assign line (`critic=astra (user: "krytykuj astrą")`); ask only when the
words are ambiguous or break a rule (`--unattended`: a validation stop, A2).

**High stakes** — defined once: the change touches auth or permissions, money,
concurrency, data integrity, or a migration that changes or drops existing data
(an additive migration is not). **High-stakes guard:** with no `--review`,
recommend one in the Assign line — recommend, never add it silently
(`--unattended` too, A12).

## Setup (`--setup`)

Configuration by questions instead of flags. **Read `docs/setup.md` before
asking.** It runs after stage 0 steps 0–4a and before the interview (setup
settles the roster, the interview the spec); step 5 then probes the chosen
slots — a failed probe asks that role again. Flags and the user's own words are
answers and are not asked again; policy values are defaults, not answers. It
ends with one reusable flag line per run (`/maestro --model=opus
--critic=astra,argon --rounds=2 --review=cross --tests=covering <task>`), then
the Assign line; separate runs go into the checkpoint's task queue.

## Roster

A slot is a **model line**, not a model: stage 0 resolves the newest usable
model of each line from the live catalogs (`docs/catalog.md`) and freezes it for
the run. **Family is decided by the model, never by the CLI.**
`bin/slots.json` is the table the helpers read.

| Slot | Line | Family | Transports, in order |
| --- | --- | --- | --- |
| `opus` | Claude Opus | Claude | native → agy → api |
| `fable` | Claude Fable | Claude | native → api |
| `sonnet` | Claude Sonnet | Claude | native → agy → api |
| `haiku` | Claude Haiku | Claude | native → api |
| `astra` | `gpt-<v>-astra` — frontier | OpenAI | codex |
| `sol` | `gpt-<v>-sol` — workhorse | OpenAI | codex |
| `luna` | `gpt-<v>-luna` — fast, cheap | OpenAI | codex |
| `terra` | `gpt-<v>-terra` — legacy, explicit only | OpenAI | codex |
| `argon` | `gemini-<v>-argon` — frontier, provisional | Google | agy |
| `gemini` | `gemini-<v>-hydrogen`, else `gemini-<v>-flash` — fast, cheap | Google | agy |
| `self` | you, directly | Claude | Edit/Write |

**Transports.** `native` = the `Agent` tool in an interactive Claude Code,
`claude -p` headless (and for a pinned native id). `agy` = `agy --model
<slug>`. `codex` = `codex exec -m <slug>`. `api` = `maestro-sdk --model <full
id>` (eligible only with `--sdk` or policy `api.fallback: true`, and only when
`maestro-sdk --check` is `available`). **An agy worker, a `claude -p` and an
`api` worker are edits-only — you run the tests**; a Codex worker runs commands
in its sandbox. Fable has no subscription transport but native: its native quota
is a swap unless `api` is eligible. A brief always matches the transport's
capabilities.

**Routing precedence** (`docs/catalog.md`, "Precedence", has the outcomes):
without `@`, the first eligible transport in the slot's order — denied
(`transports.deny`) and unavailable ones are skipped and named; explicit
`--model`/`--critic`/`--reviewer` beat policy denial (with a warning) but never
unavailability; a forced `@transport` never falls through; at first use a
transport that fails its probe is skipped and the first passing one fixes the
slot's identity. `maestro-roles --transports` decides it.

**No flag?** Evaluate in order and name the row that fired — stakes first:

1. Hard correctness — high stakes → `fable`, or `astra` when the Claude budget
   is the constraint; `opus` when Fable's cost is the problem and a high-effort
   cross-family critic covers the plan.
2. User-facing layout and UI → `opus` (it reads screenshots precisely); `fable`
   for a large redesign when the budget allows.
3. Ordinary feature work that needs thinking while writing, multistep changes
   carried until the tests pass → `opus`; `sol` when the Claude pool is the
   constraint.
4. Mechanical build from a settled plan (migration, factory, resource, CRUD
   scaffolding) → `sonnet`; `gemini` only when the user picks it to spare the
   Claude pool. `haiku` for bulk edits with no judgment in them.
5. Large self-contained chunk → `sol` or `gemini` (the idle pools); `luna`
   when it is large but not hard.
6. Change smaller than the handoff → `self` when you know your model line;
   otherwise `maestro-roles --row6` (first eligible of `sonnet`, `sol`,
   `gemini`), named in the Assign line; none → halt.

`argon` is in no row: it is the Google critic and reviewer and builds only when
named.

**Effort** — `low|medium|high|xhigh|max`, by stage (policy `effort.<stage>`):
critique `medium`, high-stakes critique `high`, build `medium`, review `high`,
cascade draft `medium`; Gate B at the critique effort. Mapped per transport and
clamped with `(clamped)`: codex `-c model_reasoning_effort` (the model's
catalog range); agy slug suffix plus `--effort`, clamped to the suffixes that
model lists (Hydrogen up to `xhigh`, Argon and Claude-on-agy up to `high`);
`claude -p --effort` and `maestro-sdk --effort`; the Agent tool takes none (the
model is the dial). Always pass effort explicitly.

This rubric is the whole routing logic — a written rule you apply and name.
`maestro.policy.yml` (repo) and `~/.config/maestro/policy.yml` (user) can deny
slots and transports, pin models and set defaults: flags > repo policy > user
policy > rubric, per key, every policy value marked `(policy)`
(`docs/policy.md`). The user can override any assignment in one word; take it
as final.

**Splitting is allowed and often best** — scaffolding to `sonnet`, the one hard
action to `fable` or `astra`. **Never two write-mode workers in one checkout at
once.** Parallel writers each get a worktree, one builder family per split,
integrated by you one at a time — **read `docs/worktrees.md` when a split is
decided**.

## The cross-family rule

Three families: **Claude** (`opus`/`fable`/`sonnet`/`haiku` and `self`),
**OpenAI** (`astra`/`sol`/`luna`/`terra`), **Google** (`argon`/`gemini`).
Same-family models share blind spots, so **no plan critic and no cross reviewer
shares the family of the builder whose code is committed**. Roles resolve over
the (model, transport) pairs stage 0 found eligible; `"$MAESTRO/bin/maestro-roles"`
applies the rule deterministically — run it and name its notes in the Assign
line.

| Builder | Critic, first eligible | High stakes, first eligible | Second critic (high stakes): first family not yet used |
| --- | --- | --- | --- |
| Claude | sol, astra, argon, gemini | astra, sol, argon, gemini | google, openai |
| OpenAI | opus, argon, gemini, sonnet | fable (budget allowing), opus, argon, gemini | google, claude |
| Google | sol, opus | astra, fable, opus | openai, claude |

- **Astra never critiques an OpenAI build — except in OpenAI-only degraded
  mode**, and the Assign line says so.
- **Cross reviewer** (`--review=full|cross`): the policy `reviewer`, else the
  plan critic's slot, else the critic order — first cross-family to the builder.
- **With `--cascade` either the implementer or the drafter may end up the
  builder,** so every critic comes from a family other than both (Opus
  implements, Luna drafts → `argon`). None eligible → halt with a question:
  drop the cascade or change the drafter; high stakes: drop the cascade
  (`--unattended`: row 2, A6). With three families a cascade from another
  family leaves one critic family, so a high-stakes cascade has no second
  critic — the report says so.
- Argon in any role is marked `(provisional)` until the ledger has measured it.

**Degraded modes.** Two eligible families: no high-stakes second critic, and
the report says so. **One eligible family** (the others off by policy or
unavailable): critic and reviewer are another model *line* of that family —
Claude: Fable for a Sonnet or Opus build, Opus for a Fable build (a denied model
is skipped); OpenAI: Astra for a Sol or Luna build, Sol for an Astra build;
Google: Argon for a Gemini build, Gemini for an Argon build. Marked
`families=<x> (degraded: same-family critique)`; no second line → halt
(`--unattended`: row 2, A7).

`--review=self` is always your own read. **Pin the model on every external
call** — agy hosts Claude models next to Gemini, and Codex falls back to
`$CODEX_HOME/config.toml` — and report the requested and the served model.

## Stage 0 — validated routing

0. **Host and lock** (`docs/hosts.md`). `"$MAESTRO/bin/maestro-host"` must say
   `claude-code` (`interactive` true or false, session key, pid). `unsupported`
   (another agent CLI directs) or `unknown` → stop and say maestro runs only in
   Claude Code. Headless without `--unattended` → validation stop. You know
   your own model and line — state them. Take the lock:
   `"$MAESTRO/bin/maestro-lock" acquire --run <run_id> --token <token> --host
   claude-code --session <key> [--pid <host_pid> --starttime <st>]`. Keep the
   returned **fence** (`<generation>.<secret>`, written `N`): every later
   mutation of the checkout or `.maestro/` goes through `maestro-lock exec --gen
   N -- …` or a helper given `--gen N` (those fence themselves: `maestro-run`,
   `-state`, `-kill`, `-ledger`, `-preflight`, `-catalog refresh|record-*` —
   never wrap them). A refusal = you were superseded: stop at once. **Never
   write the fence into a file.** `held` → another director owns this checkout
   (attended: ask; unattended: row 2). `blocked` → jobs of a previous run are
   alive (`docs/hosts.md`, "Jobs").
1. Flags: `maestro-flags` (above).
2. –3a. **Preflight**: `"$MAESTRO/bin/maestro-preflight" --gen N --interactive
   <true|false> [--resume] [--api] [--no-codex] [--no-agy] [--worktree]
   [--skills]` — workspace (`.maestro/`, the git exclude, schemas, clean tree,
   leftover `maestro-draft-*` stashes), state and git write capabilities,
   transports without model calls (native, `api`, Codex login and doctor, agy
   models), the **Codex config mode** (`isolated`, or `pinned` with the keys
   that forced it — `docs/workers.md`), the project's `.codex/config.toml`
   warnings, the Claude login expiry, and with `--skills` agy's view of the
   project skills. Every `stops` entry is a stop with its remedy (never a
   silent skip); every `warnings` entry goes in the Assign line. Also, from
   your own shell: the tests' cheap check (not under `--skip-tests`) and, when
   the run changes UI, the screenshot tool (`docs/hosts.md`, "Capability
   checks").
4. Load and merge policy (`docs/policy.md`); resolve a provisional roster
   among the eligible families and transports (`maestro-roles`), validate it,
   apply the cascade family rule (`--unattended`: halts are row 2, A8, A9).
4a. **Live catalog**: `"$MAESTRO/bin/maestro-catalog" refresh --gen N` (`codex
   debug models`, `agy models` — no model turns). Stale or bundled Codex data
   is degraded discovery: say so in the Assign line.
5. **Probes for the slots the roster uses** (under `--setup`, after its
   answers): `maestro-catalog pick <slot> <transport> --effort <e> --scope
   <scope>` names the candidate; `use` = a fresh successful probe exists;
   `probe` = run the transport's probe line (`docs/commands.md`) and record it
   (`maestro-catalog record-probe --gen N`; probe records are this checkout's
   own); a denial walks down to the next older candidate (announced); quota and
   network failures do not walk down. Native Claude is probed with `claude -p
   --model <alias>`, whose `init.model` is the frozen full id
   (`maestro-catalog native-id` / `native-verify` for a pinned version). The
   `api` transport takes full ids only: `maestro-sdk --resolve <slot>`, then
   its probe with `--tools ""` and a budget of 0.05 USD. A failed slot halts
   with a question naming slot and error — with an upgrade instruction when the
   client does not know the model; never substitute another line silently
   (`--unattended`: row 2, A5). Freeze ids, slugs, transports and efforts in the
   checkpoint (`catalog`) — `--resume` re-probes those exact slugs.
6. Skills: a skill only in `.claude/skills` is invisible to Codex and agy —
   warn (preflight does); name binding project skills in briefs.
7. In `pinned` Codex mode also report every key in `$CODEX_HOME/config.toml`
   the pins do not override that changes the rung or the cost.
8. Reach probe — only for a Codex slot that will write and run tests: `codex
   sandbox -c 'sandbox_mode="workspace-write"' -- <cheap check>` (isolated mode
   with an empty `CODEX_HOME`), judged by effect outside the sandbox
   (`docs/sandbox-and-preflight.md`) — never the suite.
9. Record `T_slow` (slowest single test or build, seconds; unknown → 900).

Steps run only for the families and transports they concern; report the
skipped ones.

## Launching workers

`docs/hosts.md` says how you launch and wait in each mode; `docs/commands.md`
has the exact lines. The invariants:

- **Every external model turn and every test run is a job you wait for
  without ending your turn**, in both modes: `"$MAESTRO/bin/maestro-run" --gen
  N --job <run_id>.<role>.r<round>.a<attempt> --run <run_id> --role <role>
  [--test-cmd …] -- "$MAESTRO/bin/maestro-env" -- <line>` in the foreground (it
  owns the redirection and returns at once). Then wait — interactive: one Bash
  call with `run_in_background: true`, `"$MAESTRO/bin/maestro-wait" <job>
  --until-done` (its notification wakes you; `lingering`/`orphaned` →
  `maestro-kill` in the same turn); headless: `maestro-wait <job> --max 540`
  in a loop. Never `&`, `nohup`, `setsid`, `disown` of your own.
  **Never end your turn while a job is `running`, `lingering`, `orphaned`, or
  `uncertain` with `leader_alive: true`**; ask nothing meanwhile. The one
  exception is `blocked`: report it and stop with the lock kept.
- **Every external worker runs through `maestro-env --`** (strips host markers,
  plugin and hook injection, `ANTHROPIC_*`).
- **Claude workers:** interactive — the `Agent` tool with an explicit `model`
  and the default `subagent_type` (`fork` **ignores** `model`); headless, and
  for a pinned native id — `claude -p` with the role's exclusive tool set.
  `agy` and `api` serve Claude models as transports of the same slot. **Before
  every `api` launch** pass `--max-budget-usd` = policy `api.max_usd_per_run`
  minus `maestro-ledger cost --run <run_id> --transport api`;
  `error_max_budget_usd` is quota on that transport.
- Briefs are files; stdin closed with `< /dev/null`; model and effort pinned;
  every Codex line carries `--ignore-user-config` (`isolated`) or the pins
  (`pinned`) — never both.
- **Effective identity** after every launch and resume, before anything the
  worker did is accepted: Codex — `maestro-identity codex --thread … --role …`;
  `claude -p` and `api` — `maestro-identity claude <out> …` on the `init` event
  (tools, MCP servers, plugins and `plugin_errors`, permission mode, model,
  `apiKeySource`); the Agent tool — the completion's model against the frozen
  id when the completion names one (Claude Code 2.1.325 reports only tokens, tool uses and
  duration: the identity rests on the explicit `model`, and the report says "served: not
  reported"); agy — no served-model field, the requested slug is recorded. Anything but
  `OK` stops the worker; a writer's output goes through the dirty-exit protocol.
- **Read-only roles leave no trace.** Around every external critic, gate or
  reviewer call: `maestro-fp snapshot` / `compare`; a change in the checkout or
  `.maestro/` → verdict discarded, dirty-exit, that transport ineligible for
  read-only roles this run. **You never overrule a `changed` result yourself.**
- **Continuing a worker** (fix rounds, after a stop): Codex `codex exec resume
  <thread UUID>` from the worker's directory; agy `--conversation <id>` only
  after a `SUCCESS` turn; `claude -p --resume <id>` and `maestro-sdk --resume
  <id>` with **every flag of the role repeated**; the Agent tool `SendMessage`
  (deferred: load it with `ToolSearch` first). Never `--last` or `--continue`.
- **Transport switch** — a Claude slot whose transport hits quota or becomes
  unavailable continues on the next eligible transport of its order *for the
  same model id* (`maestro-roles --transports`: use, switch, swap or halt) as
  one transaction (`docs/hosts.md`, "Transport switch"). Family unchanged →
  critics stand. A different version, or no transport left, is a swap ("Time
  and the watchdog").
- Validate every verdict with `"$MAESTRO/bin/maestro-validate" <schema> <file>
  --envelope codex|agy|claude` (`claude` for `api` too) before acting on it:
  one re-ask with the validator's error, then the role moves to the next
  eligible critic (a named critic → halt). An agy envelope with
  `denied_actions` or a `finished_reason` triggers that re-ask too — a denied
  read as a new conversation with the inline variant (`docs/briefs.md`).

## Briefs

**Read `docs/briefs.md` before writing the first brief**: the closing blocks
every brief ends with (verbatim, by role, transport and `--unattended`), the
agy openings, the inline variant, the size limits and the plan-critique
blocks (severity rubric, round 2, arbiter). The rules:

Everything lives under `.maestro/`. External workers start cold: absolute paths
(a worktree worker: paths relative to its worktree root), explicit change
boundaries, the convention files, what "done" looks like and the command that
proves it, and the **binding project skills by name**. Block-structured, not
prose. For Opus and Fable workers state goal, boundaries and proof of done —
not steps; for frontend work name the concrete patterns to avoid. **Critic,
gate and reviewer briefs are self-contained**: Codex and Claude get plan plus
diff embedded under 40 KB, else the path; **agy reads the repository itself**
(absolute paths inside `$REPO`, the diff written to
`.maestro/diff-<role>-r<N>.patch`, nothing quoted; it can read only inside its
`--add-dir`). A `claude -p` critic with no schema flag on its line gets the
schema quoted and the closing line *"Your final message must be the JSON object
only."*

**Test scope.** Settle it in the interview when `--tests` is not given and
record the exact test commands and runner paths in `PLAN.md` — `maestro-kill`
protects processes by them. The builder writes and runs the tests covering the
change (browser tests only with `browser`) — except an edits-only builder (agy,
`claude -p`, `api`): it writes them, you run them. Before the commit you re-run
what the builder ran plus the covering tests, and the **full suite** with
`--tests=full` or when the change has shared reach (migrations, base classes and
traits, middleware, routes, events, jobs, config, providers, dependencies) or
when you cannot bound its reach. **`--skip-tests` removes every test
obligation**: the report says `tests: skipped (flag)`. Parallel sessions share
the `testing` database: before blaming the code for a senseless red, check for
another live run.

A worker that *ends* with a question becomes a `question` blocker, answered as
a new prompt to its thread. **Under `--unattended`** classify each of its
assumptions and its closing question against the stop matrix after every turn
(`docs/unattended.md`, A11).

## The loop

1. **Interview.** Extract a complete, unambiguous spec, test scope included.
   Ask focused questions one at a time with the question tool until there are
   zero gaps — never while a job runs. Under `--unattended` ask nothing: row 1
   gaps become assumptions under `## Assumptions (unattended)` in PLAN.md,
   anything else stops; the test scope defaults to `covering` (A10).
2. **Assign.** Re-resolve the roster with what the interview revealed — above
   all the stakes — and run stage 0 step 5 for any new slot, step 8 if a Codex
   slot now writes and tests, `maestro-preflight --worktree` or the visual
   check if a split or a UI change is now decided. Then one line naming
   implementer, critic(s), reviewer, drafter, transports and frozen models,
   efforts, rounds, tests, sandbox rung, families and policy — each with its
   reason (rubric row, family rule, `(policy)`, `(user: "…")`, `(clamped)`,
   `(provisional)`, a degradation). Example: `Assign: host=claude-code
   (interactive) · implementer=opus@native→claude-opus-5-5 (UI) ·
   critic=sol→gpt-6.1-sol (cross-family default) · reviewer=none (no --review)
   · effort critique=high (policy) · rounds=2 · tests=covering,browser (user) ·
   catalog: codex live · families=claude,openai,google ·
   policy=maestro.policy.yml`. `codex-config=…` whenever a Codex worker runs;
   `unattended=on` with `--unattended`.
3. **Plan.** `.maestro/PLAN.md` (or `.maestro/tasks/<id>/PLAN.md` in a task
   queue), test commands and runner paths included.
4. **Critique — always, not gated by `--review`.** The PLAN (never code) goes to
   every required critic with the critique schema and the severity rubric
   (`docs/briefs.md`, "Plan critique": every finding names its `trigger`).
   Revise and resend up to `--rounds`; **from round 2 a critic gets its open
   findings with your resolutions, answers each in `prior_findings` and adds
   only what the revision introduced or what is blocking.** **Approved only
   when every required critic returns `approve` with empty `blocking_findings`
   and `major_findings` and every prior finding `resolved`** (`maestro-validate
   --decide critique`). At the cap without it: only majors left, not high
   stakes and `maestro-roles --arbiter` names a third family → **one arbiter
   call**; every finding downgraded approves the plan, and the report says so.
   Otherwise stop, no build, hand the disagreement to the user
   (`--unattended`: row 3, as is a `reject` in any round, A13). `--plan-only`
   ends here (A15).
5. **Build** — or cascade (`docs/cascade.md`; under `--unattended` every
   `DRAFT_ABORT` is classified before it escalates, A21). One writer in the
   checkout at a time.
6. **Your diff read — always,** even with review off: boundaries respected
   (untracked files included), nothing unplanned, no obvious bug. Then **review
   per `--review`**: `full` = your read plus the cross-family reviewer with a
   contract (spec, plan, acceptance criteria, diff; the review schema); `self` =
   your read; `cross` = reviewer, then your spot-check. The review brief says
   *"approve iff there is no blocking or major finding and every plan item is
   done; minor findings never change the verdict."* **The cross review passes
   with no blocking or major finding and `plan_coverage.missing` empty.** Minor
   findings: fix them or list them in the report — say which. **Visual check —
   not gated by `--review`:** user-facing layout changes are approved on
   screenshots, never on green tests alone; take them (desktop and ~390 px,
   both themes when the app has them) under `.maestro/evidence/` and read them
   yourself; a fix round sends the relevant ones to the builder (a Codex
   builder as `--image=` attachments, others as paths).
7. **Fix loop.** Findings and red tests go back to the builder (continued as
   above), at most 3 rounds, then checkpoint and hand the diagnosis to the user
   (`--unattended`: row 4, A14). **Bounded fixes are yours:** a few lines, no
   design change, nothing in permissions, money or data integrity. **Review
   and screenshots certify the final diff:** after any edit that follows them,
   the changed part goes back to the reviewer, the covering tests run again,
   the screenshots it touches are retaken.
8. **Approve and commit** — inside the fence (`maestro-lock exec --gen N -- git
   commit …`) — after your diff read, the passed gates and, unless
   `--skip-tests`, your own test run. A worker's green run is evidence, not a
   verdict.
9. **Report.** Spec, who did what (requested and served models, transports),
   review mode, test scope and status, sandbox rung, families and policy, the
   cost table (`docs/ledger.md`), what was skipped or degraded. When the run is
   **finished** — committed, no open decision, no queued or planned task, not
   a `--plan-only` result — close its bookkeeping (`maestro-state --gen N
   rotate --to <run_id>`). Then release the lock (`maestro-lock release
   --token <token> --gen N`) in every case. A task queue from `--setup`
   continues with the next task. Under `--unattended` the report opens with a
   `result:` line (`docs/unattended.md`, "Report").

Caps: critique ≤ `--rounds`, gate ≤ 2, fix loop ≤ 3. At the critique or fix
cap: stop, checkpoint with a diagnosis, hand the decision over — never a silent
extra round, never a silent fallback to another worker (`--unattended`: a
`needs-decision` stop). The arbiter (step 4) is the one exception, and the
report names it. At the gate cap the cascade escalates to the
implementer (`docs/cascade.md`).

## Time and the watchdog

- Claude Code caps a foreground command at 600 s: foreground only for what ends
  in seconds.
- **Never yield with a live worker.** Interactive: a live job without a
  background `maestro-wait <job> --until-done` task gets one re-armed first;
  sample progress every 5 min (a background `sleep 300` or `Monitor`) with
  `maestro-wait <job> --peek` or `maestro-status`. Headless: the
  `maestro-wait` loop (it records `last_progress_at` across calls).
- A hang is no progress for `max(15 min, 2 × T_slow)` — read the job's files,
  then `maestro-kill <job> --gen N` (again until `done` or `blocked`; it waits
  for protected tests and signals the rest one by one). **A hang never applies
  to a test**: never `timeout` or kill tests; never `pkill -f`.
- **Safety stops are not retryable** (`misalignment_policy_violation`, an
  explicit safety block): stop dispatch, keep checkpoint and output, inspect the
  tree, report. An ordinary out-of-scope decline gets one rewritten brief, then
  a reroute. A transient API failure → continue the worker. `--unattended`
  changes none of this (A16a, A18).
- **Dirty-exit protocol** — whenever a worker stops without a clean finish
  (quota, crash, kill) or the tree does not match the checkpoint: `git status`,
  `git diff` and the untracked files first; keep or reset each change
  deliberately, never wholesale by reflex (resets inside the fence); record the
  decision and `tree_state` in the checkpoint. **Quota exhaustion is routine:**
  a Claude slot with another transport left switches (above); otherwise
  dirty-exit, checkpoint, stop; on resume re-probe limits — never reason from a
  remembered one. A tree change no known worker explains is a row 2 stop under
  `--unattended` (A16b).
- **Swapping a worker mid-run** (limits with no transport left, the user's
  call, a crash): checkpoint, give the new worker the brief plus the current
  `git diff`, re-check critics, reviewer and gate against the new builder's
  family (`maestro-roles`), mark the swap in the ledger and the report. A plan
  critic that now shares the builder's family is replaced by one critique round
  of the current plan by an eligible cross-family critic; none → halt with a
  question. A new slot gets its stage 0 probes first. Under `--unattended` a
  swap for limits is a row 5 stop (A17).
- **The skill changed mid-run:** re-read this file and the `docs/` the current
  stage uses before the next step; the checkpoint stays valid.

## Checkpoint and resume

Write `.maestro/CHECKPOINT.md` (`docs/checkpoint.md`) after every stage
transition, at every worker launch (session id, job id), and on every limit, API
or safety event — **only** through `maestro-state --gen N write CHECKPOINT.md`,
never with an edit tool or a redirect: a checkpoint or ledger written any other
way has no audit entry, and the next write or `--resume` refuses it. Only the
user can accept such a file, after inspecting it (`maestro-state --gen N adopt
<file> --reason "…"`; never under `--unattended` — headless, the script refuses
it). It holds the resolved configuration (flags, roster with frozen models and
transports, efforts, `test_scope`, the Codex config mode), your identity, the
lock token, one record per worker session (transport, job id, rung tokens,
rollout offset, worktree, `baseline`, fingerprint), the open decision and,
after `--setup` with separate runs, the task queue.

`--resume` (or a new task while a checkpoint exists with `stage ≠ report` → ask
which; never overwrite it silently) follows `docs/checkpoint.md`, "Resume": the
lock with `--resume` (adopted only from a **stale** owner), host and identity
re-detected (a recorded host other than `claude-code`, a slot or transport this
version no longer has, another family or model line → ask; unattended: row 2),
every recorded job reconciled, the frozen slugs and the limits re-probed, the
tree compared with the checkpoint and every worktree's `baseline` — any
difference → dirty-exit first — then `stage` and `next_action`.

**Building a `--plan-only` plan.** The approval stands only while the plan is
unchanged (`plan_sha256`) and no approving critic shares the family of a
possible builder; otherwise one critique round by the critics the build roster
requires (A20 under `--unattended`).

## Ledger

One line per model call in `.maestro/ledger.jsonl`, appended right after reading
its output with `"$MAESTRO/bin/maestro-ledger" --gen N --job <job> --stage
<stage> --cli codex|agy|claude-cli|claude-sdk --transport <t> --family <f>
--model <requested> [--effort …] [--outcome …] [--verdict …]` — it reads tokens,
duration, session id and served model from the job's own output. An Agent-tool
call has no job: `maestro-ledger --gen N --cli claude-agent --stage …
--transport native --family claude --model <alias> [--served <completion's
model>] --agent-id <id> --total-tokens N --tool-uses N --duration-ms N`
(`docs/ledger.md`, including the `transport-switch` outcome). An `api` row
carries `cost_usd` (the SDK's estimate, not an invoice); the report shows the
run's `api` spend next to the token table. Never write a ledger row by hand;
missing numbers are `null`, never estimated; cumulative counters (`codex exec
resume`, agy conversations) keep raw values in `raw_cumulative` and record the
delta. Token totals are never presented as subscription cost.
