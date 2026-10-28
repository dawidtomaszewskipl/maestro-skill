# Launch commands

Read this before the first external launch of a run. `SKILL.md` keeps the invariants,
`docs/hosts.md` how this host launches and waits; this file keeps the exact lines.

## Launch rules

- **Every call's files live in its job directory**, `.maestro/jobs/<job>/` with `<job>` =
  `<run_id>.<role>.r<round>.a<attempt>` (never reused): the brief the call reads may sit in
  `.maestro/`, but everything the call *writes* — the CLI's stdout and stderr, Codex's `-o` answer —
  goes into the job directory. The read-only fingerprint treats every other file under `.maestro/`
  as a protected input (`docs/hosts.md`), so an answer written next to the plan would look like a
  critic editing the run's state.
- **How a line is run depends on the host** (`docs/hosts.md`, "Adapters"):
  - **interactive Claude Code**: create the job directory (`mkdir -p .maestro/jobs/<job>`) and run
    the line with the Bash tool's `run_in_background: true`, redirecting stdout and stderr into
    the job directory yourself — never `&`, `nohup`, `setsid`, `disown`;
  - **every other host**: `"$MAESTRO/bin/maestro-run" --gen N --job <job> --run <run_id> --role <role>
    -- "$MAESTRO/bin/maestro-env" -- <line>` — maestro-run creates the job directory and owns stdout and
    stderr (`out`, `err`), so the line carries **no redirection of its own**; then
    `"$MAESTRO/bin/maestro-wait" <job> --max <n>` in a loop.
  The lines below are written for the second form (no redirections). In an interactive Claude
  Code append `< /dev/null > .maestro/jobs/<job>/out 2> .maestro/jobs/<job>/err` and prefix
  `"$MAESTRO/bin/maestro-env" --`.
- **Every external worker runs through `maestro-env`** (it strips your host markers and the
  variables that inject plugins, hooks or a different effort into a child CLI).
- **Codex config mode.** Every Codex line, exec and resume, carries `--ignore-user-config`
  (**isolated**, the default) or, in **pinned** mode, the pins below — never both
  (`docs/workers.md`, "Config modes").
- **Rung 3** (`docs/sandbox-and-preflight.md`): every line of that Codex worker, resumes included,
  adds `-c approvals_reviewer="auto_review"`.
- Briefs are files; the prompt is `"$(cat file)"`; stdin is closed (`maestro-run` does it; in the
  background tool add `< /dev/null`).
- The lines are **templates** with the stage defaults: substitute the slot's frozen slug and the
  stage's effort after policy resolution and clamping.

## Codex

```bash
J="$REPO/.maestro/jobs/<job>"      # the job directory (maestro-run creates it)

# critique — read-only, context embedded in the brief
codex exec -m <gpt-…-sol> -s read-only --color never --json --ignore-user-config -c model_reasoning_effort=medium \
  --output-schema .maestro/critique-schema.json -o "$J/answer" "$(cat .maestro/brief-critique.md)"
#   high stakes: the astra slug, model_reasoning_effort=high

# build — workspace-write
codex exec -m <slug> -s workspace-write --color never --json --ignore-user-config -c model_reasoning_effort=medium \
  -o "$J/answer" "$(cat .maestro/stub-build.md)"

# builder resume — NO -s / --color / -C; sandbox via -c; ALWAYS the thread UUID from
# thread.started.thread_id in the first job's `out`. --last is banned. Before it, record the
# rollout offset (Effective-config check). Run from the worker's own directory.
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

**Pinned mode**: replace `--ignore-user-config` with `-c approvals_reviewer="user"`, and on the
read-only lines also add `-c mcp_servers.<name>.enabled=false` for each `[mcp_servers.<name>]` in
`$CODEX_HOME/config.toml`.

**Parallel Codex workers**: the director creates each worktree first (`git worktree add --detach
"$REPO/.maestro/worktrees/<part>" HEAD`, inside the fence) and launches with `-C "$REPO/.maestro/worktrees/<part>"`
(maestro-run's `--cwd` set to the worktree, so a resume runs there too). Codex's own `--worktree` is
not used (it cannot be combined with `--ignore-user-config`).

## Claude — `claude -p`

```bash
# probe (stage 0 step 5) — also how the native alias is resolved to a full id
claude -p --model <alias> --effort low --tools "" --permission-mode dontAsk --strict-mcp-config \
  --setting-sources "" --output-format stream-json --verbose "Reply with exactly: OK"
