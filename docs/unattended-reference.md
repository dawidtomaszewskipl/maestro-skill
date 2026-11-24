# Unattended runs — reference

> **What this page is for.** How the ask-point inventory of `docs/unattended.md` was found, and the scenario test that checks the stop rules. Not needed during a run.

## Reproducing the search

```bash
grep -n -i -E "\bask|question|halt|confirm|hand(s|ed)? .{0,40}over|user's call|user picks" \
  SKILL.md $(ls docs/*.md | grep -v '/unattended.md$')    # from the repository root
```

The search was re-run over SKILL.md, `docs/hosts.md` and `docs/catalog.md` on 2026-10-11: the ask
points added then are A22–A32; the remaining hits are "confirm" in director checks (`docs/hosts.md`,
transport switch step 1), "Ask the user" (the adapter table) and the routing-precedence table's
halts (A8, A9, A16a).

A hit inside an `--unattended` pointer sentence of SKILL.md belongs to the entry that sentence
names. Every other hit is either in the table above or listed here as not an ask point:

| Hit | Why it is not an ask point |
| --- | --- |
| SKILL.md, the description | "explicitly asks for maestro" |
| SKILL.md "Flags" and "Setup" on `--setup` | `--setup` and its contract: A4, unreachable |
| SKILL.md "Roster", the rubric | "only when the user picks it": a routing preference, not a question |
| docs/setup.md:3–4, :28–71 | the setup questionnaire: A4, unreachable |
| docs/commands.md:29, :174, :212 | "confirmed cause", a brief that "asks for", "confirm what" a worker runs with — no user |
| docs/policy.md:27 | "because you asked" — explains a flag that beats a deny |
| docs/cascade.md:79 | `--resume` "after confirming" branch and `HEAD` — a director check |
| docs/checkpoint.md:60, :87 | the `question` blocker kind: A11 |
| docs/checkpoint.md:99–106, :169–174 | the decision record and the resume step this file defines |
| docs/checkpoint.md:182 | "after confirming" branch and `HEAD` — a director check |
| docs/workers.md:43, :144, :189 | "confirmed it", "unless asked", "without being asked" — about workers, not the user |
| docs/troubleshooting.md:7, :41, :50, :180–181 | incident write-ups ("confirmed", "asked how it is going", a gate that "asked for a revision") |


## Scenario test

The test of the matrix. The inventory is the coverage baseline: every entry A1–A32 appears in at
least one scenario, in the **Covers** column. Each input states, in this order, the invocation
(task text and flags), the relevant policy, the checkpoint state and what is already authorized;
each expected outcome names the row and the inventory id, plus the precedence rule where several
rows apply. In the ids, `R` stands for the run id of the checkpoint and `T` for the attempt id of a
`pending-decision.md`; `s2` and `s3` are approved plan hashes. "State B" is the checkpoint of
scenario 17 (`d-R-3` open) plus a `pending-decision.md` `d-T-1` left by `/maestro --unattended add an
audit log page` (`.a continue`, `.b archive-and-start`, `refers_to` R).

