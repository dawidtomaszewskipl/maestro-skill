# maestro

**maestro** is an add-on for AI coding assistants. You type one command, and the assistant you
are already talking to stops being a lone coder and becomes the **director** of a small team of AI
models from different companies: it asks you what it needs to know, writes a plan, has the plan
checked by models from other companies, hands the coding to the model that fits the task best,
checks the result, runs your tests, commits, and tells you who did what and what it cost.

It runs inside four assistants (**hosts**): **Claude Code**, **Codex**, **Cursor** (its `agent`
command line) and **agy** (Antigravity). It can use models from four **families**: Claude
(Anthropic), GPT (OpenAI), Gemini (Google) and Grok (xAI).

Polski: [README_pl.md](README_pl.md). The guide for readers who want the whole picture:
[docs/guide/](docs/README.md).

## Why a team, and why from different companies

Every model has blind spots, and models from one company tend to share them. A plan written by
Claude and checked only by another Claude misses the same things twice. So maestro has one hard
rule: **whoever checks the work never comes from the same family as whoever wrote it.** Claude
writes the code, GPT checks the plan; GPT writes, Claude or Gemini checks. For risky changes
(permissions, money, concurrency, data migrations) a second critic from a third family joins.

The director does not have to write the code itself. It picks the builder by a short written
rubric — a hard correctness problem goes to the strongest model, a routine feature to the
all-rounder, a mechanical scaffold to the cheap fast one — and says which rule it applied. One
word from you changes the choice.

## What a run looks like

```text
/maestro add a CSV export of the invoices list
```

1. **Interview.** The director asks about whatever the code cannot tell it. One question at a
   time, until there are no gaps.
2. **Assignment.** It picks the builder and the critics and shows them on one line, with the
   reason for each pick and the exact model behind each name. "Let sol build" changes it.
3. **Plan and critique.** It writes a plan. Critics from other families read the plan — never the
   code yet — and answer approve or revise. The plan goes back and forth until every critic
   approves, up to a cap (two rounds unless you say otherwise). Not approved at the cap? The run
   stops and hands you the disagreement.
4. **Build.** The chosen model writes the code, inside the boundaries the plan set.
5. **Checks.** The director reads the whole diff itself and runs the tests. On request a model
   from a family other than the builder's — usually the one that critiqued the plan — reviews the
   result against the plan.
6. **Fixes, commit, report.** Findings and red tests go back to the builder (at most three
   rounds). Then the director commits and reports: who did what, with which model, how many
   tokens, and what was skipped.

Interrupted — a usage limit hit, a laptop closed, a session ended? Nothing is lost:
`/maestro --resume` continues from where it stopped — even from a different host, after telling you
what changes and asking.

## Quick start

You need Linux, bash ≥ 5, jq ≥ 1.6, git and util-linux (`setsid`, `flock`), plus whichever of the
four assistants you want to use, installed and signed in (`claude`, `codex`, `agent`, `agy`).
maestro uses your existing subscriptions; it adds no account of its own.

```bash
git clone <this repository> maestro-skill && cd maestro-skill
./install.sh                    # installs the skill for Claude Code, Codex, Cursor and agy
./install.sh --check            # shows where it is installed
```

Then, in a project with a clean git tree, inside the assistant of your choice:

```text
/maestro add a CSV export of the invoices list      # Claude Code, Cursor, agy
$maestro add a CSV export of the invoices list      # Codex
```

The first run in a repository spends a few cheap calls checking which models your accounts can
reach; later runs in that repository reuse the answer for up to seven days, as long as the CLI
version and account are the same. Two hosts need a one-time setting: start Codex with
`--sandbox danger-full-access` (the director must reach the model APIs and run tests), and give
Cursor a project allowlist of commands. Details: [setup and hosts](docs/guide/setup-and-hosts.md).

## The commands you will actually use

| Command | What it does |
| --- | --- |
| `/maestro <task>` | the full run above |
| `/maestro --setup <task>` | configure the run by a few questions instead of flags; ends with a reusable flag line |
| `/maestro --plan-only <task>` | interview, plan and critique only — no code, no commit |
| `/maestro --model=sol <task>` | choose the builder (a slot name from the table below; `opus@agy` also forces the road to it) |
| `/maestro --critic=astra,gemini <task>` | choose the critics |
| `/maestro --review=cross <task>` | add a review of the finished code by a model from a family other than the builder's, by default the plan critic (`full` adds the director's own read; `self` is the director's read only, no reviewer) |
| `/maestro --unattended <task>` | nobody is there to answer: small gaps become recorded assumptions, real decisions stop the run cleanly |
| `/maestro --sdk <task>` | run the Claude workers on the Max plan's API credit instead of the subscription (see [API credit](#api-credit)) |
| `/maestro --resume` | continue an interrupted run |

Plain words work too: "critique with grok", "opus through agy", "no browser tests". Every flag is
listed in `SKILL.md`; the cheat sheet with explanations is in the
[glossary](docs/guide/glossary.md).

## Which models it can use

A name like `sol` or `opus` is a **slot**: a model *line*, not a fixed version. At the start of a
run maestro reads the model lists of your CLIs, picks the newest model of each line your account
can use, checks it with one cheap call, and keeps that exact model for the whole run. A new Opus or
a new Sol needs no update of maestro.

