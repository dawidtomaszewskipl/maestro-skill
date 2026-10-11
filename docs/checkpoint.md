# Checkpoint

`.maestro/CHECKPOINT.md` is what makes a maestro run resumable after a quota wall, an API failure, a
safety stop, a closed laptop or a host that ended its session. It is rewritten in place — never
appended — after every stage transition, at every worker launch (with the session id and the job
id, the one write that saves resumability), at every worker finish, after each gate or fix round,
and on any blocker. **It is written only through `"$MAESTRO/bin/maestro-state" --gen N write
CHECKPOINT.md`**: that checks the file against its last audit entry first and refuses one changed
by anything else (`docs/hosts.md`, "Read-only proof" in `docs/commands.md`).

## Front matter

```yaml
skill: maestro              # a checkpoint without it is not maestro's (route's lives in .route/)
run_id: 2026-09-06T10-31-maestro-a1b2
host: {name: codex, interactive: true, session_key: 01a1283f-…, host_pid: 102147, host_pid_starttime: "14828171"}
director: {family: openai, model_line: sol, model_id: gpt-6.1-sol, source: "rollout turn_context"}
lock: {token: 9c0e…, generation: 3}   # the token is what --resume presents; the generation fences
catalog:                   # frozen at stage 0 step 5 — sticky for the run; --resume re-probes these exact slugs
  sol:    {version: "6.1", transport: codex, slug: gpt-6.1-sol, source: live}
  opus:   {version: "5.5", transport: native, slug: claude-opus-5-5, order: [native, agy, cursor]}
  gemini: {version: "3.8", transport: agy, slug: gemini-3.8-flash-medium}
  grok:   {version: "4.7", transport: cursor, slug: grok-4.7-medium, provisional: true}
written_at: 2026-09-06T11:02:14+02:00
task: "CRUD screens for the tags dictionary"
flags: "--model=sol --review=cross --cascade --rounds=2 --tests=covering"
test_scope: covering    # covering | covering,browser | full | full,browser | none
plan_only: false        # true after a --plan-only run; plan_sha256 is then the approved plan's hash
plan_sha256: ""
tasks:                  # only after --setup with separate runs
  - {id: 1, text: "CRUD screens for the tags dictionary", flags: "--model=sol --review=cross --cascade --rounds=2 --tests=covering",
     status: in_progress, plan: .maestro/tasks/1/PLAN.md, plan_sha256: "", critics: []}
  - {id: 2, text: "tag filter in the posts list", flags: "--model=opus --plan-only --tests=browser",
     status: queued, plan: .maestro/tasks/2/PLAN.md, plan_sha256: "", critics: []}
                        # status: queued | in_progress | planned (a --plan-only run finished) | done
current_task: 1
branch: feature/tags-crud
base_sha: 3704e20…
stage: build            # interview | assign | plan | critique | draft | gate | build | review | fix | report
round: 1
fix_cap: 3              # fix-loop cap: 3 unless an answered decision raised it (docs/unattended.md;
                        # flag_sources names it); absent = 3; restored with the configuration
roster:
  implementer: {slot: sol, transport: codex, model_requested: gpt-6.1-sol, effort: medium}
  drafter:     {slot: luna, model_requested: gpt-6-luna, effort: medium}
  critic:      {slot: gemini, transport: agy, model_requested: gemini-3.8-flash-medium, effort: medium}
  second_critic: {slot: "", model_requested: "", effort: ""}
  reviewer:    {slot: fable, transport: native, model_requested: claude-fable-5-1, effort: high}
codex: {config_mode: isolated, mode_reason: ""}   # the run default, decided at stage 0 step 3;
                         # pinned + the config.toml key that forced it. Never touched by a runtime refresh.
sessions:
  codex:                 # one record per Codex thread; a continuation is built from it, not from the default
    - {id: 01a075d7-9c4e-7580-b41d-0ce7c87bf4b9, role: build, job: 2026-09-06T10-31-maestro-a1b2.build.r1.a1,
       config_mode: isolated, mode_reason: "", rung: 1, approvals_form: "", rollout_offset: 0,
       worktree: "", baseline: "", fingerprint: ""}
                         # rollout_offset = the rollout's line count before the latest resume;
                         # a parallel worker: worktree: .maestro/worktrees/<part>, baseline: <SHA of its start
                         # commit or latest route-integrated commit>, fingerprint as for `tree`, run inside it
  agy:   [{id: b538f8bb-9a0e-4978-bc3d-988ccef298eb, role: critic, slug: gemini-3.8-flash-medium, job: …}]
  cursor: [{id: 65d9d73d-c2af-4e49-8102-08ee4bccb856, role: critic, slug: grok-4.7-medium, job: …,
            init_model: "Grok 4.7 256K Medium"}]
  claude_cli: [{id: 7c51bcf8-…, role: build, model: claude-opus-5-5, tools: "Read,Edit,Write,Glob,Grep", job: …}]
  claude: []             # Agent-tool subagent ids, continued with SendMessage within the session;
                         # a worktree subagent as {id: …, worktree: <path>, baseline: <SHA>, fingerprint: …}
                         # any session that ended by a transport switch: outcome: "transport-switch: native→agy (quota)"
artifacts:
  plan: .maestro/tasks/1/PLAN.md    # the run's PLAN.md (.maestro/PLAN.md without a queue)
  briefs: [.maestro/brief-critique.md, .maestro/brief-build.md]
  jobs: [.maestro/jobs/2026-09-06T10-31-maestro-a1b2.critique.r1.a1, …]   # every call's out/err/answer
tree_state: dirty-worker   # clean | dirty-worker | dirty-draft | stashed:route-draft-<run_id>
tree: {branch: feature/tags-crud, head: 3704e20…, fingerprint: 9f2c41…}
                           # rewritten with every checkpoint; fingerprint = sha256 of `git diff HEAD --binary`
                           # followed by each untracked file's path and sha256, in sorted order
tests: {cmd: "vendor/bin/sail artisan test --compact", last_result: "1104/1104", duration_s: 412, T_slow_s: 417}
runtime: {codex_version: 0.162.1, agy_version: 1.3.3, agent_version: 2026.10.01, claude_version: 2.1.296,
          doctor_ok: true, probed_at: 2026-10-11T10:31:00+02:00}
agy_log: {path: ~/.gemini/antigravity-cli/log/cli-20260906_103105.log, baseline_bytes: 4120}
blockers: []               # [{kind: quota|api|safety-pause|question, who, at, detail}]
decisions:                 # answer-required decisions (docs/unattended.md), apart from `blockers`;
  current: null            # one decision record (shape below) or null;
                           # no `decisions` key = none open
  history: []              # answered or superseded records, with `answer` and, after a failed
                           # validation, `failed_rule`
modes:                     # one entry per director session on this run;
                           # --unattended is never in `flags`
  - {at: 2026-09-06T10:31:00+02:00, mode: attended,
     invocation: "--model=sol --review=cross --cascade …"}
flag_sources: []           # [{flag: "--rounds=3", decision: d-<run_id>-3}]: flags and `fix_cap`
                           # values an answer changed
open_findings: []
next_action: "maestro-wait the build job; on exited 0 run tests, then review stage"
ledger: .maestro/ledger.jsonl
```