#   the full id = init.model (and result.modelUsage); freeze it for the slot

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

A parallel `claude -p` writer runs with its cwd in the worktree (maestro-run `--cwd`).

## Claude — `api` (`maestro-sdk`, the Agent SDK on an API key)

Through `maestro-env` like every worker; it drops the director's `ANTHROPIC_*` and `maestro-sdk`
sets the key from its own file. Full ids only. `B` = `--max-budget-usd`: policy
`api.max_usd_per_run` minus `maestro-ledger cost --run <run_id> --transport api`.

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

The `init` checks are those of `claude -p` below, plus `apiKeySource == "ANTHROPIC_API_KEY"`
(`maestro-sdk` aborts on anything else itself). `result.subtype == "error_max_budget_usd"` = the
run's api budget is spent: quota on this transport. The ledger row is `--cli claude-sdk --transport
api`.

**`init` checks — fail closed**, as soon as the first event is in `out` (`maestro-wait` returns
while the job runs; the first line may take a few seconds): `tools` equals the requested set,
`mcp_servers` is empty, every `plugins[].source` ends in `@builtin`, `permissionMode` is the
requested one, `model` is the frozen id. Anything else → `maestro-kill` the job, discard, the
transport is ineligible for that role this run. No `init` before another event is a failure too.

## Claude and Gemini — `agy`

```bash
J="$REPO/.maestro/jobs/<job>"      # the job directory (maestro-run creates it)
# --add-dir "$REPO" on every call or the worker sees no project skills/rules.
# --log-file "$J/agy.log" on every call: this run's own log, for maestro-wait --also.
# critique — plan mode; the brief (paths inside $REPO, nothing quoted) in -p, opening with the
# "read inside <REPO> only" paragraph; the worker reads the plan, the diff file and the code itself.
# A denied read → a new conversation with the inline variant (whole brief quoted, "no tools").
# The verdict is the envelope's .structured_output (else JSON inside .response). Same shape for a
# gate or a review.
agy --model gemini-<v>-flash-medium --mode plan --effort medium --add-dir "$REPO" --output-format json \
  --json-schema .maestro/critique-schema.json --log-file "$J/agy.log" --print-timeout 30m \
  -p "$(cat .maestro/brief-critique.md)"
#   Argon: --model gemini-<v>-argon-medium; Claude on agy: --model claude-opus-<v>-medium (or
#   claude-sonnet-…); everything else identical

# build — accept-edits, EDITS ONLY: one denied command cancels the whole run
agy --model <slug> --mode accept-edits --effort medium --add-dir "$REPO" --output-format json \
  --log-file "$J/agy.log" --print-timeout 60m -p "$(cat .maestro/stub-build.md)"

# builder resume — by id, never -c/--continue; only after a SUCCESS turn
agy --conversation <CONVERSATION_ID> --model <slug> --mode accept-edits --effort medium \
  --add-dir "$REPO" --output-format json --log-file "$J/agy.log" --print-timeout 60m \
  -p "$(cat .maestro/stub-fix1.md)"

# critic / gate / reviewer continuation — keeps plan mode, its schema and the brief in -p
agy --conversation <CONVERSATION_ID> --model <slug> --mode plan --effort medium --add-dir "$REPO" \
  --output-format json --json-schema .maestro/critique-schema.json --log-file "$J/agy.log" \
  --print-timeout 30m -p "$(cat .maestro/brief-critique-r2.md)"

