# Launch commands

> **What this page is for.** The exact command lines the director runs for every worker, critic and probe, and how it reads their output. The plain overview of what runs where is in [the guide](guide/setup-and-hosts.md).

Read this before the first external launch of a run. `SKILL.md` keeps the invariants, and
`docs/hosts.md` says how Claude Code launches and waits. This file keeps the exact lines.

## Launch rules

- **Every call's files live in its job directory**, `.maestro/jobs/<job>/`, with `<job>` =
  `<run_id>.<role>.r<round>.a<attempt>` (never reused). The brief a call reads may sit in
  `.maestro/`. Everything the call *writes* goes into the job directory: the CLI's stdout and
  stderr, and Codex's `-o` answer. The read-only fingerprint treats every other file under
  `.maestro/` as a protected input, so an answer written next to the plan would look like a critic
  editing the run's state.
- **Every line is launched as a job, in both modes** (`docs/hosts.md`, "Jobs"), in the foreground:

  ```bash
  "$MAESTRO/bin/maestro-run" --gen N --job <job> --run <run_id> --role <role> -- "$MAESTRO/bin/maestro-env" -- <line>
  ```

  maestro-run creates the job directory, owns stdout, stderr and stdin (the line carries **no
  redirection of its own**), prints the job JSON and returns at once. Test runs go the same way,
  with `--kind test`. Then wait:
  - **interactive Claude Code**: one Bash call with `run_in_background: true`:

    ```bash
    "$MAESTRO/bin/maestro-wait" <job> --until-done
    ```

    (agy: add `--also "$J/agy.log"`). Its completion notification wakes you, and its one output
    line is the snapshot: `exited`/`lost` → read the job; `lingering`/`orphaned` → `maestro-kill`
    in the same turn; `uncertain` → `--peek` again.
  - **headless `claude -p`**: a foreground loop, each call with the Bash tool's `timeout: 600000`:

    ```bash
    "$MAESTRO/bin/maestro-wait" <job> --max 540
    ```

  maestro-run is the only detach: never `&`, `nohup`, `setsid` or `disown` in a command of your
  own. The lines below are written without redirections.
- **Every external worker runs through `maestro-env`.** It strips your host markers and the
  variables that inject plugins, hooks, an API key or a different effort into a child CLI.
- **Codex config mode.** Every Codex line, exec and resume, carries either `--ignore-user-config`
  (**isolated**, the default) or, in **pinned** mode, the pins below, never both. The mode comes
  from `maestro-preflight`'s `codex_config` (`docs/workers.md`, "Config modes").
- **Rung 3** (`docs/sandbox-and-preflight.md`): every line of that Codex worker, resumes included,
  adds `-c approvals_reviewer="auto_review"`.
- **Briefs** are files; the prompt is `"$(cat file)"`.
- **The lines are templates** with the stage defaults: substitute the slot's frozen slug and the
  stage's effort after policy resolution and clamping.

## Codex

