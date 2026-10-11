# Cost ledger

`.route2/ledger.jsonl`, one line per model call, appended right after reading its output:

```
{ts, run_id, stage, host, cli, transport, family, model_requested, model_served, effort,
 service_tier_requested, service_tier_observed, effective_config, session_id, job_id, duration_s,
 input_tokens, cached_input_tokens, cache_write_input_tokens, output_tokens, reasoning_tokens,
 total_tokens, raw_cumulative, denied_actions, exit_code, status, outcome}
```

## Sources

| CLI | Where the numbers are |
| --- | --- |
| Codex | the last `turn.completed.usage` in the `.jsonl`: `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens` → `reasoning_tokens` |
| agy | the envelope's `usage`: `input_tokens`, `output_tokens`, `thinking_tokens` → `reasoning_tokens`, `cache_read_tokens` → `cached_input_tokens`, `total_tokens`; plus `duration_seconds`, `denied_actions[].action` |
| Claude subagent | the Agent tool's completion line |
| `claude -p` | the `result` event: `usage.input_tokens`, `usage.cache_read_input_tokens` → `cached_input_tokens`, `usage.cache_creation_input_tokens` → `cache_write_input_tokens`, `usage.output_tokens`, `duration_ms`/1000; `model_served` = the `modelUsage` key(s) |
| Cursor `agent -p` | the `result` event: `usage.inputTokens`, `usage.cacheReadTokens` → `cached_input_tokens`, `usage.cacheWriteTokens` → `cache_write_input_tokens`, `usage.outputTokens`, `duration_ms`/1000; `model_served` = `init.model` (a label) |
| Codex, `effective_config` | the call's `turn_context` in the session rollout, as the effective-config check read it (`docs/commands.md`): `{model, effort, sandbox, approval_policy, approvals_reviewer, network, write_roots}`; `null` for non-Codex calls |

`cli` is one of `codex`, `agy`, `cursor-agent`, `claude-cli` (`claude -p`), `claude-agent` (the
Agent tool); `transport` the slot's transport (`native`, `agy`, `cursor`, `codex`); `host` the
director's host; `job_id` the route2 job (null for an Agent-tool call). Missing → `null`, never
estimated. `codex exec review` (a manual extra, not the cross reviewer)
reports zero usage, so its token fields are `null`.

**`codex exec resume` reports usage cumulatively per thread.** Keep the thread's raw counters as
reported in `raw_cumulative` (`null` for a non-Codex call), and put the delta into the token
fields: `delta[n] = raw[n] − raw[n−1]`, both taken from `raw_cumulative`, never from the previous
row's token fields. The token fields then sum to the thread total. Example — raw input 100, 150,
180 → token fields 100, 50, 30 → sum 180. Subtracting the previous row's *delta* instead gives
100, 50, 130 → 280, the error this rule exists to prevent.

Codex runs on the standard tier (`service_tier` unset — a `fast` profile exists for interactive
use). In pinned mode a `service_tier` set in `config.toml` reaches the worker; then
`service_tier_requested` records that value instead of `null`. The served tier is not recorded
anywhere — the rollout's `turn_context` has no tier field either — so `service_tier_observed` is
always `null`. Token
totals are never presented as subscription cost.

A worker swap mid-run gets its own row with `outcome: "swapped: <reason>"` on the abandoned call; a
transport switch (`docs/hosts.md`) gets `outcome: "transport-switch: <from>→<to> (<reason>)"`.

**agy conversations report cumulative usage** too (measured: a continued critic's `thinking_tokens`
and cache counts repeated the earlier turn's): treat them like a `codex exec resume` thread — raw
counters in `raw_cumulative`, deltas in the token fields.

`bin/route2-ledger` builds the row from a job's files (the sources in the table above) and appends
it — the canaries showed that a director composing rows by hand drops fields (`stage`, `cli`,
tokens). Every row is appended through `route2-state --gen N append ledger.jsonl` (the audit makes a ledger
edited by anything else stop the next write).

## Report table

`Stage | Who (model@effort) | Wall | In | Out | Result`, totals per family, the cascade line when it
ran (`cascade: accepted at round N | escalated after N — draft+gate cost vs escalation cost`), and
the guarantees line (review mode, tests, sandbox rung, what was skipped or degraded).
