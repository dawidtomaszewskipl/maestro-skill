# Unattended runs

> **What this page is for.** The binding rules of `--unattended`: which gaps become assumptions, which stop the run, and how a stop is recorded and answered. The plain overview is in [the guide](guide/how-it-works.md#running-without-you).

`--unattended` lets a maestro run finish with nobody to answer — headless under `claude -p`, as a
benchmark contestant, overnight. Every point where maestro would ask the user to fill a **gap**
becomes a recorded assumption; every point that needs the user's **authority** stops the run cleanly
with the result `needs-decision`, recorded so that a later `--resume` can answer it. The flag never
turns a stop that protects safety, budget, scope or authority into a silent decision.

Opt-in only: without the flag the director asks, as SKILL.md says. **Under the flag this file is
authoritative.** Its outcomes override the attended wording — "ask", "halt with a question", "hand
over", "the user's call", "offered for building" — wherever it appears in SKILL.md or `docs/`,
English or Polish.

## The flag

- A property of the **invocation**, not of the run. It is never written into the checkpoint's
  `flags`; the checkpoint's `modes` records the mode of each director session.
- `--setup --unattended` is illegal — setup is questions. Run setup first, then reuse its flag line
  with `--unattended`.
- `--resume --unattended` is legal, and `--unattended` is the only flag allowed next to `--resume`.
  A bare `--resume` continues attended. Text after the flags of a `--resume` is an answer
  ("Decisions and answers").
- The assignment line carries `unattended=on`.
- The high-stakes guard is unchanged: with no `--review`, the assignment line and the report
  recommend one, and nothing is added.

## Stop matrix

Approved by the user; binding.

| Row | Situation | With `--unattended` |
| --- | --- | --- |
| 1 | spec ambiguity, convention choice, missing detail that does not affect safety | recorded assumption; the run continues |
| 2 | a question about authorization, budget, a scope change or a high-stakes decision (SKILL.md, "Flags") | **stop**, result `needs-decision` |
| 3 | critic `reject`, or blocking/major findings unresolved at the critique cap — majors alone only after the arbiter upheld one or could not run (A13) | **stop** `needs-decision` |
| 4 | review still failing at the fix-loop cap | **stop** `needs-decision` |
| 5 | safety stop, quota or limit exhaustion | **stop**, exactly as today |

**Precedence when several apply: 5 > 2 > 3 = 4 > 1.** Any stop condition beats an assumption. A
decision records the highest row that applies in `row` and the others in `also_rows`. Row 5 is
never a decision — it is today's operational blocker — so when row 5 applies together with another
row, the run stops under row 5 exactly as today; the other row's question is still written as the
checkpoint's `decisions.current` with `also_rows: [5]`, and the blocker's `detail` names that
decision, so the question survives the limit wall and the next resume needs its answer.

## What counts as authorized

The task text and the flags the user gave are the authorization.

- A high-stakes change the task asks for explicitly (for example "add a password reset") is
  authorized; the run proceeds, with the existing high-stakes guard.
- A high-stakes **decision** the task leaves open — what to do with existing data, who may access
  what, what to charge — is row 2.
- Budget means the policy and flag limits plus any limit the task states. Exceeding one is row 2.
- Scope means the task text. Touching an unrelated module the task did not ask for is row 2; a
  supporting edit the change needs (an import, a test fixture) is not.
- An answer to a recorded decision authorizes exactly what its option says, and nothing more.

## Classification first

Every gap is classified **before** it is resolved, and only row 1 becomes an assumption.

1. **Interview** (SKILL.md, "The loop", step 1). The director asks no questions. It extracts the
   spec from the task text, the repository and its conventions, and classifies each gap: row 1
   becomes an assumption, anything else is a stop. Assumptions go under `## Assumptions
   (unattended)` in PLAN.md — what was unclear, the choice, why, and whether it is easy to reverse.
   The same holds for every interview in the skill: the test scope (SKILL.md, "Briefs", "Test
   scope") and a planned plan's open decisions (SKILL.md, "Building a `--plan-only` plan"). The test
   scope defaults to `covering` unless flags say otherwise; the full suite still runs for shared or
   unbounded reach, as "Test scope" requires.
2. **Worker briefs.** Every brief adds, after the closing block of SKILL.md "Briefs":

   > If the brief is silent on authorization, budget, scope or a high-stakes decision, do not
   > decide it: stop, leave the tree as it is, and end your answer with the question.

   Every other gap stays an assumption, as today. The cascade drafter gets its own form of the
   clause (item 5).
3. **Assumption audit.** After every worker turn the director reads the worker's assumptions (the
   `assumptions` field or the `## Assumptions` heading) and classifies each one. Row 1 is adopted
   into the run's assumption list. Anything else stops the run (`needs-decision`); the worker's
   changes are handled by the dirty-exit protocol, and nothing is committed.
4. **Worker questions** — a worker that ends with a question, the attended `question` blocker
   (SKILL.md, "Briefs") — are classified too. The director answers row 1 from the spec, the plan and
   the assumptions, as a new prompt to the worker's thread; anything else stops the run, as a
   decision, never as a `question` blocker.
5. **Cascade drafter** (A21). The drafter appendix gains the same clause, ending in a line
   `DRAFT_ABORT: authority: <question>`, and the director classifies **every** `DRAFT_ABORT` reason
   before escalating (`docs/cascade.md`, "Abort classification"):
   - an authority gap (row 2) stops the run with no escalation; the draft is kept as
     `.maestro/draft.diff`, and the tree follows the cascade's own steps (stashed, or clean when the
     draft left no changes);
   - a capability or context abort escalates to the implementer as today.
