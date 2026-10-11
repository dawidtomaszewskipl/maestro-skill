# Setup

`--setup` replaces remembering flags with a short questionnaire. The director reads the prompt,
recommends a configuration from what the task is, and asks. The answer is a flag line the user can
reuse next time.

**Not with `--unattended`.** Setup is a questionnaire, and an unattended run has nobody to answer
it, so `--setup --unattended` is an illegal combination — a validation stop before any question
(`docs/unattended.md`, A1 and A4). Run setup first, then reuse its flag line with `--unattended`.

## Reading the input

- **The task text** after the flags are stripped.
- **A plan, if there is one:** a pasted result of Claude Code's `/plan`, a path to a plan file, or an
  existing `.route2/PLAN.md`. A plan changes the recommendations: its steps are the tasks, and a plan
  that is already settled lowers the value of extra critique rounds.
- **Several tasks** ("zrób A, potem B", a numbered list, plan phases) are listed separately, each with:

| Fact | How it is judged | What it drives |
| --- | --- | --- |
| Stakes | high stakes as SKILL.md defines it (under "Flags") | rubric row 1, Astra as critic, second critic, `--review`, no cascade |
| User-facing UI | views, components, layout, styles | `opus`, visual check, `browser` |
| Rubric row | SKILL.md "Roster", evaluated in order — stakes first | implementer |
| Test footprint | which suites cover the touched code; browser tests present? shared reach? | `--tests` |
| Size | files and subsystems touched | `sol`/`gemini`/`grok` for large self-contained work (grok provisional), `self` for tiny — only when the director's model line is known |
| Plan maturity | settled plan vs. an idea | rounds, `--plan-only` |

## Questions

Setup runs after stage 0 steps 0–4a, so it knows the host, which families and transports are
eligible, what the catalogs list and what policy says; it makes no model call. A slot without a
fresh probe in `.route2/model-probes.json` is offered
marked "not probed yet"; stage 0 step 5 then probes the slots the answers chose, and a failed probe
asks that role again. Setup asks with the host's question tool in steps, because later options depend on
earlier answers: the grouping decides what a run is, the mode and implementer decide which critics
are cross-family and whether review is legal. The question tool (`AskUserQuestion` in Claude Code; `request_user_input`, `ask_question` or a plain
question elsewhere — `docs/hosts.md`) takes at most 4 questions per call and 2–4
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
| Mode and implementer (`Wykonawca`) | up to four valid pairs, e.g. "full run · opus", "full run · sol", "full run · grok (provisional)", "cascade · luna drafts, sonnet escalates", "plan only · opus later"; a transport other than the first eligible one as `opus@agy` | the rubric row for the run; cascade only for large mechanical work that is not high-stakes and whose family rule can be met; plan-only when the prompt asks for a plan or the task is an idea |

**Step 2 — per run, computed from step 1**

| Question (header) | Options, recommended first | Recommended when |
| --- | --- | --- |
| Critic (`Krytyk`) | cross-family default · `astra` · `gemini` · `grok` · two or three critics | only families other than the builder's (both possible builders' under cascade; `route2-roles` gives the default); `astra` + a third family for high stakes; grok is offered marked provisional |
| Rounds (`Rundy`) | 2 · 1 · 4 | 1 for a settled plan; 4 for a design-heavy or high-stakes plan |
| Review (`Review`) — not asked under plan-only | none · `cross` · `full` · `self` | `cross` or `full` for high stakes; none for mechanical work |
| Tests (`Testy`) | `covering` · `covering,browser` · `full` · `full,browser` | `browser` when the run changes a flow a browser suite covers; `full` for shared reach (SKILL.md "Test scope"); skipping tests is not an option — the user can still type it into "Other", and it is illegal under cascade |

Each option's description says why, in one line tied to the task: "money + concurrency → hard
correctness", "3 Blade views + a modal → UI, screenshots decide". Use the `preview` field when two
options differ in a way a short flag line shows best.

**Budget:** step 0 once, then steps 1 and 2 per run — at most three calls per run. With separate
runs, a step-2 question whose recommendation is the same for every run is asked once for all.
Anything left unanswered takes the recommended option, and the flag line says so.

## Output

```
Setup: /route2 --model=opus --critic=astra,gemini,grok --rounds=2 --review=cross --tests=covering <task>
Assign: implementer=opus (user, setup; rubric: UI) · critic=astra (user, setup) · …
```

Every answer maps to a flag, so the line is complete and reusable. Separate runs: one line per task,
in order, stored in the checkpoint as `tasks` with `current_task`, each with its own plan in
`.route2/tasks/<id>/PLAN.md`; the first run starts, and each
next one starts after the previous one's report — `--resume` at `stage: report` picks up the next
queued task (one writer at a time).