## Body

- **Done** — stages and commits completed, with hashes.
- **In flight** — which worker, which session, launched when, last progress sample.
- **To do on resume** — the imperative list the director follows.
- **Diagnosis** — the current red state, if any: which test, why, what was tried.

## Decisions

The `blockers` list is operational — `quota`, `api`, `safety-pause` and the attended worker
`question` — and needs no answer: a resume recovers from `quota` and `api` by re-probing and
continuing, while a `safety-pause` is never retried ("Resume procedure", step 2). A stop that needs
the user's answer (`--unattended`, `docs/unattended.md`) is a **decision**, kept apart in
`decisions`. A row 5 stop (safety, quota or limit exhaustion) is always a blocker, never a decision.
A decision record:

```yaml
decision_id: d-2026-09-06T10-31-route-a1b2-3   # d-<run_id or attempt_id>-<n>; unique
kind: needs-decision
row: 3                     # highest stop-matrix row that applies; the others in also_rows
also_rows: []
at: 2026-09-06T11:40:00+02:00
source: A13                # ask-point id in docs/unattended.md
refers_to: {run_id: "", stage: "", written_at: "", tree_head: ""}
                           # pending decisions about a run only
question: "Critique cap (2) reached; Sol still reports one major finding: …"
options:                   # option id = <decision_id>.<letter>, each bound to an action
  - {id: d-2026-09-06T10-31-route-a1b2-3.a, text: "one more critique round (cap 2 → 3)",
     action: "continue: critique round 3 of the current plan", changes_config: "rounds=3"}
  - {id: d-2026-09-06T10-31-route-a1b2-3.b, text: "stop here; hand the plan over",
     action: "continue: stage report, plan-only style hand-over", changes_config: ""}
recommendation: d-2026-09-06T10-31-route-a1b2-3.a
answer: null
```

