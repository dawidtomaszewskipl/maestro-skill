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
| Any brief under `--unattended` | after the closing block: *"If the brief is silent on authorization, budget, scope or a high-stakes decision, do not decide it: stop, leave the tree as it is, and end your answer with the question."* |

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

Codex and Claude critics, gates and reviewers get the plan and the diff embedded while together
they stay under 40 KB; above that, the paths. agy always gets paths (above).
