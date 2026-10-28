# Glossary

## Terms

**Assignment line** — the one line printed before the plan that names the builder, critics,
reviewer, their exact models and roads, the efforts, rounds, tests, sandbox level, host and
families — each with the reason for the choice. Your one-word override starts here.

**Brief** — the written instructions a worker gets: the plan, boundaries, conventions, what "done"
looks like, how to answer. Workers start cold, so the brief is all they know.

**Builder** (implementer) — the worker that writes the code.

**Cascade** (`--cascade`) — a cheap model drafts, a gate accepts the draft or escalates to the
stronger model. See [how it works](how-it-works.md#cheaper-drafts-the-cascade).

**Catalog** — the lists of models the CLIs publish, which maestro reads at the start of a run to
find the newest model of each line.

**Checkpoint** — `.maestro/CHECKPOINT.md`, the run's complete state, rewritten at every step and
read by `--resume`.

**Critic** — a model from another family that reads the plan and answers approve, revise or
reject with findings. A **second critic** from a third family joins on high-stakes changes.

**Degraded** — a run where the cross-family rule could not be met fully: one family only (critic
from another model line of the same family) or two (no second critic). Always said in the report.

**Director** — the model you are talking to, running the loop: interview, plan, assign, gate,
test, commit, report.

**Dirty-exit** — the protocol for a worker that stopped without finishing: look at `git status` and
`git diff` first, keep or reset each change deliberately, record the decision.

**Drafter** — the cheap model that writes the first draft in a cascade (`luna`, `haiku` or
`gemini`).

**Edits-only** — a worker that can change files but not run commands: anything through agy,
`claude -p` or the API, and a Cursor builder whose reach check failed. The director runs its
tests.

**Effort** — how hard a model thinks on a call: `low`, `medium`, `high`, `xhigh`, `max`. Set per
stage; clamped to what the road supports.

**Family** — the company behind a model: Claude, OpenAI, Google, xAI.

**Fence** — a secret the lock gives the director; every change to the repository or to `.maestro/`
must present it, so a superseded director cannot write anything.

**Gate** — in a cascade, the decision after the draft: a mechanical check (boundaries, tests) plus
a cross-family critic.

**High stakes** — a change that touches authentication or permissions, money, concurrency, data
integrity, or a migration that changes or drops existing data. Brings a stronger builder, a
second critic and a recommended review.

**Host** — the assistant maestro runs in: Claude Code, Codex, Cursor's `agent`, or agy.

**Job** — a worker's turn or a test run launched so that the director can wait for it without
ending its own turn; outside Claude Code, a detached process maestro polls.

**Ledger** — `.maestro/ledger.jsonl`, one line per model call with model, tokens and time; the
source of the report's cost table.

**Lock** — one director per repository; a second `/maestro` in the same checkout is refused until
the first is done or dead.

**Plan-only** (`--plan-only`) — interview, plan and critique; no build. A later run can build the
approved plan.

**Policy** — `maestro.policy.yml` (repository) or `~/.config/maestro/policy.yml` (yours): standing
preferences such as denied slots, pinned versions, families switched off.

**Probe** — one cheap call ("Reply with exactly: OK") that proves the account can use a model on a
road. Remembered for seven days.

**Provisional** — a model the ledger has not measured enough: Grok, Argon. Marked in every
assignment line.

**Reviewer** — with `--review`, a cross-family model that reads the finished diff against the
plan.

**Run** — one `/maestro` invocation from interview to report, with its own id, checkpoint and
ledger rows.

**Sandbox rung** — the permission level a Codex or Cursor worker runs at, from "repository
writable, no network" up to "no sandbox", climbed only after a failed check and announced.

**Slot** — a short name for a model line: `opus`, `sol`, `gemini`, … Resolved to a concrete model
at the start of each run.

**Swap** — replacing a worker with a different model mid-run (limits with no road left, a crash,
your call), with critics re-checked. A **switch** keeps the same model on another road.

**Transport** (road) — the CLI that serves a model: native, agy, cursor, codex, api.
`opus@agy` names a slot on a road.

**Unattended** (`--unattended`) — a run with nobody to answer: gaps become assumptions, decisions
become clean stops. See [how it works](how-it-works.md#running-without-you).

**Worker** — any model that is not the director: builder, critic, reviewer, drafter, gate.

## FAQ

**Do I need API keys?** No. maestro uses the subscriptions your CLIs are signed in to. The only
key is optional, for running Claude workers on the Max plan's API credit.

**Can I use it with Claude only?** Yes. Critics then come from a different Claude model line and
the run is marked degraded, because same-family critique catches less.

**Does it commit without asking?** It commits after its own diff read and its own test run, as
the task implies; the interview is where you set the boundaries. Use `--plan-only` for a plan
without a build.

**What about my uncommitted changes?** A run needs a clean tree. Commit or stash first.

**Where is the report?** Printed at the end of the run; the numbers come from
`.maestro/ledger.jsonl`, the state from `.maestro/CHECKPOINT.md`. `.maestro/` is excluded from
git.

**Can two runs share a repository?** No; the second is refused. Use separate checkouts.

**Can I stop a run?** Yes; the checkpoint is written at every step, and `/maestro --resume`
continues it. A worker still running is waited for or stopped; a running test is never killed.

**What does `(policy)`, `(clamped)`, `(provisional)` in the assignment line mean?** Where the
choice came from: a policy file, an effort lowered to what the road supports, a model the ledger
has not measured yet.

## Technical details

- [SKILL.md](../../SKILL.md) — every term as the director uses it.
- [docs/README.md](../README.md) — the map of all pages.
