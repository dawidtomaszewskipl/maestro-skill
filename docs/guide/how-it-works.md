# How maestro works

maestro is a **skill**: a set of instructions an AI coding assistant loads when you type
`/maestro`. The assistant you are talking to becomes the **director**. It does not do the coding
alone; it runs a small team of models and keeps every decision visible. The people on that team
are called **workers**: a **builder** writes the code, **critics** check the plan, a **reviewer**
checks the finished code. Every term is explained in the [glossary](glossary.md).

## One run, step by step

```text
you ──► interview ──► assignment ──► plan ──► critique ──► build ──► checks ──► review ──► commit ──► report
                                      ▲          │ "revise"             │ findings, red tests
                                      └──────────┘ (≤ rounds)           └──► fix loop (≤ 3) ──► checks again
```

**Interview.** The director reads the task and the repository and asks you about what it cannot
find out itself: a missing detail, a convention, which tests should run. One question at a time,
until there are no gaps.

**Assignment.** It picks the builder, the critics and (if you asked for one) the reviewer, and
prints one line with each choice and its reason: the rubric row that fired, a policy entry, your
own words. The line also shows the exact model behind each name, the host it runs in and which
model families are available. Say "let sol build" and it changes.

**Plan.** The director writes `PLAN.md`: what will change, where, which tests prove it, what is
out of bounds.

**Critique.** The plan — never the code — goes to the critics, who always come from a different
company than the builder. Each answers with a verdict (approve, revise or reject) and findings
graded blocking, major or minor. The director revises and resends until every critic approves,
up to the round cap (two by default). If the cap is reached without approval, the run stops and
hands you the disagreement; nothing is built.

**Build.** The builder gets a brief: the plan, the boundaries, the conventions, what "done" looks
like. It writes the code and, when its sandbox allows it, runs the tests covering the change. Some
builders can only edit files; then the director runs the tests for them.

**Checks.** The director reads the whole diff itself, every time: nothing outside the boundaries,
nothing unplanned, no obvious bug. Then it runs the tests. For a change to a screen it takes
screenshots and looks at them; green tests alone never approve a layout.

**Review** (only with `--review`). With `full` or `cross`, a reviewer from a family other than the
builder's — by default the same slot that critiqued the plan — reads the diff against the plan
and the spec, and says whether every plan item is done; `full` adds the director's own read,
`cross` a spot-check after the reviewer. `--review=self` launches no reviewer: it is the
director's own read only. When only one family is available, the reviewer is another model line
of that family, and the run is marked degraded.

**Fix loop.** Findings and red tests go back to the builder, at most three rounds. Tiny fixes —
a few lines, no design change, nothing in permissions, money or data — the director may make
itself. After any fix the tests run again and the reviewer sees the changed part again.

**Commit and report.** The director commits and writes the report: who did what, with which exact
model, how long it took, how many tokens, which checks ran, what was skipped or degraded.

## What you are asked, and when

- **In the interview**, about the task. Only there, and only while no worker is running.
- **At the assignment**, implicitly: the line is printed and you may object.
- **When the run cannot decide for you**: the critique cap was reached, the fix loop ran out,
  another run holds the repository, a model you named cannot be used. The director stops with a
  question and the options; it never guesses and never silently falls back to another model.
- **Never silently.** An unknown flag is an error, not task text. A risky change without
  `--review` gets a recommendation in the assignment line, not a review added behind your back.

`--setup` turns the flags into a short questionnaire (what to build, who builds, who critiques,
how many rounds, which tests) and ends with a flag line you can paste next time.

## What "approval" means

- A **plan is approved** only when every required critic says approve with no blocking and no
  major finding for the current revision. Minor findings do not block.
- A **review passes** when there is no blocking or major finding and every plan item is reported
  done. Minor findings are fixed or listed in the report, and the report says which.
- A **worker's green test run is evidence, not a verdict.** The director runs the tests itself
  before the commit — the covering tests, or the full suite with `--tests=full` or when the
  change reaches shared code (migrations, middleware, config and the like).
- **Approval is the director's alone.** Critics and reviewers advise; the director reads the diff
  and commits.

## Cheaper drafts: the cascade

`--cascade` lets a cheap model (`luna` by default; `haiku` or `gemini` on request) write a first
draft. A **gate** then decides: first a mechanical check (did the draft stay in bounds, do the
tests pass), then a critic from another family reads the draft against the plan. Accept means the
draft is the build; revise means one round of fixes by the same drafter; escalate means the
stronger model you chose builds instead, with the rejected draft attached for reuse. Two gate
rounds at most. The cascade is refused for risky changes and cannot be combined with skipping
tests.

## When something goes wrong

- **A usage limit.** Routine, not a failure. A Claude slot continues on its next road to the same
  model (natively, then agy, then Cursor, then the API credit if enabled) and the report says so.
  With no road left, the run writes its checkpoint and stops; `--resume` checks the limit again
  and continues.
- **A model refuses.** A safety refusal is never retried: the run stops and reports. An ordinary
  "this is out of scope" gets one rewritten brief, then another builder.
- **A hang.** No progress from a worker for a long while (at least 15 minutes, or twice your
  slowest test) makes the director read the worker's files and then stop it, one process at a
  time. A running test is never killed, whatever happens.
- **A worker dies mid-build.** The director looks at `git status` and `git diff` before anything
  else, decides deliberately what to keep and what to reset, records that, and continues or
  stops.
- **A cap.** At the critique cap or the fix cap the run stops with a diagnosis and hands you the
  decision. There is no silent extra round.
- **The session ends.** Every worker launched outside an interactive Claude Code runs as a
  detached job that survives the director's session. `/maestro --resume` finds it, waits for it
  and carries on.

Everything a run knows is in `.maestro/CHECKPOINT.md`, rewritten at every step. That is what
`--resume` reads — on the same host, or on another after telling you what changes.

## Running without you

`--unattended` is for a headless run (`claude -p`, `codex exec`, `agent -p`) or an overnight one.
Small gaps — a naming choice, a missing detail that does not affect safety — become recorded
assumptions and the run goes on. Anything that needs your authority — permissions, money, scope,
what to do with existing data, a budget — stops the run cleanly with `result: needs-decision`,
the question and the options. You answer by resuming with the option's id:
`/maestro --resume --unattended d-….a`.

## Technical details

- [SKILL.md](../../SKILL.md) — the binding rules of every stage.
- [setup.md](../setup.md) — the `--setup` questionnaire.
- [cascade.md](../cascade.md) — the cascade protocol, gates and escalation.
- [checkpoint.md](../checkpoint.md) — the checkpoint file and the resume procedure.
- [unattended.md](../unattended.md) — the stop matrix and every ask point.
- [hosts.md](../hosts.md) — jobs, waiting, the transport switch.
- [troubleshooting.md](../troubleshooting.md) — the incidents behind the rules.
