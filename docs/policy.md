# Roster policy

> **What this page is for.** Every key of the policy file (`maestro.policy.toml`, `~/.config/maestro/policy.toml`) and how it is applied. The plain overview is in [the guide](guide/setup-and-hosts.md#the-policy-file).

maestro's routing is a written rubric (see "Roster" in `SKILL.md` and "Which models it can use"
in the README). A policy file lets you bend that rubric once instead of correcting
the director every run — "never pick Fable here", "critic is always Gemini", "this repo builds with
Sol by default".

## Where

| File | Scope | Typical use |
| --- | --- | --- |
| `maestro.policy.toml` at the repository root | the project, committed | team conventions: default implementer, banned slots or transports, a family the team does not license, pinned models |
| `~/.config/maestro/policy.toml` | you, every project | your own budget: "I never spend Fable on builds", "no Claude through agy" |

The user file stays where 1.x put it, outside `~/.claude`, so a reinstall of the skill never
touches it. No other policy file is read.

Precedence, highest first: **command-line flags → repo policy → user policy → skill defaults**,
resolved **per key**: a scalar, each `effort.*` entry, each `families.*` entry, each `pin.<slot>`
and each `api.*` entry is taken from the highest level that sets it. A higher-level `deny` or
`transports.deny` list *replaces* a lower one (an empty list clears it). `families.<x> = "on"` lifts
a lower-level `"off"`, but cannot make an absent or signed-out CLI available. Effort resolves per
stage and family: at each level a per-family value (`effort.<stage>.<family>`) is looked for first,
then the stage's single value — so a repo `effort.review = "high"` beats a user
`effort.review.openai`, and a repo `effort.review.openai` leaves the other families to the user's
single value.

`bin/maestro-policy resolve` is the reader: it parses both files, merges them with the flags
(`--flags` takes `maestro-flags`' output), validates the result against `bin/slots.json` and prints
one JSON line — `effective` (every key, defaults included), `sources` (`flags`, `repo`, `user` or
`default` per key path), `files`, `warnings` and `stops`. Nothing else reads a policy file.
`maestro-policy roles-input` prints the part `maestro-roles` takes (`policy_critic`,
`policy_reviewer`, the named critics and reviewer, the slots to drop from `eligible`, the denied
transports per slot, and `explicit_only` — the explicit-only slots still in the roster, which stay in
`eligible` because `maestro-roles` keeps them out of every automatic choice itself).

## Keys

All optional. Slot names are the `--model` values (strings); effort values are the CLI vocabulary.

| Key | Meaning |
| --- | --- |
| `deny = [slot, …]` | The director never picks these on its own. An explicit `--model`, `--critic` or `--reviewer` naming a denied slot still wins — with a warning in the assignment line, because you asked. |
| `implementer = slot` | Default implementer when `--model` is absent. Without it, the rubric decides. |
| `critic = slot` | Preferred plan critic, used whenever the cross-family rule allows it. The explicit-only slots `carbon` and `neon` (2.2) critique only when named here or by `--critic`, and such a critic is not reused as the reviewer (`reviewer` names it for that). |
| `reviewer = slot` | Preferred cross-family reviewer for `--review=full` and `--review=cross`. A `carbon` or `neon` named here is the reviewer only — it does not count as an eligible family for the critic choice. |
| `cascade_drafter = slot` | Default drafter for `--cascade` (default `luna`). |
| `critique_rounds = n` | Plan-critique cap, 1–8 (default 2). `--rounds` beats it. |
| `[effort]` `critique`, `high_stakes_critique`, `build`, `review`, `draft` | Per-stage effort (defaults `medium`, `high`, `medium`, `high`, `medium`), one vocabulary `low\|medium\|high\|xhigh\|max`. Each stage takes one value, or a table of per-family values (`review = { openai = "xhigh", google = "high" }`) when the families need different levels. A value above a model's range is clamped to the highest effort its slugs list (agy: Hydrogen and Neon `xhigh`, Argon, Carbon, Flash and Claude-on-agy `high`) and marked `(clamped)`. maestro passes no effort on native Agent calls (the tool's own `effort` parameter is not used, `docs/workers.md`); `claude -p`, `maestro-sdk` and agy slugs take it. |
| `[families]` `claude\|openai\|google = "on"\|"off"` | Switch a family off even if its CLIs are installed and signed in, or `"on"` to lift a lower-level `"off"` (`true`/`false` are read the same). Claude can be switched off for workers too; the director itself is always Claude Code, and `self` stays available. |
| `[transports]` `deny = ["<slot>@<transport>", …]` | Transports the director never picks on its own, e.g. `opus@agy`, `sonnet@api`. A denied transport is skipped in the slot's order and never switched onto; an explicit `@transport` naming it still wins, with a warning. |
| `[pin]` `<slot> = "<version>" \| { <transport> = "<slug>" }` | Fix a line instead of following the newest model (`docs/catalog.md`, "Pins"): `sol = "6.1"` (every transport must serve 6.1), `sol = { codex = "gpt-6.1-sol" }` (that slug, other transports off), `opus = { native = "claude-opus-5" }`. The version is a quoted string (unquoted, 6.10 would be the number 6.1). A pin missing from the catalog halts. |
| `[api]` `fallback = true\|false`, `max_usd_per_run = <n>` | The `api` transport (Claude through the Agent SDK on an API key, `docs/workers.md`). `fallback = true` makes it the last transport a Claude slot switches to on quota (default `false`: only `--sdk` uses it). `max_usd_per_run` caps the USD a run spends on it (default `20`), summed from the ledger's `cost_usd`; spent → quota on `api`. Usually a user-policy key: it is your credit. |

