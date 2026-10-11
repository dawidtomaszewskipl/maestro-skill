# Unattended runs

`--unattended` lets a route run finish with nobody to answer — headless under `claude -p`, as a
benchmark contestant, overnight. Every point where route would ask the user to fill a **gap**
becomes a recorded assumption; every point that needs the user's **authority** stops the run cleanly
with the result `needs-decision`, recorded so that a later `--resume` can answer it. The flag never
turns a stop that protects safety, budget, scope or authority into a silent decision.

Opt-in only: without the flag route behaves as before. **Under the flag this file is
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
| 3 | critic `reject`, or blocking/major findings unresolved at the critique cap | **stop** `needs-decision` |
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
     `.route2/draft.diff`, and the tree follows the cascade's own steps (stashed, or clean when the
     draft left no changes);
   - a capability or context abort escalates to the implementer as today.
6. **Dirty-exit keeps the outcome that started it** (A16b). It is recovery, never a stop by itself,
   and never turns into row 5.

## Ask-point inventory

The coverage baseline, built by searching SKILL.md and every `docs/*.md` (English; each Polish copy
in `docs/pl/` mirrors these at its own lines) for ask, question, halt, confirm, "hand … over",
"user's call" and "user picks" — the command is under "Reproducing the search". Every reachable
point has one outcome. Line numbers in A1–A21 are those of route 3.4.0, kept as a trace; in route2
the **section names are the reference** (A16a, A17 and A22–A31 cite sections only). Every `--unattended` pointer sentence in SKILL.md names its entry
here.

