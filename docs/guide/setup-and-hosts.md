# Setup and running

## Installing

Requirements: Linux, bash ≥ 5, jq ≥ 1.6, git, util-linux (`setsid`, `flock`), Claude Code
(`claude`), and whichever of `codex` and `agy` (Antigravity) you want as workers.

```bash
./install.sh                      # for you
./install.sh ~/code/my-project    # for one project only
./install.sh --check              # where it is installed
./install.sh --check=live         # Claude Code confirms it sees the skill (one cheap call)
./install.sh --sdk                # also install the Agent SDK for the API credit (needs Node ≥ 18)
```

The install copies the skill to `~/.claude/skills/maestro` (a project install: to
`<project>/.claude/skills/maestro`). Nothing else on your machine is touched. A 1.x install left a
symlink there, pointing at `~/.agents/skills/maestro`; the installer replaces the symlink with the
copy and names the 1.x leftovers — `~/.agents/skills/maestro` and the agy link
`~/.gemini/config/skills/maestro` — which nothing reads any more and you can delete by hand.

## Signing in

maestro uses the CLIs' own logins. Before a run it checks, without any model call, that each CLI
is installed, signed in and healthy (`claude auth status`, `codex login status` and `codex
doctor`, `agy models` — one helper, `maestro-preflight`, does all of it). A family whose CLI is
missing or signed out is simply not on the team, and the assignment line says so. When your Claude
login expires within a day, the assignment line warns you before a long run starts. You never give
maestro a password or a key — except the optional API key for the [API
credit](../../README.md#api-credit), which lives in a file only you can read.

## Running it

maestro runs inside **Claude Code** — the session's model is the director. Codex and agy are
only ever workers; since 2.0.0 they no longer run maestro themselves.

| | Interactive | Headless |
| --- | --- | --- |
| Start | `/maestro <task>` | `claude -p "/maestro --unattended <task>"` |
| How it asks you | a question dialog | it does not: a gap becomes a recorded assumption, a decision stops the run (`--unattended` is required) |
| Claude workers | subagents (the `Agent` tool) | `claude -p`, edits-only (the director runs the tests) |
| Long jobs | started detached by `maestro-run`; a background task waits for each and notifies the director when it ends | started the same way and polled; in both modes a job keeps running after the director's session ends, and `/maestro --resume` finds it and waits for it |

The director can make a small change itself (`self`) in both modes: Claude Code knows its own
model.

## The policy file

Standing preferences go into `maestro.policy.toml` at the repository root (for the team) or
`~/.config/maestro/policy.toml` (for you). Every key is optional; flags beat the repository file,
which beats yours.

```toml
implementer = "sol"       # default builder when --model is absent
deny = ["fable"]          # never picked on the director's own initiative
critique_rounds = 2

[families]
google = "off"            # even if agy is installed

[transports]
deny = ["opus@agy"]       # a road the director never takes on its own

[api]
fallback = true           # switch to the API credit when the Claude limit runs out
max_usd_per_run = 20
```

`maestro-policy resolve` reads both files and prints the merged values, where each came from, and
anything wrong with them — run it to check a file you have just written.

A value that came from a policy is marked `(policy)` in the assignment line, so you always see
where a choice came from. The cross-family rule is not a policy key and cannot be switched off.
Naming a denied slot on the command line still works, with a warning. The full key list and an
annotated example: [policy.md](../policy.md), [examples/maestro.policy.toml](../examples/maestro.policy.toml).

## Safety defaults

- **Workers cannot touch your configuration.** Every external worker is launched through a
  wrapper that strips the director's environment — no inherited plugins, hooks, API keys or
  effort settings. Claude workers run with an exact tool list; Codex workers with the user config
  ignored, or pinned when it must be read.
- **Sandboxes, lowest level first.** A Codex builder runs with the repository writable and the
  network off. Workers through agy, `claude -p` and the API only edit files.
  For Codex there is a ladder — repository writable with no network; the worker edits only and
  the director runs the rest; automatic review of the worker's escalation requests; no sandbox
  at all — climbed one rung at a time, only with a failed check to point at, each rung named in
  the assignment line; the top rung is per run and per project, announced before launch, and
  never written into a global config.
- **Read-only roles leave no trace.** Before and after every critic, gate, reviewer, arbiter or
  advisor call the director fingerprints the checkout; a changed file means the verdict (or the
  advice) is discarded.
- **One run per repository.** A lock in `.maestro/` keeps a second director out; a `--resume` can
  take over only a dead one.
- **A clean tree.** A run starts only on a clean git tree, so a worker's leftovers can always be
  told from your work. Everything maestro writes lives in `.maestro/`, excluded from git.
- **Tests are never killed.** Not by the hang watchdog, not by a stop, not by a resume.
- **What needs your approval:** anything the interview cannot settle; the top sandbox rung (no
  sandbox at all) for a Codex worker; an assignment that breaks a rule you asked for; accepting a
  state file that was changed outside maestro. Under `--unattended` each of these is a clean stop
  with options instead.

## Technical details

- [hosts.md](../hosts.md) — detection, interactive and headless Claude Code, jobs, the lock.
- [sandbox-and-preflight.md](../sandbox-and-preflight.md) — what each sandbox denies, the reach
  probe, the escalation ladder.
- [commands.md](../commands.md) — the exact launch lines per CLI and role.
- [workers.md](../workers.md) — the measured flags and permissions of each CLI.
- [policy.md](../policy.md) — every policy key.
- [install.sh](../../install.sh) — the installer's options, in its header comment.
