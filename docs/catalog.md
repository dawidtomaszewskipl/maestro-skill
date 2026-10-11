# Live catalog

route used fixed slugs (`gpt-6.1-sol`, `gemini-3.8-flash`): a new Sol or Opus meant editing the
skill. route2 treats a slot as a **model line** and resolves it at stage 0 from the catalogs the
CLIs publish, then freezes what it found for the run.

## Sources

`"$R2/bin/route2-catalog" refresh` reads every source **without a model turn** and writes
`.route2/catalog.json`:

| Transport | Source | Notes (measured 2026-10-11) |
| --- | --- | --- |
| codex | `codex debug models` (run through `route2-env`) | Refreshes the catalog from the server and prints `{models: [{slug, visibility, supported_reasoning_levels[].effort, default_reasoning_level, …}]}`; only `visibility: "list"` entries count. It also rewrites `$CODEX_HOME/models_cache.json`, whose `identity`, `client_version` and `fetched_at` the catalog copies (the live output has no account identity). |
| codex, fallback | `$CODEX_HOME/models_cache.json` | Used when `debug models` fails. Older than 7 days, or `client_version` ≠ `codex --version` → `stale: true`. |
| codex, last resort | `codex debug models --bundled` | The binary's own catalog, no refresh — `mode: bundled`. |
| agy | `agy models` | `<slug>\t<label>` lines after a `Fetching available models...` banner. Lists Gemini (3.8/3.7/3.6 Flash, 3.1 Pro) **and Claude** (Opus 5.5, Sonnet 5.5 at low/medium/high) and GPT-OSS. |
| cursor | `agent --list-models` | `<slug> - <label>` lines between a header and a tip. Lists Grok, Claude (current and older generations, `-thinking-` variants, `-fast` variants), GPT, Gemini, Kimi, GLM, Composer, Muse. |
| native Claude | none | Claude Code's aliases (`opus`, `fable`, `sonnet`, `haiku`) follow the newest model of each line; the full id is learned by probing (below). |

**Stale and bundled data are degraded discovery**: a successful probe proves the chosen model is
usable, not that it is the newest live one. The Assign line says `catalog codex: degraded
(stale|bundled)` and the report repeats it. A failed or malformed source is an **acquisition
failure** for that transport (`sources.<t>.error`): the transport is ineligible this run — which is
different from a line that simply has no candidates.

## Lines

| Slot | Pattern (jq/Oniguruma, `[0-9]` only) | Transports |
| --- | --- | --- |
| `astra` `sol` `luna` `terra` | `^gpt-<v>-(astra\|sol\|luna\|terra)$`, `<v>` = `[0-9]+(\.[0-9]+)*` | codex |
| `gemini` | `^gemini-<v>-flash(-(low\|medium\|high))?$` | agy |
| `opus` `fable` `sonnet` `haiku` | `^claude-(opus\|fable\|sonnet\|haiku)-<v>-<effort>$`, `<v>` = `[0-9]+(-[0-9]+)*` | agy (`low…high`), cursor (`low…max`, plus `-fast`) |
| `grok` | `^grok-<v>-<effort>(-fast)?$` | cursor |

A version is parsed into a list of integers: `gpt-6.1` → [6, 1], `gpt-7` → [7],
`claude-opus-5-5` → [5, 5], `claude-opus-5-10` → [5, 10], `grok-5` → [5]. Comparison pads the
shorter list with zeros: [5] = [5, 0]; [6, 1] > [6]; [7] > [6, 10]; [6, 10] > [6, 9]
(`route2-catalog compare` and fixture T2). Integer generations (`gpt-7-sol`, `gemini-4-flash`,
`grok-5`) are covered by the same patterns.

**Excluded from automatic resolution**, listed under `transports.<t>.unmatched`: any other suffix
(`-preview`, dates, `-mini`, `-nano`), Cursor's `-thinking-` naming of older Claude generations,
Cursor's own `cursor-grok-*` builds, and every model of a line route2 has no slot for. An unmatched
slug can still be pinned exactly (below) — a preview never becomes a worker unannounced.

## Resolution

`"$R2/bin/route2-catalog" pick <slot> <transport> [--effort E] [--pin V | --pin-slug S] --scope
<json>` walks the slot's candidates on that transport, newest first:

- `{action: "use", version, slug}` — a fresh successful probe exists for this scope;
- `{action: "probe", version, slug}` — run the transport's probe line (`docs/commands.md`), then
  `route2-catalog record-probe --gen N <transport> <slug> ok|denied --scope <json>`;
- `{action: "none", reason, previous}` — nothing usable: no candidate, every candidate denied, a
  pin not in the catalog, or no slug for that effort (clamp the effort first).