6. **Dirty-exit keeps the outcome that started it** (A16b). It is recovery, never a stop by itself,
   and never turns into row 5.

## Ask-point inventory

The coverage baseline, built by searching SKILL.md and every `docs/*.md` for ask, question, halt,
confirm, "hand … over", "user's call" and "user picks" — the command is under "Reproducing the
search". Every reachable point has one outcome. The **section names are the reference**; line
numbers are not kept, because SKILL.md changes. Every `--unattended` pointer sentence in SKILL.md
names its entry here.

| # | Source | Ask point today | `--unattended` outcome |
| --- | --- | --- | --- |
| A1 | SKILL.md "Flags" and its illegal combinations; "Stage 0" step 1 | unknown flag or value, illegal combination | validation stop ("Where a stop is recorded") |
| A2 | SKILL.md "Flags", plain words | plain-word mapping ambiguous or rule-breaking | validation stop |
| A3 | SKILL.md "Flags", `--critic` and `--reviewer` | named critic or reviewer from the builder's family; two named critics from one family on high stakes | stop, row 2 (configuration authority) |
| A4 | SKILL.md "Setup"; docs/setup.md "Questions" | setup questionnaire | unreachable: `--setup` + `--unattended` is illegal (A1; SKILL.md, docs/setup.md) |
| A5 | SKILL.md "Setup", "Stage 0" step 5; docs/policy.md; docs/setup.md | failed model probe | stop, row 2 (no silent substitution); the setup re-ask is unreachable (A4) |
| A6 | SKILL.md "The cross-family rule"; docs/cascade.md "Drafters" | cascade family rule cannot be met | stop, row 2 |
| A7 | SKILL.md "The cross-family rule" | Claude-only routing with no eligible critic or reviewer | stop, row 2 |
| A8 | docs/policy.md "What halts"; SKILL.md "Stage 0" step 4 | illegal policy; denied effective implementer; a flag requires an unavailable family | stop, row 2 |
| A9 | docs/workers.md; SKILL.md "Stage 0" step 4 | `--model` naming an unavailable family | stop, row 2 |
| A10 | SKILL.md "The loop" step 1; "Briefs", "Test scope"; "Building a `--plan-only` plan" | interview questions; test scope; a planned plan's open decisions | classification first (row 1 → assumption, otherwise stop) |
| A11 | SKILL.md "Briefs" and; docs/workers.md; docs/checkpoint.md | worker assumptions and worker questions | brief clause, assumption audit, classification |
| A12 | SKILL.md "Flags", high-stakes guard | recommend `--review` | unchanged: a recommendation in the assignment line and the report; nothing added |
| A13 | SKILL.md "The loop" step 4, caps; docs/briefs.md "Arbiter at the cap" | critique cap, critic `reject` | `reject`, a blocking finding, or high stakes → stop, row 3. Only majors left on a change that is not high stakes → the arbiter runs here too (the user's decision; one call, no stop while it runs): every finding downgraded → the plan is approved and the run continues, the report saying "approved by arbiter <slot> over <critic>'s majors"; any upheld, an invalid answer, a failed call or no eligible third family (`maestro-roles --arbiter`) → stop, row 3 |
| A14 | SKILL.md "The loop" step 7, caps | fix-loop cap | stop, row 4 |
| A15 | SKILL.md "Flags", `--plan-only`; "The loop" step 4 | `--plan-only` hand-over | not a stop: the plan-only report is the normal result, with the assumption list |
| A16a | SKILL.md "Time and the watchdog" (safety stops, dirty-exit); "Launching workers" (transport switch); docs/hosts.md "Transport switch"; docs/catalog.md "Precedence" | safety stop; quota or limit exhaustion | safety stop → row 5, exactly as today. Quota or unavailability of a Claude slot's transport → the transport-switch transaction, automatically (the user configured the order; no stop), onto the **next eligible transport serving the same model id** — denied and unavailable transports are skipped, never switched onto (`maestro-roles --transports`). Row 5 only when no such transport remains (a later one serves another version, or none is left) or a forced `@transport` failed |
| A16b | SKILL.md "Time and the watchdog", dirty-exit | dirty-exit after a crash, kill or tree mismatch | not a stop by itself. Recovery keeps the outcome that triggered it: an audit stop stays row 2; a crash continues or swaps as today (A17, A18); a tree mismatch is inspected and its keep/reset decision recorded as today. A mismatch the director cannot attribute to a known worker is row 2, because someone else changed the tree |
| A17 | SKILL.md "Time and the watchdog", swap | swap: limits, the user's call, a crashed host; no eligible critic after a swap | limits with no transport left → row 5 stop (with one left it is A16a's switch, not a swap); the user's call is unreachable (no user); a crashed host → swap as today; no eligible critic → stop, row 2 |
| A18 | SKILL.md "Time and the watchdog" | out-of-scope decline → one rewritten brief, then reroute; transient API failure | unchanged (the director's existing authority); transient API failure → continue, unchanged |
| A19 | SKILL.md "Checkpoint and resume"; docs/checkpoint.md "Decisions", candidates, "Resume procedure" step 1 | a checkpoint exists when a new (non-resume) task starts; several candidates on resume | new task over an unfinished run → stop recorded in `pending-decision.md`; several candidates → "Candidates on resume" |
| A20 | SKILL.md "Building a `--plan-only` plan"; docs/checkpoint.md "Resume procedure" step 6 | build a planned plan?; no eligible critics for it | "Candidates on resume"; no eligible critics → stop, row 2 |
| A21 | docs/cascade.md "Protocol" step 3 and step 7, "Abort classification", "Drafter appendix" | drafter `DRAFT_ABORT` → automatic escalation | the drafter appendix gains the authority clause; the director classifies the abort reason before escalating: an authority gap is row 2 with no escalation; capability or context keeps the existing escalation |
| A22 | SKILL.md "Flags", `--unattended`; docs/hosts.md "Detection" | a headless director (`claude -p`): nobody can answer | without `--unattended`: validation stop; with it: the run proceeds under this matrix |
| A23 | SKILL.md "Stage 0" step 0; docs/hosts.md "Detection" | host `unknown` or `unsupported` (since 2.0.0 maestro directs only from Claude Code) | stop, row 2: the remedy is starting `/maestro` from Claude Code |
| A24 | SKILL.md "Checkpoint and resume"; docs/hosts.md "Director identity"; docs/checkpoint.md "Resume procedure" step 0 | a resume whose checkpoint records another host or a slot or transport removed in 2.0.0; a resume under a different director model line; the director's identity changing between dispatches so that a `self` or degraded-mode assignment becomes illegal | stop, row 2 |
| A25 | SKILL.md "Stage 0" step 3a; docs/hosts.md "Capability checks" | a capability the run needs is missing (`maestro-preflight` `stops`: state, git metadata, model reach; tests, visual); a Bash permission prompt denied | stop, row 2 (changing Claude Code's configuration is the user's authority) |
| A26 | SKILL.md "Stage 0" step 0; docs/hosts.md "Lock" | the checkout's lock is held by a live director, or another run's jobs are still alive | stop, row 2 |
| A27 | SKILL.md "Launching workers"; docs/hosts.md "Jobs" | a job ends `blocked` (members that cannot be classified or killed) | not a decision: the run ends with `result: blocked`, the lock kept and the members listed; the same with or without `--unattended` |
| A28 | SKILL.md "The cross-family rule", degraded modes | one eligible family with a single eligible line (Google with only one of `argon`, `gemini`; the explicit-only `carbon` and `neon` never count as a line here unless named) | stop, row 2 (extends A7) |
| A29 | SKILL.md "Stage 0" step 5; docs/catalog.md "Resolution" | the newest candidate is denied and an older one passes; a renamed line kept on its previous slug | recorded assumption, row 1 (announced in the Assign line and the report); no candidate passing → row 2 (A5) |
| A30 | SKILL.md "Launching workers"; docs/commands.md "Validating a verdict" | a named critic's verdict invalid after the re-ask | stop, row 2 (the named critic cannot be replaced silently); an unnamed critic moves to the next eligible one |
| A31 | SKILL.md "Stage 0" step 4a; docs/catalog.md "Sources", "Pins" | a transport's catalog cannot be acquired; a pinned version or slug missing from the catalog | the transport is ineligible; a flag or pin that needs it → row 2 (as A8, A9) |
| A32 | SKILL.md "Roster", rubric row 6 | `self` ineligible (director model unknown) and none of `sonnet`, `sol`, `gemini` eligible | stop, row 2 |

Reproducing this inventory, and the scenario test that checks it: `docs/unattended-reference.md`.

## Where a stop is recorded

Each decision has this shape:

```yaml
decision_id: d-<run_id or attempt_id>-<n>   # unique; attempt_id = UTC time of the invocation
                                            # that wrote the record
kind: needs-decision
row: 2                      # highest matrix row that applies; others in also_rows
also_rows: []
at: 2026-10-03T14:00:00+02:00
source: A13                 # inventory id
refers_to: {run_id: "…", stage: "…", written_at: "…", tree_head: "…"}
                            # pending decisions about an existing run only
question: "…"
options:                    # each bound to an explicit action the director executes
  - {id: d-…-3.a, text: "one more critique round (cap 2 → 3)",
     action: "continue: critique round 3 of the current plan", changes_config: "rounds=3"}
  - {id: d-…-3.b, text: "stop here; hand the plan over",
     action: "continue: stage report, plan-only style hand-over", changes_config: ""}
recommendation: d-…-3.a
answer: null
```

`<n>` counts the decisions of its record from 1, history included; an option id is
`<decision_id>.<letter>`. A decision lives in one of two places.

**The run's checkpoint**, for every `needs-decision` stop raised inside a run — from the run's
first checkpoint on, written when stage 0 ends. It is a **separate key**, `decisions: {current:
<decision or null>, history: [...]}`; `stage` and `next_action` are kept unchanged.

- The existing `blockers` list is untouched: `quota`, `api`, `safety-pause` and `question` (the
  attended worker-question blocker) keep today's format and today's resume handling, with no
  answer — `quota` and `api` are recoverable (re-probe runtime and limits, then continue), and a
  `safety-pause` is never retried (SKILL.md, "Time and the watchdog"; `docs/checkpoint.md`,
  "Resume procedure" step 2).
- A row 5 stop writes its operational blocker as today. It is **never** a `decisions` entry, so
  recovering from a quota stop never needs an answer.
- A checkpoint without a `decisions` key — every existing one — has no open decision.

**`.maestro/pending-decision.md`**, for a stop with no run to hold it. It holds `{attempt_id,
task_text, flags, current: <decision>, history: [...]}` (`docs/checkpoint.md`, "Decisions").

- Cases:
  - validation stops (A1, A2);
  - a stop raised in stage 0 before the run's first checkpoint (A3, A5–A9 when they fire there;
    raised later, at the assignment step, they go to the checkpoint);
  - a new non-resume task over an unfinished run (A19) — checked right after the flags, before
    any other stage 0 step;
  - several candidates on an unattended resume with no answer, and a failed candidate check.

  All of them are row 2 — a validation stop (`source` A1, A2), a collision or a candidates
  decision (A19, A20) because which work runs, and with which flags, is the user's to say, and
  maestro never guesses a flag line.
