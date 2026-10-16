# Changelog

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
