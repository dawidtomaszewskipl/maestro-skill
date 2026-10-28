# Cost ledger

> **What this page is for.** The exact format of the cost ledger — one line per model call — and where each number comes from. The plain overview is in [the guide](guide/costs-and-limits.md).

`.maestro/ledger.jsonl`, one line per model call, appended right after reading its output:

```
{ts, run_id, stage, host, cli, transport, family, model_requested, model_served, effort,
 service_tier_requested, service_tier_observed, effective_config, session_id, job_id, duration_s,
 input_tokens, cached_input_tokens, cache_write_input_tokens, output_tokens, reasoning_tokens,
 total_tokens, raw_cumulative, denied_actions, tool_uses, cost_usd, exit_code, status, outcome}
```

## Sources

| CLI | Where the numbers are |
| --- | --- |
| Codex | the last `turn.completed.usage` in the `.jsonl`: `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens` → `reasoning_tokens` |
| agy | the envelope's `usage`: `input_tokens`, `output_tokens`, `thinking_tokens` → `reasoning_tokens`, `cache_read_tokens` → `cached_input_tokens`, `total_tokens`; plus `duration_seconds`, `denied_actions[].action` |
| Claude subagent | the Agent tool's completion: `total_tokens`, `tool_uses`, `duration_ms` and the model; no input/output split, so those fields are `null` — `maestro-ledger --cli claude-agent --served <model> --agent-id <id> --total-tokens N --tool-uses N --duration-ms N` (no job) |
| `claude -p` | the `result` event: `usage.input_tokens`, `usage.cache_read_input_tokens` → `cached_input_tokens`, `usage.cache_creation_input_tokens` → `cache_write_input_tokens`, `usage.output_tokens`, `duration_ms`/1000; `model_served` = the `modelUsage` key(s) |
| `api` (`maestro-sdk`) | as `claude -p` (the same event stream), plus `cost_usd` = `result.total_cost_usd` — the SDK's estimate from its bundled price table, not an invoice; `null` on every other CLI |
| Cursor `agent -p` | the `result` event: `usage.inputTokens`, `usage.cacheReadTokens` → `cached_input_tokens`, `usage.cacheWriteTokens` → `cache_write_input_tokens`, `usage.outputTokens`, `duration_ms`/1000; `model_served` = `init.model` (a label) |
| Codex, `effective_config` | the call's `turn_context` in the session rollout, as the effective-config check read it (`docs/commands.md`): `{model, effort, sandbox, approval_policy, approvals_reviewer, network, write_roots}`; `null` for non-Codex calls |

`cli` is one of `codex`, `agy`, `cursor-agent`, `claude-cli` (`claude -p`), `claude-sdk`
(`maestro-sdk`), `claude-agent` (the Agent tool); `transport` the slot's transport (`native`, `agy`,
`cursor`, `codex`, `api`); `host` the
director's host; `job_id` the maestro job (null for an Agent-tool call). `run_id` and `host` come
from the job's `meta.json`; an interactive Claude Code launches with the Bash tool's background mode,
so its job directories have none, and `maestro-ledger` takes both from the lock record (or from
`--run`/`--host`). Missing → `null`, never
estimated. `codex exec review` (a manual extra, not the cross reviewer)
reports zero usage, so its token fields are `null`.

**Codex token numbers are not comparable across CLI versions.** 0.163 started counting usage for
incomplete responses, and 0.164 stopped counting retained reasoning twice (release notes), so the
same work reports fewer reasoning tokens from 0.164 on. Compare rows of one CLI version (the probe
scope records it), not across an upgrade.

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

`bin/maestro-ledger` builds the row from a job's files (the sources in the table above) and appends
it — the canaries showed that a director composing rows by hand drops fields (`stage`, `cli`,
tokens). Every row is appended through `maestro-state --gen N append ledger.jsonl` (the audit makes a ledger
edited by anything else stop the next write).

## Report table

`Stage | Who (model@effort) | Wall | In | Out | Result`, totals per family, the cascade line when it
ran (`cascade: accepted at round N | escalated after N — draft+gate cost vs escalation cost`), and
the guarantees line (review mode, tests, sandbox rung, what was skipped or degraded).

## API spend

`maestro-ledger cost --run <run_id> --transport api` → `{run_id, transport, cost_usd, rows}`, the
sum of the run's `cost_usd`. Before every `api` launch the director passes `--max-budget-usd` =
policy `api.max_usd_per_run` minus that sum. The report shows the `api` spend in USD; token totals
of the other transports are still never presented as subscription cost.