- A validation stop creates only `.maestro/`, its exclude entry (SKILL.md, "Stage 0" step 2) and this
  file: no schemas, no checkpoint, no model call. An existing checkpoint is **never touched**.
- The pending actions are:
  - `start: <corrected flag line>` — the attempted task as a new run; the line holds the run flags
    without `--unattended`, and the run takes its mode from the invocation that answers;
  - `continue` — the existing run;
  - `start: <queued task id>`;
  - `build: <task id> <plan_sha256>`;
  - `archive-and-start` — `maestro-state --gen N rotate --to <run_id>` (the checkpoint, the pending
    decision and the audit move to `.maestro/archive/<run_id>/`), then start the attempted task.
    Never a delete.
- The file is deleted once its `current` is resolved and acted on: the started run has written its
  first checkpoint, or the existing run continues.
- A new non-resume invocation supersedes it: the old `current` moves to `history` (`answer:
  superseded`) and the checks run again. They may hit the same collision again — then the file
  gets the new `current` — and a run that starts deletes it.

## Candidates on resume

The existing ordering is preserved.

- **An active run** (checkpoint `stage ≠ report`) is the **only** candidate. `--resume` continues
  it, as today (SKILL.md, "Checkpoint and resume"). Queued and planned work waits.
- **At `stage: report`**, the candidates are:
  - the **next queued task in queue order** (`start`), if any;
  - **each planned task** (`build`), and `plan_only: true` without a queue as one more `build`.

  Candidates are deduplicated by task id: the current task's `plan_only` marker and its planned
  entry are one candidate.
