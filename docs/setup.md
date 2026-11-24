# Setup

> **What this page is for.** The questionnaire behind `--setup`: what the director reads, which questions it asks and in what order. The plain overview is in [the guide](guide/how-it-works.md#what-you-are-asked-and-when).

`--setup` replaces remembering flags with a short questionnaire. The director reads the prompt,
recommends a configuration from what the task is, and asks. The answer is a flag line the user can
reuse next time.

**Not with `--unattended`.** Setup is a questionnaire, and an unattended run has nobody to answer
it, so `--setup --unattended` is an illegal combination — a validation stop before any question
(`docs/unattended.md`, A1 and A4). Run setup first, then reuse its flag line with `--unattended`.

## Reading the input

- **The task text** after the flags are stripped.
- **A plan, if there is one:** a pasted result of Claude Code's `/plan`, a path to a plan file, or an
  existing `.maestro/PLAN.md`. A plan changes the recommendations: its steps are the tasks, and a plan
  that is already settled lowers the value of extra critique rounds.
- **Several tasks** ("zrób A, potem B", a numbered list, plan phases) are listed separately, each with:

| Fact | How it is judged | What it drives |
| --- | --- | --- |
| Stakes | high stakes as SKILL.md defines it (under "Flags") | rubric row 1, Astra as critic, second critic, `--review`, no cascade |
| User-facing UI | views, components, layout, styles | `opus`, visual check, `browser` |
| Rubric row | SKILL.md "Roster", evaluated in order — stakes first | implementer |
| Test footprint | which suites cover the touched code; browser tests present? shared reach? | `--tests` |
| Size | files and subsystems touched | `sol`/`hydrogen` for large self-contained work, `self` for tiny |
| Plan maturity | settled plan vs. an idea | rounds, `--plan-only` |

## Questions

Setup runs after stage 0 steps 0–4a, so it knows whether Claude Code runs interactively, which families and transports are
eligible, what the catalogs list and what policy says; it makes no model call. A slot without a
fresh probe in `.maestro/model-probes.json` is offered
marked "not probed yet"; stage 0 step 5 then probes the slots the answers chose, and a failed probe
asks that role again. Setup asks with Claude Code's question tool in steps, because later options depend on
earlier answers: the grouping decides what a run is, the mode and implementer decide which critics
are cross-family and whether review is legal. The question tool (`AskUserQuestion`) takes at most 4 questions per call and 2–4
options per question, plus an automatic "Other" where the user can type anything — so offer the four
options that matter most for the task, and leave the rest to "Other".

**Policy values are defaults, not answers.** Show them — "opus (policy default)" — and when the
rubric recommends something else for this task, make the rubric's pick the recommended option and
say why. Skip only questions that flags or the user's own words already answered, and questions with
a single eligible option. Every option offered must be legal together with the answers already
given.

**Step 0 — grouping (only with several tasks)**

| Question (header) | Options, recommended first | Recommended when |
| --- | --- | --- |
| Tasks (`Zadania`) | separate runs in sequence · one run · only the first task now | separate when the tasks share no files; one run when one needs the other |

**Step 1 — per run: mode and implementer as one choice**

| Question (header) | Options, recommended first | Recommended when |
| --- | --- | --- |
| Mode and implementer (`Wykonawca`) | up to four valid pairs, e.g. "full run · opus", "full run · sol", "full run · hydrogen", "cascade · luna drafts, sonnet escalates", "plan only · opus later"; a transport other than the first eligible one as `opus@agy` | the rubric row for the run; cascade only for large mechanical work that is not high-stakes and whose family rule can be met; plan-only when the prompt asks for a plan or the task is an idea |

**Step 1b — per run, the advisor (its own call, after step 1 is answered)**

Asked only when the user's words did not mention an advisor, no `--advisor` flag was given, and step
1's answer is a full run with an external implementer — never for `self`, plan-only or cascade,
where `--advisor` is illegal or off.

| Question (header) | Options, recommended first | Recommended when |
| --- | --- | --- |
| Advisor (`Doradca`) | `none` · then either the policy advisor or `auto` · then named slots — four options in all; the rest through "Other" | **always `none`**: the rubric has no advisor row and the ledger no evidence, so an unanswered question never enables one |

What each option means, and the flag it writes — the option picked must be what the flag line
selects:

- `none` → no flag.
- **First resolve the policy preference against the setup roster**, before building the options:
  `maestro-policy roles-input --flags "$(maestro-flags --advisor …)"` (the step-1 answers plus a bare
  `--advisor`), then `maestro-roles` with `advisor_on: true`, its `policy_advisor`, the step-1
  builder and stakes, and the real `eligible` and `available` lists of stage 0. `effective.advisor`
  of `maestro-policy resolve` is only the preference; the roles result decides.
- **The policy slot survives** (`advisor` equals the policy slot, the note `advisor=<slot>
  (policy)`): a bare `--advisor` would resolve to it, not to automatic choice, so it is offered by
  name with its family — "opus (policy, Claude; the builder's family)" — and writes
  `--advisor=<slot>`. `auto` is **not offered** then: no flag line could select it.
- **The policy slot drops out** — policy-denied or switched off (`roles-input` gives
  `policy_advisor: null` and a warning), or not available this run (the note `policy advisor <slot>
  is not available: auto`): it is **not** offered, since `--advisor=<slot>` would halt the run.
  `auto` is offered with a bare `--advisor`, its description saying why the policy one dropped out
  — "auto: a slot of another family, avoiding the reviewer's family if you choose a review (policy
  sol unavailable: Codex signed out)".