| # | Input | Expected outcome | Covers |
| --- | --- | --- | --- |
| 1 | `/maestro --unattended --critc=astra add a CSV export of the invoices list` · policy: none · checkpoint: none · authorized: the export | validation stop, row 2 (a flag line is the authorization and is never guessed), A1. Only `.maestro/`, its exclude entry and `pending-decision.md` are written — no schemas, no model call: `d-T-1` with `.a start: --critic=astra` (recommended), `.b start:` without a critic flag; `result: needs-decision` | A1 |
| 2 | `/maestro --setup --unattended split the billing module` · none · none · the split | illegal combination → validation stop as in 1 (A1); no setup question is asked (A4). `d-T-1`: `.a start:` with no flags (the rubric decides), its text advising to run `/maestro --setup …` first and reuse its line | A1, A4 |
| 3 | `/maestro --unattended dodaj eksport CSV, krytykuj astrą albo gemini` · none · none · the export | the plain words are ambiguous (one critic or both?) → validation stop, A2: `.a start: --critic=astra`, `.b start: --critic=gemini`, `.c start: --critic=astra,gemini` | A2 |
| 4 | `/maestro --unattended --model=opus --critic=fable add a tag filter to the posts list` · none; three families · none · the filter, built by opus | a named critic from the builder's family → row 2, A3; raised in stage 0 before any checkpoint, so recorded in `pending-decision.md`: `.a start: --model=opus --critic=sol` (recommended), `.b … --critic=gemini`, `.c start: --model=sol --critic=fable` | A3 |
| 5 | `/maestro --unattended --model=sol add rate limiting to the public API` · none; no fresh `sol` probe · none · the change, built by sol | the step 5 probe fails because **the client** does not know the model (Codex too old for the catalog it fetched — not an account denial, so no walk-down) → row 2, A5, never a substitute: `.a start: --model=sol` after upgrading Codex (the question carries the instruction), `.b start: --model=opus` | A5 |
| 6 | `/maestro --unattended --cascade --model=opus add CRUD screens for the tags dictionary` · none; Claude and OpenAI only · none · cascade, opus | Luna (OpenAI) drafts, Opus (Claude) implements, no third family → row 2, A6: `.a start: --model=opus` (drop the cascade, recommended), `.b start: --cascade=haiku --model=opus` (critic `sol`) | A6 |
| 7 | `/maestro --unattended --model=opus tidy the settings page` · `deny: [fable, sonnet, haiku]`; Claude only · none · the tidy-up, by opus | no eligible Claude critic → row 2, A7: `.a start: --model=opus --critic=fable` (a named critic beats the deny, with a warning), `.b start: --model=fable` (Opus critiques) | A7 |
| 8 | `/maestro --unattended --model=sonnet add a factory for invoices` · repo `critique_rounds = 12` · none · the factory | illegal policy → row 2, A8: `.a start: --model=sonnet`, to be answered once `maestro.policy.toml` is corrected — the director never edits policy | A8 |
| 9 | `/maestro --unattended --model=gemini regenerate the API docs` · none; `agy` not installed · none · the docs, by gemini | `--model` names an unavailable family → row 2, A9: `.a start: --model=sol`, `.b start: --model=sonnet` | A9 |
| 10 | `/maestro --unattended --model=sonnet add a CSV export of the invoices list` · none · none · the export; delimiter, file name and test scope not stated | no stop. Row 1 → `## Assumptions (unattended)`: `;` like the existing payments export, `invoices-<date>.csv`, both easy to reverse; test scope `covering` (the full suite would still run for shared reach). Committed; `result: done` with the assumptions | A10 |
| 11 | `/maestro --unattended add a password reset by e-mail link` · none; three families · none · the reset — a high-stakes change asked for explicitly | proceeds: rubric row 1 (`fable`), critics `astra` + `gemini`; the assignment line and the report recommend `--review`, nothing is added (A12); the e-mail wording is a row 1 assumption (A10) | A10, A12 |
| 12 | `/maestro --unattended delete customer accounts inactive for 12 months` · none · none · the deletion; what happens to their invoices is not stated | a high-stakes decision left open (existing data) → row 2, A10: stop at the interview, `d-R-1` in the checkpoint (`stage: interview`): `.a` keep the invoices and anonymise the customer, `.b` delete them with the account, `.c` stop. The batch size, a row 1 gap, is recorded as an assumption, but the stop wins (2 > 1) | A10 |
| 13 | run of 10 at `stage: build` · none · the builder `sonnet` ends with "Which date format for `issued_at`?" · the export | row 1, A11: the director answers from the spec and the repository (ISO 8601, like the existing exports) as a new prompt to the thread and records the assumption; no stop | A11 |
| 14 | run of 10 at `stage: build` · none · the builder ends with "Should the export include customers who opted out of data processing?" · the export | who may see what data is a high-stakes decision left open → row 2, A11: no new prompt; the turn's changes go through dirty-exit, nothing is committed; `d-R-2` in the checkpoint — a decision, not a `question` blocker | A11, A16b |
| 15 | `/maestro --unattended --model=sol add an invoice archive view` · none · `stage: build` · the view; Sol's `## Assumptions` says "dropped the unused `legacy_notes` column" | a migration that drops existing data, not asked for → row 2, A11. Dirty-exit keeps that outcome (A16b): `git status`, `git diff`, the change kept or reset deliberately and recorded in `tree_state`, nothing committed; `d-R-2` in the checkpoint; never row 5 | A11, A16b |
| 16 | `/maestro --unattended --model=sol migrate the reporting job to a queue` · none · `stage: build` · the migration; Sol declines one section as out of scope (an ordinary decline) | A18 unchanged: one rewritten brief; declined again → reroute to `opus`, with critics, reviewer and probes re-checked as for a swap; no stop, no decision | A18 |
| 17 | `/maestro --unattended --model=opus --rounds=2 add bulk tagging of posts` · none · `stage: critique`, after round 2 Sol answers its major `r1-m1` with `not_resolved`; the arbiter `argon` upholds it · bulk tagging | row 3, A13: no build; `d-R-3` in the checkpoint, its question naming `r1-m1` and Argon's reason: `.a` one more critique round (`changes_config: rounds=3`, recommended), `.b` stop and hand the plan over; `result: needs-decision` | A13 |
| 18 | `/maestro --unattended --model=opus --critic=astra add bulk tagging of posts` · none · `stage: critique`, round 1 · bulk tagging; Astra returns `reject` | row 3, A13, at once — no round 2; `d-R-1` in the checkpoint | A13 |
| 19 | run `R` of `--unattended --model=sonnet --review=cross` (critic and reviewer `sol` by default) · none · `stage: fix`, after fix round 3 the reviewer still reports a major finding · the task | row 4, A14: `d-R-5`: `.a` one more fix round (`changes_config: fix_cap=4`), `.b` one more fix round by `astra` instead (`changes_config: model=astra, fix_cap=4`), `.c` stop and hand the diagnosis over (`changes_config` empty). Every option that leads to another fix turn carries the `fix_cap` increase; the checkpoint keeps `fix_cap: 3` until one is answered | A14 |
| 20 | `/maestro --unattended --plan-only --critic=astra split the billing module` · none · none · a plan only; approved in round 2 | not a stop, A15: checkpoint `stage: report`, `plan_only: true`, `plan_sha256`; `result: plan-only` with the plan and the assumptions | A15 |
| 21 | `/maestro --unattended --model=sol add a CSV import of products` · none · `stage: build`, the Sol thread recorded · the import; Sol hits the OpenAI usage limit | row 5, A16a, exactly as today: dirty-exit, checkpoint with `blockers: [{kind: quota, …}]`, stop, `result: stopped`; no swap to another family (A17: limits). Later `/maestro --resume --unattended` with no answer, limits recovered: re-probe, continue the thread by UUID — no decision involved | A16a, A17 |
| 22 | run of 21 · none · `stage: build` · `codex exec` fails with a transient 503 | A18 unchanged: the worker continues by thread UUID as today; no stop, no decision | A18 |
| 23 | `/maestro --unattended --model=astra harden the upload validator` · none · `stage: build` · the change; the turn ends with `misalignment_policy_violation` | row 5, A16a: stop dispatch, keep checkpoint and `.jsonl`, inspect the tree, report (`result: stopped`), blocker `safety-pause`; never a decision. A later `--resume --unattended` does not retry the refused turn: it reports the blocker and stops again | A16a |
| 24 | run of 21 · none · `stage: build` · Sol's turn ends with a question asking to change the shared `Money` class the task does not mention (row 2, scope), and the same turn reports the usage limit (row 5) | 5 > 2: the run stops under row 5 exactly as today (quota blocker, `result: stopped`); the scope question is still recorded as `decisions.current` `d-R-4` with `row: 2, also_rows: [5]`, and the blocker's `detail` names it | A16a, A11 |
| 25 | checkpoint of 24 (quota blocker and `d-R-4`) · `/maestro --resume --unattended`, no answer, limits recovered · authorized: nothing new | the quota is re-probed only (a check, reported, not written); `d-R-4` is unanswered → stop again, `result: needs-decision`, nothing written, no model call | A16a, A11 |
| 26 | `/maestro --unattended --model=sol add a CSV import of products` · none · `stage: build`; the host running the Codex worker crashed · the import | A16b recovery, no stop: dirty-exit (changes inspected, kept or reset, recorded), then the thread continues by UUID or the worker is swapped for the crashed host as today (A17), a plan critic now in the builder's family replaced by one critique round of an eligible cross-family critic | A16b, A17 |
| 27 | run `R` at `stage: review` · none · `config/app.php` changed and no recorded worker session touched it; `/maestro --resume --unattended` · the task | the tree differs from `tree` → dirty-exit; the change cannot be attributed to a known worker → row 2, A16b: `d-R-6` in the checkpoint (`.a` keep it and continue, `.b` reset that file and continue, `.c` stop); no review is dispatched | A16b |
| 28 | `/maestro --unattended --cascade --model=sonnet add CRUD screens for the tags dictionary` · none; three families · `stage: draft` · the screens; Luna ends with `DRAFT_ABORT: authority: may deleting a tag detach it from existing posts?` | row 2, A21, no escalation: `draft.diff` kept, the draft stashed as `maestro-draft-R` (step 7's tree handling), `d-R-2` in the checkpoint at `stage: draft` | A21 |
| 29 | as 28 · Luna ends with `DRAFT_ABORT: context_limit` | capability or context → escalation to `sonnet` as `docs/cascade.md` step 7 says; no stop | A21 |
| 30 | checkpoint of 17 · `/maestro --resume --unattended`, no answer | the same stop again: nothing written, no model call; the report repeats `d-R-3` with its options | A13 |
| 31 | checkpoint of 17 · `/maestro --resume` (attended) | the director asks `d-R-3` with its recorded options (`AskUserQuestion`); the reply is handled as in 32; `modes` gains an attended session | A13 |
| 32 | checkpoint of 17 · `/maestro --resume --unattended d-R-3.a` | a checkpoint decision, so no `refers_to`; `rounds=3` is valid (1–8, families unchanged) → `answer` recorded, `d-R-3` to `history`, `flags` get `--rounds=3` with `flag_sources` `d-R-3`; critique round 3 runs — the cap moved only through this option | A13 |
| 33 | checkpoint of 17 · `/maestro --resume --unattended d-R-3.c` | `c` matches no option → stop again, nothing changes; the report repeats the question | A13 |
| 34 | `pending-decision.md` of 1, no checkpoint · `/maestro --resume --unattended d-T-1.a` | `start: --critic=astra` validated (flags, policy, family rule, probes) → the attempted task starts as a new unattended run (`flag_sources` `d-T-1`); `pending-decision.md` is deleted once the run's first checkpoint is written | A1 |
| 35 | checkpoint `R` at `stage: report`, tasks F2 and F3 `planned` (`s2`, `s3`) · `/maestro --unattended add an audit log page` · authorized: the audit log page | a new task over an unfinished run → stop, A19, in `pending-decision.md` (`d-T-1`, `refers_to` R): `.a build: F2 s2`, `.b build: F3 s3`, `.c archive-and-start`; the checkpoint is untouched | A19, A20 |
| 36 | checkpoint of 35, no pending file · `/maestro --resume --unattended`, then `/maestro --resume --unattended d-T-1.b` | two candidates → `d-T-1` in `pending-decision.md` (`.a build: F2 s2`, `.b build: F3 s3`), stop, no task selected. The answer: F3 exists, is still `planned`, its plan hashes to `s3` → build F3 with its recorded flags minus `--plan-only`; the approval stands; the file is deleted | A19, A20 |
| 37 | as 36, but F3's plan file was edited after approval · answer `d-T-1.b` | the `build` check fails → failed validation: `d-T-1` to `history` with its answer and `failed_rule: plan_sha256`; new `current` `d-T-2` in the same file: `.a build: F3 <new sha>` (the approval no longer stands: one critique round first), `.b build: F2 s2`; stop | A19, A20 |
| 38 | `pending-decision.md` of 37; now Claude only; `deny: [fable, sonnet, haiku]`; F3 recorded `--model=opus` · answer `d-T-2.a` | re-approval needs a critic and none is eligible → row 2, A20 (as A7): failed validation, `d-T-2` to `history`; new `current` `d-T-3`: `.a build: F3 <new sha>` with `changes_config: critic=fable`, `.b build: F2 s2`; stop | A20, A7 |
| 39 | checkpoint at `stage: build` for F1 (`in_progress`), F2 `queued` · `/maestro --resume --unattended` | the active run is the only candidate → `continue`, no decision; F2 waits | A19 |
| 40 | checkpoint at `stage: report`, `plan_only: true`, `current_task: F3`, F3 `planned` `s3`, plan unchanged · `/maestro --resume --unattended` | one candidate (deduplicated by task id) → `--resume` is the authorization: build F3, the approval stands; no decision | A20 |
| 41 | checkpoint at `stage: report`, F1 `done`, F2 `queued` without a plan · `/maestro --resume --unattended` | one candidate, `start: F2`: exists, still `queued`, next in order — no hash check; F2 starts as a new unattended run with its recorded flags | A19 |
| 42 | state B · `/maestro --resume --unattended a`, or `… d-R-3.a` | rejected either way: a bare letter with two unresolved decisions binds to neither, and `d-R-3` is not the first unresolved decision → stop again on `d-T-1` (first in the order); nothing written, `d-R-3` untouched | A19, A13 |
| 43 | state B · `/maestro --resume --unattended d-T-1.a`, then, in a separate invocation, `/maestro --resume --unattended d-R-3.a` | the first answer names the first unresolved decision: the identity check passes (R unchanged), `d-T-1` is consumed (`continue`) and `pending-decision.md` deleted; `d-R-3` is still open and unanswered → stop again on it, nothing dispatched. The second invocation consumes `d-R-3` as in 32: `rounds=3` written, critique round 3 runs | A19, A13 |
| 44 | `pending-decision.md` `d-T-1` (`refers_to` R at `written_at` W1); an attended session has since continued R (W2) · `/maestro --resume --unattended d-T-1.a` | identity mismatch → failed validation: `d-T-1` to `history` with `failed_rule: refers_to`; new `current` `d-T-2` referring to the checkpoint as it is now (`.a continue`, `.b archive-and-start`); the checkpoint untouched; stop | A19 |
| 45 | `/maestro --unattended --modle=sonnet --cascade add a factory for invoices` · repo `families: {openai: off}`, `cascade_drafter: luna` · none · the factory | validation stop `d-T-1` (`.a start: --model=sonnet --cascade`). `… --resume --unattended d-T-1.a` → policy fails (the effective drafter is in a family switched off, A8) → `d-T-1` to `history` with `failed_rule: policy`; new `current` `d-T-2`: `.a start: --model=sonnet --cascade=haiku`, `.b start: --model=sonnet`; stop. Then `… d-T-2.a` → valid → the run starts and the file is deleted | A1, A8 |
| 46 | checkpoint of 19 (`d-R-5` open, `fix_cap: 3`; the plan approved by `sol`) · `/maestro --resume --unattended d-R-5.b` (`model=astra, fix_cap=4`) | validated before the decision is cleared: `fix_cap=4` is above the 3 fix rounds run; critic and reviewer `sol` now share the builder's family → reviewer `opus`, and one critique round of the current plan by an eligible cross-family critic before Astra's first turn; step 5 probe for `astra`, step 8 reach probe (Astra writes). All pass → `flags` get `--model=astra` and the checkpoint `fix_cap: 4` (`flag_sources` `d-R-5` for both), the critique round runs, then Astra gets the brief plus the current `git diff` for fix round 4 — the last one `fix_cap` allows | A14, A17 |
| 47 | as 46, but the run named `--critic=sol` · answer `d-R-5.b` | a named critic from the new builder's family (A3) → failed validation: `d-R-5` to `history` with `failed_rule: cross-family (named critic)`; `fix_cap` stays 3. New `current` `d-R-6` in the checkpoint's `decisions`: `.a model=astra, critic=opus, fix_cap=4`, `.b model=astra, critic=gemini, fix_cap=4`, `.c` one more fix round with `sonnet` (`fix_cap=4`), `.d` stop and hand the diagnosis over; stop | A3, A14 |
| 48 | `claude -p "/maestro --unattended --model=opus add audit fields to orders"` · none · `stage: build`, `opus@native` (`claude -p`) mid-build · the change | `claude -p` ends with Claude's quota error after editing two files; agy serves `claude-opus-5-5` (the frozen id) → transport switch, no stop: termination confirmed, dirty-exit keeps the edits, a fresh edits-only brief with the diff goes to `agy --model claude-opus-5-5-medium`, ledger `transport-switch`; critics unchanged (same family) | A16a |
| 49 | as 48, but `transports: {deny: [opus@agy]}` and no `api` (no `--sdk`, no `api.fallback`) | no eligible next transport → row 5, A16a, exactly as a quota stop today | A16a, A17 |
| 50 | `claude -p "/maestro --model=sonnet fix the typo in the footer"` (headless, no `--unattended`) | validation stop, A22: nobody can answer; the remedy names `--unattended` | A22 |
| 51 | `/maestro --unattended …` launched from a nested setup where both `CODEX_THREAD_ID` and `CLAUDECODE` are set and the ancestry is hidden | `maestro-host` says `unknown` → row 2, A23; the remedy is starting `/maestro` from Claude Code itself | A23 |
| 52 | `--resume --unattended` of a 1.4 checkpoint that records `host: codex` and a critic on a removed slot | row 2, A24: the decision offers discarding the checkpoint and starting again | A24 |
| 53 | `claude -p "/maestro --unattended --model=sol …"` under a Bash sandbox that blocks `git worktree add` on a split | `maestro-preflight --worktree` lists the git write in `stops` → row 2, A25, remedy "allow the repository's `.git` or run without the sandbox" | A25 |
| 54 | `/maestro --unattended …` while another director holds the checkout's lock (live pid) | row 2, A26 | A26 |
| 55 | `--resume --unattended` where a previous builder left a process `maestro-kill` cannot end | `result: blocked`, lock kept, members listed — not a decision, A27 | A27 |
| 56 | `/maestro --unattended --model=gemini …` with `families: {claude: off, openai: off}` and `deny: [argon]` | one eligible family with one line → row 2, A28 | A28 |
| 57 | `/maestro --unattended --model=sol …` · the catalog lists `gpt-6.2-sol`, its probe says the account cannot use it; `gpt-6.1-sol` passes | row 1, A29: `sol=gpt-6.1-sol (gpt-6.2-sol listed, denied for this account)` recorded as an assumption; the run continues | A29 |
| 58 | `/maestro --unattended --critic=argon …` · Argon's verdict has two JSON objects, and again after the re-ask | named critic → row 2, A30 | A30 |
| 59 | `/maestro --unattended --model=argon …` · `agy models` fails (signed out) | the agy transport is ineligible and a flag needs it → row 2, A31 (as A9) | A31 |
| 60 | `/maestro --unattended fix the typo in the footer` from a director that cannot state its own model line, with `families: {openai: off, google: off}` and `deny: [sonnet]` | rubric row 6: `self` ineligible, no fallback eligible → row 2, A32 | A32 |
| 61 | as 17, but the arbiter `argon` answers `r1-m1` with `downgraded` (the trigger needs an input the spec excludes) | not a stop, A13: the plan is approved, the build starts; the report says "approved by arbiter argon over sol's majors" and lists `r1-m1` with Argon's reason | A13 |
| 62 | as 17, but `families: {google: off}` | `maestro-roles --arbiter` answers `stop` (no eligible third family) → no arbiter call; row 3, A13, as 17 | A13 |

The cross-family reviewer checks three things:

- every inventory entry has an outcome and at least one scenario;
- every scenario resolves to exactly one outcome under the precedence rule;
- no source line in the inventory search is missing from the table.

This repository has no automated harness for the matrix; the end-to-end canaries (`tests/canary/`,
`docs/evidence.md` "End-to-end canaries") exercise some of its stops on real runs.
