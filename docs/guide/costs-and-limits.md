# Costs and limits

maestro has no account and no price of its own. Every model call draws on the subscription of
the CLI that served it, and the run keeps a record of each call so the report can tell you where
the tokens went.

## Which pool pays for what

| Road (transport) | What it serves | Paid from |
| --- | --- | --- |
| native (`claude -p`, Claude Code subagents) | Claude models | your Claude plan's 5-hour and weekly limits |
| `codex exec` | GPT models | your ChatGPT plan |
| agy | Gemini, and Claude models | your Antigravity account |
| Cursor `agent` | Grok, Argon, and Claude models | your Cursor plan |
| `api` (the Agent SDK) | Claude models | the Max plan's monthly API credit, through an API key |

Three things cost tokens beyond the build itself. **Critique**: each critic reads the plan once per
round, and a risky change adds a second critic. **Probes**: the first run in a repository checks
each chosen model with one cheap call; a passed probe is reused for up to seven days, in that
repository only and only while the CLI version, account and host still match (an agy probe is
never reused across director sessions). **Review**: with `--review=full` or `cross` a model from a
family other than the builder's — by default the plan critic's slot — reads the whole diff;
`--review=self` adds no external call. The director's own work — reading diffs, running tests,
waiting for jobs — costs its host's tokens, like any assistant session.

More critics does not simply mean more cost from one pool: Gemini and Grok draw on pools that
would otherwise sit idle, which is often the point of using them.

## The API credit

A Max plan includes a monthly API credit ($200 on Max 20x, $100 on Max 5x) that covers the Claude
API and the Agent SDK but not Claude Code. With `--sdk` the Claude workers run on that credit
instead of the subscription; with `api: {fallback: true}` in your policy the director switches to
it on its own when the subscription limit runs out mid-run. Set-up steps and caveats are in the
[README](../../README.md#api-credit). The credit is only visible in the Console; the dollar figure
maestro reports is the SDK's estimate.

## The ledger and the cost table

Every model call is appended to `.maestro/ledger.jsonl` right after its output is read: the stage,
the host, the CLI and road, the family, the model requested and the model that actually answered,
the effort level, tokens in and out (with cached and reasoning tokens where the CLI reports them),
wall time, the outcome. A number the CLI did not report is left empty, never estimated.

The report turns the ledger into one table — `Stage | Who (model@effort) | Wall | In | Out |
Result` — with totals per family, a cascade line when a draft ran, and a line with the guarantees
(review mode, tests, sandbox level, what was skipped or degraded). Token totals are never shown as
money, because a subscription has no per-token price; the one exception is `api` calls, which
carry a dollar estimate and a per-run sum.

## When a limit runs out

A usage limit is routine. What happens depends on the slot:

- **A Claude slot with another road left** continues on it, for the same model: natively, then
  agy, then Cursor, then `api` if you enabled it. The brief is rewritten for the new road (for
  example "edits only, the director runs the tests"), critics stay (same family), and the ledger
  marks the switch.
- **A slot with no road left** — a GPT, Gemini or Grok worker, or a Claude slot whose roads are
  all exhausted — makes the director inspect what the worker left behind, write the checkpoint
  with a `quota` blocker, and stop. `/maestro --resume` probes the limit again and continues the
  same worker session; the director never reasons from a remembered reset time.
- **A forced road** (`--model=opus@agy`) never switches: it stops and asks.

When your Claude Code session itself hits the limit, the director stops too. Directing from Codex,
Cursor or agy and letting only the Claude workers use the credit avoids that.

## Hard stops

- **Per run on the API credit:** `api.max_usd_per_run` in the policy, $20 by default. Each `api`
  call is launched with the remaining budget, and the SDK stops the call when it is spent.
- **Beyond maestro:** the spend limit of the Console workspace your key belongs to. Set it; it is
  the only stop maestro cannot overrun.
- **Rounds:** critique at most `--rounds` (default 2, up to 8) and the fix loop at most 3 — at
  either cap the run stops with a diagnosis and hands you the decision; there is no silent extra
  round. The cascade's gate is different: it gets at most 2 rounds to accept the draft (a draft
  can pass in either); if it has not passed by then, the implementer builds — the planned
  fallback, not a stop.
- **Time:** a cascade draft gets 25 minutes; a worker with no progress for at least 15 minutes (or
  twice the slowest test, whichever is longer) is stopped. Tests are never stopped.
- **Scope:** every worker gets explicit boundaries, and the director's diff read rejects anything
  outside them.

## Technical details

- [ledger.md](../ledger.md) — every field of a ledger row and where it comes from.
- [workers.md](../workers.md), "Claude through the Agent SDK" — the `api` road, the key file, the
  budget flag.
- [hosts.md](../hosts.md), "Transport switch" — the switch as one transaction.
- [policy.md](../policy.md) — `api.fallback`, `api.max_usd_per_run`, denying roads.
- [catalog.md](../catalog.md), "Precedence" — what a quota failure does to each kind of slot.
