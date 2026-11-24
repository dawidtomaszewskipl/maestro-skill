# Changelog

## 2.2.0 — 2026-11-24

**New CLI versions and models, no routing change.** The docs are brought up to Codex 0.172.0,
agy 1.5.16 and Claude Code 2.1.331 and to GPT-6.2, Gemini 4 Carbon and Neon and the Claude 5.5
models. Every new claim carries a date, a source and a label (vendor, independent, secondhand,
local measurement); what had no retrievable source is marked "not verified". The rubric rows,
the critic, reviewer and arbiter orders and the degraded-mode orders are unchanged
(`docs/workers.md`, "Evidence and the rubric").

### Slots
- **`carbon` and `neon`** (Gemini 4 Carbon and Neon, family Google, transport agy, provisional)
  in `bin/slots.json`, the roster, the catalog lines and the policy keys. Both are
  **`explicit_only`**: no automatic choice picks them, and an eligible but unnamed one does not
  count as an eligible family — so, for example, Sol + Astra + Neon with Claude unavailable and
  Argon and Gemini denied is still OpenAI-only degraded critique (Astra), not a halt. Naming one
  is role-scoped: `--critic`/policy `critic` makes it a critic, `--reviewer`/policy `reviewer` the
  reviewer only, `--model` the builder.
- `maestro-catalog`'s agy classifier maps Hydrogen and Flash to `gemini` and Argon, Carbon and
  Neon each to its own slot. The orchestrator slugs (`gemini-pro-orchestrator`, `-neon`, `-argon`)
  stay unmatched.
- `maestro-roles` takes `named_reviewer` (`--reviewer`): it beats the policy reviewer, and an
  unavailable one or one of the builder's or drafter's family is a stop, as for a named critic.
  A `carbon`/`neon` critic named for critique only is never reused as the reviewer: the reviewer
  then comes from the usual order with the explicit-only slots left out (degraded same-family
  review when only one family is left; none eligible → no reviewer, said in the notes).
  `maestro-policy roles-input` adds `explicit_only`.

### Evidence
- Sources were read for each published figure: OpenAI's GPT-6.2 page (prices incl. Sol's $0.10
  cached input; Sol within 0.5 points of Astra on FrontierCode 2.0 at a fifth of the cost),
  Artificial Analysis (Coding Agent Index: Astra flat, Sol −3; Intelligence Index per effort; Gemini
  dates and prices), Google's Gemini 4 Neon model card and methodology (Neon's Terminal-Bench 4.1
  65.2 % is an independent Artificial Analysis run on the Antigravity CLI 1.5.9 harness), Google's
  Hydrogen announcement (2026-11-12 — it was not unannounced, as 2.1 said), Google's Argon
  (2026-10-13) and Carbon (2026-11-10) launch posts ($2 / $10 until 2026-11-30, $4 / $20 after),
  Cognition's FrontierCode 2.0 data (scores and mean cost per rollout per effort), Anthropic's
  Haiku price. Claims without a retrievable source were dropped.
- `maestro-roles`: the reviewer fallback first takes a selected critic that is not explicit-only
  (a high-stakes second critic such as Fable), then the critic order for the run's stakes.
- `docs/troubleshooting.md`: the "resume runs in the shell's directory" incident is dated to
  its observation on 0.159.2; on 0.172 the thread restores its saved cwd.

### Codex 0.170–0.172
- GPT-6.2 Sol and Astra are the first candidates of `sol` and `astra` (the resolver is generic)
  until the account probe succeeds; pin `sol = "6.1"` to keep 6.1. Evidence is mixed: recorded,
  not a routing change.
- `codex exec resume` restores the saved cwd and sandbox unless overridden (0.172). **Observed:**
  a resume from another directory ran in the thread's original directory; the role's
  `-c sandbox_mode` still wins. The recipe is unchanged. `--remote` (0.171) is not used.