```bash
J="$REPO/.maestro/jobs/<job>"      # the job directory

# critique — read-only, context embedded in the brief
codex exec -m <gpt-…-sol> -s read-only --color never --json --ignore-user-config -c model_reasoning_effort=medium \
  --output-schema .maestro/critique-schema.json -o "$J/answer" "$(cat .maestro/brief-critique.md)"
#   high stakes: the astra slug, model_reasoning_effort=high

# build — workspace-write
codex exec -m <slug> -s workspace-write --color never --json --ignore-user-config -c model_reasoning_effort=medium \
  -o "$J/answer" "$(cat .maestro/stub-build.md)"

# builder resume — NO -s / --color / -C; sandbox via -c; ALWAYS the thread UUID from
# thread.started.thread_id in the first job's `out`. --last is banned. Before it, record the
# rollout offset ("Effective identity"). Run from the worker's own directory (maestro-run --cwd).
# Codex 0.172 restores the thread's saved cwd and sandbox unless overridden: the cwd comes back
# by itself (observed, docs/workers.md), the sandbox is always overridden by the role's -c.
codex exec resume <THREAD_UUID> --ignore-user-config --json -m <slug> -c 'sandbox_mode="workspace-write"' \
  -c model_reasoning_effort=medium -o "$J/answer" "$(cat .maestro/brief-fix1.md)"
# a critic, gate or reviewer keeps its role on resume: read-only and its schema
codex exec resume <THREAD_UUID> --ignore-user-config --json -m <slug> -c 'sandbox_mode="read-only"' \
  -c model_reasoning_effort=medium --output-schema .maestro/critique-schema.json -o "$J/answer" \
  "$(cat .maestro/brief-critique-r2.md)"

# visual fix round for a Codex builder — screenshots as attachments: --image=<png>[,<png>…]
codex exec resume <THREAD_UUID> --ignore-user-config --json -m <slug> -c 'sandbox_mode="workspace-write"' \
  -c model_reasoning_effort=medium -o "$J/answer" \
  --image=.maestro/evidence/01-desktop-light.png,.maestro/evidence/03-mobile-light.png "$(cat .maestro/brief-fix2.md)"

# cross review — read-only, with a contract (spec, PLAN.md, acceptance criteria, diff; the verdict
# rule "approve iff no blocking or major finding and every plan item is done"); effort = review
codex exec -m <slug> -s read-only --color never --json --ignore-user-config -c model_reasoning_effort=high \
  --output-schema .maestro/review-schema.json -o "$J/answer" "$(cat .maestro/brief-review.md)"

# model probe (stage 0 step 5)
codex exec -m <slug> -s read-only --color never --json --ignore-user-config -c model_reasoning_effort=low \
  -o "$J/answer" "Reply with exactly: OK"
#   success = exit 0 and the answer says OK → maestro-catalog record-probe --gen N codex <slug> ok --scope …
#   "model not found"/"not available" → record-probe … denied (the walk-down tries the next candidate)

# cascade drafter
codex exec -m <gpt-…-luna> -s workspace-write --color never --json --ignore-user-config -c model_reasoning_effort=medium \
  -o "$J/answer" "$(cat .maestro/brief-draft.md)"

# catalog (no model turn): codex debug models   — maestro-catalog runs it
```

Never pass `--trust` (0.169): it saves trust for the project persistently, MCP commands outside the
sandbox included.

**Pinned mode**: replace `--ignore-user-config` with `-c approvals_reviewer="user"`, and on the
read-only lines also add `-c mcp_servers.<name>.enabled=false` for each `[mcp_servers.<name>]` in
`$CODEX_HOME/config.toml`.

**Parallel Codex workers**: create each worktree first, inside the fence (`git worktree add
--detach "$REPO/.maestro/worktrees/<part>" HEAD`). Launch with `-C "$REPO/.maestro/worktrees/<part>"`
and maestro-run's `--cwd` set to the worktree, so a resume runs there too. Codex's own `--worktree`
is not used: it cannot be combined with `--ignore-user-config`.

## Claude — `claude -p`

```bash
# probe (stage 0 step 5) — also how the native alias is resolved to a full id
claude -p --model <alias> --effort low --tools "" --permission-mode dontAsk --strict-mcp-config \
  --setting-sources "" --output-format stream-json --verbose "Reply with exactly: OK"
#   the full id = init.model (and result.modelUsage); freeze it for the slot
#   (fable → claude-fable-5-2 since Claude Code 2.1.321; measured 2026-11-14)

# critic / gate / reviewer — read tools only, no MCP, no settings (no hooks), schema-enforced
claude -p --model <full id> --effort medium --tools "Read,Grep,Glob" --allowedTools "Read,Grep,Glob" \
  --permission-mode dontAsk --strict-mcp-config --setting-sources "" --output-format stream-json --verbose \
  --json-schema "$(cat .maestro/critique-schema.json)" "$(cat .maestro/brief-critique.md)"

# builder — edits-only (the director runs the tests)
claude -p --model <full id> --effort medium --tools "Read,Edit,Write,Glob,Grep" --permission-mode acceptEdits \
  --strict-mcp-config --setting-sources "" --output-format stream-json --verbose "$(cat .maestro/stub-build.md)"

# continuation — by session id (from init), EVERY flag of the role repeated, never -c/--continue
claude -p --resume <SESSION_ID> --model <full id> --effort medium <the role's --tools/--allowedTools/
  --permission-mode/--strict-mcp-config/--setting-sources/--output-format/--verbose/[--json-schema]> \
  "$(cat .maestro/brief-fix1.md)"
```