The example with comments: [`examples/maestro.policy.toml`](examples/maestro.policy.toml).

## How it is applied

Stage 0 runs `maestro-policy resolve` (both files, if present), reports which were found and the
effective values, and then the picker runs with them. Every value that came from a policy is
marked `(policy)` in the
assignment line, so a run always shows where a choice came from:

```
Assign: implementer=sol (policy: repo default) · critic=fable (cross-family; policy critic gemini
unavailable: families.google off) · …
```

The cross-family rule is not a policy key and cannot be switched off. If a policy makes it
unsatisfiable (for example `critic = "sol"` with `implementer = "sol"`), the director ignores the critic
preference, says so, and applies the rule.

Precedence is resolved **before** anything is validated: only the winning value of a key is
checked, so a repo `implementer` hides a mistyped one in the user file. (A malformed file and a
name 2.0.0 removed stop wherever they stand.) An explicit `--model` overrides a denied
slot or a policy-disabled family *for the implementer*, with a warning in the assignment line — it
never overrides real unavailability (the CLI is missing or signed out) and never the cross-family
rule. An ineligible `critic` or `reviewer` preference — its family switched off or unavailable, or
the cross-family rule against it — is dropped with a sentence saying why, and an eligible
alternative is chosen. A slot whose model probe fails is different: the run halts with a question
(SKILL.md, stage 0 step 5).

## What halts

Like an illegal flag, an illegal policy stops the loop with a question instead of guessing. Each
is an entry in `maestro-policy resolve`'s `stops`, except those that need more than the files — a
pin against the catalog and an OpenAI or Google model's own effort list (`maestro-catalog`), an
unavailable family (`maestro-preflight`), the cascade family rule (`maestro-roles`) and the
*default* drafter being denied or switched off, which matters only under `--cascade` (the
director checks it then):

- a slot name that is not in the roster (`gemini-pro`, `gpt-5`), or a transport a slot does not have
  (`haiku@agy`, `fable@agy`, `argon@codex`, `neon@codex`) — the slots and their transports are `bin/slots.json`;
- a `pin` whose version or slug is not in that transport's catalog;
- a `cascade_drafter` other than `luna`, `haiku` or `gemini`;
- a `critique_rounds` outside 1–8;
- a file that is not valid TOML (the parser's message is quoted), or a value of the wrong type;
- a `maestro.policy.yml` or `~/.config/maestro/policy.yml` left from before the format changed:
  "convert to TOML", with both paths — it is not read;
- an effort that is not a level at all (`hgih`), or a per-family value outside that family's range
  — a Google model the efforts its agy slugs list (Hydrogen and Neon `low…xhigh`, Argon, Carbon
  and Flash `low…high`), an OpenAI model its own catalog list (up to `ultra` for Astra/Sol/Terra, `max` for
  Luna), native Claude `low…max`; a single shared value is clamped instead (see `effort` above).
  `maestro-policy` knows the family ranges (`google` up to `xhigh`, `claude` up to `max`, `openai`
  up to `ultra`); `ultra` as a single shared value halts, because only OpenAI has it;
- an effective, non-overridden `implementer` or `cascade_drafter` that is denied or belongs to a
  family switched off;
- an unavailable family that a flag requires;
- a `--cascade` whose family rule cannot be met (SKILL.md, "The cross-family rule");
- a key, family, slot or transport that 2.0.0 removed (below).

Removed in 2.0.0: the slot `grok`, the family key `xai` (in `families` and in per-family `effort`), the key `cursor_fast` and every `<slot>@cursor` pair — a 1.x policy that still names one halts until the entry is deleted.

## Format

TOML, read by `maestro-policy` with Python's `tomllib` (python3 ≥ 3.11). Strings are quoted
(`implementer = "sol"`, `google = "off"`), and the plain keys come before the first `[table]`.
Keep it to the keys above; other unknown keys are reported in `warnings` and ignored (the removed
ones above halt, because ignoring them would silently change a roster the file meant to shape).
Check a file by running `maestro-policy resolve` in the repository.
