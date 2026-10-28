# Models and roles

## Families and slots

A **family** is the company behind a model: Claude (Anthropic), OpenAI (GPT), Google (Gemini),
xAI (Grok). A **slot** is a short name for a model *line* within a family — `opus`, `sol`,
`gemini`, `grok`. It is not a fixed version: `sol` means "the newest GPT Sol your account can
use", found afresh at the start of each run and then kept for the whole run.

| Family | Slots | Character |
| --- | --- | --- |
| Claude | `opus`, `fable`, `sonnet`, `haiku` | `fable` the strongest and most expensive, `opus` the all-rounder, `sonnet` for mechanical builds, `haiku` for bulk edits |
| OpenAI | `astra`, `sol`, `luna`, `terra` | `astra` the strongest, `sol` the workhorse, `luna` fast and cheap, `terra` an older line used only when named |
| Google | `argon`, `gemini` | `argon` the strongest, a critic and reviewer; `gemini` (Flash) fast and cheap |
| xAI | `grok` | provisional (below) |

There is also `self`: the director itself, for a change smaller than the handoff — only when the
director knows its own model, which Claude Code and Codex reveal and Cursor and agy do not.

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

## Who checks whom: the cross-family rule

Models of one family share blind spots, so **no critic and no reviewer may share the family of
the builder whose code gets committed.** The director applies a fixed order and names it:

- Claude builds → `sol` critiques; on a risky change `astra`, with `argon` or `grok` as the second
  critic.
- OpenAI builds → `opus` critiques (`fable` on a risky change when the budget allows).
- Google or xAI builds → `sol` or `opus`.
- `astra` never critiques an OpenAI build, except when OpenAI is the only family present.

You can override any role (`--critic=…`, `--reviewer=…`), but not the rule: a named critic from
the builder's family stops the run with a question instead of running.

## How the newest model is picked

At the start of a run the director reads the model lists the CLIs publish — Codex's catalog,
`agy models`, Cursor's `agent --list-models` — without spending a model call. For each slot it
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

A policy file can **pin** a version (`pin: {sol: "6.1"}`) or an exact slug when you need to stay
put.

## Transports: more than one road to a model

A **transport** is the CLI that serves a model. The family comes from the model, not from the
CLI: Opus through agy is still Claude. Claude slots have several roads, tried in order — natively
(a subagent in Claude Code, `claude -p` elsewhere), then agy, then Cursor, then the Agent SDK on
an API key (`api`, only with `--sdk` or a policy that allows it). The other families have one road
each: GPT through `codex exec`, Gemini through agy (Argon also through Cursor), Grok through
Cursor.

The road changes what a worker can do. A worker through agy, `claude -p` or `api` is
**edits-only**: it can change files but not run commands, so the director runs the tests. A Cursor
worker runs commands only inside Cursor's sandbox (no network, no home directory) and runs the
tests only when a quick reach check passed. A Codex worker runs in Codex's sandbox with the
repository writable and the network off.

When a road hits its usage limit mid-run, the director moves the same model to the next road,
rewrites the brief for that road's abilities, and records the switch in the ledger. `opus@agy`
forces one road and never switches.

## Provisional models

`grok` and `argon` are marked **provisional** in every assignment line. Grok has found real bugs
as a critic; neither has been measured as a builder by the ledger yet. Grok is also never a
cascade drafter.

## When fewer families are available

The director uses only the families whose CLIs are installed, signed in and healthy — checked
without model calls — minus whatever a policy switches off. With **two** families there is no
second critic on a risky change, and the report says so. With **one** family the critic and
reviewer are a different model line of that family than the builder (Fable checks an Opus build,
Opus checks a Fable build; Astra checks a Sol build), and the run is marked `degraded:
same-family critique`. xAI alone has one line, so it cannot run alone.

## Technical details

- [SKILL.md](../../SKILL.md), "Roster", "The cross-family rule", "Stage 0" — the rubric, the
  critic orders, the probe steps.
- [catalog.md](../catalog.md) — catalog sources, version comparison, probes, pins, freezing.
- [workers.md](../workers.md) — what each CLI can do, measured.
- [policy.md](../policy.md) — denying slots and roads, pinning, switching families off.
