---
name: route2
description: >-
  Multi-model build loop that runs in Claude Code, Codex, agy or Cursor: the
  session model directs — interviews, plans, has the plan critiqued by other
  model families, hands the build to a chosen worker (Claude, OpenAI via codex
  exec, Gemini and Claude via agy, Grok and Claude via Cursor's agent), gates,
  tests, commits and reports. Models are resolved from the live catalogs.
  Trigger ONLY when the user types /route2 (in Codex: $route2), says "route2
  this", "run the route2 loop", or explicitly asks for route2. Do NOT use for
  ordinary single-model coding, planning, refactors, or chat — and not for
  /route (the older skill).
---

# Route2: director + selectable workers, any host

You are the director. You interview, plan, decide who does what, gate the result
and approve — approval is yours alone. You do not write the implementation
unless the roster says you are the right worker, the user picked
`--model=self`, or it is a bounded fix in the fix loop. You do the commits.
Announce every assignment with the rule that produced it and report who did
what and what it cost: the user is directing a team, not watching a black box.

**Where the helpers are.** This skill ships scripts next to this file. Before
anything else set `R2` to the directory of this SKILL.md, resolved through
symlinks — `R2="$(dirname "$(readlink -f "<path you read this file from>")")"` —
and call every helper as `"$R2/bin/<name>"` (`--help` prints a helper's usage). The working state of a run lives in
`.route2/` at the repository top (never `.route/`, which belongs to the older
`/route` skill; never `/tmp`).

Read `docs/` files when a section points at them, not up front:
`docs/hosts.md` (**read it in stage 0** — the host you run in decides how you
launch, wait and ask), `docs/commands.md` (exact launch lines, reading results,
progress sampling — **read it before the first external launch of a run**),
`docs/catalog.md` (model lines, probes, pins), `docs/workers.md` (CLI facts per
transport), `docs/policy.md`, `docs/cascade.md`, `docs/setup.md`,
`docs/sandbox-and-preflight.md`, `docs/checkpoint.md`, `docs/ledger.md`,
`docs/unattended.md` (**read it as soon as `--unattended` is given**),
`docs/troubleshooting.md` (every incident behind the rules below),
`docs/schemas/*.json`.

## Flags

Look for these anywhere in the arguments and strip them from the task text.
**Unknown flag names, unknown values and illegal combinations all fail loudly**
— ask the user; never keep an unrecognised switch as task text, never fall
back silently to `self`, to no review, or to a different worker. Under
`--unattended` that ask is a validation stop (`docs/unattended.md` A1).

- `--model=<slot>[@<transport>]` — the implementer (roster below). The
  `@transport` suffix forces one transport (`opus@agy`, `sonnet@cursor`,
  `opus@native`); without it the slot uses its first eligible transport.
- `--review[=full|self|cross]` — post-build review. **Absent = no review
  stage.** `full` (default) = your read + cross-family reviewer; `self` = your
  read only; `cross` = reviewer, then your spot-check.
- `--critic=<slot>[@t][,<slot>[@t]…]` — the plan critic(s); every named slot is
  a critic that runs whatever the stakes. `--reviewer=<slot>[@t]` — the cross
  reviewer; alone it implies `--review=full`. Both beat policy (a denied slot
  runs with a warning), never the cross-family rule: a named critic or reviewer
  from the builder's family halts with a question, and so do two named critics
  from one family on a high-stakes change (`--unattended`: a row 2 stop,
  `docs/unattended.md` A3).
- `--rounds=<n>` — plan-critique cap, 1–8 (default 2; policy `critique_rounds`).
- `--tests=<scope>[,browser]` — `covering` (default: the tests covering the
  change) or `full` (the full suite before the commit), optionally with
  `browser` (browser tests too); `--tests=browser` means `covering,browser`.
- `--skip-tests` — no test runs at all (section "Test scope").
- `--setup` — configure the run by questions first (section "Setup").
- `--plan-only` — interview, plan, critique, then stop: hand over the plan
  (PLAN.md), the unresolved findings and the decisions left to the user. No
  build, no commit. `--model` and `--tests` are recorded for the later build.
- `--cascade[=luna|haiku|gemini]` — a cheap drafter builds first, a gate
  accepts or escalates (`docs/cascade.md`). Default drafter `luna`. Grok is not
  a drafter.
- `--resume` — continue the run recorded in `.route2/CHECKPOINT.md`, with the
  configuration recorded there.
- `--unattended` — nobody answers: a gap becomes a recorded assumption, a
  question of authority stops the run with `result: needs-decision`
  (`docs/unattended.md`, which overrides "ask", "halt with a question" and
  "hand over" everywhere under this flag). A property of the invocation, not
  of the run. **A headless director (`claude -p`, `codex exec`, `agent -p`)
  requires it** — nobody can answer there.
- `--host=<claude-code|codex|agy|cursor>` — override the detected host *name*
  when detection says `unknown` (`docs/hosts.md`); it never adds a capability
  the host does not have.

**Illegal combinations:** `--plan-only` with `--cascade`, `--review` or
`--reviewer`; `--reviewer` with `--review=self`; `--tests` with two scopes or
with `--skip-tests`; `--cascade` with `--model=luna|haiku`, with drafter ==
implementer, or with `--skip-tests`; `--setup` with `--unattended`; `--host`
with `--resume`; `--resume` with any other flag except `--unattended` — to
change the configuration, discard the checkpoint and start again, or answer a
recorded decision whose option changes it. Text after the flags of a `--resume`
is that answer (`docs/unattended.md`).

**Plain words are flags too.** "Krytykuj astrą", "krytykuj grokiem", "review
gemini", "bez fable", "astra implementuje", "grok buduje", "opus przez agy",
"więcej rund krytyki", "bez testów przeglądarkowych", "zbuduj tylko plan",
"zapytaj o konfigurację" map to `--critic`, `--reviewer`, a per-run deny,
`--model[@t]`, `--rounds`, `--tests`, `--plan-only`, `--setup`. Echo the
mapping in the assignment line (`critic=grok (user: "krytykuj grokiem")`); ask
only when the words are ambiguous or break a rule (`--unattended`: a validation
stop, `docs/unattended.md` A2).

**High stakes** — defined once, used everywhere in this skill and its docs: the
change touches auth or permissions, money, concurrency, data integrity, or a
migration that changes or drops existing data (an additive migration is not
high stakes). **High-stakes guard:** when no `--review` was given, recommend
one in the assignment line. Recommend — do not add it silently, under
`--unattended` too (`docs/unattended.md` A12).

## Setup (`--setup`)

Configuration by questions instead of flags. **Read `docs/setup.md` before
asking** — it has the reading of the input, the question order and the
recommendation rules. Illegal with `--unattended`. The contract:

- Runs after stage 0 steps 0–4a (host, families, transports, catalog and
  policy — no model calls) and before the interview; setup settles the roster,
  the interview still settles the spec. Step 5 then probes the slots the
  answers chose; a failed probe asks that role again.
- Flags and the user's own words are answers and are not asked again; policy
  values are shown as defaults, not treated as answers.
- Ends with one reusable flag line per run —
  `/route2 --model=opus --critic=astra,gemini,grok --rounds=2 --review=cross
  --tests=covering <task>` — then the assignment line. Separate runs go into
  the checkpoint's task queue.

## Roster

A slot is a **model line**, not a model: stage 0 resolves the newest usable
model of each line from the live catalogs (`docs/catalog.md`) and freezes it for
the run. **Family is decided by the model, never by the CLI.**

| Slot | Line | Family | Transports, in order |
| --- | --- | --- | --- |
| `opus` | Claude Opus | Claude | native → agy → cursor |
| `fable` | Claude Fable | Claude | native → cursor |
| `sonnet` | Claude Sonnet | Claude | native → agy → cursor |
| `haiku` | Claude Haiku | Claude | native |
| `astra` | `gpt-<v>-astra` — frontier | OpenAI | codex |
| `sol` | `gpt-<v>-sol` — workhorse | OpenAI | codex |
| `luna` | `gpt-<v>-luna` — fast, cheap | OpenAI | codex |
| `terra` | `gpt-<v>-terra` — legacy, explicit only | OpenAI | codex |
| `gemini` | `gemini-<v>-flash` | Google | agy |
| `grok` | `grok-<v>` (Cursor's own line, not `cursor-grok-*`) — provisional | xAI | cursor |
| `self` | you, directly | your family (stage 0 step 0) | Edit/Write |

**Transports.** `native` = the `Agent` tool when you run in an interactive
Claude Code, otherwise `claude -p`. `agy` = `agy --model <slug>`. `cursor` =
`agent -p --model <slug>`. `codex` = `codex exec -m <slug>`. What a transport
lets a worker do differs (`docs/workers.md`): **an agy worker (Gemini or Claude)
and a `claude -p` worker are edits-only — you run the tests**; a Cursor worker
runs commands only inside Cursor's sandbox (no network, no `$HOME`), so it runs
tests only when its reach probe passed. A brief always matches the transport's
capabilities.

**Routing precedence** (one table, `docs/catalog.md` "Precedence" has the
attended/unattended outcomes): without `@`, the first eligible transport in the
slot's order — denied (`transports.deny`) and unavailable ones are skipped and
named; explicit `--model`/`--critic`/`--reviewer` beat policy denial (with a
warning) but never unavailability; a forced `@transport` never falls through; at
first use (no identity frozen yet) a transport that fails its probe is skipped
and the first passing one fixes the slot's identity.

**No flag?** Evaluate in this order and name the row that fired — stakes first,
so a payment feature never lands in the ordinary-feature row:

1. Hard correctness — high stakes → `fable`, or `astra` when the Claude budget
   is the constraint; `opus` when Fable's cost is the problem and a high-effort
   cross-family critic covers the plan.
2. User-facing layout and UI → `opus` (it reads screenshots precisely); `fable`
   for a large redesign when the budget allows.
3. Ordinary feature work that needs thinking while writing, multistep changes
   carried through the codebase until the tests pass → `opus`; `sol` when the
   Claude pool is the constraint.
4. Mechanical build from a settled plan (migration, factory, resource, CRUD
   scaffolding — convention-heavy, not truly mechanical) → `sonnet`; `gemini`
   only when the user picks it to spare the Claude pool. `haiku` for bulk edits
   with no judgment in them.
5. Large self-contained chunk → `sol`, `gemini` or `grok` (the idle pools; grok
   is provisional — say so); `luna` when it is large but not hard.
6. Change smaller than the handoff → `self` — **only when your own family and
   model line are known** (stage 0 step 0); otherwise the first eligible of
   `sonnet`, `sol`, `gemini`, `grok`, named in the Assign line; none → halt.

**Effort** — one vocabulary `low|medium|high|xhigh|max`, by stage (policy key
`effort.<stage>`): critique `medium`, high-stakes critique `high`, build
`medium`, review `high`, cascade draft `medium`; the cascade's Gate B runs at
the critique effort. Mapped per transport and clamped with `(clamped)`: codex
`-c model_reasoning_effort` (the model's catalog range); agy slug suffix plus
`--effort` (`low|medium|high`); cursor slug suffix (Grok `low…xhigh`, Claude
`low…max`; `-fast` variants only with policy `cursor_fast: true`); `claude -p
--effort`; the Agent tool takes none (the model is the dial). Always pass effort
explicitly — catalog defaults differ per model.

This rubric is the whole routing logic — a written rule you apply and name, not
a learned router. `route2.policy.yml` (repo) and `~/.config/route2/policy.yml`
(user) can deny slots and transports, pin models and set defaults: flags > repo
policy > user policy > rubric, per key, and every policy-sourced value is marked
`(policy)` (`docs/policy.md`). The user can override any assignment in one
word; take it as final.

**Splitting is allowed and often best** — scaffolding to `sonnet`, the one hard
action to `fable` or `astra`. **Never two write-mode workers in one checkout at
once**: they collide on files and `.git/index.lock`. Parallel writers each get
a worktree, one builder family per split: Claude subagents in an interactive
Claude Code `isolation: "worktree"`; every other writer a worktree you create
before launch (`git worktree add --detach "$REPO/.route2/worktrees/<part>"
HEAD`), entered with `codex exec -C <wt>`, `agent -p --workspace <wt>`, or a
`claude -p` whose cwd is the worktree; agy takes no part. Every part starts from
`HEAD` and must not depend on another part's integration. Their briefs write
every path and boundary relative to the worktree root — never the checkout's
absolute paths, which would send the edits into the checkout — and say *"Do not
run tests; the director will"* (parallel runs would share the `testing`
database, and a fresh worktree has no `.env`, `vendor/` or `node_modules/`);
edits-only and sandboxed builders never run tests there anyway. The checkpoint
records each worktree with its session id, `baseline` SHA and fingerprint. You
integrate each worktree's result into the checkout yourself, one at a time —
`git -C <worktree> add -A`, then `git -C <worktree> diff --cached HEAD
--binary`, applied in the checkout with `git apply` (inside the fence,
`"$R2/bin/route2-lock" exec --gen N -- …`) — and then mark the integrated state
with a commit **inside the worktree** (`git -C <worktree> commit -m
route-integrated`, never merged) whose SHA becomes its `baseline`: the next
integration after a fix round first checks `HEAD == baseline` and then takes
only what changed since. All this happens before your diff read, the tests
(covering the integrated result) and the review; until integrated, the
checkpoint's `tree` does not cover it. **Keep every worktree until the
report**, then remove it (`git worktree remove --force`, `git worktree prune`)
and any branch. A single external worker owns the checkout while it runs;
while parallel workers run, they own only their worktrees and the checkout is
yours, for integration only.

## The cross-family rule

Four families: **Claude** (`opus`/`fable`/`sonnet`/`haiku`, and `self` when you
are Claude), **OpenAI** (`astra`/`sol`/`luna`/`terra`), **Google** (`gemini`),
**xAI** (`grok`). Same-family models share blind spots, so **no plan critic and
no cross reviewer shares the family of the builder whose code is committed**.
Roles resolve over the (model, transport) pairs stage 0 found **eligible**;
`"$R2/bin/route2-roles"` applies the rule below deterministically — run it and
name its notes in the Assign line.

| Builder | Critic, first eligible | High stakes, first eligible | Second critic (high stakes): first eligible family not yet used |
| --- | --- | --- | --- |
| Claude | sol, astra, gemini, grok | astra, sol, gemini, grok | google, xai, openai |
| OpenAI | opus, gemini, grok, sonnet | fable (when its budget allows), opus, gemini, grok | google, xai, claude |
| Google | sol, opus, grok | astra, fable, opus, grok | openai, claude, xai |
| xAI | sol, opus, gemini | astra, fable, opus, gemini | openai, claude, google |

- **Astra never critiques an OpenAI build — except in OpenAI-only degraded
  mode** (below), and the Assign line says so.
- **Cross reviewer** (`--review=full|cross`): the policy `reviewer`, else the
  plan critic's slot, else the critic order — first cross-family to the builder
  whose code is committed.
- **With `--cascade` either the implementer or the drafter may end up the
  builder,** so every critic comes from a family other than both (the drafter's
  family is removed from every order first: Opus implements, Luna drafts →
  `gemini`). When no eligible family can give that, `--cascade` halts with a
  question: drop the cascade or change the drafter; on a high-stakes change with
  one remedy only — drop the cascade (`--unattended`: a row 2 stop, A6).
- Grok in any role is marked `(provisional)` until the ledger has measured it.

**Degraded modes.** Two eligible families: no high-stakes second critic, and
the report says so. **One eligible family**: critic and reviewer are a different
model *line* of that family than builder and drafter — Claude: Fable for a
Sonnet or Opus build, Opus for a Fable build (a denied model is skipped: Opus
build with Fable denied → Sonnet); OpenAI: Astra for a Sol or Luna build, Sol
for an Astra build; Google and xAI have one line → halt with a question
(`--unattended`: a row 2 stop, A7). Marked `families=<x> (degraded:
same-family critique)`. Claude is not always present any more — on another host
without a Claude transport, or switched off by policy, it is simply absent.

`--review=self` is always your own read. **Pin the model on every external
call** — agy and Cursor host Claude models next to their own, and Codex falls
back to `$CODEX_HOME/config.toml` — and report the requested model and the one
the session reports serving (`docs/commands.md`, "Effective identity").

## Stage 0 — validated routing

0. **Host, identity, lock** (`docs/hosts.md`). Run `"$R2/bin/route2-host"`: it
   names the host (`claude-code`, `codex`, `cursor`, `agy`, `unknown`), whether
   it is interactive, the session key, and — where a measured source exists —
   your model and family (Claude Code: you know your model; Codex: the latest
   `turn_context` of your own thread). `unknown` → ask which host (unattended:
   row 2). A headless host without `--unattended` → validation stop. Then take
   the lock: `"$R2/bin/route2-lock" acquire --run <run_id> --token <token>
   --host <host> --session <key> [--pid <host_pid> --starttime <st>]` (pid and
   start time from `route2-host` when known; otherwise heartbeat liveness).
   Keep the returned **generation** `N`: every later mutation of the checkout or
   of `.route2/` goes through `"$R2/bin/route2-lock" exec --gen N -- …` or a
   helper given `--gen N`, and a refusal there means you were superseded — stop
   at once. `held` → another director owns this checkout (attended: ask whether
   to wait or abandon; unattended: row 2). `blocked` → jobs of a previous run are
   still alive (`docs/hosts.md`, "Jobs").
1. Parse flags; reject unknown names, unknown values, illegal combinations.
2. Workspace: `REPO="$(git rev-parse --show-toplevel)"`; `mkdir -p .route2`;
   add `.route2/` to the file `git rev-parse --git-path info/exclude` names
   (never `.gitignore`); copy this skill's `docs/schemas/*.json` into `.route2/`.
   Clean tree required; warn about leftover `route-draft-*` stashes, and about a
   `.route/CHECKPOINT.md` with `stage ≠ report` (an unfinished `/route` run in
   this checkout — the two skills must not run here at once).
3. **Families and transports, without model calls**, each check run from your
   own shell: Claude native (interactive Claude Code: always; elsewhere `command
   -v claude` + `claude auth status`), OpenAI (`command -v codex`, `codex login
   status`, `codex doctor --summary`; then the **Codex config mode** —
   `isolated` unless `$CODEX_HOME/config.toml` sets a connection or auth key →
   `pinned`, naming the key, `docs/workers.md`), agy (`command -v agy`, `agy
   models`, `agy --version`), Cursor (`command -v agent`, `agent status`).
3a. **Your own capabilities** (`docs/hosts.md`, "Capability checks"): state
   writes, git object/index/ref writes, model reach from this shell, the tests'
   cheap check (not under `--skip-tests`), the visual tooling when the run
   changes UI; a worktree probe when a split is decided. A failure is a stop
   with the remedy for this host — never a silent skip.
4. Load and merge policy (`docs/policy.md`), resolve a provisional roster among
   eligible families and transports (`route2-roles`), validate it, apply the
   cascade family rule. It becomes final at the assignment step. Under
   `--unattended` every halt here is a row 2 stop (A8, A9).
4a. **Live catalog**: `"$R2/bin/route2-catalog" refresh` (codex `debug
   models`, `agy models`, `agent --list-models` — no model turns). Stale or
   bundled Codex data is degraded discovery: say so in the Assign line.
5. **Probes for the slots the roster uses** (under `--setup`, after its
   answers): `"$R2/bin/route2-catalog" pick <slot> <transport> --effort <e>
   --scope <scope>` names the candidate; `use` = a fresh successful probe
   exists; `probe` = run the transport's probe line (`docs/commands.md`) and
   record it with `route2-catalog record-probe --gen N`; a denial walks down to
   the next older candidate (announced: "gpt-6.2-sol listed, denied for this
   account"); quota and network failures do not walk down (§ "Routing
   precedence"). Native Claude is probed through `claude -p --model <alias>`,
   which reports the full model id that becomes the slot's frozen identity. A
   failed slot halts with a question naming the slot and the error — with an
   upgrade instruction when the error says the client does not know the model;
   never substitute another line silently (`--unattended`: row 2, A5). Freeze
   the resolved ids, slugs, transports and efforts in the checkpoint
   (`catalog`) — `--resume` re-probes those exact slugs, it does not re-resolve.
6. Skills: `agy --add-dir "$REPO" --output-format json --print-timeout 2m -p
   "/skills" < /dev/null` (no model turn). Zero workspace skills with a
   populated `.agents/skills/` = trust/mount failure. A skill only in
   `.claude/skills` is invisible to Codex and agy — warn.
7. Read the project's `.codex/config.toml`, in either mode: a
   `default_permissions` profile or a container-backed MCP server silently
   cripples a Codex worker — warn. In `pinned` mode also report every key in
   `$CODEX_HOME/config.toml` the pins do not override that changes the rung or
   the cost.
8. Reach probes — only for a slot that will write and run tests: Codex
   (`codex sandbox -c 'sandbox_mode="workspace-write"' -- <cheap check>`,
   isolated mode with an empty `CODEX_HOME`) and Cursor (one cheap sandboxed
   model turn that runs `<cheap check>` once), judged by effect outside the
   sandbox (`docs/sandbox-and-preflight.md`). The check needs the same
   resources as the tests but ends in seconds — never the suite.
9. Record `T_slow` (slowest single test or build, seconds; unknown → 900).

Steps 3–8 run only for the families and transports they concern; report the
skipped ones.

## Launching workers

`docs/hosts.md` says how you launch and wait **on this host**;
`docs/commands.md` has the exact lines. The invariants, on every host:

- **Every model turn through an external CLI and every test run is a job you
  can wait for without ending your turn.** In an interactive Claude Code: the
  Bash tool's `run_in_background: true` (never `&`, `nohup`, `setsid`, `disown`
  — the completion notification exists only for harness tasks). **On every other
  host:** `"$R2/bin/route2-run" --gen N --job <run_id>.<role>.r<round>.a<attempt>
  --run <run_id> --role <role> [--test-cmd …] -- "$R2/bin/route2-env" -- <line>`
  (it owns the output redirection — the line carries none), then
  `"$R2/bin/route2-wait" <job>` in a loop. **Never end your turn while a job is
  `running`, `lingering` or `orphaned`**; ask the user nothing meanwhile. The
  one exception is `blocked` (`docs/hosts.md`): report it and stop with the
  lock kept.
- **Every external worker runs through `"$R2/bin/route2-env" --`**, which strips
  your host markers and anything that injects plugins or hooks into a child CLI.
- **Claude workers**: interactive Claude Code — the `Agent` tool with an explicit
  `model` and the default `subagent_type` (`fork` **ignores** `model`);
  anywhere else, and for a pinned native id — `claude -p` with the exclusive
  tool set of its role (`docs/commands.md`). agy and Cursor serve Claude models
  as transports of the same slot.
- Briefs are files; stdin closed with `< /dev/null`; model and effort pinned;
  every Codex line carries `--ignore-user-config` (`isolated`) or the pins
  (`pinned`) — never both.
- **Effective identity** after every launch and resume, before anything the
  worker did is accepted: Codex — the effective-config check against the
  rollout's `turn_context`; `claude -p` and Cursor — the `init` event of their
  `stream-json` output (model, tools, MCP servers, plugins, permission mode);
  the Agent tool — the completion's model against the frozen id; agy — no
  served-model field, the requested slug is recorded. A mismatch stops the
  worker; a writer's output is discarded through the dirty-exit protocol.
- **Read-only roles leave no trace.** Before and after every external critic,
  gate or reviewer call: `"$R2/bin/route2-fp" snapshot` / `compare`; a change
  in the checkout or in `.route2/` → verdict discarded, dirty-exit, that
  transport ineligible for read-only roles this run.
- **Continuing a worker** (fix rounds, after a stop): Codex `codex exec resume
  <thread UUID>` from the worker's own directory; agy `--conversation <id>` only
  after a `SUCCESS` turn; `claude -p --resume <session_id>` and `agent -p
  --resume <session_id>` with **every flag of the role repeated**; the Agent
  tool `SendMessage` (a deferred tool: load it with `ToolSearch` first). Never
  `--last` or `--continue`.
- **Transport switch** — a Claude slot whose transport hits quota or becomes
  unavailable continues on the next eligible transport of its order *for the
  same model id*, as one transaction (`docs/hosts.md`, "Transport switch"):
  confirm the old session ended, dirty-exit, checkpoint, probe, a new session
  with a brief rewritten for the new transport's capabilities plus the current
  diff and open findings, announced and ledgered. Family unchanged → critics
  stand. A different version, or no transport left, is a swap ("Time and the
  watchdog").
- Validate every verdict with `"$R2/bin/route2-validate" <schema> <file>
  --envelope codex|agy|claude|cursor` before acting on it: one re-ask with the
  validator's error, then the role moves to the next eligible critic (a named
  critic → halt).

## Briefs

Everything lives under `.route2/`. External workers start cold: absolute paths
(a worktree worker: paths relative to its worktree root, its artifacts at
absolute `$REPO/.route2/…` paths), explicit change boundaries, the convention
files, what "done" looks like and which command proves it, and the **binding
project skills by name** (Codex discovers `.agents/skills`; agy only with
`--add-dir`; Cursor reads `.agents/skills`, `.cursor/skills`, `.claude/skills`).
Block-structured, not prose. For Opus and Fable workers state goal, boundaries
and proof of done — not step-by-step instructions; for frontend work name the
concrete patterns to avoid. Cursor workers answer in the user's language unless
told: say *"Answer in English."*

**Critic, gate and reviewer briefs are self-contained.** Codex, Claude and
Cursor: plan plus diff embedded under 40 KB, else the path. **agy reads
nothing** (Gemini and Claude-on-agy alike): its whole brief goes into `-p`, with
the conventions it must judge against quoted inline. Above ~100 KB (argv limit
~128 KB) split it into parts, each a full brief for its slice. Combined: approve
only when every part approves, findings are the union; a gate or review part
also names the plan items its slice covers, combined `done` is the union and
`missing` the plan items no part reports done. Or give the role to another
family. A Cursor or `claude -p` critic with no schema flag on its line gets the
schema quoted in the brief and the closing line *"Your final message must be the
JSON object only."*

**Test scope.** Settle it in the interview when `--tests` is not given, and
record the exact test commands (and the test runner path, e.g.
`vendor/bin/pest`) in `PLAN.md` — `route2-kill` protects processes by them. The
builder writes and runs the tests covering the change, browser tests only with
`browser` — except an edits-only builder (agy, `claude -p`, a Cursor builder
whose reach probe failed): it writes them, you run them. Before the commit you
re-run what the builder ran plus the covering tests, and the **full suite** with
`--tests=full` or when the change has shared reach (migrations, base classes and
traits, middleware, routes, events, jobs, config, providers, dependencies) or
when you cannot bound its reach. **`--skip-tests` removes every test
obligation**: the report says `tests: skipped (flag)`. Parallel sessions share
the `testing` database: before blaming the code for a senseless red, check for
another live run.

Every brief ends with: *"Do not ask questions. Where the brief is silent, decide
and record each assumption — in the `assumptions` field when a JSON schema was
given, otherwise under a `## Assumptions` heading. Do not commit. Do not write
outside the boundaries or into `.route2/`."* Builders that run tests add: *"Run
test commands without a `timeout` wrapper and never kill them; if your shell
caps foreground execution, run any test that can take more than a few minutes
in the background and wait for it."* Edits-only builders add: *"Do not execute
shell or terminal commands; edit files only — the director runs the tests."*
agy critics, gates and reviewers **open** with: *"This brief is self-contained.
Do NOT call any tools: do not read files, do not run commands, do not call MCP,
do not search the repository. Answer from the text below alone."* A worker that
*ends* with a question becomes a `question` blocker, answered as a new prompt to
its thread.

**Under `--unattended`** every brief adds after that closing block: *"If the
brief is silent on authorization, budget, scope or a high-stakes decision, do
not decide it: stop, leave the tree as it is, and end your answer with the
question."* After every worker turn classify each of its assumptions and its
closing question against the stop matrix (`docs/unattended.md` A11).

## The loop

1. **Interview.** Extract a complete, unambiguous spec, including test scope.
   Ask focused questions one at a time until there are zero gaps — with this
   host's question tool (`docs/hosts.md`), never while a job is running. Under
   `--unattended` ask nothing: classify each gap — row 1 becomes an assumption
   under `## Assumptions (unattended)` in PLAN.md, anything else stops — and the
   test scope defaults to `covering` (A10).
2. **Assign.** Re-resolve the provisional roster with what the interview
   revealed — above all the stakes — and run stage 0 step 5 for any slot that is
   new, step 8 if a slot now writes and tests, and step 3a's worktree and visual
   probes if a split or a UI change is now decided. Then one line naming
   implementer, critic(s), reviewer, drafter, the transports and the frozen
   models, the efforts in use, rounds, tests, sandbox rung, host, families and
   policy — each with its reason (rubric row, family rule, `(policy)`, `(user:
   "…")`, `(clamped)`, `(provisional)`, a degradation). Example:
   `Assign: host=codex (interactive) · implementer=opus@native→claude-opus-5-5
   (UI) · critic=sol→gpt-6.1-sol (cross-family default) · reviewer=none (no
   --review) · effort critique=high (policy) · rounds=2 · tests=covering,browser
   (user) · catalog: codex live · families=claude,openai,google,xai ·
   policy=route2.policy.yml`. `codex-config=…` whenever a Codex worker runs;
   `unattended=on` with `--unattended`.
3. **Plan.** Draft the run's plan, test commands and runner paths included:
   `.route2/PLAN.md`, or `.route2/tasks/<id>/PLAN.md` in a task queue.
4. **Critique — always, not gated by `--review`.** The PLAN (never code) goes to
   every required critic with the critique schema. Revise and resend up to
   `--rounds`. **The plan is approved only when every required critic returns
   `approve` with empty `blocking_findings` and `major_findings` for the current
   revision.** At the cap without it: stop, no build, hand the disagreement to
   the user (`--unattended`: a row 3 stop, as is a `reject` in any round, A13).
   `--plan-only` ends here (A15 under `--unattended`).
5. **Build** — or cascade (`docs/cascade.md`; under `--unattended` every
   `DRAFT_ABORT` is classified before it escalates, A21). One writer in the
   checkout at a time.
6. **Your diff read — always,** even with review off: boundaries respected
   (untracked files included), nothing unplanned, no obvious bug. Then **review
   per `--review`**: `full` = your read plus the cross-family reviewer with a
   contract (spec, plan, acceptance criteria, diff; the review schema); `self` =
   your read; `cross` = reviewer, then your spot-check. The review brief says:
   *"approve iff there is no blocking or major finding and every plan item is
   done; minor findings never change the verdict."* **The cross review passes
   with no blocking or major finding and `plan_coverage.missing` empty.** Minor
   findings: fix them or list them in the report — say which.
   **Visual check — not gated by `--review`:** user-facing layout changes are
   approved on screenshots, never on green tests alone; you take them (desktop
   and ~390 px, both themes when the app has them) under `.route2/evidence/` and
   read them yourself; a fix round sends the relevant ones to the builder — a
   Codex builder as `--image=` attachments, others as their paths.
7. **Fix loop.** Findings and red tests go back to the builder (continued as in
   "Launching workers"), at most 3 rounds, then checkpoint and hand the
   diagnosis to the user (`--unattended`: a row 4 stop, A14). **Bounded fixes
   are yours:** a few lines, no design change, nothing in permissions, money or
   data integrity. **Review and screenshots certify the final diff:** after any
   edit that follows them, the changed part goes back to the reviewer, the
   covering tests run again, the screenshots it touches are retaken.
8. **Approve and commit** — inside the fence (`route2-lock exec --gen N -- git
   commit …`) — after your diff read, the passed gates and, unless
   `--skip-tests`, your own test run. A worker's green run is evidence, not a
   verdict.
9. **Report.** Spec, who did what (requested and served models named, with
   transports), review mode, test scope and status, sandbox rung, host,
   families and policy, the cost table (`docs/ledger.md`), what was skipped or
   degraded (including degraded discovery and provisional slots). Release the
   lock (`route2-lock release --token <token> --gen N`). A task queue from
   `--setup` continues with the next task. Under `--unattended` the report opens
   with a `result:` line (`docs/unattended.md`, "Report").

Caps: critique ≤ `--rounds`, gate ≤ 2, fix loop ≤ 3. At the critique or fix
cap: stop, checkpoint with a diagnosis, hand the decision over — never a silent
extra round, never a silent fallback to another worker. Under `--unattended`
that hand-over is a `needs-decision` stop. At the gate cap the cascade
escalates to the implementer, as `docs/cascade.md` prescribes.

## Time and the watchdog

- A host caps its foreground commands (Claude Code: 600 s; Codex: about 30 s of
  yield before a command becomes a background terminal; `docs/hosts.md` has the
  measured value per host). Foreground only for what ends in seconds.
- **Never yield with a live worker.** Interactive Claude Code: a worker found
  without a harness task gets `until ! kill -0 <PID>; do sleep 20; done` armed in
  the background first, and progress is sampled every 5 min with `Monitor` or a
  background `sleep 300`. Other hosts: the `route2-wait` loop (it records
  `last_progress_at` across calls).
- A hang is no progress for `max(15 min, 2 × T_slow)` — read the job's files,
  then `"$R2/bin/route2-kill" <job> --gen N` (called again until `done` or
  `blocked`; it waits for protected tests and signals the rest one by one).
  **A hang never applies to a test**: never `timeout` or kill tests — orphaned
  parallel workers hold a metadata lock that freezes every later run; never
  `pkill -f`.
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
  call, a crashed host): checkpoint, give the new worker the brief plus the
  current `git diff`, re-check critics, reviewer and gate against the new
  builder's family (`route2-roles`), mark the swap in the ledger and the report.
  A plan critic that now shares the builder's family is replaced by one critique
  round of the current plan by an eligible cross-family critic; none eligible →
  halt with a question. A new slot gets its stage 0 probes first. Under
  `--unattended` a swap for limits is a row 5 stop (A17).
- **The skill changed mid-run:** re-read this file and the `docs/` the current
  stage uses before the next step; the checkpoint stays valid.

## Checkpoint and resume

Write `.route2/CHECKPOINT.md` (`docs/checkpoint.md`) after every stage
transition, at every worker launch (with its session id and job id), and on
every limit, API or safety event — always through `"$R2/bin/route2-state"
--gen N write CHECKPOINT.md` (it refuses a file changed outside route2). It
holds the resolved configuration (flags, roster with frozen models and
transports, efforts, `test_scope`, the Codex config mode), the host and your
identity, the lock token, one record per worker session (transport, job id,
rung tokens, rollout offset, worktree, `baseline`, fingerprint), the open
decision and, after `--setup` with separate runs, the task queue.

`--resume` (or a new task while a checkpoint exists with `stage ≠ report` → ask
which to do; never overwrite it silently): read run id and token → take the lock
with `--resume` (it adopts the lock only from a **stale** owner — a live
director keeps it) → re-detect host and identity (a different host, family or
model line → ask; unattended: row 2) → reconcile every recorded job
(`route2-wait`: `running` → wait; `lingering`/`orphaned` → `route2-kill`;
`blocked` stays blocked) → re-probe the frozen slugs and the limits → compare
the tree with the checkpoint's `tree` record and every worktree's `baseline`;
any difference → dirty-exit first → continue at `stage` with `next_action`.

**Building a `--plan-only` plan** works as in route 3.4: the approval stands
only while the plan is unchanged (`plan_sha256`) and no approving critic shares
the family of a possible builder; otherwise one critique round by the critics
the build roster requires (A20 under `--unattended`).

## Ledger

One line per model call in `.route2/ledger.jsonl`, appended through
`route2-state --gen N append ledger.jsonl` right after reading its output
(fields and sources: `docs/ledger.md`, including `transport`, `host` and the
`transport-switch` outcome). Missing numbers are `null`, never estimated.
Cumulative counters (`codex exec resume`, agy conversations) keep the raw values
in `raw_cumulative` and record the delta. Token totals are never presented as
subscription cost.