### agy 1.5.10–1.5.16
- The Gemini 4 line-up table; `-r`/`--resume` aliases (maestro keeps `--conversation`); the
  1.5.13 fix of `ERROR` after a successful retry; the 4-minute rate-limit wait (watchdog threshold
  unchanged); swarms and the Orchestrator are not used; `~/.agents/skills` discovery.

### Claude Code 2.1.326–2.1.331
- Recorded, no change to maestro: the Agent tool's `effort` parameter (honored for named teammates
  since 2.1.329; maestro passes none), the 10 s model-settings grace of `-p`, exit 1 on an output
  failure, the 10-minute background-subagent wait, resumed subagents keeping their model, the
  `Agent(model:*)` follow-up fix, the startup warning for malformed `--tools`/`--allowedTools`
  entries, `sandbox.failIfUnavailable`.

### Tests
- Fixture `tests/fixtures/catalogs/machine-2026-11-24`; T2 checks it (GPT-6.2, Carbon, Neon,
  Hydrogen, the three orchestrator slugs unmatched, full-slug picks); T7 the explicit-only rule
  and the named reviewer; T18 the exclusion lists with Carbon and Neon.

## 2.1.0 — 2026-11-14

**The 2.0 review's thirteen items: the plan critique converges, and more of the director's hand
work moved into helpers.** Fable 5.2 built the plan-critique, policy, checkpoint-patch and
interactive-job parts as a builder; every diff was read, tested and merged by the director.

### Plan critique converges
- **Severity rubric** in every critique brief (`docs/briefs.md`, "Plan critique"): `blocking` = the
  plan cannot meet the spec or would cause damage; `major` = a defect reachable with an input or
  state the spec allows; the rest are notes. Blocking and major findings carry a required
  `trigger`.
- **Delta rounds.** From round 2 a critic gets its open findings with the director's resolutions,
  answers each in the new required `prior_findings` (`resolved` | `not_resolved`) and reports new
  findings only when the revision introduced them, they are blocking, or they are a major missed
  earlier with a trigger inside the spec. Approval also needs every
  prior finding resolved.
- **Arbiter at the cap.** Only majors left, not high stakes, a third family eligible
  (`maestro-roles --arbiter`) → one call with `docs/schemas/arbiter-schema.json`; every finding
  downgraded approves the plan (the report says so), anything else is the stop as before. Also
  under `--unattended` (A13).
- `maestro-validate --decide critique|arbiter [--ids …]` prints the mechanical decision; an
  `approve` that still lists findings is invalid.

  Live: Argon as arbiter downgraded the int64 finding that stopped the 2.0 canary at the cap
  ("a state the system cannot reach").

### Policy is TOML and has a reader
- `maestro.policy.toml` and `~/.config/maestro/policy.toml` (stdlib `tomllib`). `maestro-policy
  resolve` merges flags > repo > user > defaults per key, validates against `bin/slots.json`, and
  returns `{effective, sources, warnings, stops}`; `roles-input` feeds `maestro-roles`. A
  `maestro.policy.yml` left over stops with "convert to TOML". The removed 1.x keys stop.
- Bare `--cascade` now leaves the drafter to policy (`cascade: "default"` in `maestro-flags`).

### One job model in both modes
- Interactive Claude Code also launches every external worker and test run through `maestro-run`;
  one background Bash call runs `maestro-wait <job> --until-done` and its notification wakes the
  director. Interactive jobs now have `meta.json`, an exit code and `maestro-kill`; the
  hand-rolled `kill -0` watchdog is gone. `--until-done` keeps waiting on `running` and on
  `uncertain` with a live leader, and returns on every other state (lingering and orphaned need
  `maestro-kill`, so waiting on them would hang).
- `maestro-run` takes host and session from the lock when the environment has none, so ledger rows
  keep their host.