A parallel `claude -p` writer runs with its cwd in the worktree (maestro-run `--cwd`). Since 2.1.323
`claude -p` warns on stderr when settings block the requested model; the init check below catches
the result.

## Claude — `api` (`maestro-sdk`, the Agent SDK on an API key)

Like every worker it runs through `maestro-env`, which drops the director's `ANTHROPIC_*`, and
`maestro-sdk` sets the key from its own file. It takes full ids only. `B` = `--max-budget-usd`:
policy `api.max_usd_per_run` minus `maestro-ledger cost --run <run_id> --transport api`.

```bash
"$MAESTRO/bin/maestro-sdk" --check                    # stage 0 step 3: available? (no model turn)
"$MAESTRO/bin/maestro-sdk" --resolve opus              # newest id for the key (Models API, free)

# probe (stage 0 step 5)
"$MAESTRO/bin/maestro-sdk" --model <full id> --effort low --tools "" --permission-mode dontAsk \
  --max-budget-usd 0.05 --prompt-file .maestro/probe.md        # probe.md: "Reply with exactly: OK"

# critic / gate / reviewer
"$MAESTRO/bin/maestro-sdk" --model <full id> --effort medium --tools "Read,Grep,Glob" \
  --allowed-tools "Read,Grep,Glob" --permission-mode dontAsk --json-schema .maestro/critique-schema.json \
  --max-budget-usd "$B" --prompt-file .maestro/brief-critique.md

# builder — edits-only (the director runs the tests); a worktree writer adds --cwd <worktree>
"$MAESTRO/bin/maestro-sdk" --model <full id> --effort medium --tools "Read,Edit,Write,Glob,Grep" \
  --permission-mode acceptEdits --max-budget-usd "$B" --prompt-file .maestro/stub-build.md

# continuation — every flag of the role repeated
"$MAESTRO/bin/maestro-sdk" --resume <SESSION_ID> --model <full id> <the role's flags> \
  --max-budget-usd "$B" --prompt-file .maestro/brief-fix1.md
```

`result.subtype == "error_max_budget_usd"` means the run's api budget is spent: quota on this
transport. The ledger row is `--cli claude-sdk --transport api`.

## Claude and Gemini — `agy`

```bash
J="$REPO/.maestro/jobs/<job>"      # the job directory
# On every call: --add-dir "$REPO" (or the worker sees no project skills/rules), --log-file
# "$J/agy.log" (this run's own log, for maestro-wait --also) and an explicit --mode (the default is
# Auto since agy 1.5.7). Never --disable-slash-commands: it switches plan mode off (below).
# Effort: the slug's suffix and --effort always agree; agy accepts low…max, but clamp to the
# suffixes the model lists (Hydrogen and Neon up to xhigh, Argon, Carbon and Claude-on-agy up to
# high; agy 1.5.16).
#
# critique — plan mode; the brief (paths inside $REPO, nothing quoted) in -p, opening with the
# "read inside <REPO> only" paragraph; the worker reads the plan, the diff file and the code itself.
# A denied read → a new conversation with the inline variant (whole brief quoted, "no tools").
# The verdict is the envelope's .structured_output (else JSON inside .response). Same shape for a
# gate or a review.
agy --model gemini-<v>-argon-medium --mode plan --effort medium --add-dir "$REPO" --output-format json \
  --json-schema .maestro/critique-schema.json --log-file "$J/agy.log" --print-timeout 30m \
  -p "$(cat .maestro/brief-critique.md)"
#   slot gemini: --model gemini-<v>-hydrogen-medium (or -flash- when only Flash is listed);
#   the explicit-only carbon / neon, when named: gemini-<v>-carbon-medium / gemini-<v>-neon-medium;
#   Claude on agy: --model claude-opus-<v>-medium (or claude-sonnet-…); everything else identical

# build — accept-edits, EDITS ONLY: one denied command cancels the whole run
agy --model <slug> --mode accept-edits --effort medium --add-dir "$REPO" --output-format json \
  --log-file "$J/agy.log" --print-timeout 60m -p "$(cat .maestro/stub-build.md)"

# builder resume — by id, never -c/--continue; only after a SUCCESS turn. agy 1.5.16 also takes
# -r / --resume as aliases of --conversation; maestro keeps the long form.
agy --conversation <CONVERSATION_ID> --model <slug> --mode accept-edits --effort medium \
  --add-dir "$REPO" --output-format json --log-file "$J/agy.log" --print-timeout 60m \
  -p "$(cat .maestro/stub-fix1.md)"

# critic / gate / reviewer continuation — keeps plan mode, its schema and the brief in -p
# (schema follow-ups through --conversation return JSON since agy 1.5.8)
agy --conversation <CONVERSATION_ID> --model <slug> --mode plan --effort medium --add-dir "$REPO" \
  --output-format json --json-schema .maestro/critique-schema.json --log-file "$J/agy.log" \
  --print-timeout 30m -p "$(cat .maestro/brief-critique-r2.md)"

# probe
agy --model <slug at its lowest effort> --mode plan --effort low --add-dir "$REPO" --output-format json \
  --log-file "$J/agy.log" --print-timeout 2m -p "Reply with exactly: OK"

# skills listing (stage 0 step 6, no model turn) — maestro-preflight --skills runs it
agy --add-dir "$REPO" --mode plan --output-format json --print-timeout 2m -p "/skills"
```

