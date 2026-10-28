# Setup and hosts

## Installing

Requirements: Linux, bash ≥ 5, jq ≥ 1.6, git, util-linux (`setsid`, `flock`), and whichever of
`claude`, `codex`, `agent` (Cursor) and `agy` (Antigravity) you want to use.

```bash
./install.sh                      # for you: Claude Code, Codex, Cursor and agy
./install.sh ~/code/my-project    # for one project only
./install.sh --hosts=claude-code,codex
./install.sh --check              # where it is installed
./install.sh --check=live         # each host confirms it sees the skill (a few cheap calls)
./install.sh --sdk                # also install the Agent SDK for the API credit (needs Node ≥ 18)
```

The global install copies the skill to `~/.agents/skills/maestro` (read by Codex and Cursor) and
links `~/.claude/skills/maestro` (Claude Code) and `~/.gemini/config/skills/maestro` (agy) to it.
A project install puts the same under `<project>/.agents/skills/maestro` and
`<project>/.claude/skills/maestro`. Nothing else on your machine is touched.

## Signing in

maestro uses the CLIs' own logins. Before a run it checks, without any model call, that each CLI
is installed, signed in and healthy (`claude auth status`, `codex login status` and `codex
doctor`, `agent status`, `agy models`). A family whose CLI is missing or signed out is simply not
on the team, and the assignment line says so. You never give maestro a password or a key — except
the optional API key for the [API credit](../../README.md#api-credit), which lives in a file only
you can read.

## Running from Claude Code, Codex, Cursor or agy

The host is the assistant you type `/maestro` into; its model is the director. The loop is the
same everywhere; four things differ.

| | Claude Code | Codex | Cursor (`agent`) | agy |
| --- | --- | --- | --- | --- |
| Invoke | `/maestro` | `$maestro` | `/maestro` | `/maestro` |
| One-time setting | none | start Codex with `--sandbox danger-full-access` — the director must reach the model APIs and run the tests, and Codex's default sandbox blocks the network | a project `.cursor/cli.json` allowlist of the commands the director needs; **never `--force`**, it turns the sandbox off | interactive session only; approve commands and file writes, or add `permissions.allow` rules |
| Can the director build itself (`self`) | yes | yes | no — Cursor does not reveal the director's model, so another model always builds | no, for the same reason |
| How it asks you | a question dialog | a dialog when Codex offers one, otherwise a plain question | a plain question, then it waits | agy's question dialog |
| Headless (`--unattended`) | `claude -p "/maestro --unattended …"` | `codex exec` | `agent -p` | no — in print mode agy refuses every command |

Long jobs — a worker's turn, a test run — are handled in two ways. In an interactive Claude Code
they are the host's own background tasks, with its completion notification, and belong to that
session. On every other host maestro launches each job detached and polls it; such a job keeps
running after the director's session ends (measured on each host), and `/maestro --resume` finds
it and waits for it.

**Which host?** An interactive Claude Code is the most comfortable: proper question dialogs,
completion notifications, and the director can make a small change itself. Codex is handy when
the Claude quota is gone. Cursor and agy work, but need the permission setup and do not let the
director build.

## The policy file

Standing preferences go into `maestro.policy.yml` at the repository root (for the team) or
`~/.config/maestro/policy.yml` (for you). Every key is optional; flags beat the repository file,
which beats yours.

```yaml
implementer: sol          # default builder when --model is absent
deny: [fable]             # never picked on the director's own initiative
critique_rounds: 2
families:
  google: off             # even if agy is installed
transports:
  deny: [fable@cursor]    # a road the director never takes on its own
api:
  fallback: true          # switch to the API credit when the Claude limit runs out
  max_usd_per_run: 20
```

A value that came from a policy is marked `(policy)` in the assignment line, so you always see
where a choice came from. The cross-family rule is not a policy key and cannot be switched off.
Naming a denied slot on the command line still works, with a warning. The full key list and an
annotated example: [policy.md](../policy.md), [examples/maestro.policy.yml](../examples/maestro.policy.yml).

## Safety defaults

- **Workers cannot touch your configuration.** Every external worker is launched through a
  wrapper that strips the director's environment — no inherited plugins, hooks, API keys or
  effort settings. Claude workers run with an exact tool list; Codex workers with the user config
  ignored, or pinned when it must be read.
- **Sandboxes, lowest level first.** A Codex builder runs with the repository writable and the
  network off. A Cursor builder runs in Cursor's sandbox (repository and `/tmp` writable, no
  network, no home directory). Workers through agy, `claude -p` and the API only edit files.
  For Codex there is a ladder — repository writable with no network; the worker edits only and
  the director runs the rest; automatic review of the worker's escalation requests; no sandbox
  at all — climbed one rung at a time, only with a failed check to point at, each rung named in
  the assignment line; the top rung is per run and per project, announced before launch, and
  never written into a global config. For Cursor there is no ladder: `--force` turns its sandbox
  off entirely and is used only on your explicit approval for one run, never under `--unattended`.
- **Read-only roles leave no trace.** Before and after every critic, gate or reviewer call the
  director fingerprints the checkout; a changed file means the verdict is discarded.
- **One run per repository.** A lock in `.maestro/` keeps a second director out; a `--resume` can
  take over only a dead one.
- **A clean tree.** A run starts only on a clean git tree, so a worker's leftovers can always be
  told from your work. Everything maestro writes lives in `.maestro/`, excluded from git.
- **Tests are never killed.** Not by the hang watchdog, not by a stop, not by a resume.
- **What needs your approval:** anything the interview cannot settle; running a Cursor worker with `--force` (no sandbox at all); an
  assignment that breaks a rule you asked for; taking over a run on a different host; accepting a
  state file that was changed outside maestro. Under `--unattended` each of these is a clean stop
  with options instead.

## Technical details

- [hosts.md](../hosts.md) — host detection, the adapter table, jobs, the lock, Cursor's allowlist.
- [sandbox-and-preflight.md](../sandbox-and-preflight.md) — what each sandbox denies, the reach
  probe, the escalation ladder.
- [commands.md](../commands.md) — the exact launch lines per CLI and role.
- [workers.md](../workers.md) — the measured flags and permissions of each CLI.
- [policy.md](../policy.md) — every policy key.
- [install.sh](../../install.sh) — the installer's options, in its header comment.