- **No policy `advisor`**: `auto` — "a slot of another family, chosen by `maestro-roles`, avoiding
  the reviewer's family if you choose a review" — writes a bare `--advisor`.
- **`auto` never promises a slot.** Which slot it picks depends on `review_active`, which step 2
  decides: with Opus building, Sol denied and Astra and Argon eligible, auto is Astra without a
  review and Argon once `cross` makes Astra the reviewer. After step 2, run `maestro-roles` again
  with `review_active` known and **name the resolved slot** in the flag line's explanation and the
  Assign line (`advisor=argon (auto; reviewer astra)`).
- **Avoiding the reviewer's family is a preference**, applied only when another eligible
  cross-family slot exists. With Opus building and Astra the only eligible cross-family slot, a
  `cross` review makes Astra both the reviewer and the advisor: `maestro-roles` says so with
  `advisor and reviewer share a family` and the warning `reviewer anchored: the advisor shaped the
  build`. Say this in the `auto` option's description when the roster already shows a single
  candidate, and keep the resolved slot and the warning in the Assign line after step 2
  (`advisor=astra (auto; reviewer astra — anchored)`).
- **Named slots** (one or two, to make four options) come from families other than the step-1
  implementer's and write `--advisor=<slot>`; a same-family slot only when typed into "Other", and
  the Assign line notes it.

**Step 2 — per run, computed from step 1**

| Question (header) | Options, recommended first | Recommended when |
| --- | --- | --- |
| Critic (`Krytyk`) | cross-family default · `astra` · `argon` · `hydrogen` · two critics | only families other than the builder's (both possible builders' under cascade; `maestro-roles` gives the default); `astra` + the third family for high stakes; argon is offered marked provisional. `carbon` and `neon` are never offered as a recommendation (explicit-only, unmeasured); a user who types one into "Other" gets it, marked provisional |
| Rounds (`Rundy`) | 2 · 1 · 4 | 1 for a settled plan; 4 for a design-heavy or high-stakes plan |
| Review (`Review`) — not asked under plan-only | none · `cross` · `full` · `self` | `cross` or `full` for high stakes; none for mechanical work |
| Tests (`Testy`) | `covering` · `covering,browser` · `full` · `full,browser` | `browser` when the run changes a flow a browser suite covers; `full` for shared reach (SKILL.md "Test scope"); skipping tests is not an option — the user can still type it into "Other", and it is illegal under cascade |

Each option's description says why, in one line tied to the task: "money + concurrency → hard
correctness", "3 Blade views + a modal → UI, screenshots decide". Use the `preview` field when two
options differ in a way a short flag line shows best.

**Budget:** step 0 once, then steps 1, 1b and 2 per run — at most four calls per run, the fourth
only when step 1b applies; step 2 keeps its four questions. With separate runs, a step-2 question
whose recommendation is the same for every run is asked once for all.
Anything left unanswered takes the recommended option, and the flag line says so.

## Output

```
Setup: /maestro --model=opus --critic=astra,argon --rounds=2 --review=cross --tests=covering [--advisor[=<slot>]] <task>
Assign: implementer=opus (user, setup; rubric: UI) · critic=astra (user, setup) · …
```

Every answer maps to a flag, so the line is complete and reusable. Separate runs: one line per task,
in order, stored in the checkpoint as `tasks` with `current_task`, each with its own plan in
`.maestro/tasks/<id>/PLAN.md`; the first run starts, and each
next one starts after the previous one's report — `--resume` at `stage: report` picks up the next
queued task (one writer at a time).
