# maestro documentation — the map

Two kinds of pages live here. **The guide** (`docs/guide/`) explains maestro in plain language for
someone who has used an AI coding assistant but does not know maestro's terms. **The technical
pages** (`docs/*.md`) are what the director itself reads while it works: exact rules, command
lines, file formats and measurements. Each technical page opens with one or two plain sentences
saying what it is for, and each guide page ends with links to the technical pages behind it.

Start with the [README](../README.md) (what maestro does, what it costs, how to start), then the
guide, then the technical pages when you need the exact rule.

## The guide — for everyone

| Page | What it answers |
| --- | --- |
| [how-it-works.md](guide/how-it-works.md) | What happens during a run, step by step; what you are asked; what "approved" means; what happens when something fails |
| [models-and-roles.md](guide/models-and-roles.md) | Which models maestro can use, who checks whom and why, how the newest model is found, what "provisional" and "degraded" mean |
| [costs-and-limits.md](guide/costs-and-limits.md) | Which subscription pays for what, the API credit, the cost table in the report, what happens at a usage limit, the hard stops |
| [setup-and-hosts.md](guide/setup-and-hosts.md) | Installing, signing in, running from Claude Code, Codex, Cursor or agy, the policy file, the safety defaults |
| [glossary.md](guide/glossary.md) | Every maestro term in a sentence or two, plus a short FAQ |

## The technical pages — for the director, and for you when you need the exact rule

| Page | What it holds | Read it when |
| --- | --- | --- |
| [../SKILL.md](../SKILL.md) | The skill itself: every rule the director follows | you want the binding wording of a rule |
| [hosts.md](hosts.md) | Host detection, launching and waiting for jobs, asking the user, the repository lock, transport switch, end-to-end canaries | something behaves differently in one host |
| [commands.md](commands.md) | The exact command lines per CLI and role, reading results, validating verdicts, the effective-config check | you want to see what a worker is launched with |
| [workers.md](workers.md) | Measured facts about each CLI: flags, sandboxes, permissions, quirks, model notes | a worker did something unexpected |
| [catalog.md](catalog.md) | The live model catalog: sources, version rules, probes, pins, freezing | a slot resolved to a model you did not expect |
| [policy.md](policy.md) | Every policy key and how it is applied | you are writing a policy file |
| [setup.md](setup.md) | The `--setup` questionnaire | you want to know what `--setup` will ask |
| [cascade.md](cascade.md) | The `--cascade` protocol: drafter, gates, escalation | you use the cascade |
| [checkpoint.md](checkpoint.md) | The checkpoint file, decisions, the resume procedure, the audit | a resume did something you did not expect |
| [ledger.md](ledger.md) | The cost ledger's fields and sources | you are reading `.maestro/ledger.jsonl` |
| [unattended.md](unattended.md) | The `--unattended` rules: stop matrix, ask-point inventory, scenarios | you run maestro headless |
| [sandbox-and-preflight.md](sandbox-and-preflight.md) | What each sandbox denies, the reach probe, the escalation ladder | a worker could not run the tests |
| [troubleshooting.md](troubleshooting.md) | Real incidents with their diagnoses | something hangs, fails or looks wrong |
| [manual-checks_pl.md](manual-checks_pl.md) | Checks that need a human (Polish) | you want to verify maestro by hand |
| [examples/maestro.policy.yml](examples/maestro.policy.yml) | An annotated policy file | you want a template |
| `schemas/` | The JSON schemas critics, gates and reviewers must answer with | you are debugging a verdict |