# probe
agy --model <slug at its lowest effort> --mode plan --effort low --add-dir "$REPO" --output-format json \
  --log-file "$J/agy.log" --print-timeout 2m -p "Reply with exactly: OK"
```

The slug suffix and `--effort` always agree. Progress for an agy job: `maestro-wait <job> --also
"$J/agy.log"` — the run's own log, written while it runs (agy 1.4.8 `--log-file`, measured
2026-10-28); the envelope is written whole at exit. (Before `--log-file`, maestro had to guess the
newest `~/.gemini/antigravity-cli/log/cli-*.log`, which races when two agy runs start together.) agy usage is reported per
conversation and looks cumulative across `--conversation` turns: keep it raw in the ledger's
`raw_cumulative`.

**Stubs — builders and drafters only.** Their `-p` prompt is a pointer — *"Read
`.maestro/stub-build.md`'s brief at `.maestro/brief-build.md` in the workspace and execute it exactly.
Your final answer is only what it asks for."* — small and free of shell quoting. Critics, gates and
reviewers get their brief in `-p` — short, since it names paths and quotes nothing; only the inline
variant (after a denied read) carries everything, and above ~100 KB it is split or the role goes to
another family.

## Grok and Claude — Cursor `agent`

```bash
# critic / gate / reviewer / probe — plan mode INSIDE the sandbox, never --force
agent -p --mode plan --sandbox enabled --trust --model grok-<v>-medium --output-format stream-json \
  --workspace "$REPO" "$(cat .maestro/brief-critique.md)"
#   the brief quotes the schema, forbids reading or searching outside $REPO (since 2026.10.15
#   Cursor's Grep and Glob can search folders outside the workspace) and ends: "Your final message
#   must be the JSON object only. Answer in English."

# builder — rung 1: Cursor's sandbox (workspace and /tmp writable, no network, no $HOME)
agent -p --sandbox enabled --trust --model <slug> --output-format stream-json \
  --workspace "$REPO_OR_WORKTREE" "$(cat .maestro/stub-build.md)"

# continuation — by session id, every flag of the role repeated, never --continue
agent -p --resume <SESSION_ID> --mode plan --sandbox enabled --trust --model <slug> \
  --output-format stream-json --workspace "$REPO" "$(cat .maestro/brief-critique-r2.md)"

# reach probe for a Cursor builder (stage 0 step 8) — one cheap model turn
agent -p --sandbox enabled --trust --model grok-<v>-low --output-format stream-json --workspace "$REPO" \
  "Run exactly this shell command once and reply with its exit code and the last 5 lines of its output: <cheap check>"
#   judge by effect (docs/sandbox-and-preflight.md); fail → Cursor builders are edits-only

# probe
agent -p --mode plan --sandbox enabled --trust --model <slug at its lowest effort> --output-format stream-json \
  --workspace "$REPO" "Reply with exactly: OK"