- **One candidate:** `--resume` is the authorization, so it proceeds. `build` keeps the plan
  approval conditions (A20, SKILL.md "Building a `--plan-only` plan"); a new invocation's build
  flags travel as the option's `changes_config` and are validated like any configuration change.
- **Several candidates:** a decision with one option per candidate.
  - Attended without an answer: the director asks.
  - Unattended without a matching answer: stop, recorded in `pending-decision.md`. No task is
    selected.
- **Checks before acting:**
  - `continue`: the run's identity matches `refers_to`;
  - `start`: the task exists, is still `queued`, and is next in queue order (no plan to hash);
  - `build`: the task exists and is still `planned`, and its plan file still hashes to the
    approved `plan_sha256`.

  A failed check is a failed validation (below).

## Decisions and answers

- `--unattended` is a property of the **invocation**, not of the run. `--resume --unattended` is
  legal, and it is the only flag allowed next to `--resume`. A bare `--resume` continues attended.
  The checkpoint records which mode each session ran in (`modes`).
- **Text after the flags** of a `--resume` invocation is an answer: a full option id (`d-…-3.a`). A
  bare letter is accepted **only** when exactly one unresolved decision exists across
  `pending-decision.md` and the checkpoint's `decisions`. For an attended resume, the answer can
  also come from the question the director asks.