**`.maestro/pending-decision.md`** holds a decision that has no run checkpoint to live in: a
validation stop (nothing has started), a stop in stage 0 before the first checkpoint, a new
non-resume task over an unfinished run, several candidates on an unattended resume with no
answer, and a failed candidate check. It never touches an existing checkpoint; a decision about one
carries `refers_to`.

```yaml
attempt_id: 2026-10-03T12-00-05Z    # UTC time of the invocation that wrote the record
task_text: "add a CSV export of the invoices list"
flags: "--unattended --critc=astra" # as typed
current: {decision_id: d-2026-10-03T12-00-05Z-1, …}   # one decision record
history: []
```

Its actions: `start: <corrected flag line>`, `continue` (the existing run), `start: <queued task
id>`, `build: <task id> <plan_sha256>`, and `archive-and-start` — `maestro-state --gen N rotate --to
<run_id>` (the checkpoint, the pending decision and the audit move to `.maestro/archive/<run_id>/`,
verified first), then start the attempted task; never a delete. The file is
deleted (`maestro-state --gen N delete pending-decision.md`) once its `current` is answered and acted
on; a new non-resume invocation moves its
`current` to `history` and re-runs every check.

**Candidates on resume** — the existing order, for an attended resume too:
- An active run (`stage ≠ report`) is the **only** candidate: `--resume` continues it. Queued and
  planned work waits.
- At `stage: report`: the next `queued` task in queue order (`start`), each `planned` task
  (`build`), and `plan_only: true` without a queue as one more `build` — deduplicated by task id,
  so the current task's `plan_only` and its planned entry are one candidate.
- One candidate: `--resume` is the authorization and it proceeds; `build` keeps the approval
  conditions of SKILL.md, "Building a `--plan-only` plan".
- Several: one decision with an option per candidate — asked when attended; recorded in
  `pending-decision.md` when unattended, and no task is selected until an answer names one.
- Before acting: `continue` — the run's identity still matches `refers_to`; `start` — the task
  exists, is still `queued` and is next in queue order (a queued task has no plan to hash); `build`
  — the task exists, is still `planned`, and its plan file hashes to the approved `plan_sha256`. A
  failed check is a failed validation (`docs/unattended.md`, "Decisions and answers").

**Session mode.** `--unattended` belongs to the invocation, not to the run: `flags` never holds it,
`modes` records each director session's mode, and a bare `--resume` continues attended.

## Resume procedure

0. **Lock, host, jobs** (maestro). Read `run_id` and the lock token from the checkpoint and take the
   lock with `maestro-lock acquire --resume` — it takes over only a **stale** owner (a live director
   keeps it: stop, attended ask / unattended row 2). Re-detect the host and your identity
   (`maestro-host`); a different host, family or model line than `host` / `director` → attended:
   say what changes and ask; unattended: row 2 (`docs/unattended.md` A24). Then reconcile every
   recorded job (`maestro-wait <job> --peek`): `running` → back into the wait loop; `exited` /
   `lost` → its output is read or the dirty-exit protocol runs; `lingering` / `orphaned` →
   `maestro-kill`; still alive → `result: blocked`, lock kept. Nothing is dispatched before this.
1. Read the checkpoint, and `.maestro/pending-decision.md` when it exists. At `stage: report`: a
   `queued` task starts as a new run with its recorded flags; a `planned` task, or `plan_only:
   true`, is built (SKILL.md, "Building a `--plan-only` plan"); with several candidates, ask which
   (above). With none of these and no open decision there is nothing to resume.