```

**`init` check**: the first event must be `system/init`; `init.model` must match the requested
slug on family, version and effort, ignoring decoration ("Grok 4.7 256K Low" ↔ `grok-4.7-low`);
mismatch or no `init` → `maestro-kill`, discard, dirty-exit for a writer.

## Reading results

Never load a whole event stream into context — a long build log is tens of thousands of tokens:

```bash
J=.maestro/jobs/<job>
grep -m1 '"thread.started"' "$J/out"                     # codex: thread_id for resume
grep '"turn.completed"' "$J/out" | tail -1                # codex: usage
grep -E '"turn.failed"' "$J/out" | tail -3                # codex: failure, if any
jq -c 'select(.type == "system" and .subtype == "init")' "$J/out" | head -1      # claude -p / cursor: init
jq -c 'select(.type == "result") | del(.result)' "$J/out" | tail -1              # claude -p / cursor: result
jq -c '{status, conversation_id, denied_actions, usage}' "$J/out"                # agy envelope
jq -c '.structured_output' "$J/out"                                               # agy verdict (schema calls)
```

- **Codex:** the `-o` file (`$J/answer`) is the answer; a reconnect `error` event is Codex
  retrying, a failure is `turn.failed` or an exit without `turn.completed`.
- **agy:** check `status == "SUCCESS"`, `(denied_actions ?? []) == []`, and a non-empty answer —
  `structured_output` when present (schema calls), else `response`. Any
  other status invalidates the `conversation_id` — follow up in a new conversation with the
  current diff.
- **`claude -p`, Cursor:** the `result` event; `subtype == "success"` and `is_error == false`, and
  for `claude -p` `permission_denials` (empty for read-only roles; a denied Edit or Write fails a
  builder's turn).
- **Completion = all of:** the job `exited` with code `0`, the envelope above succeeded, and for a
  read-only role a valid verdict.

### Validating a verdict

```bash
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json .maestro/jobs/<job>/answer --envelope codex
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json .maestro/jobs/<job>/out --envelope agy
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json .maestro/jobs/<job>/out --envelope claude --role read-only
"$MAESTRO/bin/maestro-validate" .maestro/critique-schema.json .maestro/jobs/<job>/out --envelope cursor
```

It checks the envelope first (an envelope failure is not an invalid verdict), then extracts
**exactly one** top-level JSON object (one surrounding fence stripped; leading prose allowed —
Grok opened two of seven critiques with a sentence; trailing text or a second object rejected),
then validates it completely against the schema. Invalid → one re-ask on the same session with
the validator's `errors`; still invalid → the role moves to the next eligible critic (a named
critic → halt).

### Read-only proof

```bash
"$MAESTRO/bin/maestro-fp" snapshot > .maestro/tmp/fp-<job>.json     # before the call
… the call …
"$MAESTRO/bin/maestro-fp" compare .maestro/tmp/fp-<job>.json         # after: {result: same|changed, diffs}
```

`changed` → the verdict is discarded, dirty-exit, the transport is ineligible for read-only roles
this run. Bookkeeping written legitimately during the call (the session id from `init`, the ledger
row) goes through `maestro-state`, so it compares as audited, not as a change.

### Effective-config check

After every Codex launch (once `thread.started` is in the `.jsonl`) and every resume, confirm what
the worker actually runs with. Codex writes a rollout file per thread,
`$CODEX_HOME/sessions/YYYY/MM/DD/rollout-<time>-<thread_id>.jsonl`, with one `turn_context` record
per turn: `model`, `effort`, `sandbox_policy`, `approval_policy`, `approvals_reviewer` and a
`permission_profile` that lists network access and every writable root. Before a resume, record the
rollout's line count as the session's `rollout_offset` (`wc -l < "$R"`); the check reads the first
`turn_context` after it, so an earlier turn's record can never pass for the resumed one (a launch
uses 0). Run it in the foreground; it waits at most two minutes:

```bash
# Effective-config check. Set THREAD (thread.started.thread_id), OFFSET (rollout lines before this
# launch or resume; 0 for a launch) and the expected values, then run in the foreground (<= 2 min).
# Prints OK, MISMATCH <fields> or MISSING; anything but OK stops the worker.
TC=""
for i in $(seq 25); do            # 24 waits of 5 s, then one last read (the rollout outlives the process)
  R=$(find "${CODEX_HOME:-$HOME/.codex}/sessions" -name "rollout-*-$THREAD.jsonl")
  if [ "$(printf '%s' "$R" | grep -c .)" = 1 ]; then
    TC=$(tail -n +$((OFFSET + 1)) "$R" | grep -m1 '"type":"turn_context"')
  fi
  [ -n "$TC" ] || [ "$i" = 25 ] && break
  sleep 5