### Checkpoint patches
- `maestro-state --gen N set key=value…` and `add-session <transport> '<json>'` patch the front
  matter in place through the same audit as `write`; the first checkpoint and structural changes
  still use `write` (`docs/checkpoint.md`, "Format rules").

### Helpers
- `maestro-brief open|close|rubric`: the fixed brief text, checked word for word against
  `docs/briefs.md` (T12).
- `maestro-status`: stage, round, next action, open decision, live jobs, ledger, lock.
- `maestro-limits`: Claude's `rate_limit_event` and Codex's rollout `rate_limits`, no model turn;
  a pool at ≥ 90 % is a warning in the Assign line and steers rubric rows 3–5.
- `maestro-ledger report --run <id>`: the report's cost table; Codex rows now carry `duration_s`.
- `maestro-flags`: a lone `--` ends the flags; a near-miss flag gets "did you mean".
- `maestro-wait` defaults to `--max 100` (the Bash default cap is 120 s); with `timeout: 600000`
  the director passes `--max 540` — about 20× fewer turns on a long build than with 25 s.

### Loop
- Two high-stakes critics run at once under one fingerprint snapshot/compare.
- A re-review after a fix round gets only the diff since the last reviewed state plus the open
  findings (the review stage was the costliest in the ledger).
- `docs/unattended.md` 52 → 28 KB: the inventory reproduction and the scenario test moved to
  `docs/unattended-reference.md`.

## 2.0.0 — 2026-11-14

**Claude Code only; Cursor and Grok out; Gemini 4 Hydrogen and Fable 5.2; the director's hand
checks became helpers.** Breaking: read "Migration" before upgrading.

### Breaking
- **Claude Code is the only director host**, interactive or headless (`claude -p --unattended`).
  Codex and agy stay as worker transports. `maestro-host` now answers `claude-code`, `unsupported`
  (another agent CLI is directing) or `unknown`; the `--host` flag, `$maestro` (Codex) and the
  agy and Cursor directors are gone, and so are the director identity from a Codex rollout and the
  per-host adapters.
- **Cursor's `agent` transport, the `grok` slot and the xAI family are removed.** Three families
  remain: Claude, OpenAI, Google. Transport orders: opus and sonnet native → agy → api, **fable
  native → api** (no subscription fallback: a native quota hit is a swap unless `api` is
  eligible), haiku native → api, argon agy only. Second-critic orders: Claude → google, openai;
  OpenAI → google, claude; Google → openai, claude. Rubric row 5 is `sol` or `gemini`, row 6's
  fallback `sonnet`, `sol`, `gemini`. `maestro-ledger --cli cursor-agent` and
  `maestro-validate --envelope cursor` are gone.
- **Install location:** a real copy in `~/.claude/skills/maestro` (was a symlink to
  `~/.agents/skills/maestro`, also linked for agy). `install.sh --hosts` is gone.

### Models
- **Gemini 4 Hydrogen** (`gemini-4-hydrogen-{low,medium,high,xhigh}`, reported as Gemini 4 Flash;
  Google has not confirmed it) is now the line of slot `gemini`; Flash (3.8) stays as the older
  candidate, and at one version Hydrogen wins. agy slugs up to `max` are parsed; effort is clamped
  to the suffixes a model lists (Hydrogen up to `xhigh`, Argon to `high`).
- **Fable 5.2**: `claude -p --model fable` serves `claude-fable-5-2` (probed); $8/$40 per MTok.
- New fixture `tests/fixtures/catalogs/machine-2026-11-14` (Codex 0.169.0, agy 1.5.9);
  `gemini-pro-orchestrator-g1-pro` and `gpt-oss-120b-medium` stay unmatched.

### CLI catch-up (Claude Code 2.1.325, Codex 0.169.0, agy 1.5.9)
- agy: a print timeout exits 3 with `finished_reason: print_timeout` — `maestro-validate` rejects
  any `finished_reason`; Auto is the default mode since 1.5.7, so every agy line passes `--mode`
  (the `/skills` probe now `--mode plan`). `--disable-slash-commands` was measured and **not**
  adopted: it makes `--mode plan` ineffective.