- **Progress** for an agy job: `maestro-wait <job> --also "$J/agy.log"`. The run's own log is
  written while it runs; the envelope is written whole at exit.
- **Timeout.** When `--print-timeout` expires, agy (1.5.0+) exits **3**, prints an `AGY_ERROR` line
  and `[agy] print timeout after …` on stderr, and the envelope carries `finished_reason:
  "print_timeout"`. `maestro-validate` rejects any non-empty `finished_reason` (`print_timeout`,
  `interrupted`, `error`).
- **`--disable-slash-commands` is not used.** Measured on agy 1.5.9: with it agy prints
  `warning: --mode plan has no effect while slash command expansion is disabled.` That would
  silently drop plan mode, and plan mode is what keeps an agy critic read-only. A brief therefore
  never starts with `/`.
- **Usage** is reported per conversation and is cumulative across `--conversation` turns. Keep it
  raw in the ledger's `raw_cumulative`.
- **Retries.** Since agy 1.5.10 a rate-limit delay of up to 4 minutes is waited out and retried
  inside the turn, and since 1.5.12 brief connection drops are retried (spend-cap, prepaid and
  weekly-quota errors still end the turn); since 1.5.13 a run that succeeded after such a retry
  reports `SUCCESS`, not `ERROR`. The checks above and the watchdog threshold are unchanged
  (`docs/workers.md`, "Google — `agy`").

**Stubs — builders and drafters only.** Their `-p` prompt is a pointer: *"Read
`.maestro/stub-build.md`'s brief at `.maestro/brief-build.md` in the workspace and execute it exactly.
Your final answer is only what it asks for."* It is small and free of shell quoting. Critics, gates
and reviewers get their brief in `-p`. That brief is short, because it names paths and quotes
nothing. Only the inline variant (after a denied read) carries everything; above ~100 KB it is
split, or the role goes to another family.

## Reading results

Never load a whole event stream into context — a long build log is tens of thousands of tokens:

```bash
J=.maestro/jobs/<job>
grep -m1 '"thread.started"' "$J/out"                     # codex: thread_id for resume
grep '"turn.completed"' "$J/out" | tail -1                # codex: usage
grep -E '"turn.failed"' "$J/out" | tail -3                # codex: failure, if any
jq -c 'select(.type == "system" and .subtype == "init")' "$J/out" | head -1      # claude -p / api: init
jq -c 'select(.type == "result") | del(.result)' "$J/out" | tail -1              # claude -p / api: result
jq -c '{status, finished_reason, conversation_id, denied_actions, usage}' "$J/out"   # agy envelope
jq -c '.structured_output' "$J/out"                                               # agy verdict (schema calls)
```