- **One answer consumes exactly one decision.** Order before any dispatch:
  1. `pending-decision.md`'s `current`;
  2. the checkpoint's `decisions.current`;
  3. the candidates.

  Only the **first unresolved decision** in this order takes an answer. An answer that names a
  later decision is no answer to the first one: unattended, the run stops again on the first one
  with nothing written; attended, the director asks the first one. After one decision is resolved,
  the next unresolved one needs its own answer, in a separate invocation when unattended — the
  director asks (attended), or stops with that decision (unattended). Nothing is dispatched while
  any decision is open. A `refers_to` is never rewritten: any change to the checkpoint it names is
  a mismatch.
- **Operational blockers** (`blockers`) are handled by today's resume procedure, before or
  alongside the decision order above, and an answer is never required for them.
  - `quota` and `api` are recoverable: resume re-probes and continues. If an open decision also
    exists, the decision still needs its answer, and the operational recovery is only re-checked:
    the re-probe is reported, not written.
  - A `safety-pause` is never retried, attended or not (SKILL.md: safety stops are not
    retryable): no resume re-sends the refused turn. Unattended, the resume reports the blocker
    and stops again under row 5; attended, the director reports it and the user decides how to go
    on (`docs/checkpoint.md`, "Resume procedure" step 2).
- **Per decision:**
  - **attended, no answer:** the director asks with the recorded options (`AskUserQuestion`);
  - **unattended, no answer, or an answer that names another decision or matches no option:** stop
    again. Nothing changes — nothing is written, so `written_at` and every `refers_to` stay valid —
    there are no model calls, and the report repeats the current question with its `decision_id`;
  - **with an answer for this decision:**
    1. **identity check:** for a decision with `refers_to`, the current checkpoint has the same
       `run_id`, `stage`, `written_at` and `tree.head`. A mismatch means the run changed since the
       decision was recorded, which is a failed validation;
    2. compute the resulting configuration (`changes_config`, `action`);
    3. **validate it under every existing rule**:
       - flags and illegal combinations;
       - policy;
       - the cross-family rule for every critic, reviewer and gate against every possible builder;
       - stage 0 step 5 probes for any new OpenAI slot, and the step 8 reach probe for any new
         Codex writer;
       - the candidate checks above;
       - plan re-approval when the plan's approving critics no longer fit (SKILL.md, "Building a
         `--plan-only` plan"), with an eligible critic for it;
       - **caps:** an action that runs past a reached cap carries the matching increase in the same
         `changes_config` — another critique round needs `rounds=<n>` (1–8), and another fix turn
         after the fix cap — by the same builder, a swapped builder or the director's own bounded
         fix — needs `fix_cap=<n>`, an integer above the fix rounds already run. Without it the
         validation fails and the run stays stopped;
    4. **valid:**
       - record `answer` and move the decision to `history`, so it is consumed exactly once;
       - write the changed flags, and a raised `fix_cap`, into the checkpoint of the run that
         continues or starts, with the decision id as their source (`flag_sources`);
       - execute the `action`;
       - delete `pending-decision.md` (`maestro-state --gen N delete pending-decision.md`) once its
         `current` is resolved and acted on;
    5. **failed validation:** move the answered decision to `history` with its answer and the
       failed rule (`failed_rule`), and write the remedy as the new `current` in the **same**
       record. That record is `pending-decision.md` or the checkpoint's `decisions`; an unrelated
       checkpoint is never modified. The remedy has a new `decision_id` and options that satisfy
       the rule, or `archive-and-start` / `start: <corrected flags>`. Then stop (unattended) or ask
       (attended). The next resume answers the new `current`.