- Claude Code: the init check fails closed on `plugin_errors`; `maestro-preflight` warns when the
  login expires within a day (`loginExpiresAt`); since 2.1.323 the Bash sandbox makes `git
  worktree` read-only — preflight names the remedy. `--restricted` was measured and not adopted
  (no gain over the read-only lines' own flags).
- Codex: `--trust` is never used; `cyber_access_program` must be `standard`; the effective-config
  check was verified on a 0.169.0 rollout; the coming rollout migration is a known risk.
- Agent SDK 0.3.312 → 0.3.325 (bundles Claude Code 2.1.325); one paid probe on Fable 5.2 cost
  $0.0036 (the SDK's estimate).

### Refactor
- `bin/slots.json`: one slot table (family, transport order, pin pattern, provisional) read by
  `maestro-roles` and `maestro-catalog`; T12 checks SKILL.md's roster against it.
- New helpers: `maestro-preflight` (stage 0 steps 2, 3, 3a, 6, 7 in one call, about 2 s),
  `maestro-identity` (the Codex effective-config check that was a script copied by hand from
  commands.md, and the `claude -p`/`api` init check), `maestro-flags` (syntax, unknown values and
  every illegal combination).
- `maestro-wait`: meta.json read once, members matched in one pass, the unowned scan by one
  `find` — a snapshot went from about 870 to 210 ms here.
- `_lib.sh`: shared fencing, job-dir, rollout and event readers. **Fix:** `maestro-wait`,
  `maestro-kill` and `maestro-ledger` accepted a job id with `..`; every helper now refuses it.
- SKILL.md 46 → 35 KB and `docs/hosts.md` 28 → 16 KB; the fixed brief text moved to
  `docs/briefs.md`, splits to `docs/worktrees.md`, measurement history to `docs/evidence.md`.
- Tests: T12 (docs consistency, ban on the removed names), T13 identity, T14 preflight, T15 flags;
  378 pass. A /code-review pass found ten defects in the branch before release; all fixed.
- `maestro-state adopt` refuses unless `maestro-host` reports an interactive Claude Code (headless
  `claude -p`, or another agent CLI): no user there could have inspected the file. An interactive
  Claude Code running `--unattended` cannot be told apart and stays the director's rule.
- Interactive check: an Agent-tool Sonnet builder, an agy Argon critic with `--json-schema`, the
  `claude-agent` ledger row and a fenced commit (`docs/evidence.md`). The Agent tool's completion
  names no model, so `maestro-ledger --cli claude-agent --served` is optional (null when absent).
- `maestro-lock` refuses unknown options; `maestro-preflight` does not count an untracked project
  install of the skill (`.claude/skills/maestro/`) as a dirty tree; `tests/run.sh` prints the time
  of each group.
- Live canary (`tests/canary/build-interrupt-resume.sh`, headless Sonnet director, `--critic=sol`):
  the first run stopped correctly at the critique cap (`needs-decision`, row 3); resumed with the
  build option, the director was killed while the build job ran, and `--resume --unattended`
  reconciled the finished job, checked its identity, ran the tests and committed.

### Migration from 1.x
- Run `./install.sh` (add `--sdk` for the api transport). It replaces the 1.x symlink and names
  the leftovers: delete `~/.agents/skills/maestro` and `~/.gemini/config/skills/maestro` yourself.
- A policy that names `grok`, `xai`, `cursor_fast` or a `<slot>@cursor` pair halts until the
  entry is removed.
- A checkpoint from 1.x that recorded another host, a `cursor` transport or a `grok` slot stops on
  `--resume`: finish or discard that run with 1.4.0, or start again.

## 1.4.0 — 2026-10-28

**Documentation for people, not only for the author; the skill caught up with four CLI updates.**

- **New documentation.** README.md and README_pl.md explain in plain words what maestro does, why it
  uses models from several companies, what a run looks like and how to start. A new `docs/guide/`
  (how it works, models and roles, costs and limits, setup and hosts, glossary) sits in front of
  the technical pages, which stay in `docs/` with a short "what this page is for" note each.
  `docs/README.md` is the map.
- **No more `/route`.** Every reference to the older skill is gone outside this changelog. Stage 0
  no longer looks for an unfinished `.route/CHECKPOINT.md`; the cascade's stash is now
  `maestro-draft-<run_id>` and a worktree's integration commit `maestro-integrated`.
  `docs/release-1.0.0.md` and `docs/evidence/1.0.0/` were removed (they remain in tag v1.0.0).
- **Codex 0.165:** `terra` now resolves to `gpt-6.1-terra` (probe passed); unknown models fail
  fast, so a denied model walks down in seconds; token numbers across Codex versions are not
  comparable (0.163/0.164 accounting changes).
- **agy 1.4.8:** every agy call writes its own log (`--log-file "$J/agy.log"`) for
  `maestro-wait --also`, instead of guessing the newest global log; `maestro-validate --envelope
  agy` reads `structured_output` first. A denied command now comes back as `SUCCESS` with
  `denied_actions` — the validator already rejects it. `--mode auto` was measured: not available
  on this account, so agy builders stay edits-only. Gemini 3.7/3.6 Flash and 3.1 Pro left agy's
  catalog.
- **Cursor 2026.10.22:** stage 0 reads `agent status --format json` and `agent about --format json`
  (version, update status). Critic briefs forbid searching outside the repository, since Grep and
  Glob now can. A per-repository `.cursor/sandbox.json` network allowlist was measured to work
  with the sandbox's containment intact — documented as a setup step that lets a Cursor builder
  run tests needing a registry; maestro never writes that file. Cursor's `slug[effort=…]` model
  syntax is refused.
- **Agent SDK 0.3.312** (bundled Claude Code 2.1.312) for the `api` transport; one paid probe
  confirmed `apiKeySource`, the full model id and the bundled version (estimated $0.00004).
- **Fix:** `maestro-wait` could report a job that ended at the wrong instant as `lost` instead of
  `exited`; it now reads the exit code again after its liveness checks (test T4 was flaky).
- shellcheck now runs in the suite here; 293 tests pass.

## 1.3.0 — 2026-10-15

**`--sdk` and the `api` transport: Claude workers on the Max plan's API credit.** A Max plan
includes a monthly API credit ($200 on Max 20x) that covers the Claude API and the Agent SDK but
not Claude Code. `bin/maestro-sdk` runs one worker turn through the Claude Agent SDK (pinned
0.3.286, `install.sh --sdk`) on a key read from `~/.config/maestro/anthropic-api-key` (mode 600).
It emits the `claude -p` stream-json shape, so jobs, validation and the ledger work unchanged.
`--sdk` puts every Claude slot on `api`. Policy `api: {fallback: true}` makes `api` the last
transport a Claude slot switches to on quota. `api.max_usd_per_run` (default 20) caps a run through
the SDK's `maxBudgetUsd`.

- **Fail closed on billing.** `maestro-sdk` aborts unless `init.apiKeySource` is
  `ANTHROPIC_API_KEY`. `maestro-env` now drops every `ANTHROPIC_*` variable, so a key left in the
  director's shell can no longer bill native `claude -p` workers silently (in `-p` mode a key
  outranks the subscription login).
- **Full ids only on `api`.** The SDK's bundled CLI resolved `haiku` to `claude-haiku-4-5-20251001`
  (measured), so aliases are refused. `maestro-sdk --resolve <slot>` reads the newest id from the
  Models API (no model turn).
- **Ledger**: `--cli claude-sdk`, a `cost_usd` field (the SDK's estimate) and `maestro-ledger cost
  --run <id> --transport api`.
- Measured without spending: a run with an invalid key reported `apiKeySource: "ANTHROPIC_API_KEY"`,
  `tools: []`, `mcp_servers: []` and builtin plugins only. A paid canary and the Console check that
  the credit, not the balance, went down are still open (`docs/manual-checks_pl.md`).

**Slot `argon`: Gemini Argon.** Google's frontier line (`gemini-<v>-argon-<effort>`, first
`gemini-4-argon`) is listed by both `agy models` and `agent --list-models` since 2026-10-16. Until
now it landed in `unmatched` and was never used. It is now its own slot, family Google, transports
agy → cursor.

- **Critic and reviewer first.** In every critic order Argon stands before Flash, and a high-stakes
  second critic from Google is Argon when eligible. Flash (`gemini`) keeps its rubric rows, row 6
  and `--cascade=gemini`. Argon builds only when named.
- **Google-only degraded mode** now exists: Argon critiques a Flash build and the other way round.
- **Provisional**, like Grok, until the ledger has measured it.

## 1.2.0 — 2026-10-12

**agy critics, gates and reviewers read the repository themselves.** Their brief names absolute
paths inside `$REPO` — the plan, the diff written to `.maestro/diff-<role>-r<N>.patch`, the
convention files, the code — instead of the director quoting all of it; file tools are allowed
inside `--add-dir`, commands, MCP and anything outside the repository stay forbidden. Measured with
Gemini 3.8 Flash (medium), the same critique three times each way: both variants answered 3/3 with
no denial and the same findings; reading took 112–145 s and 114–144 k input tokens against 58–67 s
and 37–40 k inline — Gemini's pool, and on a large repository no quoting and no argv limit. A read
from an excluded `.maestro/` works; a path outside `--add-dir` is denied and empties the answer, so
a denial falls back to the inline variant (whole brief quoted, no tools) in a new conversation.
Applies to Claude-on-agy as well.

## 1.1.1 — 2026-10-12

Fixes from the first real run (legat, interactive Claude Code):

- **A helper given `--gen` inside `maestro-lock exec` no longer fails.** The nested exec used to
  be refused outright; it now runs the command directly while the enclosing `flock` process (the
  one holding this repository's lock) is alive and the fence is still current, and refuses
  otherwise. Workers and jobs never inherit the fence variables. SKILL.md says which helpers take
  the fence themselves, so wrapping them is not needed at all.
- **`maestro-catalog refresh --gen N`.** The sources are read outside the lock (network calls), the
  write of `catalog.json` runs inside the fence; a superseded fence leaves the file untouched.
- **Ledger rows on an interactive Claude Code carry `run_id` and `host`.** Its job directories
  have no `meta.json` (the Bash tool's background mode, not `maestro-run`); `maestro-ledger` now
  takes both from the lock record, or from the new `--run`/`--host` options.
- **Agent-tool rows through `maestro-ledger`.** `--cli claude-agent` (no job) takes the
  subagent's completion — `--served`, `--agent-id`, `--total-tokens`, `--tool-uses`,
  `--duration-ms` — and leaves the input/output split `null`, as the harness reports none. Rows
  gain a `tool_uses` field. SKILL.md: never write a ledger row by hand.
- Tests 253 passing.

## 1.1.0 — 2026-10-11

**Renamed from route2 to maestro** — a new skill in its own right, not a version of route. No change
in behaviour.

- Command `/maestro` (`$maestro` in Codex); helpers `bin/maestro-*`; state in `.maestro/`; policy
  in `maestro.policy.yml` and `~/.config/maestro/policy.yml`; environment variables `MAESTRO_*`;
  install target `~/.agents/skills/maestro` (plus the Claude Code and agy links).
- Nothing is migrated: a `.route2/` directory or a `route2.policy.yml` left by 1.0.0 is not read.
  Finish or discard an open route2 run before switching.
- README.md and README_pl.md rewritten for people: how a run goes, what is new compared to route,
  the hosts compared side by side, models, cost, known limits.
- `docs/manual-checks_pl.md`: the cases still to be checked by hand, step by step.
- The 1.0.0 evidence (`docs/evidence/1.0.0/`, `docs/release-1.0.0.md`) was measured under the name
  route2 and is kept as recorded.

## route2 1.0.0 — 2026-10-11

Forked from route 3.4.0 (`route-skill` at `2912f16`, including `--unattended`) as a separate skill,
invoked as `/route2` (`$route2` in Codex). route is unchanged.

**Hosts.** The director runs in Claude Code, Codex, Cursor's `agent` and agy. `bin/route2-host`
detects the host from the process ancestry and the host's own markers — markers are inherited by
children, and sandboxes hide parts of the ancestry, so a host whose marker is present but whose
process is not visible makes the ancestry untrusted (measured in Cursor's and Codex's sandboxes).
One adapter per host decides how Claude workers start, how long commands are waited for and how
the user is asked (`docs/hosts.md`). A headless director requires `--unattended`; agy directs only
interactively.

**Families and transports.** A fourth family, xAI (Grok through `agent -p`), as critic, reviewer
and builder (rubric row 5, provisional). Claude slots have transports in order native (Agent tool /
`claude -p`) → agy → Cursor; a quota or availability failure continues the same model on the next
transport as one transaction (termination confirmed, dirty-exit, capability-adjusted brief, ledger
row). `@transport` forces one. The cross-family rule, its critic orders and degraded modes are
generalised to four families and implemented in `bin/route2-roles`; Astra may critique an OpenAI
build only in OpenAI-only degraded mode; Claude can be switched off.

**Live catalog.** Slots are model lines resolved at stage 0 from `codex debug models`, `agy
models` and `agent --list-models` (`bin/route2-catalog`), with integer-segment version ordering,
walk-down past models the account cannot use, pins, scoped and dated probe records, and a run
freeze. No model numbers remain in SKILL.md's rules.

**Jobs, lock, audit.** Off an interactive Claude Code there is no completion notification, so
`bin/route2-run`/`route2-wait`/`route2-kill` run every worker and test as a detached job that
survives the director's commands and session (measured on all four hosts), track every process of
its tree, never signal a test, and report `running|exited|lingering|orphaned|lost|uncertain`. One
director per checkout: `bin/route2-lock` with a generation fence — every mutation runs inside
`route2-lock exec` holding the flock. Bookkeeping goes through `bin/route2-state`, verified against
`audit.jsonl` before every write. State lives in `.route2/`, never `.route/`.

**Workers.** `claude -p` workers run with an exclusive tool set, `dontAsk`, no MCP and no settings
sources, edits-only as builders; `bin/route2-env` strips the director's markers and inherited
plugin and effort variables (a `CLAUDE_CODE_PLUGIN_DIRS` plugin with hooks reached a critic before
it). Cursor workers run in `--mode plan --sandbox enabled` as critics and `--sandbox enabled` as
builders, never `--force` (which disables the sandbox entirely). Effective identity is checked
from each CLI's `init` event. Every verdict goes through `bin/route2-validate` (envelope, exactly
one JSON object, full schema); every external read-only call through `bin/route2-fp`.

**Not adopted.** The Codex SDK and the Claude Agent SDK (both wrap the CLIs), `claude --bare`
(API key only), Cursor's `--worktree`, `--auto-review`, `--approve-mcps`, `-fast` variants by
default, Kimi/GLM/Composer/Muse slots, a Claude Code bash-sandbox rung for `claude -p` builders
(unmeasured).

**Docs.** New `docs/hosts.md` and `docs/catalog.md`; every other doc updated; Polish only in
`README_pl.md` (no `docs/pl`). Tests: `tests/run.sh` (fixtures and real processes, no model calls).
