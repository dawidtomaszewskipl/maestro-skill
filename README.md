# route2

A multi-model build loop for coding agents. The model you are talking to becomes the **director**:
it interviews you, writes a plan, has the plan critiqued by models from **other families**, hands
the build to the worker that fits the task, gates and tests the result, commits, and reports who
did what and what it cost.

route2 is a separate fork of route 3.4.0 (the `route-skill` repository). What it adds:

- **Four hosts.** It runs as the director inside **Claude Code**, **Codex**, **Cursor's `agent`**
  and **agy** (Antigravity CLI), detects which one it is in, and adapts how it launches workers,
  waits for them and asks you questions.
- **Four model families, more transports.** Claude, OpenAI, Google and now **xAI** (Grok, through
  Cursor). Claude models are reachable four ways — Claude Code subagents, `claude -p`, agy and
  Cursor — and route2 falls through them in that order when one runs out of quota.
- **A live catalog.** A slot is a model *line* (`sol` = the newest `gpt-*-sol`), resolved at the
  start of every run from the CLIs' own catalogs and probed — no skill edit when a new Opus or Sol
  ships.
- **Shell helpers** (`bin/`, bash + jq) for what a markdown skill cannot do reliably on its own:
  host detection, a fenced lock, detached jobs that survive the director's session, verdict
  validation, a read-only fingerprint, deterministic role resolution.

No SDKs: both the Codex SDK and the Claude Agent SDK only wrap the CLIs route2 already drives.

## Workers

| Family | Slots | Reached through |
| --- | --- | --- |
| Claude | `opus`, `fable`, `sonnet`, `haiku` | Claude Code `Agent` tool or `claude -p` → agy → Cursor |
| OpenAI | `astra`, `sol`, `luna`, `terra` (explicit only) | `codex exec` |
| Google | `gemini` (Flash) | `agy` |
| xAI | `grok` (provisional — not yet measured as a builder) | Cursor `agent -p` |

Same-family models share blind spots, so **no plan critic and no reviewer comes from the family of
the builder whose code is committed** (with defined fallbacks when fewer families are available).

## Install

```bash
git clone <this repository> && cd route2-skill
./install.sh                   # ~/.agents/skills/route2 (Codex, Cursor) + links for Claude Code and agy
./install.sh ~/code/my-app     # into one project instead
./install.sh --check           # where it is installed
./install.sh --check=live      # ask each host to list its skills (cheap headless calls)
```

Requirements: Linux, bash ≥ 5, jq ≥ 1.6, git, util-linux (`setsid`, `flock`), and whichever of
`claude`, `codex`, `agent`, `agy` you want to use, signed in. The older `/route` skill is never
touched; **do not run `/route` and `/route2` in the same checkout at once** (route cannot see
route2's lock).

## Use

| Host | Invoke | Configuration the director needs |
| --- | --- | --- |
| Claude Code | `/route2 <task>` | none |
| Codex | `$route2 <task>` | start Codex with `--sandbox danger-full-access` (the director's own commands must reach the model APIs and run your tests) |
| Cursor (`agent`) | `/route2 <task>` | a project `.cursor/cli.json` allowing route2's scripts, `git`, `jq` and your test command — never `--force` (see `docs/hosts.md`) |
| agy | `/route2 <task>` | an interactive session (print mode cannot run commands); approve the commands or add `permissions.allow` rules |

Headless (`claude -p`, `codex exec`, `agent -p`) works only with `--unattended`.

```text
/route2 add a CSV export of the invoices list
/route2 --model=grok --critic=sol,opus --review=cross split the report builder into jobs
/route2 --model=opus@agy fix the pagination bug          # force a transport
/route2 --setup <task>                                    # configure the run by questions
/route2 --plan-only <task>                                # plan + critique, no build
/route2 --resume                                          # continue after a quota wall or a closed laptop
```

Flags: `--model=<slot>[@transport]`, `--critic=…`, `--reviewer=…`, `--review[=full|self|cross]`,
`--rounds=n`, `--tests=covering|full[,browser]`, `--skip-tests`, `--cascade[=luna|haiku|gemini]`,
`--setup`, `--plan-only`, `--resume`, `--unattended`, `--host=…`. Plain words work too ("krytykuj
grokiem", "opus przez agy").

## Policy

`route2.policy.yml` in a repository, `~/.config/route2/policy.yml` for you: deny slots or
transports (`fable@cursor`), pin a line (`sol: "6.1"`), switch a family off, set efforts per stage
and family. See [docs/policy.md](docs/policy.md) and the
[example](docs/examples/route2.policy.yml).

## How it was checked

`tests/run.sh` runs the helpers against fixtures and real processes (no model calls): catalog
parsing and ordering, host detection on fake `/proc` trees, the job lifecycle (exit, linger,
orphan, kill without touching tests), verdict validation, fingerprints, role resolution, the lock
and its generation fence, the audit. Live gates on 2026-10-11 measured each host's markers, job
survival across commands and sessions, Cursor's sandbox, `claude -p`'s tool and plugin isolation,
and an end-to-end canary per host; the results are written next to the rules they justify, in
[docs/hosts.md](docs/hosts.md) and [docs/workers.md](docs/workers.md).

## Docs

[hosts](docs/hosts.md) · [catalog](docs/catalog.md) · [commands](docs/commands.md) ·
[workers](docs/workers.md) · [policy](docs/policy.md) · [setup](docs/setup.md) ·
[cascade](docs/cascade.md) · [checkpoint](docs/checkpoint.md) · [ledger](docs/ledger.md) ·
[unattended](docs/unattended.md) · [sandbox and pre-flight](docs/sandbox-and-preflight.md) ·
[troubleshooting](docs/troubleshooting.md)

Polish: [README_pl.md](README_pl.md).