- **Codex:** the `-o` file (`$J/answer`) is the answer. A reconnect `error` event is Codex
  retrying. A failure is `turn.failed`, or an exit without `turn.completed`.
- **agy:** an answer counts when:
  - `status == "SUCCESS"`;
  - there is no `finished_reason`;
  - `(denied_actions ?? []) == []`;
  - the answer is non-empty: `structured_output` when present (schema calls), else `response`.

  Any other outcome invalidates the `conversation_id`: follow up in a new conversation with the
  current diff.
- **`claude -p`, `api`:** the `result` event, with `subtype == "success"`, `is_error == false` and
  `permission_denials` (empty for read-only roles; a denied Edit or Write fails a builder's turn).
- **Completion = all of:**
  - the job `exited` with code `0`;
  - the envelope above succeeded;
  - for a read-only role, the verdict is valid.

### Validating a verdict

```bash
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json .maestro/jobs/<job>/answer --envelope codex
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json .maestro/jobs/<job>/out --envelope agy
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json .maestro/jobs/<job>/out --envelope claude --role read-only
```

`--envelope claude` covers `api` too. The validator works in three steps:
1. It checks the envelope first. An envelope failure is not an invalid verdict.
2. It extracts **exactly one** top-level JSON object. One surrounding fence is stripped and leading
   prose is allowed; trailing text or a second object is rejected.
3. It validates that object completely against the schema.

When the verdict is invalid, re-ask once on the same session with the validator's `errors`. Still
invalid → the role moves to the next eligible critic (a named critic → halt).

`--decide critique|arbiter [--ids <id,id,…>]` adds the mechanical decision of the plan critique
(`docs/briefs.md`, "Plan critique") as `decision: {approved, reasons}`:

```bash
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json "$J/answer" --envelope codex --decide critique --ids ""           # round 1
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json "$J/answer" --envelope codex --decide critique --ids r1-m1,r1-m2  # round 2+
"$MAESTRO/bin/maestro-validate" .maestro/arbiter-schema.json "$J/out" --envelope agy --decide arbiter --ids r1-m2,r2-m1
```

- `critique`: approved iff verdict `approve`, `blocking_findings` and `major_findings` empty, every
  prior finding `resolved`. `arbiter`: approved iff there is a verdict and every one is `downgraded`.
- A contradiction is `valid: false` at stage `decide`, not a decision: an `approve` that still
  lists a finding or a `not_resolved` prior finding, a finding with an empty `trigger`, an id
  listed twice, and — with `--ids` — an id sent but not answered or answered but not sent.
- The exit code follows `valid` alone: a valid `revise` exits 0 with `approved: false`. Every
  invalid output carries `approved: false`.
- An invalid critique is re-asked as above; an invalid arbiter answer is not (one call, then the
  stop).

### Read-only proof

```bash
"$MAESTRO/bin/maestro-fp" snapshot > .maestro/tmp/fp-<job>.json     # before the call
… the call …
"$MAESTRO/bin/maestro-fp" compare .maestro/tmp/fp-<job>.json         # after: {result: same|changed, diffs}
```

`changed` → the verdict is discarded, dirty-exit, and the transport is ineligible for read-only
roles this run. Bookkeeping written legitimately during the call (the session id from `init`, the
ledger row) goes through `maestro-state`, so it compares as audited, not as a change.

### Effective identity

Check it after every launch and resume, before anything the worker did is accepted. Anything other
than `OK` stops the worker; a writer's output is discarded through the dirty-exit protocol.

**`claude -p` and `api`** check the `init` event, fail closed, as soon as the first event is in
`out` (the first line may take a few seconds; `maestro-wait` returns while the job runs):

```bash
"$MAESTRO/bin/maestro-identity" claude .maestro/jobs/<job>/out --model <frozen full id> \
  --tools "Read,Grep,Glob" --permission-mode dontAsk [--api]
```

It requires:
- `model` equal to the frozen id;
- `tools` equal to the requested set;
- `mcp_servers` empty;
- every `plugins[].source` ending in `@builtin`;
- `plugin_errors` empty or `null` (Claude Code 2.1.325 writes `null` when there are none);
- the requested `permissionMode`;
- `apiKeySource` equal to `none` (native: the subscription) or `ANTHROPIC_API_KEY` (`--api`;
  `maestro-sdk` also aborts on anything else itself).

No `init` event → `MISSING`.

**Codex** checks the rollout. Codex writes one rollout file per thread,
`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-<time>-<thread_id>.jsonl`, with one `turn_context` record
per turn: `model`, `effort`, `sandbox_policy`, `approval_policy`, `approvals_reviewer`,
`permission_profile` (network access and every writable root) and `cyber_access_program`. Before a
resume, record the rollout's line count as the session's `rollout_offset` (`wc -l`). The check
reads the first `turn_context` after that offset, so an earlier turn's record can never pass for the
resumed one. A launch uses 0. Run it in the foreground once `thread.started` is in `out`; it waits
up to `--wait` seconds (default 120), because the rollout outlives the process:

```bash
"$MAESTRO/bin/maestro-identity" codex --thread <thread_id> --offset <rollout_offset> --role <role> \
  [--rung 1|3|4] --model <slug> --effort <effort> [--root <dir the worker writes in>]
# → {result: OK|MISMATCH|MISSING, mismatches: [...], effective_config: {...}}
```

Expected values per role (`--root` = the checkout, or the worktree of a parallel worker):

| Role | Sandbox | Approval | Reviewer | Network | Write roots |
| --- | --- | --- | --- | --- | --- |
| critic, gate, reviewer, probe | `read-only` | `never` | `user` | restricted | none |
| builder, drafter, fix — rung 1 | `workspace-write` | `never` | `user` | restricted | `ROOT` only |
| rung 3 | `workspace-write` | `on-request` | `auto_review` | restricted | `ROOT` only |
| rung 4 | `danger-full-access` | `never` | `user` | not checked (`permission_profile.type: disabled`) | not checked |

- `/tmp` and `$TMPDIR` are writable specials in every sandboxed profile and are allowed. Any other
  writable special (such as the file-system root) is a mismatch.
- `cyber_access_program` must be `standard` or absent.
- Pinned mode produces the same rows; that is what the pins are for.
- The ledger row of the call gets `effective_config` (`--effective-config`).
- Two rollouts for one thread id → `MISSING`.
- Verification status: the format was verified on 0.159.2 and 0.166.0 rollouts
  (`docs/evidence.md`); 0.169.0 is confirmed by the first live probe of a run.
- If Codex moves rollouts into its history database (`codex migrate-rollouts`, off by default),
  this check finds no file and says `MISSING`: see `docs/troubleshooting.md`.

**The Agent tool**: the completion's model against the frozen id when the completion names it (Claude Code 2.1.325's completion reports tokens, tool uses and duration only — measured 2026-11-14 — so the identity rests on the explicit `model`; ledger `model_served` is `null`). **agy** has no served-model
field: the requested slug is recorded.

## Progress sampling

- **Interactive Claude Code:** the background `maestro-wait <job> --until-done` keeps
  `last_progress_at` current. Sample every 5 minutes, woken by a background `sleep 300` or a
  `Monitor`, with `maestro-wait <job> --peek` (`idle_s`; agy: the same `--also` as the waiter) or
  `maestro-status`. Never end the turn for it; re-arm the sampler on every expiry.
- **Headless:** `maestro-wait <job> --max 540` in a loop (Bash `timeout: 600000`). It persists `last_progress_at` in the job
  directory, so the hang clock survives calls and turns.

Progress sources:
- new events in a codex `--json` or `claude -p` `stream-json` stream (thinking deltas count);
- the agy CLI log passed with `--also`;
- `git status` changing.

Silence is a hang only after `max(15 min, 2 × T_slow)`, and never for a test run. Before killing,
read the job's files. Codex's stderr prints `Reading additional input from stdin...` even on healthy
runs; the hang signal is that line **with no `thread.started` event**.

Kill with `maestro-kill` (it spares tests and signals members one by one), in both modes. Stopping
the harness task of `--until-done` stops only the waiter, never the job. Never `pkill -f`.
