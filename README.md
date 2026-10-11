# maestro

**maestro** turns the agent you are talking to into the conductor of a team of models. It does
not have to write the code itself: it interviews you briefly, writes a plan, has the plan critiqued
by models from **other families**, hands the build to the model that fits the task best, checks
the result, runs the tests, commits, and reports who did what and what it cost.

It runs in four agents: **Claude Code**, **Codex**, **Cursor** (the `agent` CLI) and **agy**
(Antigravity). It uses models from four families: Claude, OpenAI (GPT), Google (Gemini) and xAI
(Grok).

maestro grew out of route 3.4 and is a separate skill. `/route` keeps working unchanged; both can
be installed at once.

## How a run goes

```text
/maestro add a CSV export of the invoices list
```

1. **Interview.** The conductor asks about whatever the code cannot tell it.
2. **Assignment.** It picks the builder and the critics and shows them on one line, e.g.
   `implementer=opus=claude-opus-5-5 (native) · critic=sol=gpt-6.1-sol (codex) · row 3`.
   One word changes it ("let sol build").
3. **Plan and critique.** Models from a family other than the builder's read the plan, because
   models of one family share blind spots. Revisions continue until approval or the round cap.
4. **Build.** The builder follows the plan.
5. **Checks.** The conductor reads the diff and runs the tests. On request, a model from another
   family reviews the result.
6. **Fixes** (at most 3 rounds), **commit** and **report**: who, with which model, how many tokens.

An interruption (a quota wall, a closed laptop) is not lost: `/maestro --resume` continues where
the run stopped.

## What is new compared to route

The flow, the flags and the rubric that picks the builder are the same as in route 3.4. What
changes is **where** you run it, **who** is on the team, and **what happens when something runs
out or gets interrupted**.

| | route 3.4 | maestro |
| --- | --- | --- |
| Where it runs | Claude Code only | Claude Code, Codex, Cursor, agy; detects which one it is in |
| Model families | Claude, OpenAI, Google | + **xAI (Grok)** through Cursor |
| A new model (a new Opus or Sol) | edit the skill | **found automatically** in the CLIs' model lists and checked for access |
| Claude quota runs out in Claude Code | the run stops | the same Claude model through **agy**, then **Cursor** |
| Two runs in one repository | could collide | the second is refused (repository lock) |
| The session closes mid-build | the build is tied to the Claude Code session | the build keeps running and `--resume` takes it over (outside an interactive Claude Code) |
| Assignment line | slot name (`critic=astra`) | exact model and route (`astra=gpt-6-astra (codex)`) |
| State directory and policy | `.route/`, `route.policy.yml` | `.maestro/`, `maestro.policy.yml` |

### What it means day to day

- **You start it wherever you are working.** The conductor is that agent's model. In Codex, Sol
  conducts, so maestro picks the critics from Claude, Gemini or Grok. The rule "no critic from the
  builder's family" adapts by itself.
- **More independent eyes.** For high-stakes changes (permissions, money, concurrency, data
  integrity, migrations that change data) a second critic comes from a third family. With Grok,
  three families are available more often.
- **Grok is marked provisional for now.** As a critic it found real bugs; as a builder it has not
  been measured yet.
- **Some builders only edit files and the conductor runs the tests.** This applies to Claude
  through agy and `claude -p`, and to Gemini. Cursor runs tests only when its sandbox passed the
  reach check. For you: a few more conductor steps and fewer surprises.
- **Tests are never killed.** Stopping a job never kills a test. If maestro cannot tell which
  process is a test, it stops (`blocked`) instead of guessing.

## Hosts compared

