# Models and roles

## Families and slots

A **family** is the company behind a model: Claude (Anthropic), OpenAI (GPT), Google (Gemini).
A **slot** is a short name for a model *line* within a family — `opus`, `sol`, `gemini`. It is not a fixed version: `sol` means "the newest GPT Sol your account can
use", found afresh at the start of each run and then kept for the whole run.

| Family | Slots | Character |
| --- | --- | --- |
| Claude | `opus`, `fable`, `sonnet`, `haiku` | `fable` (Fable 5.2 today) the strongest and most expensive, `opus` the all-rounder, `sonnet` for mechanical builds, `haiku` for bulk edits |
| OpenAI | `astra`, `sol`, `luna`, `terra` | `astra` the strongest, `sol` the workhorse, `luna` fast and cheap, `terra` an older line used only when named |
| Google | `argon`, `carbon`, `neon`, `gemini` | `argon` the Google critic and reviewer; `carbon` and `neon` (Gemini 4 Carbon and Neon, in agy's catalog since November 2026) only when you name them; `gemini` fast and cheap — Gemini 4 Hydrogen today (announced by Google on 2026-11-12 as the upgrade from Gemini 3.8 Flash), Gemini Flash before it |

There is also `self`: the director itself (a Claude model in Claude Code), for a change smaller
than the handoff.

## The roles

- **Director** — the model you are talking to. Interviews, plans, assigns, reads every diff, runs
  the tests, commits. Never a critic of its own plan.
- **Builder** (also *implementer*) — writes the code. Chosen by a written rubric unless you name
  one with `--model`.
- **Critic** — reads the plan and answers approve, revise or reject with graded findings. Always
  from a family other than the builder's. On a risky change a **second critic** from a third
  family joins.
- **Reviewer** — with `--review`, reads the finished diff against the plan. Cross-family to the
  builder as well.
- **Drafter** and **gate** — only with `--cascade`: a cheap model drafts, a gate (a mechanical
  check plus a critic from another family) accepts or escalates.
- **Advisor** — only with `--advisor`: a read-only model the builder may ask for short guidance at
  a checkpoint. Chosen from another family unless you name one; never a gate, never a critic.

## Who checks whom: the cross-family rule

Models of one family share blind spots, so **no critic and no reviewer may share the family of
the builder whose code gets committed.** The director applies a fixed order and names it:

- Claude builds → `sol` critiques; on a risky change `astra`, with `argon` (else `gemini`) as the
  second critic.
- OpenAI builds → `opus` critiques (`fable` on a risky change when the budget allows), with `argon`
  as the second critic on a risky change.
- Google builds → `sol` critiques; on a risky change `astra`, with `opus` (or `fable`) second.
- `astra` never critiques an OpenAI build, except when OpenAI is the only family present.

You can override any role (`--critic=…`, `--reviewer=…`), but not the rule: a named critic from
the builder's family stops the run with a question instead of running.

## How the newest model is picked

At the start of a run the director reads the model lists the CLIs publish — Codex's catalog,
`agy models` — without spending a model call. For each slot it
takes the newest version that matches the line's naming pattern (previews, dated builds and
`-mini` variants are excluded, so a preview never becomes a worker unannounced). Native Claude has
no list; its aliases (`opus`, `sonnet`, …) follow the newest model, and the director learns the
exact id from the probe.

Then it **probes** the chosen model with one cheap call ("Reply with exactly: OK"). If the account
is refused that model, the director steps down to the next older version and says so in the
assignment line (`gpt-6.2-sol listed, denied for this account`). A quota or network error is not a
denial and does not step down. A passed probe is remembered for seven days, a denial for one day,
and only for this repository and this CLI version. The resolved ids are frozen in the checkpoint:
a fix round never silently moves to a model that appeared mid-run.

A policy file can **pin** a version (`pin.sol = "6.1"`) or an exact slug when you need to stay
put.

## Transports: more than one road to a model

A **transport** is the CLI that serves a model. The family comes from the model, not from the
CLI: Opus through agy is still Claude. Claude slots have several roads, tried in order — natively
(a subagent in an interactive Claude Code, `claude -p` in a headless one), then agy (Opus and
Sonnet only), then the Agent SDK on an API key (`api`, only with `--sdk` or a policy that allows
it). Fable and Haiku have no agy road, so when their native limit runs out they continue only on
`api` — without it the run stops or swaps the worker. The other families have one road each: GPT
through `codex exec`, Gemini through agy.

The road changes what a worker can do. A worker through agy, `claude -p` or `api` is
**edits-only**: it can change files but not run commands, so the director runs the tests. A Codex
worker runs in Codex's sandbox with the repository writable and the network off, and runs the
tests itself when a quick reach check passed.

When a road hits its usage limit mid-run, the director moves the same model to the next road,
rewrites the brief for that road's abilities, and records the switch in the ledger. `opus@agy`
forces one road and never switches.

## Provisional models

`argon` is marked **provisional** in every assignment line: it has critiqued plans well, but the
ledger has not measured it as a builder yet. It is also never a cascade drafter.

`carbon` and `neon` are provisional too, and **explicit-only**: the director never picks them on
its own — not as builder, critic, reviewer or arbiter — and an unnamed one does not count as an
extra family. Name one (`--critic=neon`, `--reviewer=carbon`, `--model=neon`, or the policy's
`critic`/`reviewer`) and it serves that role — builder, critic or cross reviewer; it is never a
cascade drafter, and a critic named for critique is not reused as the reviewer. Published benchmarks put them near the top, but from
one or two sources; the rubric changes only when maestro's own ledger shows it.

## When fewer families are available

The director uses only the families whose CLIs are installed, signed in and healthy — checked
without model calls — minus whatever a policy switches off. With **two** families there is no
second critic on a risky change, and the report says so. With **one** family the critic and
reviewer are a different model line of that family than the builder (Fable checks an Opus build,
Opus checks a Fable build; Astra checks a Sol build), and the run is marked `degraded:
same-family critique`.

## Technical details

- [SKILL.md](../../SKILL.md), "Roster", "The cross-family rule", "Stage 0" — the rubric, the
  critic orders, the probe steps.
- [catalog.md](../catalog.md) — catalog sources, version comparison, probes, pins, freezing.
- [workers.md](../workers.md) — what each CLI can do, measured.
- [policy.md](../policy.md) — denying slots and roads, pinning, switching families off.
