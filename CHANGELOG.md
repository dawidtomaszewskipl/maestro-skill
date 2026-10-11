# Changelog

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