| # | Source | Ask point today | `--unattended` outcome |
| --- | --- | --- | --- |
| A1 | SKILL.md "Flags" :32–36 and its illegal combinations :69–76; "Stage 0" step 1 :239 | unknown flag or value, illegal combination | validation stop ("Where a stop is recorded") |
| A2 | SKILL.md "Flags", plain words :78–84 | plain-word mapping ambiguous or rule-breaking | validation stop |
| A3 | SKILL.md "Flags", `--critic` and `--reviewer` :42–48 | named critic or reviewer from the builder's family; two named critics from one family on high stakes | stop, row 2 (configuration authority) |
| A4 | SKILL.md "Setup" :93–109; docs/setup.md "Questions" :28–72 | setup questionnaire | unreachable: `--setup` + `--unattended` is illegal (A1; SKILL.md :72–73, docs/setup.md :7–9) |
| A5 | SKILL.md "Setup" :102–103, "Stage 0" step 5 :267–271; docs/policy.md:58; docs/setup.md:31–33 | failed model probe | stop, row 2 (no silent substitution); the setup re-ask is unreachable (A4) |
| A6 | SKILL.md "The cross-family rule" :212–219; docs/cascade.md "Drafters" :34–40 | cascade family rule cannot be met | stop, row 2 |
| A7 | SKILL.md "The cross-family rule" :221–230 | Claude-only routing with no eligible critic or reviewer | stop, row 2 |
| A8 | docs/policy.md "What halts" :61–74; SKILL.md "Stage 0" step 4 :253–258 | illegal policy; denied effective implementer; a flag requires an unavailable family | stop, row 2 |
| A9 | docs/workers.md:39; SKILL.md "Stage 0" step 4 :256–258 | `--model` naming an unavailable family | stop, row 2 |
| A10 | SKILL.md "The loop" step 1 :400–406; "Briefs", "Test scope" :361–362; "Building a `--plan-only` plan" :570–571 | interview questions; test scope; a planned plan's open decisions | classification first (row 1 → assumption, otherwise stop) |
| A11 | SKILL.md "Briefs" :374–377 and :385–396; docs/workers.md:97–99; docs/checkpoint.md:60 | worker assumptions and worker questions | brief clause, assumption audit, classification |
| A12 | SKILL.md "Flags", high-stakes guard :86–91 | recommend `--review` | unchanged: a recommendation in the assignment line and the report; nothing added |
| A13 | SKILL.md "The loop" step 4 :424–430, caps :483–487 | critique cap, critic `reject` | stop, row 3 |
| A14 | SKILL.md "The loop" step 7 :460–463, caps :483–487 | fix-loop cap | stop, row 4 |
| A15 | SKILL.md "Flags", `--plan-only` :55–58; "The loop" step 4 :431–435 | `--plan-only` hand-over | not a stop: the plan-only report is the normal result, with the assumption list |
| A16a | SKILL.md "Time and the watchdog" (safety stops, dirty-exit); "Launching workers" (transport switch); docs/hosts.md "Transport switch"; docs/catalog.md "Precedence" | safety stop; quota or limit exhaustion | safety stop → row 5, exactly as today. Quota or unavailability of a Claude slot's transport → the transport-switch transaction, automatically (the user configured the order; no stop), onto the **next eligible transport serving the same model id** — denied and unavailable transports are skipped, never switched onto (`route2-roles --transports`). Row 5 only when no such transport remains (a later one serves another version, or none is left) or a forced `@transport` failed |
| A16b | SKILL.md "Time and the watchdog", dirty-exit :511–519 | dirty-exit after a crash, kill or tree mismatch | not a stop by itself. Recovery keeps the outcome that triggered it: an audit stop stays row 2; a crash continues or swaps as today (A17, A18); a tree mismatch is inspected and its keep/reset decision recorded as today. A mismatch the director cannot attribute to a known worker is row 2, because someone else changed the tree |
| A17 | SKILL.md "Time and the watchdog", swap | swap: limits, the user's call, a crashed host; no eligible critic after a swap | limits with no transport left → row 5 stop (with one left it is A16a's switch, not a swap); the user's call is unreachable (no user); a crashed host → swap as today; no eligible critic → stop, row 2 |
| A18 | SKILL.md "Time and the watchdog" :506–510 | out-of-scope decline → one rewritten brief, then reroute; transient API failure | unchanged (the director's existing authority); transient API failure → continue, unchanged |
| A19 | SKILL.md "Checkpoint and resume" :550–563; docs/checkpoint.md "Decisions", candidates :132–145, "Resume procedure" step 1 :152–155 | a checkpoint exists when a new (non-resume) task starts; several candidates on resume | new task over an unfinished run → stop recorded in `pending-decision.md`; several candidates → "Candidates on resume" |
| A20 | SKILL.md "Building a `--plan-only` plan" :565–578; docs/checkpoint.md "Resume procedure" step 6 :192–193 | build a planned plan?; no eligible critics for it | "Candidates on resume"; no eligible critics → stop, row 2 |
| A21 | docs/cascade.md "Protocol" step 3 :49–56 and step 7 :70–79, "Abort classification" :83–99, "Drafter appendix" :101–117 | drafter `DRAFT_ABORT` → automatic escalation | the drafter appendix gains the authority clause; the director classifies the abort reason before escalating: an authority gap is row 2 with no escalation; capability or context keeps the existing escalation |
| A22 | SKILL.md "Flags", `--unattended`; docs/hosts.md "Detection" | a headless director (`claude -p`, `codex exec`, `agent -p`) — nobody can answer | without `--unattended`: validation stop; with it: the run proceeds under this matrix |
| A23 | SKILL.md "Stage 0" step 0; docs/hosts.md "Detection" | host `unknown` | stop, row 2 (`--host=` is the answer) |
| A24 | SKILL.md "Checkpoint and resume"; docs/hosts.md "Resume across hosts", "Director identity" | a resume in a different host, director family or model line; the director's identity changing between dispatches so that a `self` or degraded-mode assignment becomes illegal | stop, row 2 |
| A25 | SKILL.md "Stage 0" step 3a; docs/hosts.md "Capability checks" | a capability the run needs is missing (state, git metadata, model reach, tests, visual); a host permission prompt denied | stop, row 2 (changing the host's configuration is the user's authority) |
| A26 | SKILL.md "Stage 0" step 0; docs/hosts.md "Lock" | the checkout's lock is held by a live director, or another run's jobs are still alive | stop, row 2 |
| A27 | SKILL.md "Launching workers"; docs/hosts.md "Jobs" | a job ends `blocked` (members that cannot be classified or killed) | not a decision: the run ends with `result: blocked`, the lock kept and the members listed; the same with or without `--unattended` |
| A28 | SKILL.md "The cross-family rule", degraded modes | one eligible family with a single line (Google, xAI) | stop, row 2 (extends A7) |
| A29 | SKILL.md "Stage 0" step 5; docs/catalog.md "Resolution" | the newest candidate is denied and an older one passes; a renamed line kept on its previous slug | recorded assumption, row 1 (announced in the Assign line and the report); no candidate passing → row 2 (A5) |
| A30 | SKILL.md "Launching workers"; docs/commands.md "Validating a verdict" | a named critic's verdict invalid after the re-ask | stop, row 2 (the named critic cannot be replaced silently); an unnamed critic moves to the next eligible one |
| A31 | SKILL.md "Stage 0" step 4a; docs/catalog.md "Sources", "Pins" | a transport's catalog cannot be acquired; a pinned version or slug missing from the catalog | the transport is ineligible; a flag or pin that needs it → row 2 (as A8, A9) |
| A32 | SKILL.md "Roster", rubric row 6 | `self` ineligible (director model unknown) and none of `sonnet`, `sol`, `gemini`, `grok` eligible | stop, row 2 |

### Reproducing the search

```bash
grep -n -i -E "\bask|question|halt|confirm|hand(s|ed)? .{0,40}over|user's call|user picks" \
  SKILL.md $(ls docs/*.md | grep -v '/unattended.md$')    # from the repository root
```

route2 re-ran the search over its own SKILL.md, `docs/hosts.md` and `docs/catalog.md`
(2026-10-11): every new ask point is A22–A32; the remaining hits are "confirm" in director checks
(`docs/hosts.md`, "Marker confirmation", transport switch step 1), "how it asks the user" (the
adapter table) and the routing-precedence table's halts (A8, A9, A16a).

A hit inside an `--unattended` pointer sentence (SKILL.md :36, :63–67, :97, :228–229, :256–258,
:388–396, :401–406, :478–481, :528–530) belongs to the entry that sentence names. Every other hit
is either in the table above or listed here as not an ask point:

| Hit | Why it is not an ask point |
| --- | --- |
| SKILL.md:8 | the skill description ("explicitly asks for the multi-model loop") |
| SKILL.md:54, :95–96, :104 | `--setup` and its contract: A4, unreachable |
| SKILL.md:145 | "only when the user picks it" — a routing preference in the rubric, not a question |
| docs/setup.md:3–4, :28–71 | the setup questionnaire: A4, unreachable |
| docs/commands.md:29, :174, :212 | "confirmed cause", a brief that "asks for", "confirm what" a worker runs with — no user |
| docs/policy.md:27 | "because you asked" — explains a flag that beats a deny |
| docs/cascade.md:79 | `--resume` "after confirming" branch and `HEAD` — a director check |
| docs/checkpoint.md:60, :87 | the `question` blocker kind: A11 |
| docs/checkpoint.md:99–106, :169–174 | the decision record and the resume step this file defines |
| docs/checkpoint.md:182 | "after confirming" branch and `HEAD` — a director check |
| docs/workers.md:43, :144, :189 | "confirmed it", "unless asked", "without being asked" — about workers, not the user |
| docs/troubleshooting.md:7, :41, :50, :180–181 | incident write-ups ("confirmed", "asked how it is going", a gate that "asked for a revision") |

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

**`.route2/pending-decision.md`**, for a stop with no run to hold it. It holds `{attempt_id,
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
  route never guesses a flag line.
- A validation stop creates only `.route2/`, its exclude entry (SKILL.md, "Stage 0" step 2) and this
  file: no schemas, no checkpoint, no model call. An existing checkpoint is **never touched**.
- The pending actions are:
  - `start: <corrected flag line>` — the attempted task as a new run; the line holds the run flags
    without `--unattended`, and the run takes its mode from the invocation that answers;
  - `continue` — the existing run;
  - `start: <queued task id>`;
  - `build: <task id> <plan_sha256>`;
  - `archive-and-start` — `route2-state --gen N rotate --to <run_id>` (the checkpoint, the pending
    decision and the audit move to `.route2/archive/<run_id>/`), then start the attempted task.
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
       - delete `pending-decision.md` (`route2-state --gen N delete pending-decision.md`) once its
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
decision: d-2026-10-03T14-02-route-c3d4-3 (row 3, A13)
question: Critique cap (2) reached; Sol still reports one major finding: the bulk job has no retry.
options:
  d-2026-10-03T14-02-route-c3d4-3.a  one more critique round (cap 2 → 3)   [recommended]
  d-2026-10-03T14-02-route-c3d4-3.b  stop here; hand the plan over
answer: /route2 --resume --unattended d-2026-10-03T14-02-route-c3d4-3.a
assumptions:
  - batch size 500, like the existing reindex job (easy to reverse)
```

## Scenario test

The test of the matrix. The inventory is the coverage baseline: every entry A1–A32 appears in at
least one scenario, in the **Covers** column. Each input states, in this order, the invocation
(task text and flags), the relevant policy, the checkpoint state and what is already authorized;
each expected outcome names the row and the inventory id, plus the precedence rule where several
rows apply. In the ids, `R` stands for the run id of the checkpoint and `T` for the attempt id of a
`pending-decision.md`; `s2` and `s3` are approved plan hashes. "State B" is the checkpoint of
scenario 17 (`d-R-3` open) plus a `pending-decision.md` `d-T-1` left by `/route2 --unattended add an
audit log page` (`.a continue`, `.b archive-and-start`, `refers_to` R).

| # | Input | Expected outcome | Covers |
| --- | --- | --- | --- |
| 1 | `/route2 --unattended --critc=astra add a CSV export of the invoices list` · policy: none · checkpoint: none · authorized: the export | validation stop, row 2 (a flag line is the authorization and is never guessed), A1. Only `.route2/`, its exclude entry and `pending-decision.md` are written — no schemas, no model call: `d-T-1` with `.a start: --critic=astra` (recommended), `.b start:` without a critic flag; `result: needs-decision` | A1 |
| 2 | `/route2 --setup --unattended split the billing module` · none · none · the split | illegal combination → validation stop as in 1 (A1); no setup question is asked (A4). `d-T-1`: `.a start:` with no flags (the rubric decides), its text advising to run `/route2 --setup …` first and reuse its line | A1, A4 |
| 3 | `/route2 --unattended dodaj eksport CSV, krytykuj astrą albo gemini` · none · none · the export | the plain words are ambiguous (one critic or both?) → validation stop, A2: `.a start: --critic=astra`, `.b start: --critic=gemini`, `.c start: --critic=astra,gemini` | A2 |
| 4 | `/route2 --unattended --model=opus --critic=fable add a tag filter to the posts list` · none; three families · none · the filter, built by opus | a named critic from the builder's family → row 2, A3; raised in stage 0 before any checkpoint, so recorded in `pending-decision.md`: `.a start: --model=opus --critic=sol` (recommended), `.b … --critic=gemini`, `.c start: --model=sol --critic=fable` | A3 |
| 5 | `/route2 --unattended --model=sol add rate limiting to the public API` · none; no fresh `sol` probe · none · the change, built by sol | the step 5 probe fails because **the client** does not know the model (Codex too old for the catalog it fetched — not an account denial, so no walk-down) → row 2, A5, never a substitute: `.a start: --model=sol` after upgrading Codex (the question carries the instruction), `.b start: --model=opus` | A5 |
| 6 | `/route2 --unattended --cascade --model=opus add CRUD screens for the tags dictionary` · none; Claude and OpenAI only · none · cascade, opus | Luna (OpenAI) drafts, Opus (Claude) implements, no third family → row 2, A6: `.a start: --model=opus` (drop the cascade, recommended), `.b start: --cascade=haiku --model=opus` (critic `sol`) | A6 |
| 7 | `/route2 --unattended --model=opus tidy the settings page` · `deny: [fable, sonnet, haiku]`; Claude only · none · the tidy-up, by opus | no eligible Claude critic → row 2, A7: `.a start: --model=opus --critic=fable` (a named critic beats the deny, with a warning), `.b start: --model=fable` (Opus critiques) | A7 |
| 8 | `/route2 --unattended --model=sonnet add a factory for invoices` · repo `critique_rounds: 12` · none · the factory | illegal policy → row 2, A8: `.a start: --model=sonnet`, to be answered once `route2.policy.yml` is corrected — the director never edits policy | A8 |
| 9 | `/route2 --unattended --model=gemini regenerate the API docs` · none; `agy` not installed · none · the docs, by gemini | `--model` names an unavailable family → row 2, A9: `.a start: --model=sol`, `.b start: --model=sonnet` | A9 |
| 10 | `/route2 --unattended --model=sonnet add a CSV export of the invoices list` · none · none · the export; delimiter, file name and test scope not stated | no stop. Row 1 → `## Assumptions (unattended)`: `;` like the existing payments export, `invoices-<date>.csv`, both easy to reverse; test scope `covering` (the full suite would still run for shared reach). Committed; `result: done` with the assumptions | A10 |
| 11 | `/route2 --unattended add a password reset by e-mail link` · none; three families · none · the reset — a high-stakes change asked for explicitly | proceeds: rubric row 1 (`fable`), critics `astra` + `gemini`; the assignment line and the report recommend `--review`, nothing is added (A12); the e-mail wording is a row 1 assumption (A10) | A10, A12 |
| 12 | `/route2 --unattended delete customer accounts inactive for 12 months` · none · none · the deletion; what happens to their invoices is not stated | a high-stakes decision left open (existing data) → row 2, A10: stop at the interview, `d-R-1` in the checkpoint (`stage: interview`): `.a` keep the invoices and anonymise the customer, `.b` delete them with the account, `.c` stop. The batch size, a row 1 gap, is recorded as an assumption, but the stop wins (2 > 1) | A10 |
| 13 | run of 10 at `stage: build` · none · the builder `sonnet` ends with "Which date format for `issued_at`?" · the export | row 1, A11: the director answers from the spec and the repository (ISO 8601, like the existing exports) as a new prompt to the thread and records the assumption; no stop | A11 |
| 14 | run of 10 at `stage: build` · none · the builder ends with "Should the export include customers who opted out of data processing?" · the export | who may see what data is a high-stakes decision left open → row 2, A11: no new prompt; the turn's changes go through dirty-exit, nothing is committed; `d-R-2` in the checkpoint — a decision, not a `question` blocker | A11, A16b |
| 15 | `/route2 --unattended --model=sol add an invoice archive view` · none · `stage: build` · the view; Sol's `## Assumptions` says "dropped the unused `legacy_notes` column" | a migration that drops existing data, not asked for → row 2, A11. Dirty-exit keeps that outcome (A16b): `git status`, `git diff`, the change kept or reset deliberately and recorded in `tree_state`, nothing committed; `d-R-2` in the checkpoint; never row 5 | A11, A16b |
| 16 | `/route2 --unattended --model=sol migrate the reporting job to a queue` · none · `stage: build` · the migration; Sol declines one section as out of scope (an ordinary decline) | A18 unchanged: one rewritten brief; declined again → reroute to `opus`, with critics, reviewer and probes re-checked as for a swap; no stop, no decision | A18 |
| 17 | `/route2 --unattended --model=opus --rounds=2 add bulk tagging of posts` · none · `stage: critique`, after round 2 Sol still reports one major finding · bulk tagging | row 3, A13: no build; `d-R-3` in the checkpoint: `.a` one more critique round (`changes_config: rounds=3`, recommended), `.b` stop and hand the plan over; `result: needs-decision` | A13 |
| 18 | `/route2 --unattended --model=opus --critic=astra add bulk tagging of posts` · none · `stage: critique`, round 1 · bulk tagging; Astra returns `reject` | row 3, A13, at once — no round 2; `d-R-1` in the checkpoint | A13 |
| 19 | run `R` of `--unattended --model=sonnet --review=cross` (critic and reviewer `sol` by default) · none · `stage: fix`, after fix round 3 the reviewer still reports a major finding · the task | row 4, A14: `d-R-5`: `.a` one more fix round (`changes_config: fix_cap=4`), `.b` one more fix round by `astra` instead (`changes_config: model=astra, fix_cap=4`), `.c` stop and hand the diagnosis over (`changes_config` empty). Every option that leads to another fix turn carries the `fix_cap` increase; the checkpoint keeps `fix_cap: 3` until one is answered | A14 |
| 20 | `/route2 --unattended --plan-only --critic=astra split the billing module` · none · none · a plan only; approved in round 2 | not a stop, A15: checkpoint `stage: report`, `plan_only: true`, `plan_sha256`; `result: plan-only` with the plan and the assumptions | A15 |
| 21 | `/route2 --unattended --model=sol add a CSV import of products` · none · `stage: build`, the Sol thread recorded · the import; Sol hits the OpenAI usage limit | row 5, A16a, exactly as today: dirty-exit, checkpoint with `blockers: [{kind: quota, …}]`, stop, `result: stopped`; no swap to another family (A17: limits). Later `/route2 --resume --unattended` with no answer, limits recovered: re-probe, continue the thread by UUID — no decision involved | A16a, A17 |
| 22 | run of 21 · none · `stage: build` · `codex exec` fails with a transient 503 | A18 unchanged: the worker continues by thread UUID as today; no stop, no decision | A18 |
| 23 | `/route2 --unattended --model=astra harden the upload validator` · none · `stage: build` · the change; the turn ends with `misalignment_policy_violation` | row 5, A16a: stop dispatch, keep checkpoint and `.jsonl`, inspect the tree, report (`result: stopped`), blocker `safety-pause`; never a decision. A later `--resume --unattended` does not retry the refused turn: it reports the blocker and stops again | A16a |
| 24 | run of 21 · none · `stage: build` · Sol's turn ends with a question asking to change the shared `Money` class the task does not mention (row 2, scope), and the same turn reports the usage limit (row 5) | 5 > 2: the run stops under row 5 exactly as today (quota blocker, `result: stopped`); the scope question is still recorded as `decisions.current` `d-R-4` with `row: 2, also_rows: [5]`, and the blocker's `detail` names it | A16a, A11 |
| 25 | checkpoint of 24 (quota blocker and `d-R-4`) · `/route2 --resume --unattended`, no answer, limits recovered · authorized: nothing new | the quota is re-probed only (a check, reported, not written); `d-R-4` is unanswered → stop again, `result: needs-decision`, nothing written, no model call | A16a, A11 |
| 26 | `/route2 --unattended --model=sol add a CSV import of products` · none · `stage: build`; the host running the Codex worker crashed · the import | A16b recovery, no stop: dirty-exit (changes inspected, kept or reset, recorded), then the thread continues by UUID or the worker is swapped for the crashed host as today (A17), a plan critic now in the builder's family replaced by one critique round of an eligible cross-family critic | A16b, A17 |
| 27 | run `R` at `stage: review` · none · `config/app.php` changed and no recorded worker session touched it; `/route2 --resume --unattended` · the task | the tree differs from `tree` → dirty-exit; the change cannot be attributed to a known worker → row 2, A16b: `d-R-6` in the checkpoint (`.a` keep it and continue, `.b` reset that file and continue, `.c` stop); no review is dispatched | A16b |
| 28 | `/route2 --unattended --cascade --model=sonnet add CRUD screens for the tags dictionary` · none; three families · `stage: draft` · the screens; Luna ends with `DRAFT_ABORT: authority: may deleting a tag detach it from existing posts?` | row 2, A21, no escalation: `draft.diff` kept, the draft stashed as `route-draft-R` (step 7's tree handling), `d-R-2` in the checkpoint at `stage: draft` | A21 |
| 29 | as 28 · Luna ends with `DRAFT_ABORT: context_limit` | capability or context → escalation to `sonnet` as `docs/cascade.md` step 7 says; no stop | A21 |
| 30 | checkpoint of 17 · `/route2 --resume --unattended`, no answer | the same stop again: nothing written, no model call; the report repeats `d-R-3` with its options | A13 |
| 31 | checkpoint of 17 · `/route2 --resume` (attended) | the director asks `d-R-3` with its recorded options (`AskUserQuestion`); the reply is handled as in 32; `modes` gains an attended session | A13 |
| 32 | checkpoint of 17 · `/route2 --resume --unattended d-R-3.a` | a checkpoint decision, so no `refers_to`; `rounds=3` is valid (1–8, families unchanged) → `answer` recorded, `d-R-3` to `history`, `flags` get `--rounds=3` with `flag_sources` `d-R-3`; critique round 3 runs — the cap moved only through this option | A13 |
| 33 | checkpoint of 17 · `/route2 --resume --unattended d-R-3.c` | `c` matches no option → stop again, nothing changes; the report repeats the question | A13 |
| 34 | `pending-decision.md` of 1, no checkpoint · `/route2 --resume --unattended d-T-1.a` | `start: --critic=astra` validated (flags, policy, family rule, probes) → the attempted task starts as a new unattended run (`flag_sources` `d-T-1`); `pending-decision.md` is deleted once the run's first checkpoint is written | A1 |
| 35 | checkpoint `R` at `stage: report`, tasks F2 and F3 `planned` (`s2`, `s3`) · `/route2 --unattended add an audit log page` · authorized: the audit log page | a new task over an unfinished run → stop, A19, in `pending-decision.md` (`d-T-1`, `refers_to` R): `.a build: F2 s2`, `.b build: F3 s3`, `.c archive-and-start`; the checkpoint is untouched | A19, A20 |
| 36 | checkpoint of 35, no pending file · `/route2 --resume --unattended`, then `/route2 --resume --unattended d-T-1.b` | two candidates → `d-T-1` in `pending-decision.md` (`.a build: F2 s2`, `.b build: F3 s3`), stop, no task selected. The answer: F3 exists, is still `planned`, its plan hashes to `s3` → build F3 with its recorded flags minus `--plan-only`; the approval stands; the file is deleted | A19, A20 |
| 37 | as 36, but F3's plan file was edited after approval · answer `d-T-1.b` | the `build` check fails → failed validation: `d-T-1` to `history` with its answer and `failed_rule: plan_sha256`; new `current` `d-T-2` in the same file: `.a build: F3 <new sha>` (the approval no longer stands: one critique round first), `.b build: F2 s2`; stop | A19, A20 |
| 38 | `pending-decision.md` of 37; now Claude only; `deny: [fable, sonnet, haiku]`; F3 recorded `--model=opus` · answer `d-T-2.a` | re-approval needs a critic and none is eligible → row 2, A20 (as A7): failed validation, `d-T-2` to `history`; new `current` `d-T-3`: `.a build: F3 <new sha>` with `changes_config: critic=fable`, `.b build: F2 s2`; stop | A20, A7 |
| 39 | checkpoint at `stage: build` for F1 (`in_progress`), F2 `queued` · `/route2 --resume --unattended` | the active run is the only candidate → `continue`, no decision; F2 waits | A19 |
| 40 | checkpoint at `stage: report`, `plan_only: true`, `current_task: F3`, F3 `planned` `s3`, plan unchanged · `/route2 --resume --unattended` | one candidate (deduplicated by task id) → `--resume` is the authorization: build F3, the approval stands; no decision | A20 |
| 41 | checkpoint at `stage: report`, F1 `done`, F2 `queued` without a plan · `/route2 --resume --unattended` | one candidate, `start: F2`: exists, still `queued`, next in order — no hash check; F2 starts as a new unattended run with its recorded flags | A19 |
| 42 | state B · `/route2 --resume --unattended a`, or `… d-R-3.a` | rejected either way: a bare letter with two unresolved decisions binds to neither, and `d-R-3` is not the first unresolved decision → stop again on `d-T-1` (first in the order); nothing written, `d-R-3` untouched | A19, A13 |
| 43 | state B · `/route2 --resume --unattended d-T-1.a`, then, in a separate invocation, `/route2 --resume --unattended d-R-3.a` | the first answer names the first unresolved decision: the identity check passes (R unchanged), `d-T-1` is consumed (`continue`) and `pending-decision.md` deleted; `d-R-3` is still open and unanswered → stop again on it, nothing dispatched. The second invocation consumes `d-R-3` as in 32: `rounds=3` written, critique round 3 runs | A19, A13 |
| 44 | `pending-decision.md` `d-T-1` (`refers_to` R at `written_at` W1); an attended session has since continued R (W2) · `/route2 --resume --unattended d-T-1.a` | identity mismatch → failed validation: `d-T-1` to `history` with `failed_rule: refers_to`; new `current` `d-T-2` referring to the checkpoint as it is now (`.a continue`, `.b archive-and-start`); the checkpoint untouched; stop | A19 |
| 45 | `/route2 --unattended --modle=sonnet --cascade add a factory for invoices` · repo `families: {openai: off}`, `cascade_drafter: luna` · none · the factory | validation stop `d-T-1` (`.a start: --model=sonnet --cascade`). `… --resume --unattended d-T-1.a` → policy fails (the effective drafter is in a family switched off, A8) → `d-T-1` to `history` with `failed_rule: policy`; new `current` `d-T-2`: `.a start: --model=sonnet --cascade=haiku`, `.b start: --model=sonnet`; stop. Then `… d-T-2.a` → valid → the run starts and the file is deleted | A1, A8 |
| 46 | checkpoint of 19 (`d-R-5` open, `fix_cap: 3`; the plan approved by `sol`) · `/route2 --resume --unattended d-R-5.b` (`model=astra, fix_cap=4`) | validated before the decision is cleared: `fix_cap=4` is above the 3 fix rounds run; critic and reviewer `sol` now share the builder's family → reviewer `opus`, and one critique round of the current plan by an eligible cross-family critic before Astra's first turn; step 5 probe for `astra`, step 8 reach probe (Astra writes). All pass → `flags` get `--model=astra` and the checkpoint `fix_cap: 4` (`flag_sources` `d-R-5` for both), the critique round runs, then Astra gets the brief plus the current `git diff` for fix round 4 — the last one `fix_cap` allows | A14, A17 |
| 47 | as 46, but the run named `--critic=sol` · answer `d-R-5.b` | a named critic from the new builder's family (A3) → failed validation: `d-R-5` to `history` with `failed_rule: cross-family (named critic)`; `fix_cap` stays 3. New `current` `d-R-6` in the checkpoint's `decisions`: `.a model=astra, critic=opus, fix_cap=4`, `.b model=astra, critic=gemini, fix_cap=4`, `.c` one more fix round with `sonnet` (`fix_cap=4`), `.d` stop and hand the diagnosis over; stop | A3, A14 |
| 48 | `/route2 --unattended --model=opus add audit fields to orders` in Codex as host · none · `stage: build`, `opus@native` (`claude -p`) mid-build · the change | `claude -p` ends with Claude's quota error after editing two files; agy serves `claude-opus-5-5` (the frozen id) → transport switch, no stop: termination confirmed, dirty-exit keeps the edits, a fresh edits-only brief with the diff goes to `agy --model claude-opus-5-5-medium`, ledger `transport-switch`; critics unchanged (same family) | A16a |
| 49 | as 48, but `transports: {deny: [opus@agy]}` and Cursor's Claude quota exhausted | no eligible next transport → row 5, A16a, exactly as a quota stop today | A16a, A17 |
| 50 | `claude -p "/route2 --model=sonnet fix the typo in the footer"` (headless, no `--unattended`) | validation stop, A22: nobody can answer; the remedy names `--unattended` | A22 |
| 51 | `/route2 --unattended …` launched from a nested setup where both `CODEX_THREAD_ID` and `CLAUDECODE` are set and the ancestry is hidden | `route2-host` says `unknown` → row 2, A23; the decision offers `--host=codex` and `--host=claude-code` | A23 |
| 52 | `--resume --unattended` of a run started in Claude Code, now invoked from Codex | host changed → row 2, A24 (adapter, `self`, critics to re-check) | A24 |
| 53 | `/route2 --unattended --model=opus …` in Codex without `danger-full-access` | step 3a: model reach from the director's shell fails (network) → row 2, A25, remedy "start Codex with `--sandbox danger-full-access`" | A25 |
| 54 | `/route2 --unattended …` while another director holds the checkout's lock (live pid) | row 2, A26 | A26 |
| 55 | `--resume --unattended` where a previous Cursor builder left a process `route2-kill` cannot end | `result: blocked`, lock kept, members listed — not a decision, A27 | A27 |
| 56 | `/route2 --unattended --model=gemini …` with `families: {claude: off, openai: off, xai: off}` | one eligible family with one line → row 2, A28 | A28 |
| 57 | `/route2 --unattended --model=sol …` · the catalog lists `gpt-6.2-sol`, its probe says the account cannot use it; `gpt-6.1-sol` passes | row 1, A29: `sol=gpt-6.1-sol (gpt-6.2-sol listed, denied for this account)` recorded as an assumption; the run continues | A29 |
| 58 | `/route2 --unattended --critic=grok …` · Grok's verdict has two JSON objects, and again after the re-ask | named critic → row 2, A30 | A30 |
| 59 | `/route2 --unattended --model=grok …` · `agent --list-models` fails (signed out) | the cursor transport is ineligible and a flag needs it → row 2, A31 (as A9) | A31 |
| 60 | `/route2 --unattended fix the typo in the footer` in Cursor (director model unknown) with `families: {claude: off, openai: off, google: off}` and Grok's quota exhausted | rubric row 6: `self` ineligible, no fallback eligible → row 2, A32 | A32 |

The cross-family reviewer checks three things:

- every inventory entry has an outcome and at least one scenario;
- every scenario resolves to exactly one outcome under the precedence rule;
- no source line in the inventory search is missing from the table.

The route-bench F3 route canary is the behavioural test. This repository has no harness.