**Walk-down.** A probe failure that says the account cannot use the model (unknown model,
entitlement, "not available for your plan") is recorded as `denied` and the next older candidate
is tried; the highest passing version wins and the Assign line says so — `sol=gpt-6.1-sol
(gpt-6.2-sol listed, denied for this account)`. **Quota and network failures do not walk down**:
they are transport problems (SKILL.md, "Routing precedence"; `docs/hosts.md`, "Transport switch").
No candidate passes → halt (unattended: row 2).

**A renamed line** (no candidates at all): `previous` — the version this repository resolved last
time, kept in `catalog.json` — is probed; it passes → used, with `line unmatched — kept <slug>` in
the Assign line (unattended: a recorded assumption, row 1); it fails or there is none → halt
(row 2).

## Identity and the native transport

The canonical identity of a model is `{line, version}`; each transport derives its slug and effort
from it. Native Claude has no catalog, so stage 0 **probes the alias** — `claude -p --model opus`
— and reads the full id from the `init` event and `modelUsage` (measured: `claude-haiku-5-5` for
`haiku`). That id becomes the slot's frozen identity, and later native calls use it exactly
(`claude -p --model claude-opus-5-5`). An Agent-tool call can only take the alias, so its
completion's model is compared with the frozen id; a writer whose model differs is discarded
through the dirty-exit protocol.

**First use with native exhausted**: the alias probe fails before any id exists → native is
skipped; the next transport's probe passes and its `{line, version}` becomes the identity; native
rejoins later only if a probe of the matching full id (`claude-<line>-<version joined by ->`)
returns exactly that id.

**Same model across transports.** agy and Cursor slugs match the frozen `{line, version}`; a
transport without that version is not a switch target — moving there is a swap (SKILL.md).

## Pins

Policy `pin` (`docs/policy.md`):

- **canonical** — `pin: {sol: "6.1", opus: "5.5"}`: every transport of the slot must serve that
  version; a transport without it is ineligible for the slot. Native reaches a canonical pin only
  through the constructed full id (`pin: {opus: "5"}` → `claude-opus-5`), accepted only if its
  probe returns exactly that id; otherwise native is ineligible for the pinned slot (no alias
  fallback).
- **exact** — `pin: {sol: {codex: "gpt-6.1-sol"}}`, `pin: {opus: {native: "claude-opus-5"}}`:
  that slug on that transport, the slot's other transports disabled. An excluded slug
  (`gpt-6.2-sol-preview`) can only be pinned exactly; its identity is `{line, version, tag}` and it
  never matches another transport.
- A pin missing from the catalog halts like an unknown slot.

## Probes

`.route2/model-probes.json`, one record per `<transport>:<slug>`: `{result: ok|denied, scope,
at, at_epoch, detail}`. A record counts only when its **scope** equals the caller's and it is
fresh — successful probes for 7 days, denials for 24 hours. The scope:

| Field | codex | agy | cursor | native |
| --- | --- | --- | --- | --- |
| CLI version | `codex --version` | `agy --version` | `agent --version` | `claude --version` |
| account | catalog `identity` | none known | `agent status` account | `claude auth status` account |
| config | Codex config mode | — | — | — |
| context | host and its sandbox profile | same | same | same |
| session | — | the host session key (no account identity → never reused across sessions) | — | — |

The probe lines (lowest effort of the transport, *"Reply with exactly: OK"*, through `route2-env`)
are in `docs/commands.md`.

## Freezing

The resolved ids, slugs, transports and efforts go into the checkpoint (`catalog`) and are sticky
for the run: a fix round never silently moves to a model that appeared mid-run. `--resume`
re-probes those exact slugs (availability, quota), it does not re-resolve. `route2-catalog
record-resolved --gen N <slot> <transport> <version>` keeps the resolution in `catalog.json` as
next run's `previous`.

## Precedence (routing over transports)

| Situation | Attended | `--unattended` |
| --- | --- | --- |
| Slot without `@` | first eligible transport in order; denied and unavailable transports skipped, each named | same |
| `@transport` forced | that transport only; ineligible → halt with a question | row 2 stop |
| `@transport` forced, quota/unavailable at run time | no switch — halt | row 5 stop |
| Quota/unavailable at run time, no `@`, next eligible transport serves the same model id | transport switch (`docs/hosts.md`) | same (A16a/A17) |
| Next transport serves a different version, or none left | swap | row 5 stop |
| Explicit `--model=<slot>` whose transports are all denied by policy | first *available* transport in order, with a warning | same |
| Explicit `@transport` that policy denies | used, with a warning | same |
| Explicit anything that is unavailable (CLI missing, signed out, probe failed) | halt — explicit never beats unavailability | row 2 stop |
| First use (no identity frozen yet), a transport's probe fails (quota, unavailable), no `@` | skipped; the first transport whose probe passes fixes the identity — this row wins over the one above, which applies only when no transport of the slot passes | same; halt = row 2 |
