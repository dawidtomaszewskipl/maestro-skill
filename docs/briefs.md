# Briefs

*What this page is for: the fixed text every worker brief carries. Read it before the first brief
of a run (SKILL.md, "Briefs" has the rules about content).*

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

## Sizes

Codex and Claude critics, gates and reviewers get the plan and the diff embedded while together
they stay under 40 KB; above that, the paths. agy always gets paths (above).