| | Claude Code | Codex | Cursor (`agent`) | agy |
| --- | --- | --- | --- | --- |
| Invoke | `/maestro` | `$maestro` | `/maestro` | `/maestro` |
| Setup needed | none | start Codex with `--sandbox danger-full-access` (the conductor must reach the model APIs and run the tests) | a project `.cursor/cli.json` allowlist ([template](docs/hosts.md#adapters)); **never `--force`**, it turns the sandbox off | interactive session only; approve commands and file writes, or add `permissions.allow` rules |
| Can the conductor build itself (`self`) | yes | yes | **no**: Cursor does not reveal the conductor's model, so another model always builds | **no**, for the same reason |
| How it starts Claude models | Claude Code subagents | `claude -p` | `claude -p` | `claude -p` |
| How it waits for long jobs | Claude Code's notification, as in route | maestro's own jobs, checked every 25 s | as Codex | as Codex, every 8 s |
| How it asks you | a question dialog | a dialog when Codex offers one, otherwise a plain question | a plain question, then it waits | agy's question dialog |
| The build survives the session closing | as in route | yes (measured over 10 min) | yes | yes |
| Unattended (`--unattended`) | `claude -p "/maestro --unattended …"` | `codex exec` | `agent -p` | **no** (in `-p` mode agy refuses every command) |
| Screenshots for UI changes | yes | yes | yes (needs `Shell(npx)`) | yes |
| Checked end to end | yes | yes, including a parallel split | yes | yes |

**Which host?** An interactive Claude Code is the most comfortable: proper question dialogs,
completion notifications, and the conductor can make a small change itself. Codex is handy when
the Claude quota is gone. Cursor and agy work, but need permission setup and do not let the
conductor build.

## Models

| Family | Slots | Route to the model, in order |
| --- | --- | --- |
| Claude | `opus`, `fable`, `sonnet`, `haiku` | native (subagent or `claude -p`) → agy → Cursor (`haiku` native only, `fable` not through agy) |
| OpenAI | `astra` (strongest), `sol` (workhorse), `luna` (fast, cheap), `terra` (explicit only) | `codex exec` |
| Google | `gemini` (Flash) | agy |
| xAI | `grok` (provisional) | Cursor `agent -p` |

A slot is a **model line**, not a fixed model: `sol` is the newest `gpt-*-sol` your account has.
At the start of a run maestro reads the CLIs' model lists, picks the newest and checks it with one
cheap call; the result is remembered for 7 days. The chosen model stays fixed for the whole run.

Want a specific version or route? `--model=opus@agy` forces the route; `pin` in the policy pins
a version.

## Cost and time

- **The first run on a host** spends a few cheap calls checking the models; later runs skip them
  for 7 days.
- **More critics** means more tokens in the planning phase, but Gemini and Grok use pools other
  than Claude's and OpenAI's. Building maestro itself took about 0.4 M input tokens on each.
- **Outside Claude Code** the conductor polls its jobs in a loop: a few extra tool calls, no model
  cost.
- Every model call goes into `.maestro/ledger.jsonl` (the model requested and the one that
  actually answered, tokens, time), and the report sums it up.

## Install

```bash
cd maestro-skill
./install.sh                    # for you: Claude Code, Codex, Cursor and agy
./install.sh ~/code/my-project  # for one project only
./install.sh --check            # where it is installed
./install.sh --check=live       # each host confirms it sees the skill (a few cheap calls)
```

Requirements: Linux, bash ≥ 5, jq ≥ 1.6, git, util-linux (`setsid`, `flock`), and whichever of
`claude`, `codex`, `agent`, `agy` you want to use, signed in. The installer never touches
`/route`. **Do not run `/route` and `/maestro` in the same repository at once**: route cannot see
maestro's lock.

## Examples

```text
/maestro add a CSV export of the invoices list
/maestro --setup <task>                     # configure the run by questions
/maestro --plan-only <task>                 # plan and critique only, no build
/maestro --model=grok --critic=sol,opus <task>
/maestro --model=opus@agy fix the pagination  # Opus through agy
/maestro --review=cross <task>              # a review by another family
/maestro --resume                           # finish an interrupted run
```

Flags: `--model=<slot>[@route]`, `--critic=…`, `--reviewer=…`, `--review[=full|self|cross]`,
`--rounds=n`, `--tests=covering|full[,browser]`, `--skip-tests`, `--cascade[=luna|haiku|gemini]`,
`--setup`, `--plan-only`, `--resume`, `--unattended`, `--host=…`. Plain words work too: "critique
with grok", "opus through agy", "no browser tests".

## Policy

Standing preferences go into `maestro.policy.yml` in a repository, or `~/.config/maestro/policy.yml`
for yourself. You can:

- deny a slot (`deny: [fable]`) or a route (`transports: {deny: [opus@cursor]}`);
- pin a version (`pin: {sol: "6.1"}`);
- switch a whole family off (`families: {google: off}`);
- set the model effort per stage.

[Annotated example](docs/examples/maestro.policy.yml).

## Known limits

- **Grok** has not been measured as a builder yet.
- **Claude through Cursor** has not been checked: this account's Cursor quota for Claude is used
  up.
- **Switching routes after a quota wall** in an interactive Claude Code goes through subagents and
  cannot be simulated; it was checked with a `claude -p` conductor.
- **A process that detaches within the first second** of a job can go unnoticed. maestro then
  reports suspicious processes and never kills anything it cannot attribute.

Cases worth checking by hand are described step by step (in Polish) in
[docs/manual-checks_pl.md](docs/manual-checks_pl.md).

## Technical documentation

The conductor reads the files in `docs/` while it works, so they are precise rather than friendly:
[hosts](docs/hosts.md) · [model catalog](docs/catalog.md) · [commands](docs/commands.md) ·
[workers](docs/workers.md) · [policy](docs/policy.md) · [setup](docs/setup.md) ·
[cascade](docs/cascade.md) · [checkpoint](docs/checkpoint.md) · [ledger](docs/ledger.md) ·
[unattended](docs/unattended.md) · [sandbox](docs/sandbox-and-preflight.md) ·
[troubleshooting](docs/troubleshooting.md) · [release 1.0.0 measurements](docs/release-1.0.0.md)

Polski: [README_pl.md](README_pl.md).