- **Caps** change only through an option whose `changes_config` says so (`rounds=3`,
  `fix_cap=4`). That option is the user's explicit authorization, never a silent reset — SKILL.md
  "The loop", caps, still holds.
  - `rounds` is the `--rounds` flag: an answer writes it into the checkpoint's `flags`.
  - The fix-loop cap has no flag. It is the checkpoint's resolved field `fix_cap` — 3 (SKILL.md's
    cap) unless an answered option raised it, with `flag_sources` naming that decision — and a
    checkpoint without it (every existing one) reads as 3. A resumed run restores it with the rest
    of the resolved configuration, and its fix loop stops at `fix_cap` rounds, attended or not.
  - An option whose action is another builder or fix turn after the fix cap without a `fix_cap`
    increase is never offered; one that reaches validation anyway fails it (above).

## Ending a run on `needs-decision`

A stop is raised where the attended director would ask.

1. Stop new dispatch.
2. Let in-flight harness tasks (workers, tests) finish under the existing rules: no killing tests,
   and the hang watchdog with its existing kill procedure for a hung worker. This is waiting for
   processes, not for a human.
3. If anything ended uncleanly, run the dirty-exit protocol. Then write the checkpoint with the
   decision as `decisions.current` — or `pending-decision.md` when there is no run.
4. Write the report ("Report" below): it opens with `result: needs-decision`, then the question,
   the options and the recommendation, and it lists the assumptions so far.

Then the run ends. A row 5 stop follows today's procedures exactly.

## Report

Under `--unattended` the report opens with one `result:` line:

- `result: needs-decision` — then the decision id with its row and source, the question, the
  options with their ids, the recommendation, and the line that answers it;
- `result: done` — committed, with the hash;
- `result: plan-only` — the plan handed over (A15);
- `result: stopped` — a row 5 stop; the rest is today's report of that stop;
- `result: blocked` — a job that could not be ended (A27): its members, the lock kept; the next
  `--resume` reconciles.

Every unattended report then lists the assumptions made so far (interview, worker answers, audit),
and continues as SKILL.md "The loop" step 9 describes.

```
result: needs-decision
decision: d-2026-10-03T14-02-maestro-c3d4-3 (row 3, A13)
question: Critique cap (2) reached; Sol still reports one major finding: the bulk job has no retry.
options:
  d-2026-10-03T14-02-maestro-c3d4-3.a  one more critique round (cap 2 → 3)   [recommended]
  d-2026-10-03T14-02-maestro-c3d4-3.b  stop here; hand the plan over
answer: /maestro --resume --unattended d-2026-10-03T14-02-maestro-c3d4-3.a
assumptions:
  - batch size 500, like the existing reindex job (easy to reverse)
```