2. **Re-probe**: `codex doctor --summary`, `agy --version`, `agent status`, `claude auth status`,
   the limits, and the frozen `catalog` slugs (each one's probe line — the catalog is **not**
   re-resolved) — overwrite `runtime` (only `runtime`: the `codex` block, `catalog` and the
   session records are routing state). Never reason from a
   remembered limit. While a decision stays unanswered (step 3) the re-probe is only a check: it is
   reported, not written. Then the `blockers`, attended or not:
   - `quota` and `api` are recoverable: once the re-probe shows the limit or the API back, the run
     continues in step 5, with no answer;
   - a `safety-pause` is **never retried** (SKILL.md, "Time and the watchdog": safety stops are not
     retryable): no resume re-sends the refused turn. Attended, the director reports it and the
     user decides how to go on — a changed brief goes to a new thread (SKILL.md, "Launching
     workers"); unattended, the resume reports it and stops again under row 5
     (`docs/unattended.md`).
3. **Open decisions**, before anything is dispatched, in this order: `pending-decision.md`'s
   `current`, the checkpoint's `decisions.current`, the candidates. Only the first unresolved one
   takes an answer — the text after the flags, or the reply to an attended question — and one
   answer consumes exactly one decision; the next needs its own, in a separate invocation when
   unattended. Attended with no answer: ask the first one with its recorded options. Unattended with
   no answer, or with an answer that names another decision (a later one included) or matches no
   option: stop again on the first one — no dispatch, no model call, nothing written — and repeat
   its question with its `decision_id`. An answered decision is identity-checked, validated and
   consumed as `docs/unattended.md` says; recording it leaves `tree` as it was, so step 4 still
   compares against it. Operational `blockers` never wait for an answer; with a decision open they
   are only re-checked.
4. Compare the tree with `tree`: the branch, `git rev-parse HEAD`, and the fingerprint recomputed the
   same way. Any difference means someone (a worker, the user) touched the tree since the checkpoint
   was written — even when `git status` looks the same — so the dirty-exit protocol (SKILL.md, "Time
   and the watchdog") comes before anything else. A `stashed:` state is applied or dropped only
   after confirming `branch` is checked out and `git rev-parse HEAD == base_sha`. Then the same for
   every worktree in the session records: `git -C <worktree> rev-parse HEAD` must equal its
   `baseline` and its fingerprint must match; a difference sends that worktree through the dirty-exit
   protocol before it is continued or integrated.
5. Continue at `stage` with `next_action` — or with the action of the decision answered in step 3 —
   under the recorded configuration (`flags`, roster, `fix_cap`), continuing each worker as SKILL.md
   "Launching workers" says: Codex by thread UUID (also after an API or quota stop), from its
   session record — mode, rung tokens, and for a worktree worker from inside its worktree — agy by
   id only after a `SUCCESS` turn, `claude -p` and Cursor by session id with every flag of the
   role repeated, Claude subagents with `SendMessage` in the same session or anew after a restart.
   A transport the frozen slot can no longer use → the transport switch (`docs/hosts.md`).
6. A checkpoint with `plan_only: true` at `stage: report` is not resumed but built: SKILL.md,
   "Building a `--plan-only` plan".

## Audit and the bookkeeping lifecycle (maestro)

`CHECKPOINT.md`, `ledger.jsonl`, `pending-decision.md`, `lock` and every job's `meta.json`, `cmd`
and `cwd` are **audited**: each write appends `{file, sha256_after, gen, at}` to
`.maestro/audit.jsonl`, and every later write first checks the file against its last entry. Every
change goes through a helper, inside the fence:

| Operation | Helper |
| --- | --- |
| write or append | `maestro-state --gen N write|append <file>` (`maestro-ledger` for ledger rows) |
| remove (a resolved `pending-decision.md`) | `maestro-state --gen N delete <file>` — recorded as absent, so the file can be created again later |
| move one file away | `maestro-state --gen N archive <file> --to <name>` |
| end of a run, or `archive-and-start` | `maestro-state --gen N rotate --to <run_id>` — verifies every audited file, moves `CHECKPOINT.md`, `pending-decision.md` and `audit.jsonl` to `.maestro/archive/<run_id>/`, and starts a fresh audit whose first entries are the current hashes of what stays (the ledger, the lock, the jobs) |
| accept a file changed outside maestro | `maestro-state --gen N adopt <file> --reason "…"` — **only on the user's decision** after they inspected it; never under `--unattended` |

A file changed any other way stops the next write or `--resume` (row 2 under `--unattended`).
