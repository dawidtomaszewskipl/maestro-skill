# Briefs

*What this page is for: the fixed text every worker brief carries. Read it before the first brief
of a run (SKILL.md, "Briefs" has the rules about content). `bin/maestro-brief` prints these blocks
(`open`, `close`, `rubric`); T12 checks that its text and this page agree word for word.*

## Closing blocks (verbatim)

Every brief ends with:

> Do not ask questions. Where the brief is silent, decide and record each assumption — in the
> `assumptions` field when a JSON schema was given, otherwise under a `## Assumptions` heading. Do
> not commit. Do not write outside the boundaries or into `.maestro/`.

Then, by role and transport:

| Worker | Adds |
| --- | --- |
| A builder that runs tests (Agent tool, Codex) | *"Run test commands without a `timeout` wrapper and never kill them; if your shell caps foreground execution, run any test that can take more than a few minutes in the background and wait for it."* |
| An edits-only builder (agy, `claude -p`, `api`) | *"Do not execute shell or terminal commands; edit files only — the director runs the tests."* |
| A worktree writer (a split, `docs/worktrees.md`) | *"Do not run tests; the director will."* — and every path relative to the worktree root |
| A `claude -p` or `api` critic, gate or reviewer with no schema flag on its line | the schema quoted, and *"Your final message must be the JSON object only."* |
| A builder or fix brief under `--advisor` with checkpoints left | the advisor block below, `<N>` = the checkpoints left (`maestro-brief close … --advisor-checkpoints <N>`); none left → no block |
| Any brief under `--unattended` | after the closing block: *"If the brief is silent on authorization, budget, scope or a high-stakes decision, do not decide it: stop, leave the tree as it is, and end your answer with the question."* |

### Advisor block (verbatim, builder and fix briefs under `--advisor`)

The one exception to the closing block's "Do not ask questions" (SKILL.md, "Advisor"). A builder on
an edits-only transport gets the same block.

> Advisor checkpoints, the one exception to "Do not ask questions" (requests left: <N>): you may
> ask a read-only advisor model for guidance, and only
> - after reading the code and choosing an approach, before your first edit, or
> - when you are blocked on a design choice the plan leaves open.
> To ask, end your answer with a line `ADVICE_REQUEST`, then the question, the options you see and
> what you already tried (at most 1500 characters), then a line `END_ADVICE_REQUEST`. Edit nothing
> further and stop: the director answers, or resumes you with the advice. Advice is not binding;
> the approved plan and the spec win. Never write into `.maestro/`.

## Plan critique

Three fixed blocks: the rubric in every critique brief, the delta block from round 2, the arbiter
brief at the cap. The mechanical decisions are `maestro-validate --decide` (`docs/commands.md`,
"Validating a verdict").

### Severity rubric (verbatim, every critique brief and the arbiter brief)

> Severity of a finding:
> - `blocking`: the plan cannot meet the spec, or it would cause damage (data loss, a security
>   hole, a broken build).
> - `major`: a defect reachable with an input or state the spec allows. It MUST name that input or
>   state.
> - Everything else is a note, not a finding.
>
> Every blocking and major finding carries a `trigger`: the concrete input or state, inside the
> spec, that triggers the defect. A defect with no such trigger — it needs an input the spec
> excludes, or a state the system cannot reach — is a note.

A critique brief adds, after the rubric:

> Notes go in `non_blocking_notes` and never block. `approve` only with `blocking_findings` and
> `major_findings` both empty; otherwise `revise`; `reject` only when no revision of this plan can
> meet the spec.

and in round 1: *"This is round 1: return `prior_findings` as an empty array."*

### Round 2 and later (verbatim)

Instead of the round-1 line:

> This is round <N>. The plan was revised after round <N−1>. Your open findings from that round,
> each with the director's resolution:
>
> - `<id>` (<blocking|major>) — <problem> · trigger: <trigger> · resolution: <fixed: what changed,
>   in which section | not changed: why>
>
> Return one `prior_findings` item per id above — every id once, no other id. `status` is
> `resolved` when the revision removes the defect, or the resolution shows it is not one (the
> trigger is outside what the spec allows, or the defect is not real); otherwise `not_resolved`.
> `note` says why in one sentence. Do not repeat a prior finding in `blocking_findings` or
> `major_findings`.
> Do not re-judge the whole plan. Report a new finding only if this revision introduced it — name
> the changed section in `section` — or if it is blocking, or if it is a major you missed before
> whose `trigger` the spec allows — start its `problem` with "missed earlier:". Anything else you
> notice now goes in `non_blocking_notes`.
> `approve` only when every prior finding is `resolved` and both finding arrays are empty.

- **Ids** are yours: `r<round>-<b|m><n>` — the round that first reported the finding, `b` blocking
  or `m` major, numbered across all critics of that round (`r1-m1`, `r1-m2`, `r2-b1`). Unique in the
  run, never reused; a `not_resolved` finding keeps its id into the next round.
