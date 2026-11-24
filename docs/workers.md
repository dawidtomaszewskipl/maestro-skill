# Workers and CLI mechanics

> **What this page is for.** Measured facts about each CLI that serves a model — flags, sandboxes, permissions, quirks — so that briefs and launch lines match what a worker can do. The plain overview is in [the guide](guide/models-and-roles.md).

The OpenAI and agy facts below were first checked against **Codex CLI 0.153.4** and **Antigravity
CLI 1.1.27** on 2026-09-06 and re-checked up to Codex 0.159.2 (2026-09-30). The parts maestro
changes were re-checked on **2026-10-11** with **Codex CLI 0.162.1**, **agy 1.3.3** and **Claude
Code 2.1.296**, on **2026-10-28** against **Codex 0.165.0**, **agy 1.4.8** and **Claude Code
2.1.312**, on **2026-11-14** against **Codex 0.169.0**, **agy 1.5.9** and **Claude Code
2.1.325** (help diffs of old and new binaries, `agy changelog`, Claude Code's changelog, the live
catalogs; those statements say so), and on **2026-11-24** against **Codex 0.172.0**, **agy
1.5.16** and **Claude Code 2.1.331** (the Codex release notes through `gh release view`, `agy
changelog`, Claude Code's `CHANGELOG.md` for 2.1.326–2.1.331 — 2.1.321–2.1.325 were not re-read —,
`--help` of each binary, the live catalogs and one observed `codex exec resume`). Every claim
added on 2026-11-24 carries a label: **vendor** (the maker's own notes or numbers),
**independent** (a third party's own measurement), **secondhand** (someone reporting either), or
**local measurement** (run here); "not verified" marks what has no retrievable source. Catalogs and flag
sets move: maestro reads the catalogs live (`docs/catalog.md`) and re-checks a flag with `--help`
rather than trusting a table that has aged.

## Family is decided by the model, not by the CLI

agy's catalog hosts other vendors' models next to Google's own (local measurement 2026-11-24,
agy 1.5.16; the fixture is `tests/fixtures/catalogs/machine-2026-11-24/agy-models.txt`):

```
$ agy models
gemini-4-neon-{low,medium,high,xhigh}       Gemini 4 Neon
gemini-4-carbon-{low,medium,high}           Gemini 4 Carbon
gemini-4-argon-{low,medium,high}            Gemini 4 Argon
gemini-4-hydrogen-{low,medium,high,xhigh}   Gemini 4 Hydrogen
gemini-pro-orchestrator-neon                Orchestrator (Neon)
gemini-pro-orchestrator                     Orchestrator (Carbon)
gemini-pro-orchestrator-argon               Orchestrator (Argon)
gemini-3.8-flash-{low,medium,high}          Gemini 3.8 Flash
claude-opus-5-5-{low,medium,high}           Claude Opus 5.5
claude-sonnet-5-5-{low,medium,high}         Claude Sonnet 5.5
gpt-oss-120b-medium                         GPT-OSS 120B
```

(agy listed Gemini 3.7 and 3.6 Flash and 3.1 Pro on 2026-10-11; by 2026-10-28 they were gone.
Hydrogen appeared between 2026-10-28 and 2026-11-14; Carbon and Neon between 2026-11-14 and
2026-11-24, when `gemini-pro-orchestrator-g1-pro` of 2026-11-14 was gone.)

So a slot's family follows the **model** it resolves to, whatever CLI serves it: `opus@agy` is
Claude, exactly like `opus` through the Agent tool. maestro uses agy's Claude models as a further
**transport** of the Claude slots (SKILL.md, "Roster"). The orchestrator entries and GPT-OSS have no
slot (they stay `unmatched` in the catalog and can never be pinned to a slot).

An `agy` call with no `--model` runs the account default, and Codex falls back to
`~/.codex/config.toml`. If that default is from another family, "Google critiqued the Claude plan"
was Claude critiquing Claude, and nothing in the output says so.

**Availability is detected, not assumed.** Stage 0 checks three different things, all free of model
turns: installation (`command -v codex|agy|claude`), sign-in (`codex login status` — prints
`Logged in using ChatGPT` and exits 0; `agy models` succeeding, since it fetches the catalog; `claude
auth status` — `loggedIn: true`, and since Claude Code 2.1.318 `loginExpiresAt`, which
`maestro-preflight` turns into a warning when the login ends within a day) and
health (`codex doctor --summary`, exit 0 with `0 fail` — on 0.169 the line reads `21 ok · 0 warn ·
0 fail ok` —, **run where the worker will run** — the same
signed-in install fails doctor inside a sandbox with unreachable endpoints). A health failure makes the
worker unavailable in that environment, not signed out; none of the checks proves entitlement to a
particular model. `bin/maestro-preflight` runs all of these in one call. The cross-family rule then resolves among the families that are actually there; with
Claude alone every external role is a different Claude model than the implementer and the run is marked
degraded. A `--model` naming an unavailable family halts with a question. A policy file
(`docs/policy.md`) can also switch a family off.

**Pass `--model` / `-m` on every external call. Record the requested model; the served model is
unverified unless you confirmed it** (vendor-side substitution at quota limits is a rumour, not a
verified behaviour — omitting `--model` is the real risk).

## OpenAI — `codex exec`

### Models

maestro resolves the OpenAI lines live (`docs/catalog.md`); the table below is the catalog as
measured on 0.159.2 (2026-09-30), kept for its per-model notes. On 2026-11-14 (0.169.0) the live
catalog resolves `sol` → `gpt-6.1-sol` (its probe passed the same day), `astra` → `gpt-6-astra`, `luna` → `gpt-6-luna`, `terra` →
`gpt-6.1-terra`, with nothing unmatched (fixture `machine-2026-11-14`). On 2026-10-11 `codex debug models`
(0.162.1) listed the same `visibility: list` slugs except that `gpt-5.5` is now hidden; `sol`
resolved to `gpt-6.1-sol`, `astra` to `gpt-6-astra`, `luna` to `gpt-6-luna`, `terra` to
`gpt-5.6-terra`. On 2026-10-28 (0.165.0) the live catalog also lists **`gpt-6.1-terra`** ("GPT-6.1
Terra Codex model", efforts `low … ultra`, catalog default `low`; no announcement found), so `terra`
now resolves to 6.1 — its probe passed the same day (evidence: maestro run docs-20261028-0134, `1.1-terra-probe.txt`). `gpt-5.5` is gone from the live catalog (it
retired on 2026-10-14) but stays in `--bundled`.

**2026-11-24, Codex 0.172.0 — GPT-6.2.** Local measurement (`codex debug models`, the reduced copy
is fixture `machine-2026-11-24`): `visibility: list` holds `gpt-6.2-sol` (context 500 000),
`gpt-6.2-astra` (272 000), `gpt-6.1-sol` (500 000), `gpt-6.1-terra` (500 000), `gpt-6-astra`,
`gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra` and `gpt-5.6-luna`, nothing unmatched.
Efforts `low … ultra` for Sol, Astra and Terra, `low … max` for Luna; catalog default `low` for both
6.2 models. The resolver is generic, so nothing in the skill changed for them: on a catalog
refreshed from the fixture, `maestro-catalog candidates sol codex` gives 6.2, 6.1, 6, 5.6 and
`astra` gives 6.2, 6 (test T2). **6.2 is the first candidate until the account probe succeeds**;
a denial walks down to 6.1 Sol / 6 Astra as for any line (`docs/catalog.md`, "Walk-down"). A
read-only probe of `gpt-6.2-astra` at `low` passed on 2026-11-24 (local measurement, maestro run
upd-20261124-1248); `gpt-6.2-sol` had not been probed here yet.

Evidence on GPT-6.2, as recorded on 2026-11-24 (sources read that day):

| Claim | Label | Source |
| --- | --- | --- |
| API prices per million tokens: Astra "$8 for input, $0.40 for cached input, and $40 for output", Sol "$2 for input, $0.10 for cached input, and $10 for output" | vendor | [OpenAI, "Introducing GPT-6.2 Astra and Sol"](https://openai.com/index/introducing-gpt-6-2-astra-sol/), read 2026-11-24 (the page carries no calendar date) |
| Released 2026-11-17 | independent (date of the measurement article) | [Artificial Analysis, 2026-11-17](https://artificialanalysis.ai/articles/openai-has-the-2-model-in-the-intelligence-index-with-the-release-of-gpt-6-2-astra-and-gpt-6-2-sol), read 2026-11-24 |
| FrontierCode 2.0: "GPT-6.2 Sol comes within 0.5 points of GPT-6.2 Astra at about one-fifth the cost (both at max)" — no absolute scores on the page | vendor | the OpenAI page above |
| Coding Agent Index (max effort, Codex harness): Astra 6.2 flat against GPT-6 Astra; Sol 6.2 3 points below 6.1 Sol, "driven by a 14-point drop in SWE-Atlas-QnA-AA" | independent | the Artificial Analysis article above. Its absolute index values are not quoted: they differed between fetches during the research |
| FrontierCode 2.0 main score and mean cost per rollout (list API prices), Codex harness: Astra 6.2 44.2 % at `max` ($5.97), 44.1 % at `xhigh` ($4.29); Sol 6.2 43.8 % at `max` ($1.29), 39.7 % at `high` ($0.88); Sol 6.1 39.7 % at `max` ($1.03). For scale: Fable 5.2 50.2 % at `xhigh` ($17.73), Opus 5.5 47.3 % at `max` ($12.82), both on the Claude Code harness | independent (Cognition's own runs); both 6.2 models added 2026-11-09 | [Cognition, FrontierCode leaderboard](https://cognition.com/frontiercode) — the chart's data file `cognition.com/data/frontier-code-2.0/data.json` (field `new_score` = the board's score), read 2026-11-24; the page's own ranking list gives the same top scores |
| Sol 6.2 is the default catalog selection of Codex | vendor | [Codex 0.171.0 release notes](https://github.com/openai/codex/releases/tag/rust-v0.171.0) |
| "Blocker Deception": GPT-6.2 Astra concealed or misrepresented a known obstacle in 22.28 % of coding trials, GPT-6 Astra in 11.09 % | vendor figure (system card), reported secondhand | [The New Stack](https://thenewstack.io/astra-hides-coding-failures/); [Decrypt, 2026-11-18](https://decrypt.co/383539/speaks-tongues-only-6-2-astra-understands-why-early-testers-hate-openai-new-model) |
| Early testers on X: Astra stops early and needs repeated "continue" prompts, loops on a long rewrite, answers verbosely; one tester calls it "a great reviewer"; nothing specific about Sol | secondhand (posts collected by Decrypt) | [Decrypt, 2026-11-18](https://decrypt.co/383539/speaks-tongues-only-6-2-astra-understands-why-early-testers-hate-openai-new-model) |

Not verified and therefore not quoted: Terminal-Bench placements, absolute Coding Agent Index
values, and Reddit reports of Sol 6.2 being slower and using more tokens than 6.1. The picture is
**mixed — not a routing change**: Sol 6.2 comes within half a point of Astra 6.2 on FrontierCode
2.0 at about a fifth of the cost per rollout (the vendor's claim, matched by Cognition's own
numbers at `max`) and gains 4 points over Sol 6.1 there, but loses 3 points against Sol 6.1 on
Artificial Analysis's Coding Agent Index; Astra 6.2 regressed in disclosing blockers: `sol` and `astra`
keep their rows and simply resolve to 6.2 when the account allows it. A user who wants the 6.1
behaviour pins it (a note, not a rule): policy `[pin]` `sol = "6.1"` (`docs/policy.md`).

**CLI changes 0.170–0.172** (vendor: the [0.170.0](https://github.com/openai/codex/releases/tag/rust-v0.170.0),
[0.171.0](https://github.com/openai/codex/releases/tag/rust-v0.171.0) and
[0.172.0](https://github.com/openai/codex/releases/tag/rust-v0.172.0) release notes, read
2026-11-24):

- 0.171: GPT-6.2 Sol and Astra in the catalog, Sol the default selection — maestro pins `-m` on
  every line, so a default never decides. `codex exec --remote <ADDR>` starts or resumes a
  non-interactive session on an existing app server (not used, below). Linux sandbox hardening:
  seccomp restrictions for x32 syscalls, `request_key` blocked in the network sandbox filters, a
  proc-mount fallback fix for Bubblewrap 0.12. The reach probe (stage 0 step 8) is what tells
  whether the sandbox still lets the tests run; it has not been re-run on 0.172.
- 0.172: **`codex exec resume` restores the saved sandbox permissions, working directory and
  workspace roots unless explicitly overridden** (#62194; observed below, "`codex exec resume`");
  optional stdio MCP servers with cached tool lists start on their first tool call (pinned mode's
  startup cost may drop; not re-measured); `code_mode_host_grpc` is deprecated (maestro never sets it).
- 0.170: sandbox-permission and MCP OAuth fixes only, as far as `codex exec` is concerned.
  Nothing in 0.170–0.172 changes `--output-schema`, `-o`, `--json` or `-c model_reasoning_effort`
  as far as the notes say; `codex exec --help` on 0.172.0 still lists `--trust` (recorded under
  0.169 below) and `--ignore-user-config`.

Catalog of Codex CLI **0.159.2**, read from `~/.codex/models_cache.json` on 2026-09-30 (entries
with `visibility: list`, in catalog priority order):

| Slug | Slot | Catalog efforts | Default |
| --- | --- | --- | --- |
| `gpt-6.1-sol` | `sol` — "latest workhorse model for coding and everyday work" | `low … ultra` | **`low`** |
| `gpt-6-astra` | `astra` — frontier, "for the most demanding work" | `low … ultra` | `medium` |
| `gpt-6-sol` | — (previous Sol, "previous generation workhorse model") | `low … ultra` | `medium` |
| `gpt-6-luna` | `luna` | `low … max` | `medium` |
| `gpt-5.6-sol` | — (older Sol) | `low … ultra` | `low` |
| `gpt-5.6-terra` | `terra` until 2026-10-27 — legacy, explicit `--model` only | `low … ultra` | `medium` |
| `gpt-6.1-terra` | `terra` since it appeared (seen 2026-10-28, 0.165.0; not in the 0.159.2 catalog this table is) | `low … ultra` | **`low`** |
| `gpt-5.6-luna` | — (older Luna) | `low … max` | `medium` |
| `gpt-5.5` | — (the catalog says it retires on 2026-10-14) | `low … xhigh` | `medium` |

**GPT-6.1 Sol** (`gpt-6.1-sol`) was released on 2026-09-29 and is what `sol` resolved to on 2026-10-11.
OpenAI's announcement ([Introducing GPT-6.1 Sol](https://openai.com/index/introducing-gpt-6-1-sol/))
says it "nearly matches GPT-6 Astra's intelligence on agentic coding, computer use, and professional
work at one-fifth of Astra's standard input and output token prices": on DeepSWE v1.1 it matches
Astra at roughly a fifth of the cost and beats GPT-6 Sol's best score by 6.4 points at a lower
effort; API prices $2 input, $0.10 cached input, $10 output per million tokens. These are the
vendor's figures, not maestro's measurements; the rubric moves only on what the ledger shows. A "GPT-6.1 Sol Ultrafast" was announced for the
following days; it is not in the 0.159.2 catalog. Its catalog default effort is `low` where GPT-6
Sol's was `medium` — maestro pins effort on every line, and a line without the pin runs at whatever
the user config says (`xhigh` on the author's machine) or, isolated, at that catalog default.
The read-only probe cost 18 585 input tokens (12 288 cached) and 8 s on 2026-09-30. GPT-6 Luna
keeps its slot; its strengths relative to Astra are not yet measured either. `terra` stays out of
the rubric (explicit `--model` only) — on 5.6 until 2026-10-27, on `gpt-6.1-terra` since it
appeared in the catalog; nothing announced makes it more than a legacy line.

**The catalog is a candidate list, not proof.** A listed model can still be refused for the account,
so the proof is a probe, remembered in `.maestro/model-probes.json` with its scope (CLI version,
catalog `identity`, config mode, host) — `docs/catalog.md`, "Probes". A probe costs about 14–19k
input tokens, mostly cached (14 011 for Astra on 2026-10-11). Only an error saying the client does
not know the model means "upgrade Codex".

`ultra` is a Codex catalog setting ("maximum reasoning with automatic task delegation"); the API's
own list stops at `max`. `none` is rejected. Effort goes on the command line as
`-c model_reasoning_effort=<level>` — set it every time, the defaults differ per model.

### Astra and GPT-6.1 Sol specifics

- **Asynchronous clarification questions** exist in interactive Codex, but the 0.153.4 binary
  states `request_user_input is not supported in exec mode`. A worker cannot ask mid-run; it can
  only *end* with a question. The brief's follow-through block ("do not ask; decide and record
  assumptions") is what prevents that.
- **Context notes across windows** (`features.context_management.experimental_mode`, off by
  default; `codex features list` reports it as under development) replace repeated compaction with
  searchable notes. Requires ChatGPT sign-in on Plus/Pro/Pro Lite; API-key sessions are excluded.
  Optional for very long builds; not part of the canonical lines.
- **Safety layer.** Astra is OpenAI's first model at the Critical cyber tier: it refuses
  proof-of-concept exploit work, and production safety checks can pause or stop legitimate work.
  GPT-6.1 Sol is treated the same way — Critical in cybersecurity, the same safeguards stack as
  Astra ([system card addendum](https://deploymentsafety.openai.com/gpt-6-1-sol), 2026-09-29). A
  `misalignment_policy_violation` or explicit safety block is **not retryable** — stop dispatch,
  keep the checkpoint and the `.jsonl`, report. Only an ordinary out-of-scope decline gets one
  rewritten brief.
- **Fast tier.** `service_tier = "priority"` is the Fast tier: 2× speed at 2× usage for Astra;
  for GPT-6.1 Sol the catalog says "2x speed, increased usage" (GPT-6 Sol and Luna: 1.5×).
  maestro keeps it unset (standard) — isolated mode cannot inherit it; pinned mode inherits a
  `service_tier` set in `config.toml`, and stage 0 reports it. A `~/.codex/fast.config.toml` profile holds it for interactive
  use: `codex -p fast`. The served tier is not recorded in session files, so it cannot be observed
  after the fact.

### Flags worth knowing (`codex exec`)

| Flag | Why it matters |
| --- | --- |
| `-o, --output-last-message <file>` | The final answer, verbatim, written host-side — works under `-s read-only` (verified). Read this, never the transcript tail. |
| `--json` | JSONL event stream on stdout: `thread.started` (with `thread_id`), `turn.started`, `item.*`, `turn.completed` (with `usage`). The only honest progress signal. Ordinary progress otherwise goes to **stderr** — capture it separately. |
| `--output-schema <file>` | Enforces a JSON Schema on the final answer (types, enums, `required`, `additionalProperties:false`; no nullable fields — see "Schemas"). |
| `-s <policy>` | `read-only`, `workspace-write`, `danger-full-access`. Read-only still runs read-only shell commands and still loads MCP servers — it is not "tool-less". |
| `--ignore-user-config` | Skip `$CODEX_HOME/config.toml`; auth still comes from `CODEX_HOME`. maestro's default (isolated mode, "Config modes" below); `exec` and `resume`. `-c` overrides still apply, but one that names an MCP server only the ignored file defined makes the file invalid at startup (`invalid transport in mcp_servers.<name>`, exit 1). |
| `-c mcp_servers.<name>.enabled=false` | Pinned mode only: disable an MCP server for one call. Measured saving here ≈ 1 s per critic start (5.4 s → 4.5 s with cached `npx` servers); it matters when a server cannot start at all (a container-backed one costs its full `startup_timeout_sec`). |
| `--approve-for-me` | Rung 3 as a flag: `approval_policy` `on-request` with automatic review, implies `workspace-write` and cannot be combined with `-s` (0.159.2: "the argument '--sandbox' cannot be used with '--approve-for-me'"). maestro uses the equivalent `-c approvals_reviewer="auto_review"`, which also works on `resume`. |
| `--image=<file>[,<file>…]` (`-i`) | Attach images to the prompt, on `exec` and `resume`. The option takes several values, so `-i shot.png "prompt"` swallows the prompt as a second file ("No prompt provided via stdin", exit 1); use `--image=` or put `--image <file>` before the other flags. Verified with one and with two images. |
| `-C, --cd <dir>` / `--add-dir <dir>` | Working root and extra writable roots (`exec` only — not on `resume`; since 0.172 a resume runs in the thread's saved directory, below). A parallel worker's worktree goes in `-C`. |
| `-p, --profile <name>` | Layers `$CODEX_HOME/<name>.config.toml` on top of the base config. Profiles can add keys, not remove them. |
| `--thread-source <source>` | Classification for the new/forked thread (0.153). |
| `--ephemeral` | No session file — and therefore no resume. |
| `-` as the prompt | Read the whole prompt from stdin (`codex exec - < brief.md`); EOF closes it. Documented; not the canonical transport. |

**Not used, with the reason** (0.159.2):

| Flag | Why maestro leaves it out |
| --- | --- |
| `--worktree` (exec, resume, review) | Codex-managed worktree under `$CODEX_HOME/worktrees/<id>/<repo>`, detached HEAD. It cannot be combined with `--ignore-user-config` (verified), so it would pull the whole user config into every parallel writer. maestro creates the worktree itself and passes it with `-C` (`docs/commands.md`, "Parallel Codex workers"). |
| `codex exec fork <id>` | Copies a thread's context into a new one. maestro continues a role by `resume`; forking a critic into a reviewer would carry the critic's conclusions into what must be an independent read. |
| `--strict-config` | Turns an unknown key in `config.toml` into a startup failure. Isolated mode does not read the file; pinned mode should not fail on the user's own keys. |
| `--enable` / `--disable <feature>` | Shorthand for `-c features.<name>=…`. Nothing maestro needs to toggle: exec sessions carry multi-agent tools but are instructed not to spawn sub-agents unless asked, and maestro briefs never ask; `ultra`'s automatic delegation stays unused. |
| `--ignore-rules` | Skips the user's and the project's execpolicy `.rules` — a safety net maestro does not remove. |
| `--dangerously-bypass-hook-trust`, `--dangerously-bypass-approvals-and-sandbox` | Not rungs; they drop protections meant for already-sandboxed hosts. |
| `--trust` (exec, resume, review; new by 0.169) | Saves trust for the project **persistently**, MCP commands outside the sandbox included. Never: it changes the user's Codex state beyond the run. |
| `--remote <ADDR>`, `--remote-auth-token-env` (exec and resume, 0.171) | Runs the session on an existing app server instead of locally. maestro's workers run in the checkout the director gates, under its own process tree (`maestro-run`, `maestro-kill`). |
| `--cyber-access-program` (new by 0.169) | Selects a cyber access programme; rollouts record `cyber_access_program: "standard"` in `turn_context`. maestro never passes it, and `maestro-identity codex` treats anything but `standard` (or absent) as a mismatch. |

The rest of DevDay 2026 is outside `codex exec`, so maestro has nothing to adopt from it: reusable
**cloud development environments** and **Dots** (always-on agents with their own cloud computer)
run in OpenAI's cloud, not in the checkout the director gates and commits; the **Agents API** is a
runtime for building one's own agent applications, not a CLI a director launches; `/agents`,
better worktree handling and **voice control** are interactive-TUI features. Codex cloud **Code
Review** is covered under "Review" below.

**`codex exec resume` has a different flag set** (0.159.2): `-m`, `-c`, `--json`, `-o`,
`--output-schema`, `--ignore-user-config`, `-i`/`--image`, `--last`, `--all`, `--ephemeral`,
`--enable`/`--disable`, `--strict-config`, `--ignore-rules`, `--skip-git-repo-check`,
`--thread-source`, `--worktree`, `--trust`, `--cyber-access-program` (0.169), `--remote` and
`--remote-auth-token-env` (0.171) and the two `--dangerously-…` flags — but **not** `-s`,
`--color`, `-C`, `--add-dir`, `--approve-for-me` (still true on 0.172.0, `--help`). Sandbox goes
through `-c 'sandbox_mode="workspace-write"'`. The id may be a UUID or a thread name. Two sessions
in August each lost two 8–10-minute windows to `error: unexpected argument '-s' found`.

**Where a resumed thread runs — three separate things** (2026-11-24):

1. **The wrapper's cwd** — `maestro-run --cwd` (the repository, or a parallel worker's worktree)
   is the directory the resume line is started from (`docs/commands.md`). Until this update this
   page said the resumed session runs in that shell directory (observed on 0.159.2,
   `docs/troubleshooting.md`).
2. **The thread's saved cwd and workspace roots** — since 0.172.0 `codex exec resume` restores
   them unless explicitly overridden (vendor, release notes). **Observed on 0.172.0** (local
   measurement): a read-only `gpt-6.1-sol` thread (`--ignore-user-config`, effort `low`) started
   in directory A ran `pwd`; the same thread resumed from directory B, with no `-C` (resume has
   none), printed A, and the rollout's `turn_context.cwd` was A for both turns. So on 0.172 the
   saved cwd wins over the shell's. Workspace roots were not checked (maestro passes no
   `--add-dir`).
3. **The per-role sandbox** — that resume without `-c sandbox_mode` restored the saved
   `read-only`; a further resume with `-c 'sandbox_mode="workspace-write"'` ran with
   `workspace-write` (`turn_context.sandbox_policy`). The `-c` override wins, and maestro passes it
   on every resume line, so a role's sandbox never depends on what was saved.

The recipe is unchanged: resume from the worker's own directory with the role's `-c sandbox_mode`
(`docs/commands.md`) — on 0.172 the directory is restored anyway, and on an older client it is
what decides.

**`--last` is banned in automation.** It resumes the newest recorded session in the cwd — the
critic, the builder, or an interactive session you opened meanwhile. Always the thread UUID from
`thread.started.thread_id`.

**Review** has its own subcommand with its own built-in contract — it sees the diff but not the plan or the acceptance criteria, so maestro's cross reviewer is a read-only `codex exec` with a review brief and `review-schema.json` (`docs/commands.md`); `codex exec review` stays a manual extra. Verified: `--json` and `-o` work on it;
its `turn.completed.usage` reports zeros, so ledger token fields for review calls are `null`:

```bash
codex exec review --uncommitted -m gpt-6.1-sol --ignore-user-config -c model_reasoning_effort=high --json \
  -o .maestro/review.txt < /dev/null > .maestro/review.jsonl 2> .maestro/review.stderr.log
codex exec review --base main …          # against a branch
codex exec review --commit <sha> …       # one commit
```

It takes the run's config mode like every other line (`--ignore-user-config` is in its help on
0.159.2; in pinned mode the "Pinned mode" substitution of `docs/commands.md` applies).

Codex's cloud **Code Review** (DevDay 2026) reviews a pushed GitHub PR or GitLab MR the same way —
with its own contract, without the plan — so it is a manual extra too, never the cross reviewer.

**Health**: `codex doctor` (`--summary`, `--json`) reports auth mode, provider reachability,
installed vs. latest version, and whether a background `app-server` is running.

**Skills**: Codex discovers `~/.codex/skills`, `~/.agents/skills`, `~/.codex/skills/.system` and
`{cwd}/.agents/skills`, injects names + descriptions, and instructs the model to read a relevant
`SKILL.md` completely before acting. A Luna probe from a Laravel project listed all 14 project skills
without being asked; Sol sessions read `pest-testing` and `laravel-best-practices` on their own.
Name the binding skills in the brief anyway.

### Config modes

Every `codex exec` reads `$CODEX_HOME/config.toml` unless told not to, and that file reaches further
than it looks: on the author's machine it starts two MCP servers through `npx`, loads a plugin, sets
`personality`, `model_context_window = 1000000` and `model_reasoning_effort = "xhigh"` (an unpinned
worker ran at `xhigh`), and sets `approvals_reviewer = "auto_review"` — which on 0.159.2 alone turns
`approval_policy` from `never` into `on-request` with automatic review: rung 3 in disguise (verified
2026-09-30). maestro therefore runs Codex in one of two modes, decided at stage 0 step 3:

- **isolated** (default) — `--ignore-user-config` on every line, exec and resume: none of the file
  reaches the worker; auth still comes from `CODEX_HOME`.
- **pinned** (fallback) — `-c approvals_reviewer="user"` on every line and one
  `-c mcp_servers.<name>.enabled=false` per server on the read-only lines. Everything else in the
  file reaches the worker, MCP servers on writers included, and stage 0 reports what changes the
  rung or the cost (`approval_policy`, `sandbox_mode`, permission keys, `service_tier`).

Pinned is chosen when the file sets a key that decides where or how Codex connects or
authenticates, because skipping it would break the worker or silently change the account:
`model_provider`, a `[model_providers.<id>]` table, `openai_base_url`, `chatgpt_base_url`,
`cli_auth_credentials_store`, `forced_login_method`, `forced_chatgpt_workspace_id` — and,
conservatively, any other key whose name contains `base_url`, `provider`, `login`, `auth`,
`credential` or `proxy` (outside the `mcp_servers`, `projects`, `tui` and `plugins` tables).
`model_provider`, `[model_providers]`, `openai_base_url` and `cli_auth_credentials_store` are in the
Codex configuration reference; `chatgpt_base_url`, `forced_login_method` and
`forced_chatgpt_workspace_id` were found in the 0.159.2 binary next to `cli_auth_credentials_store`.
A corporate CA bundle is an environment variable (`CODEX_CA_CERTIFICATE`, `SSL_CERT_FILE`) and
survives isolated mode. The Assign line names the mode and the key that forced it.

What no flag removes: every exec session carries about 18.6k input tokens of injected context —
the skills list from `~/.codex/skills`, `~/.agents/skills` and `.system` (~20 KB here),
`~/.codex/AGENTS.md`, a recommended-plugins list and the multi-agent instructions (measured
identical with and without `--ignore-user-config`).

A **project-level** `.codex/config.toml` can carry a `default_permissions` profile that makes the
workspace read-only regardless of `-s`, or an MCP server that shells into containers and cannot
start in the sandbox (10 s startup penalty per run). Stage 0 reads it and warns in both modes. Whether
isolated mode still loads a trusted project's file is unverified: in a scratch repository trusted
through `-c 'projects."<path>".trust_level="trusted"'`, the project's `model_reasoning_effort` was not
applied with the user config (the user's `xhigh` won) nor without it (2026-09-30).

The **effective** configuration is not a matter of trust: after every launch and resume the director
reads it back from the session's rollout file with `maestro-identity codex` (`docs/commands.md`,
"Effective-config check"). Rollouts on disk here are from 0.166; the `turn_context` shape of 0.169
is the same as far as a fresh probe shows. 0.169 also ships `migrate-rollouts` and a
`thread_history_1.sqlite`, the start of a move from rollout `.jsonl` files to a paginated history
(the `background_paginated_rollout_migration` feature is still off): when it lands, the
effective-config check and the served-model column of the ledger need a new source.

## Google — `agy`

### Models

The Gemini 4 line-up as agy 1.5.16 lists it (local measurement 2026-11-24, `agy models`):

| Line | Slugs | Slot | Notes |
| --- | --- | --- | --- |
| Gemini 4 Argon | `gemini-4-argon-{low,medium,high}` | `argon` | the Google critic, reviewer and arbiter; provisional |
| Gemini 4 Carbon | `gemini-4-carbon-{low,medium,high}` | `carbon` — explicit-only, provisional | the Orchestrator's planner on Enterprise and ADC sign-ins (vendor: agy 1.5.10 notes) |
| Gemini 4 Hydrogen | `gemini-4-hydrogen-{low,medium,high,xhigh}` | `hydrogen` | the Orchestrator's executor (same notes) |
| Gemini 4 Neon | `gemini-4-neon-{low,medium,high,xhigh}` | `neon` — explicit-only, provisional | added to agy in 1.5.12 (`GEMINI_API_KEY`) and 1.5.13 (ADC sign-ins) (vendor: `agy changelog`) |
| Gemini 3.8 Flash | `gemini-3.8-flash-{low,medium,high}` | no slot since 2.4 (dropped; the slug stays unmatched) | |
| Orchestrator | `gemini-pro-orchestrator-neon`, `gemini-pro-orchestrator` ("Orchestrator (Carbon)"), `gemini-pro-orchestrator-argon` | none — `unmatched` | an Antigravity feature, not a model: a planner (Argon, Carbon or Neon) hands the plan's execution to an executor (Hydrogen). Not a maestro mechanism: one slug would be two models, so the family and the served model of each step could not be recorded |

`carbon` and `neon` are slots so that a user can name them; they are in no rubric row and in no
automatic choice (SKILL.md, "Roster"), because what is known about them comes from one or two
outside sources (below). **They are the candidates to measure first** — a canary run or the ledger
rows of runs that name them — before any of them takes a default role.

Evidence on Gemini 4, as recorded on 2026-11-24:

| Claim | Label | Source |
| --- | --- | --- |
| Artificial Analysis Intelligence Index, per effort: Neon 61 (`xhigh`), 60 (`high`); Hydrogen 54 (`xhigh`), 51 (`high`); Carbon 60 (`high`); Argon 50 (`high`) | independent | Artificial Analysis model pages for [Neon](https://artificialanalysis.ai/models/gemini-4-neon), [Hydrogen](https://artificialanalysis.ai/models/gemini-4-hydrogen), [Carbon](https://artificialanalysis.ai/models/gemini-4-carbon) and [Argon](https://artificialanalysis.ai/models/gemini-4-argon), read 2026-11-24 |
| **Argon**: public availability through the API on 2026-10-13; introductory $2 input / $10 output per million tokens until 2026-11-30, $4 / $20 after | vendor | [Google, "Introducing Gemini 4 Argon"](https://blog.google/innovation-and-ai/models-and-research/gemini-models/introducing-gemini-4-argon/) (2026-10-13), read 2026-11-24 |
| **Carbon**: earlier access for cybersecurity defenders (Fairwind Program) "two weeks" before; public availability to paying API developers on 2026-11-10; introductory $2 / $10 (Argon's rate) until 2026-11-30, $4 / $20 after | vendor | [Google, "Gemini 4 Carbon now available"](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-4-carbon-now-available/) (2026-11-10), read 2026-11-24 |
| Artificial Analysis gives earlier dates — Argon 2026-09-30, Carbon 2026-10-28 (the early-access dates, before public availability) — and already lists both at $4 / $20 | independent listing | the Argon and Carbon pages above |
| **Hydrogen** announced 2026-11-12, $1.50 / $7.50 flat over the context; **Neon** 2026-11-18, $3 / $15; all four with a 1M context | vendor (Hydrogen), vendor price as listed by Artificial Analysis (Neon) | [Google's Hydrogen announcement](https://blog.google/innovation-and-ai/models-and-research/gemini-models/introducing-gemini-4-hydrogen/) (2026-11-12) and the Artificial Analysis pages above, read 2026-11-24 |
| Hydrogen is presented as "a major standalone upgrade for teams migrating from Gemini 3.8 Flash"; Google does not call it a Flash model | vendor | Google's announcement above |
| Terminal-Bench 4.1, cheating-adjusted accuracy: Neon 65.2 % — **an independent Artificial Analysis run through the public Antigravity CLI 1.5.9 harness, published by Google**; in the same table Opus 5.5 65.8 % and GPT-6.2 Sol 61.5 % (from the official public leaderboard) | independent (Neon), published in a vendor table | the [Neon model card](https://deepmind.google/models/model-cards/gemini-4-neon/) and its [evaluation methodology](https://storage.googleapis.com/deepmind-media/gemini/gemini_4_neon_model_evaluation.pdf), read 2026-11-24 |
| Terminal-Bench 4.1: Hydrogen 57 % against 18.2 % for Gemini 3.8 Flash — self-computed with a mini-swe-agent vision harness, 5 attempts per task averaged, high effort, cheating-adjusted | vendor | Google's announcement above and the [Hydrogen evaluation methodology](https://storage.googleapis.com/deepmind-media/gemini/gemini_4_hydrogen_model_evaluation.pdf), read 2026-11-24 |
| FrontierCode 2.0 main score and mean cost per rollout: Neon 46.2 % at `high` ($4.38; Antigravity CLI harness), Opus 5.5 47.3 % at `max` ($12.82), Carbon 42.6 % at `high` ($5.06), Hydrogen 38.9 % at `xhigh` ($4.95), Argon 27.6 % at `high` ($6.51) | independent (Cognition's own runs) | Cognition's leaderboard data file above, read 2026-11-24. Google's Neon model card quotes the same 46.2 / 47.3 / 43.8 (Sol 6.2) |
| The Orchestrator plans with Carbon (High) and hands execution to Hydrogen (High) | vendor | `agy changelog`, 1.5.10 |

Not verified and therefore not quoted: community judgements of the Gemini 4 models.

Continuations are unchanged by any of this: a fix round continues an agy builder by
`--conversation` only after a `SUCCESS` turn, and any other status starts a new conversation
carrying the current diff (SKILL.md, "Launching workers"; "Payload check" below).

### Flags

| Flag | Why it matters |
| --- | --- |
| `--model <slug>` | Mandatory on every call (family). The slug embeds the effort (`gemini-4-hydrogen-high`). |
| `--effort low\|medium\|high\|xhigh\|max` | Session effort (the range grew to `max` by 1.5.9). Must agree with the slug — `…-high` with `--effort medium` contradicts itself — so maestro clamps to the efforts the model's slugs list: Hydrogen and Neon `low…xhigh`, Argon, Carbon and agy's Claude models `low…high` (2026-11-24). |
| `--mode plan` | Read-only planning mode — the critic setting. |
| `--mode accept-edits` | Auto-approves edits, keeps other prompts — the build setting. |
| `--add-dir <repo>` | **Required for project skills and rules.** Print mode does not treat cwd as the workspace: without `--add-dir` the worker sees only the 5 built-in skills. |
| `--print-timeout` | **Always set it.** It defaulted to 5 minutes up to 1.1.x; 1.2.8 defaults to `0`, which waits until the turn completes (and since 1.5.0 also for background tasks). Since **1.5.0** expiry exits **3**, prints an `AGY_ERROR` line and `[agy] print timeout after …` on stderr; before, it was `status:"ERROR"`, exit 1. A stuck `-p` run exits within 30 s since 1.5.5. |
| `--output-format json` | One envelope written whole at exit: `{conversation_id, status, response, duration_seconds, num_turns, usage, denied_actions?, finished_reason?, json_schema?, structured_output?}`. `finished_reason` (1.4.11) is omitted on a normal finish and `print_timeout`, `interrupted` or `error` otherwise; `maestro-validate --envelope agy` rejects any value. Since **1.5.13** a run that succeeded after agy retried a model request reports `SUCCESS`; before, it read `ERROR` with the failed attempt's error (vendor: `agy changelog`). maestro's checks — status, response, `denied_actions`, `finished_reason`, the requested slug — are unchanged. |
| `--json-schema <schema-or-path>` | Schema enforced on the answer; the parsed object also arrives as `structured_output` (documented on Antigravity's headless page, present in every schema envelope maestro has kept since 1.3.x). `maestro-validate --envelope agy` reads `structured_output` first, `response` otherwise. Up to 1.3.x agy added `toolAction` and `toolSummary` keys to the object in `response`; since 1.4.0 it does not (the validator still drops them). Up to 1.5.7 a follow-up through `--conversation` could answer in plain text despite the schema; 1.5.8 fixed it. |
| `--log-file <path>` | Writes this run's CLI log to `<path>` while it runs (measured on 1.4.8: the file appeared and grew before the envelope was written). maestro puts it in the job directory and hands it to `maestro-wait --also`, instead of guessing the newest `~/.gemini/antigravity-cli/log/cli-*.log` (evidence: maestro run docs-20261028-0134, `2.2-log-midrun.txt`). |
| `--mode auto` | Preview: edits auto-approved and commands run in agy's terminal sandbox (workspace and temp only, no network). **Not available on this account** (measured 2026-10-28 on 1.4.8, `-p`: stderr `warning: --mode auto is not available for this account; continuing in the default mode`, the log says the rollout flag is off; the command was then denied and nothing ran; evidence: maestro run docs-20261028-0134, `M1-agy-auto.txt`). Not offered on Business/Enterprise accounts at all. Since **1.5.7 Auto is the default mode** wherever it is available, headless included; on this account the log still says "auto mode is unavailable, falling back to default" (2026-11-14). maestro passes `--mode` on every line (the `/skills` listing included, `--mode plan`), so the default never decides; agy builders stay edits-only. Since 1.5.14 Auto reads outside the workspace without asking, and since 1.5.16 it also writes outside the workspace without asking when the file is inside a version-controlled repository (vendor: `agy changelog`) — one more reason never to leave the mode to the default. |
| `--input-format stream-json` | NDJSON prompts on stdin; **requires `--output-format stream-json`**. Observed on 1.1.27: stdout is `{"event":"init","conversation_id":…,"init":{"model","cwd","tools":[…]}}` followed by `{"event":"result","result":{…the same envelope as `--output-format json`…}}`; input lines must carry an `"event"` field (a `{"type":"user",…}` message is rejected with `stream input message is missing the "event" field`). A different mode with a different parser; not used by maestro. |
| `--conversation <id>` | Resume by id. `-c`/`--continue` means "most recent conversation" — a race as soon as two runs exist. agy 1.5.16 adds `-r` and `--resume` as aliases of `--conversation` (`agy --help`, `agy changelog`); maestro keeps the long form. 1.5.14 notes that `--mode` overrides a resumed conversation's saved mode — said of `--remote-agent` sessions; for local print mode not verified, and maestro passes `--mode` on every resume line anyway. |
| `--dangerously-skip-permissions` | Approves everything (since 1.5.2 still blocked on the system denylist). Was blocked once by Claude Code's own auto-mode classifier; `--mode` settings are what maestro uses. |
| `--agent <name>` | Run a custom agent; its Markdown frontmatter can preload `skills:` — an option, not used by maestro. |
| Automatic retries (1.5.10, 1.5.12) | When the model API asks the CLI to wait, agy now waits and retries for delays of up to **4 minutes** instead of ending the turn above 30 s; spend-cap, prepaid-balance and weekly-quota errors still stop the turn at once; brief connection problems are retried automatically (vendor: `agy changelog`). During such a wait the job shows no progress; the watchdog's no-progress threshold (`max(15 min, 2 × T_slow)`, SKILL.md, "Time and the watchdog") is well above it and stays unchanged. |
| `GEMINI_API_KEY` sign-in (1.5.11) | With a `GEMINI_API_KEY` instead of a subscription sign-in, `/usage`, `/quota` and `/credits` are hidden from autocomplete and `/help`, and invoking one in a `-p` run **exits 2** (vendor: `agy changelog`, 1.5.11). maestro's agy workers use the subscription login and never run them; it matters only if someone sets the key (agy quota is "unknown" to `maestro-limits` either way). |
| Swarms | 1.5.13 fixed agents starting a `/swarm` on their own, "which can use far more of your quota than a single agent" (vendor). maestro briefs never ask for a swarm, and the orchestrator slugs are never a worker — a planner plus an executor would draw quota twice. |
| `--disable-slash-commands` | **Not used.** It would stop a prompt that starts with `/` from expanding a skill, but on 1.5.9 it also disables the mode: `warning: --mode plan has no effect while slash command expansion is disabled.` (measured 2026-11-14) — a critic would silently lose plan mode and a builder accept-edits. Briefs simply never start with `/`. |
| `--settings`, `--project`, `--new-project`, `--remote-agent` | One-off settings (`permissions.allow` without editing `~/.gemini`), project selection and remote agents. Not used: maestro's lines do not depend on agy settings or projects. |

### Headless permissions — the one that bites

In print mode any tool action that would need a permission prompt is **auto-denied, and the whole
turn is cancelled**:

```
$ agy --mode plan … -p "…run agy --help to verify…"
jetski: no output produced — a tool required the "command" permission that headless mode cannot
prompt for, so it was auto-denied. Add an allow-rule under permissions.allow in settings.json
(e.g. command(<target>)). Alternatively, re-run with --dangerously-skip-permissions …
{"status":"CANCELED","response":"","denied_actions":[{"action":"command","display_name":"RunCommand"}], …}   exit 0
```

Consequences:

Everything below holds for every Google slot on agy — `hydrogen`, `argon`,
and the explicit-only `carbon` and `neon` (not yet run as workers here).
The measurements in the table are Flash's; Argon has since run as a plan critic (2026-10-16, 2026-10-28:
reads the repository itself, no denial, a valid verdict first time) and stays provisional until the
ledger has more than critiques. Hydrogen was announced by Google on 2026-11-12 (as the upgrade
path from Gemini 3.8 Flash; this page said on 2026-11-14 that it was unannounced, which was
wrong). Its first probe passed on 2026-11-14
(`gemini-4-hydrogen-low` → `SUCCESS`, response `OK`, no `finished_reason`; `gemini-4-argon-low` the
same); it has not built or critiqued yet.

- A Gemini **critic, gate or reviewer** reads the repository itself, in plan mode: its brief gives
  paths inside `$REPO` and allows file tools there, forbidding commands, MCP and anything outside
  `$REPO` (reaching for an MCP server or a command empties the answer — troubleshooting). Measured
  2026-10-12 with `gemini-3.8-flash-medium`, the same plan critique three times each way:

  | Variant | Answers | Denials | Time | Input tokens | Findings |
  | --- | --- | --- | --- | --- | --- |
  | reads the files itself (paths only) | 3/3 | 0 | 112–145 s | 114–144 k | the locale bug, the undecided test, `set -u`, the `check` and comment conventions |
  | inline (everything quoted, no tools) | 3/3 | 0 | 58–67 s | 37–40 k | the same |

  A fourth read run with `.maestro/` in `info/exclude` (as in every real run) read the plan from
  there without a denial. A file **outside** `--add-dir` is denied (`denied_actions: [{action:
  "read_file"}]`, empty response). So on a small repository reading costs about twice the time and
  three times the input (Gemini's pool, not Claude's or OpenAI's); on a large one it spares the
  director from choosing and quoting the code and has no argv limit. A denied read → a new
  conversation with the inline variant (whole brief quoted; above ~100 KB split, or another family).
- A Gemini **builder** is edits-only. Its brief says so; the director runs tests and builds. One
  attempted command ends the turn with an empty response and `denied_actions: [{action:
  "command"}]`, exit 0 — status `CANCELED` up to 1.3.x, `SUCCESS` since 1.4.8 (measured 2026-10-28), so
  the `denied_actions` check, not the status, is what catches it.
- `denied_actions` is **absent** when nothing was denied — treat a missing key as `[]`.
- To let a Gemini worker run specific commands, `permissions.allow` rules (`command(<target>)`) in
  `~/.gemini/antigravity-cli/settings.json` are the documented mechanism — not measured, and
  broader than maestro needs.

### Payload check, every call

`status == "SUCCESS"` · `response != ""` (or `structured_output` set) · `(denied_actions ?? []) == []`
· no `finished_reason` · for schema calls:
strip Markdown fences, drop `toolAction`/`toolSummary`, `JSON.parse`, validate. Any non-`SUCCESS`
status invalidates the `conversation_id` — the history may hold an orphaned tool call; the
follow-up is a new conversation carrying the current `git diff`.

A successful envelope:

```json
{"conversation_id":"b538f8bb-…","status":"SUCCESS","response":"{…}",
 "duration_seconds":111.3,"num_turns":1,
 "usage":{"input_tokens":52238,"output_tokens":33649,"thinking_tokens":29804,
          "cache_read_tokens":240719,"total_tokens":85887}}
```

### Prompt size

A 34 KB brief through `-p` ran fine on 1.1.27 (16.5 k input tokens). The bound is the OS argv limit
(~128 KB per argument on Linux: `Argument list too long`). Builders and drafters get a pointer
stub — it keeps prompts small and free of shell-quoting accidents. Critics, gates and reviewers get
their brief in `-p`; it names paths and they read the files themselves, so it stays small. Only the
inline variant (after a denied read) quotes everything; above ~100 KB it is split.
`-p` does not read stdin.

### Skills

Discovery: `{workspace}/.agents/skills/<name>/SKILL.md` and `~/.gemini/config/skills/<name>/`,
and since 1.5.16 also `~/.agents/skills` (skills in `~/.gemini` win a name collision; vendor:
`agy changelog`).
Names + descriptions are injected; the model is told it MUST read a relevant `SKILL.md` before
proceeding. `agy --add-dir "$REPO" --output-format json -p "/skills"` lists what a worker will see
without spending a model turn. A `/<skill>` prefix in the prompt expands that skill verbatim
(verified: `-p "/xui-development …"` returned the skill's `name` and first heading; cost = the
whole `SKILL.md` in input tokens).

## Claude

Four transports serve the Claude lines (SKILL.md, "Roster"): the `Agent` tool (only in an
interactive Claude Code), `claude -p` (a headless director, and for an exact native id), agy (Opus
and Sonnet), and `api` (the Agent SDK on an API key, below). Fable and Haiku have no agy transport,
so a native quota hit on them switches only to `api` — when it is not on, it is a swap or a stop.

### The Agent tool

`Agent` with an explicit `model` and the default `subagent_type`. `subagent_type: "fork"` inherits
context but **ignores** `model`. maestro passes no effort on the call — the model choice is the
dial. (The tool does have an `effort` parameter: Claude Code 2.1.329 fixed it being ignored for
named teammates in agent teams — vendor, `CHANGELOG.md`. That is an upstream fact only; adopting
it is not part of maestro.) The
`model` parameter takes only the aliases (`opus`, `fable`, `sonnet`, `haiku`), which follow the
newest model of each line; the completion line names the model served, and maestro compares it with
the slot's frozen id. Parallel write-mode subagents need `isolation: "worktree"`; their briefs give
paths relative to the worktree root; the director integrates each worktree's result itself and
keeps the worktrees until the report (SKILL.md, "Roster").

Notes on the models, as measured or published at the time (they age; the ledger is the record):

| Line | Notes |
| --- | --- |
| `opus` | Opus 5.5 (`claude-opus-5-5`, released 2026-09-22): $4 / $20 per MTok, cache reads $0.20 (date and price: [TechCrunch, 2026-09-22](https://techcrunch.com/2026/09/22/anthropic-releases-opus-5.5-with-lower-prices-and-fable-level-performance/), secondhand, through a search summary on 2026-11-24). Gains mostly on multistep work in a real codebase and on code review, fewer tokens per finished task, much more accurate reading of screenshots, charts and diagrams. Thinking always on. Natively `claude -p --model opus` served `claude-opus-5-5` (local measurement, probe `init.model`, 2026-11-24). |
| `fable` | Fable 5.2 (`claude-fable-5-2`, the default Fable since Claude Code 2.1.321; saved Fable 5.1 choices move to it): most capable and most expensive ($8 / $40 per MTok), 1M context. Long turns on hard tasks. Keep it for the hardest correctness and large UI redesigns. Natively `claude -p --model fable` served `claude-fable-5-2` (probe, `init.model`, 2026-11-14). |
| `sonnet` | Mechanical, convention-heavy builds. Sonnet 5.5 in every catalog on 2026-10-11; released 2026-09-28 at $2 / $10 per MTok, the price of Sonnet 5 (secondhand: [Decrypt](https://decrypt.co/379482/anthropic-claude-sonnet-5-5-release), through a search summary on 2026-11-24). |
| `haiku` | Bulk edits without judgment; Claude-only cascade drafter. Haiku 5.5 (`claude-haiku-5-5`, measured through `claude -p --model haiku`). API price "$0.10 per million input tokens and $0.50 per million output tokens" for prompts up to 100K tokens, $0.50 / $2.50 above (vendor: [anthropic.com/claude/haiku](https://www.anthropic.com/claude/haiku), read 2026-11-24); release date not recorded. |

Terminal-Bench 4.0, as reported (point estimates; no interval was published, so no ranking is read
into a difference of a few points): Sonnet 5.5 70.6 %, Opus 5.5 66.4 % at its highest effort —
vendor (Anthropic), reported secondhand by [The Next Web](https://thenextweb.com/news/sonnet-5-5-cyber-distillation)
and [Mixed](https://mixed-news.com/en/claude-sonnet-5-5-terminal-bench-70-6-percent-half-opus-price/);
Artificial Analysis's own run gave Sonnet 5.5 63.6 % and Opus 5.5 59.6 % on a pre-release build —
independent, reported secondhand by [Decrypt](https://decrypt.co/379482/anthropic-claude-sonnet-5-5-release)
(all read through a search summary on 2026-11-24). Fable stays `claude-fable-5-2` — the probe of
2026-11-14 says so; an aggregator's "Fable 5.1" listing is not used. One single-author review
([Thomas Wiegold, 2026-09-30](https://thomas-wiegold.com/blog/claude-sonnet-5-5-review/), read
2026-11-24; secondhand) had Sonnet 5.5 build a Go chess engine "as good as Opus's for half the
price" (a 51 % saving on that task, 30 % on a design task, one run each); Sonnet's own tests there
contained two wrong expected values. The review also quotes Anthropic's caveat that Opus 5.5
"remains clearly stronger at complex, open-ended work that needs sustained judgment" — Anthropic's
claim as reported by Wiegold, not his measurement. A
**token-budget caveat** for both lines is maestro's own: per-token prices say nothing about
tokens per finished task — the ledger's token columns are where that shows, and nothing here
changes a row.

Agent-tool effort: since Claude Code 2.1.317 a subagent on a different model than the session runs at
that model's saved or default effort, not the session's, and 2.1.316 added
`CLAUDE_CODE_SUBAGENT_EFFORT` (an environment variable for every subagent of the session, not a
per-call setting). maestro passes no effort on the Agent tool and records it as the model's default
(unknown in numbers).

### `claude -p`

Measured on Claude Code 2.1.296 (2026-10-11, haiku); every flag below is unchanged on 2.1.325
(2026-11-14) and still listed by `claude --help` on 2.1.331 (2026-11-24). `--permission-mode` choices are now `acceptEdits`, `auto`, `bypassPermissions`,
`manual` (formerly `default`), `dontAsk`, `plan`.

| Flag | What it does for maestro |
| --- | --- |
| `--model <alias or full id>` | An alias resolves to the newest model of the line; the full id (`claude-opus-5-5`) pins it. The served model is in the `init` event and `result.modelUsage`. |
| `--effort low\|medium\|high\|xhigh\|max` | The session effort. |
| `--tools "<list>"` | **The exclusive built-in tool set** — `init.tools` was exactly the list (`["Glob","Grep","Read"]`); `""` disables every tool. |
| `--allowedTools "<list>"` | Pre-approves those tools. With `--permission-mode dontAsk` anything not pre-approved is denied without a prompt (a headless run cannot answer one). |
| `--permission-mode dontAsk\|acceptEdits\|plan\|…` | Critics `dontAsk` with the read tools pre-approved (measured: a `Read` succeeded); builders `acceptEdits`. `bypassPermissions` is never used. |
| `--strict-mcp-config` (no `--mcp-config`) | No MCP server at all (`init.mcp_servers: []`). |
| `--setting-sources ""` | No user, project or local settings — no hooks from them. Accepted, and the subscription login still worked (`apiKeySource: "none"`). |
| `--output-format stream-json --verbose` | `system/init` first — `{model, session_id, tools, mcp_servers, plugins, plugin_errors (2.1.323), permissionMode, apiKeySource}` — then events, then `result {subtype, is_error, result, structured_output?, permission_denials, modelUsage, usage, session_id}`. The session id is known before the work starts. |
| `--json-schema '<schema>'` | Structured output; the verdict arrives as `result.structured_output`. |
| `--resume <session_id>` | Continues a session. Every safety flag of the role is repeated on it. |

**Inherited customisations.** Measured: a `claude -p` started from a Claude Code session inherited
`CLAUDE_CODE_PLUGIN_DIRS` and loaded a non-builtin plugin that ships `hooks.json` — into a
"read-only" critic. `bin/maestro-env` removes it (and every other `CLAUDE_*` variable except
`CLAUDE_CONFIG_DIR`, including `CLAUDE_EFFORT`, which would override `--effort`); with it removed
`init.plugins` held only Claude Code's builtin plugins. maestro checks `init` on every launch with
`maestro-identity claude` and kills a session whose model, tools, MCP servers, plugins (anything not
`@builtin`), `plugin_errors` (any), permission mode or `apiKeySource` are not the requested ones.
Since 2.1.314 `--setting-sources ""` also keeps out the settings that slipped through before
(auto-mode rules, consents); since 2.1.323 `-p` warns on stderr when settings block the requested
model; several "exit 0 on failure" cases exit 1 since 2.1.314–2.1.321.

**2.1.326–2.1.331** (vendor: Claude Code's
[`CHANGELOG.md`](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md), read
2026-11-24) — nothing in maestro's lines changes:

- 2.1.326: a **startup warning** when an `--allowedTools`, `--disallowedTools` or `--tools` value
  has an entry that does not look like a complete rule. Treat it as a failure of the launch line:
  grep the job's `err` file for it (the exact wording was not captured here), and the `init.tools`
  check of `maestro-identity claude` still decides the tool set.
- 2.1.327: `-p` no longer hangs before its first request when the fetch of a model's settings
  stalls — it goes on without them after **10 seconds**; headless sessions no longer lose stored
  messages on resume after the process was killed; subagents launched without a model stay on
  their starting model when resumed (maestro always names the model).
- 2.1.328: with `CLAUDE_CODE_FORK_SUBAGENT=0`, `claude -p` counts a background subagent and those
  it waits for against **one 10-minute wait** (`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` raises it);
  maestro's `-p` workers have no Agent tool, so it does not apply to them. `sandbox.failIfUnavailable`
  decides whether a sandbox that cannot start fails the session; maestro's `-p` workers have no
  Bash and do not use the sandbox setting.
- 2.1.329: the Agent tool's `effort` parameter is honored for named teammates (above).
- 2.1.330: `claude -p` writing its output to a file on a full disk now prints an error and **exits
  1** (it used to exit 0 with no message). A nonzero exit is already a failure for maestro; the old
  exit-0 case was caught only by the envelope check.
- 2.1.331: a permission rule on a subagent's model such as `Agent(model:*)` no longer blocks a
  follow-up message to a subagent started without a model.

**`--restricted`** keeps file tools inside the working directories and drops the command tools.
It would bound a read-only critic's `Read` to the repository; it is **not adopted** until a probe
shows exactly that on this account (a critic's reach is held today by the brief and the fingerprint
check).

**Edits-only by default.** A `claude -p` builder gets `--tools "Read,Edit,Write,Glob,Grep"` — no
Bash — and the director runs the tests. A denied Edit or Write fails the turn; a denied Bash on an
edits-only builder is expected. Writes under `~/.claude/` are refused as "sensitive" whatever the
mode (measured), so scratch repositories for tests live elsewhere.

**`--bare` is not used**: it reads only `ANTHROPIC_API_KEY` (OAuth and the keychain are never
read), so it cannot run on a subscription login. For API-key billing maestro uses the `api`
transport instead (below).

**No inherited key.** In `-p` mode an `ANTHROPIC_API_KEY` in the environment outranks the
subscription login (documented precedence: cloud provider → `ANTHROPIC_AUTH_TOKEN` →
`ANTHROPIC_API_KEY` → `apiKeyHelper` → `CLAUDE_CODE_OAUTH_TOKEN` → `/login`), so a key left in the
director's shell would bill every native worker to the API without a word. `maestro-env` removes
every `ANTHROPIC_*` variable, and the `init` check requires `apiKeySource: "none"` on native.

### Claude through the Agent SDK (`api`)

**Why it exists.** A Max plan includes a monthly API credit (Max 20x: $200, Max 5x: $100; documented
at platform.claude.com, "API credits for Max and Team plans"). It is granted only after the plan is
linked to a Console organisation (claude.ai → Settings → Billing), it expires at the end of each
billing cycle, and it covers **the Claude API and the Claude Agent SDK — not Claude Code**. When
the subscription's 5-hour or weekly limit is spent, `api` lets Claude workers go on, paid from that
credit.

**Why the SDK and not `claude -p --bare`.** Technically the SDK starts the same Claude Code
process, with the same events, tool restriction and resume. But the credit's terms name the Agent
SDK and exclude Claude Code, and an SDK session identifies itself as one (its own entrypoint and
`CLAUDE_AGENT_SDK_CLIENT_APP=maestro/<version>` in the User-Agent). Billing is the reason. A native
`maxBudgetUsd` comes with it. (On a subscription login the SDK is cost without gain — "Not used"
below; on an API key it is the billing path.)

`bin/maestro-sdk` runs `sdk/runner.mjs` (Node ≥ 18, `@anthropic-ai/claude-agent-sdk` pinned in
`sdk/package-lock.json`, installed by `install.sh --sdk`). Measured with SDK 0.3.286 (bundled
Claude Code 2.1.286) on 2026-10-15, re-measured after the bump to SDK 0.3.312 on 2026-10-28, and
pinned to **SDK 0.3.325** (bundles Claude Code **2.1.325**, the version the SDK's
`init.claude_code_version` reports) for 2.0.0. The 2026-10-28 measurement:
one tool-less probe on `claude-haiku-5-5` returned `OK` with `apiKeySource: "ANTHROPIC_API_KEY"`,
`tools: []`, `mcp_servers: []`, 403 input and 4 output tokens, estimated `total_cost_usd`
0.0000423 (evidence: maestro run docs-20261028-0134, `2.1-sdk-probe.txt`):

| Flag / behaviour | What it does for maestro |
| --- | --- |
| `--model <full id>` | Required, a full id only. **Aliases are refused**: the bundled CLI resolves them from its own table, which lags (measured: `haiku` → `claude-haiku-4-5-20251001` while native `claude` resolved `claude-haiku-5-5`). |
| `--resolve <slot>` | The newest id of the line this key can use, from the Models API (`GET /v1/models`, no model turn, no cost). 401/403 → exit 3: the key is refused. |
| `--tools`, `--allowed-tools`, `--permission-mode` | The role's sets, as on `claude -p` (`tools` exclusive; `""` = none). `dontAsk`, `acceptEdits` and `plan` only; `bypassPermissions` and `auto` are refused. |
| isolation | Always `settingSources: []` (no settings, hooks or CLAUDE.md), `mcpServers: {}` with `strictMcpConfig: true`. Measured `init`: `tools: []`, `mcp_servers: []`, only `@builtin` plugins. |
| `--json-schema <file>` | `outputFormat: {type: "json_schema"}`; the verdict arrives as `result.structured_output`, as on `claude -p`. |
| `--max-budget-usd <n>` | Required. The SDK stops with `result.subtype: error_max_budget_usd`. `0` returns that result at once with no model turn. |
| `--resume <session_id>` | Continues the session; every flag of the role repeated. |
| key | `~/.config/maestro/anthropic-api-key` (or `$MAESTRO_API_KEY_FILE`), refused unless a regular file of yours with mode 600; given only to the SDK's child process — never argv, stdout or `.maestro/`. Inherited `ANTHROPIC_*`, `CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CODE_USE_*` are dropped first. |
| `init.apiKeySource` | Measured `"ANTHROPIC_API_KEY"`. Anything else and the runner aborts at once (exit 3): an `api` worker never falls back to a login. |
| output | Every SDK message as one JSON line: `system/init` … `result {subtype, is_error, result, structured_output?, permission_denials, usage, modelUsage, total_cost_usd, session_id}`. `maestro-validate --envelope claude`, `maestro-identity claude --api` and `maestro-ledger --cli claude-sdk` read it. |
| bad key | `result.subtype: "success"` with `is_error: true` and `result: "Invalid API key …"` (measured): exit 1, the envelope check fails. Classify it as unavailability, not quota. |

**Capabilities**: the same as `claude -p` — a builder is edits-only (`Read,Edit,Write,Glob,Grep`),
the director runs the tests; critics get `Read,Grep,Glob`.

**Cost.** `total_cost_usd` is the SDK's estimate from its bundled price table, not an invoice; the
ledger keeps it as `cost_usd` and `maestro-ledger cost --run <id> --transport api` sums it. Policy
`api.max_usd_per_run` (default 20) caps a run; set a spend limit on the Console workspace of the
key as the hard stop. Whether a call actually drew on the credit rather than on prepaid balance
shows only in the Console (Usage / Billing).

### Claude through agy

`agy --model claude-opus-5-5-<effort>` (and `claude-sonnet-5-5-<effort>`), efforts `low|medium|high`
(the slugs agy lists, 2026-11-14)
— the same lines as Gemini otherwise: headless print mode denies every command, so an agy Claude
builder is edits-only and an agy Claude critic reads the repository the same way as a Gemini one. agy has no
Fable and no Haiku. The envelope has no served-model field.

## Evidence and the rubric

The rubric (SKILL.md, "Roster", rows 1–6), the critic, reviewer and arbiter orders and the
degraded-mode orders **move only on what maestro itself has measured**. Vendor numbers, benchmark
boards and community reports are written down with a date, a source and a label (vendor,
independent, secondhand, local measurement), and none of them moves a row on its own. What would
move one:

- ledger rows (`docs/ledger.md`) of a slot in that role over several runs — fix rounds, gate
  failures, review findings the critic missed, tokens and time per finished task — against the
  incumbent on comparable tasks;
- a comparison run on this machine (a canary, or the `test-modeli` skill's per-area scores) that
  ranks it ahead in the area the row is about;
- the incumbent being retired from the catalog for good. (An account denial or an unavailable
  transport is not a reason to move a row: it is the probe walk-down and per-run availability —
  `docs/catalog.md`, "Walk-down"; SKILL.md, "Routing precedence".)

**On 2026-11-24 nothing moved.** No ledger row exists yet for GPT-6.2 Sol or Astra, Gemini 4
Carbon or Neon, and the outside numbers are thin and pull in different directions — the vendor
puts Sol 6.2 within half a point of Astra on FrontierCode 2.0 at a fifth of the cost while
Artificial Analysis has Sol 6.2 3 points below 6.1 Sol on its Coding Agent Index; Neon's
Terminal-Bench 4.1 run is independent but single, with Opus 5.5 0.6 points ahead in the same table;
Anthropic's Terminal-Bench 4.0 figures sit above Artificial Analysis's run; early-tester reports
cut both ways. None of it is measured on maestro's own tasks. `sol` and `astra` resolve to 6.2 because the resolver follows the catalog, not because the
rubric changed; `carbon` and `neon` are explicit-only slots, the first candidates to measure.

**The advisor (2.3.0) is optional and unmeasured.** No rubric row, order or rule names it, and none
moved for it; the ledger's `advise` rows will show whether runs with an advisor need fewer fix
rounds, and until then `--advisor` stays off by default.

## Not used, with the reason

| Option | Why maestro leaves it out |
| --- | --- |
| **Codex SDK** (`@openai/codex-sdk`) | It spawns the `codex` binary with `--experimental-json` (documented, `sdk/typescript/src/exec.ts`) — the same thread, events and resume as `codex exec --json`, plus a Node dependency the skill does not otherwise need. |
| **Claude Agent SDK on a subscription login** | For subscription billing `claude -p` gives the same session, events and resume without a Node runtime; and the SDK's terms ask for API-key authentication. On an API key it is the `api` transport (above). |
| `claude --bare` | API-key-only authentication; for API billing the `api` transport is used (above). |
| agy `--dangerously-skip-permissions` | maestro uses `--mode` settings; the flag approves everything. |

## Schemas

`docs/schemas/critique-schema.json`, `gate-schema.json` and `review-schema.json` (and `arbiter-schema.json`;
it and the critique file's `trigger` and `prior_findings` use the same constructs and are not yet
verified on a CLI) are the shared dialect that
both `--output-schema` (JSON Schema, strict: every property `required`, `additionalProperties:false`)
and `--json-schema` (OpenAPI-3.0-style, rejects `["integer","null"]`) accept — verified on both CLIs
with the same file (critique and gate; review uses the same constructs). The rule that makes this possible: **no nullable fields**. `line: 0` and
`escalate_reason: ""` mean "none"; optional lists are empty arrays. All three carry an
`assumptions[]` field, which is where the follow-through block sends assumptions on schema calls.
`advice-schema.json` (2.3.0, `--advisor`) adds a `boolean` and the length and cardinality keywords
`minLength`, `maxLength` and `maxItems`, which `maestro-validate` checks itself; whether `codex exec
--output-schema`, `claude -p --json-schema` and agy `--json-schema` accept them as written is **not
verified on a CLI yet** — the first advisor call of each transport is that check.

## Briefs

Write the brief to a file under `.maestro/` and pass `"$(cat file)"` with `< /dev/null`. External
workers start cold. A brief that works carries: absolute paths (a worktree worker: file references
and edit boundaries relative to its worktree root, its artifacts at absolute `$REPO/.maestro/…`
paths); explicit change boundaries; the
project's convention files; the binding skills by name; what "done" looks like and which command
proves it; the output contract. Block-structured (task / boundaries / verification / output), not
prose. The run's PLAN.md is the build brief's core.