| Family | Slots | Good for |
| --- | --- | --- |
| Claude | `opus` | everyday features, multi-step changes, anything with screenshots and UI |
| | `fable` | the hardest correctness problems and large redesigns — the most capable and most expensive |
| | `sonnet` | mechanical builds from a settled plan |
| | `haiku` | bulk edits with no judgment in them |
| OpenAI | `astra` | the strongest critic for risky plans; the builder when the Claude budget is the constraint |
| | `sol` | the workhorse: large self-contained chunks, and the default critic of a Claude build |
| | `luna` | fast and cheap: the drafter of a cascade (below) |
| | `terra` | an older line, used only when you name it |
| Google | `argon` | the Google critic and reviewer; builds only when you name it |
| | `gemini` | fast and cheap mechanical work, when you want to spare the Claude pool |
| xAI | `grok` | a critic that has found real bugs; as a builder still unmeasured, so it is marked *provisional* |

A slot can be reached by more than one road (**transport**): `opus` runs natively in Claude Code,
or through agy, or through Cursor, or on the API credit. If one road hits its usage limit mid-run,
maestro continues the same model on the next road and says so.

Two cheaper modes: `--cascade` lets a cheap model draft first and a gate decide whether the draft
is good enough or the stronger model must take over; `--plan-only` buys you a reviewed plan for the
price of the critique alone.

## What it costs

- Every model call draws on the subscription of the CLI that served it: GPT on ChatGPT, Gemini
  on agy, Grok on Cursor; Claude on your Claude plan when it runs natively, on agy's or Cursor's
  pool when it runs through them, and on the API credit on the `api` road. More critics mean more
  tokens at the planning stage, but spread over pools that would otherwise sit idle.
- Every call is written to a **ledger** (`.maestro/ledger.jsonl`): the model asked for, the model
  that answered, tokens and time. The report sums it per stage and per family. Token counts are
  never presented as money, except for API-credit calls, which carry a dollar estimate.
- A usage limit is routine, not a failure: a Claude slot moves to its next road; otherwise the run
  checkpoints and stops, and `--resume` continues once the limit resets.

### API credit

A Max plan includes a monthly API credit: $200 on Max 20x, $100 on Max 5x. It expires at the end
of each billing cycle. It covers the Claude API and the Claude Agent SDK, **not Claude Code**.
maestro can run its Claude workers on it once the subscription's 5-hour or weekly limit is spent:

1. claude.ai → Settings → Billing: link a Console organisation (one-way; the credit appears only
   after that). New subscriptions wait 7 days.
2. In that Console organisation create a workspace and an API key **inside it** (an
   organisation-level key is refused: "not scoped to a workspace"). Set the workspace spend limit
   as a hard stop.
3. In your own terminal: `mkdir -p ~/.config/maestro && install -m 600 /dev/stdin
   ~/.config/maestro/anthropic-api-key`, paste the key, then Ctrl-D.
4. `./install.sh --sdk` (Node ≥ 18): installs the pinned Agent SDK next to the skill.
5. `~/.agents/skills/maestro/bin/maestro-sdk --check` should say `"available": true`.

Then `/maestro --sdk <task>` runs every Claude worker through the SDK on that key. With
`api: {fallback: true}` in `~/.config/maestro/policy.yml`, maestro also switches to it on its own
when the limit runs out mid-run. `api.max_usd_per_run` (default $20) caps a run. The report shows
what the run spent.

When the limit is spent, your Claude Code session stops too. Direct from Codex, Cursor or agy and
let only the Claude workers use the credit. Claude Code started with an API key is Claude Code
usage and does not draw on the credit.

## Standing preferences

Put them in `maestro.policy.yml` in a repository (for the team) or in
`~/.config/maestro/policy.yml` (for you): never pick a slot (`deny: [fable]`), never use a road
(`transports: {deny: [opus@cursor]}`), pin a version (`pin: {sol: "6.1"}`), switch a family off
(`families: {google: off}`), set the effort per stage. Flags beat the repository file, which beats
your own. [Annotated example](docs/examples/maestro.policy.yml).

## Safety defaults

Workers never touch your settings, hooks or plugins: every external worker starts with a stripped
environment, inside its CLI's sandbox or with a fixed set of tools. Only one run per repository at a time (the second is
refused). Workers that cannot be sandboxed only edit files, and the director runs the tests.
Tests are never killed, not even when a worker hangs. Every state file of a run lives in
`.maestro/` and is written only through audited helpers. Nothing is committed before the director
has read the diff and run the tests itself.

## Known limits

- **Grok** has not been measured as a builder yet.
- **Claude through Cursor** is not verified yet (the circumstances are in
  [docs/workers.md](docs/workers.md)).
- **agy** can direct only in an interactive session, and you approve its commands and file
  writes (or add allow rules).
- **The API credit** is visible only in the Console; the dollar figure in the ledger is the SDK's
  estimate, not an invoice.

Cases worth checking by hand are described step by step (in Polish) in
[docs/manual-checks_pl.md](docs/manual-checks_pl.md).

## Tests

`bash tests/run.sh` runs the suite (no model calls; about five minutes; the lint group needs
`shellcheck`). It covers the helper scripts in `bin/`, not the documentation.

## Where to read next

- [docs/README.md](docs/README.md) — the map of all pages.
- The guide: [how it works](docs/guide/how-it-works.md) · [models and
  roles](docs/guide/models-and-roles.md) · [costs and limits](docs/guide/costs-and-limits.md) ·
  [setup and hosts](docs/guide/setup-and-hosts.md) · [glossary](docs/guide/glossary.md).
- The technical pages in `docs/` are what the director itself reads while it works, so they are
  precise rather than friendly: [hosts](docs/hosts.md) · [model catalog](docs/catalog.md) ·
  [commands](docs/commands.md) · [workers](docs/workers.md) · [policy](docs/policy.md) ·
  [setup](docs/setup.md) · [cascade](docs/cascade.md) · [checkpoint](docs/checkpoint.md) ·
  [ledger](docs/ledger.md) · [unattended](docs/unattended.md) ·
  [sandbox](docs/sandbox-and-preflight.md) · [troubleshooting](docs/troubleshooting.md).