- **Open findings** of a critic: what it reported new in the previous round plus its prior findings
  still `not_resolved`. Each critic gets its own only. A critic with none (it approved) gets the
  block with *"none"* and returns `prior_findings: []`.
- **Resolution**: one line per finding — what you changed and where, or why you did not (the
  trigger is outside the spec, with the spec's words). Never silence.
- **Decision**: `maestro-validate <schema> <answer> --envelope … --decide critique --ids <the ids
  sent>` (`--ids ""` in round 1). The plan is approved when `decision.approved` is true for every
  required critic: verdict `approve`, both finding arrays empty, every prior finding `resolved`.
  `valid: false` at stage `decide` (an `approve` that still lists a finding or a `not_resolved`
  prior finding, an empty `trigger`, an id missing, unknown or doubled) is an invalid verdict like
  any other.

### Arbiter at the cap

One extra call that keeps a run from stopping over a finding nobody can trigger. It runs **only
when all hold** after the last round — `--unattended` included:

- the cap (`--rounds`) is reached without approval;
- only `major` findings remain: no critic's last verdict is `reject`, none lists a blocking finding
  or leaves a `-b` id `not_resolved`;
- the change is not high stakes;
- `maestro-roles --arbiter` names a slot: the first eligible one of a third family — not the
  builder's, not the drafter's (`--cascade`), not that of any critic still holding a finding.

Input `{builder, drafter, high_stakes, eligible, critics_with_findings, director_family}`; output
`{arbiter, reason, stop}`. `stop` not null → no arbiter: the stop below. Otherwise **one** call to
that slot — read-only, launched and proven like a critic (job role `arbiter`; a Codex arbiter's
`maestro-identity codex --role arbiter`, the read-only profile), at the critique
effort, `.maestro/arbiter-schema.json`, a new slot probed first (stage 0 step 5). The disputed findings
are every critic's `major_findings` of the last round (give them ids) and its `-m` ids still
`not_resolved`. The brief (verbatim; plan and spec embedded or as paths, as for a critic):

> You are the arbiter of a plan critique that reached its round cap. A critic from another model
> family still holds the major findings below; the planner disputes them. Rule on each finding and
> on nothing else: do not review the rest of the plan, do not raise new findings.
>
> <the severity rubric above, verbatim — the rubric block only>
>
> Spec: <the spec, whole>
> Plan: <PLAN.md, the current revision>
> Disputed findings:
> - `<id>` (critic <slot>) — <section> · <problem> · trigger: <trigger> · evidence: <evidence> ·
>   resolution: <the director's> · the critic's last note: <note, or "none">
>
> Return one `verdicts` item per id above — every id once, no other id — with `decision` and a
> one-sentence `reason` naming the part of the spec or the plan that decides it. Downgrade only
> when the trigger is outside what the spec allows or the defect is not real; otherwise uphold.

Decision: `maestro-validate .maestro/arbiter-schema.json <answer> --envelope … --decide arbiter
--ids <the disputed ids>`.

- **Every verdict `downgraded`** (`decision.approved`) → the plan is approved. The checkpoint's
  roster records the arbiter (slot, requested and served model); the report says *"approved by arbiter <slot> over
  <critic>'s majors"* and lists each downgraded finding with the arbiter's reason.
- **Any `upheld`**, an invalid answer or a failed call → today's stop (`--unattended`: row 3, A13),
  its question naming the upheld findings and the arbiter's reasons. No re-ask, no second arbiter,
  no extra round.

## Advisor brief

The advisor (SKILL.md, "Advisor") is a read-only role launched like that slot's critic
(`docs/commands.md`, "Advisor"). Its brief embeds the spec, the plan copy, the builder's request
(the text between `ADVICE_REQUEST` and `END_ADVICE_REQUEST`) and the restricted change, under 40 KB
together, else their paths; agy always gets the paths and reads them itself. Its inputs are
**protected briefing inputs** like a critic's: the brief, `.maestro/plan-advise-r<N>.md` and
`.maestro/diff-advise-r<N>.patch` sit directly in `.maestro/` (never in the excluded `tmp/`), all
written **before** the `maestro-fp snapshot`, so an advisor that edits the plan or the diff it is
asked about is caught by the comparison.

**It never sees a critic's or reviewer's verdict or finding.**

- **PLAN.md keeps every critique and verdict text under one exact heading, `## Critique record`**
  (the critique rounds, the verdicts, the arbiter's ruling), placed last in the file. The advisor
  gets a copy of PLAN.md with that section cut out — from its heading to the next `## ` heading or
  the end — written by you as `.maestro/plan-advise-r<N>.md`, embedded, or for agy given by its
  absolute path. Never the original PLAN.md.
- **The request is quoted from the `ADVICE_REQUEST` block only.** In a fix round the builder's
  request may quote the review it is fixing: every quoted finding, verdict or reviewer's or critic's
  text in it is replaced by *"[review text removed]"* before it goes into the brief; the builder's
  own question, options and attempts stay.
- **The change is restricted, then read by you.** No mechanical filter can find every quotation of
  review text in a diff, so the rule is conservative and ends with your own reading:
  1. The advisor-facing change is `git diff HEAD` **restricted to the implementation files the
     PLAN's Boundaries list**, excluding `CHANGELOG.md` and the `docs/**`-style record files that
     quote review text; untracked implementation files are appended as `git diff --no-index
     /dev/null <file>`. It is written to `.maestro/diff-advise-r<N>.patch` before the snapshot.
  2. **Before every advisor call — the initial build included — you read that patch before sending
     it** (a builder may copy a plan critic's finding into a test comment at any time) and remove any
     hunk that quotes a critic's or reviewer's text or names a finding — or withhold the whole file
     when the hunks cannot be separated from it.
  3. The brief then says *"CHANGELOG.md and quoted review text were withheld."*

  An embedded brief quotes that patch, a path-based brief (agy, or above 40 KB) points at it, never
  at `git diff` itself.

The brief opens with the agy paragraph when on agy (`maestro-brief open --role advisor`), ends with `maestro-brief close --role advisor …` (plus `--schema` for a `claude
-p` or `api` advisor without a schema flag), and its fixed text is (verbatim; the parts in angle
brackets are filled in):

> You are the advisor of a build in progress. The builder, a model working from the approved plan
> below, stopped to ask one question. Answer that question only, in at most 3000 characters: what
> you would do and why, the risks you see (at most 5) and at most 3 questions back. You are read-only:
> change nothing in the repository. Your advice is not binding and is not a review: do not
> judge the whole plan or the code, do not approve or reject anything, and do not change the scope,
> the boundaries or the plan. If the question needs a decision of the user (scope, data kept or
> deleted, permissions, money), say so in `questions_back` instead of deciding it.
>
> Spec: <the spec, whole>
> Plan: <the copy of PLAN.md without its `## Critique record` section>
> The builder's request: <the request, verbatim, with any quoted review text removed>
> The current change: <the restricted patch, or its path> CHANGELOG.md and quoted review text were withheld.

Validation: `maestro-validate .maestro/advice-schema.json <answer> --envelope …` (no `--decide`:
there is nothing to decide). One re-ask with the validator's errors; still invalid → the checkpoint
is skipped (`docs/unattended.md`, "Advisor").

The director forwards the triaged advice to the builder as a new prompt to its thread:

> ADVISORY, NOT BINDING — the approved plan and the spec win.
> 1. <item>
> 2. <item>
> Open: <a question back the director could not answer from the spec> — decide and record your
> assumption.

copied verbatim when nothing was removed, rewritten when something was; after a skipped checkpoint
the prompt is *"no advice available; decide and record your assumption"*. The resume carries the
advisor block again with the checkpoints now left, or without it when none are.

## agy critics, gates and reviewers

agy (Gemini and Claude-on-agy alike) **reads the repository itself**: its brief gives absolute
paths inside `$REPO` — the plan, the diff written to `.maestro/diff-<role>-r<N>.patch`, the
convention files, the code to judge — and quotes none of it. It can read only inside its
`--add-dir`: a path outside it is denied and empties the answer (measured 2026-10-12,
`docs/workers.md`). The brief **opens** with:

> You may read files inside <REPO> with your file tools (view a file, list a directory, search the
> repository). Do NOT run commands or terminal tools, do NOT call MCP servers, do NOT read anything
> outside <REPO>.

**Inline variant** — after a denied read (an envelope with `denied_actions`), a new conversation
with the whole brief in `-p`, every fact and convention quoted, opening with:

> This brief is self-contained. Do NOT call any tools: do not read files, do not run commands, do
> not call MCP, do not search the repository. Answer from the text below alone.

Above ~100 KB (the argv limit is ~128 KB) split it into parts, each a full brief for its slice.
Combined: approve only when every part approves; findings are the union; a gate or review part
also names the plan items its slice covers — combined `done` is the union and `missing` the plan
items no part reports done. Or give the role to another family.

## Re-review after a fix round

The reviewer gets only what changed since the state it last reviewed (`git diff <reviewed
state>`, written to `.maestro/diff-review-r<N>.patch`) plus its open findings, each with the
builder's fix — not the whole change again. It answers with the review schema; `plan_coverage`
covers the plan items the fix touched. The review stage is the costliest one in the ledger.

## Sizes

Codex and Claude critics, gates, reviewers and advisors get the plan and the diff embedded while
together they stay under 40 KB; above that, the paths. agy always gets paths (above).