done
[ -z "$TC" ] && echo MISSING || printf '%s\n' "$TC" | jq -r \
  --arg model "$MODEL" --arg effort "$EFFORT" --arg sandbox "$SANDBOX" \
  --arg approval "$APPROVAL" --arg reviewer "$REVIEWER" --arg root "$ROOT" '
  .payload as $p | ($p.permission_profile // {}) as $pp
  | [ (if $p.model != $model then "model=\($p.model)" else empty end),
      (if $p.effort != $effort then "effort=\($p.effort)" else empty end),
      (if $p.sandbox_policy.type != $sandbox then "sandbox=\($p.sandbox_policy.type)" else empty end),
      (if $p.approval_policy != $approval then "approval_policy=\($p.approval_policy)" else empty end),
      (if $p.approvals_reviewer != $reviewer then "approvals_reviewer=\($p.approvals_reviewer)" else empty end),
      (if $sandbox == "danger-full-access" then
         (if $pp.type != "disabled" then "permission_profile=\($pp.type)" else empty end)
       elif $pp.type != "managed" or $pp.file_system.type != "restricted"
            or ($pp.file_system.entries | type) != "array" then
         "permission_profile=\($pp.type)/\($pp.file_system.type // "none")"
       else
         (if $pp.network != "restricted" then "network=\($pp.network)" else empty end),
         (if ($p.sandbox_policy | has("network_access")) then
            (if $p.sandbox_policy.network_access != false then "network_access=\($p.sandbox_policy.network_access)" else empty end)
          elif $sandbox != "read-only" then "network_access=missing" else empty end),
         ([$pp.file_system.entries[] | select(.access == "write")
           | if .path.type == "path" then .path.path else "special:\(.path.value.kind)" end
           | select(. != "special:slash_tmp" and . != "special:tmpdir")] as $w
          | if $sandbox == "read-only" then (if $w != [] then "writable=\($w | join(","))" else empty end)
            elif $w != [$root] then "writable=\($w | join(","))" else empty end)
       end) ]
  | if length == 0 then "OK" else "MISMATCH " + join(" ") end' || echo "MISMATCH malformed"
```

Expected values (`ROOT` = the directory the worker writes in: the checkout, or its worktree for a
parallel worker; empty for read-only):

| Role | `SANDBOX` | `APPROVAL` | `REVIEWER` | Network | Write roots |
| --- | --- | --- | --- | --- | --- |
| critic, gate, reviewer, probe | `read-only` | `never` | `user` | restricted | none |
| builder, drafter, fix — rung 1 | `workspace-write` | `never` | `user` | restricted | `ROOT` only |
| rung 3 | `workspace-write` | `on-request` | `auto_review` | restricted | `ROOT` only |
| rung 4 | `danger-full-access` | `never` | `user` | not checked (`permission_profile.type: disabled`) | not checked |

`/tmp` and `$TMPDIR` are writable specials in every sandboxed profile and are allowed; any other
writable special (such as the file-system root) is a mismatch. Pinned mode produces the same rows —
that is what the pins are for. The ledger row of the call gets the checked fields as
`effective_config`.

Verified on 0.159.2 against real rollouts — read-only, rung 1, rung 3 on exec and resume, a worktree
writer and its resumed fix, rung 4, a resume at effort `medium` after a launch at the catalog default
— and against altered copies: stale offset, wrong effort, `network_access: true`, contradictory
network fields, a missing or unrestricted file-system section, a writable root special, truncated
JSON, no record, two rollouts for one id.

## Progress sampling

Interactive Claude Code: every 5 minutes, by a background `sleep 300` or a `Monitor` whose command
prints one line per sample and exits when the PID dies — never by ending the turn; re-arm the
monitor on every expiry. Every other host: `maestro-wait <job> --max <n>` in a loop; it persists
`last_progress_at` in the job directory, so the hang clock survives calls and turns. Progress
sources: new events in a codex `--json`, `claude -p` or Cursor `stream-json` stream (thinking deltas
count), the agy CLI log passed with `--also`, `git status` changing. Silence is a hang only after
`max(15 min, 2 × T_slow)`, and never for a test run. Before killing, read the job's files: stderr
prints `Reading additional input from stdin...` even on healthy Codex runs; the hang signal is that
line **with no `thread.started` event**. Kill with `maestro-kill` (it spares tests and signals
members one by one) or, in an interactive Claude Code, by the harness task or PID — never `pkill -f`.
