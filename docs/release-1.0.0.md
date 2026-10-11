# Release 1.0.0 — gate evidence

Every release gate of the approved plan (§11), per host, as measured on this machine on
2026-10-11 (Claude Code 2.1.296, Codex CLI 0.162.1, agy 1.3.3, Cursor agent 2026.10.01). The raw
transcripts are in the build run's evidence directory (`route-skill/.route/r2/v/`, outside this
repository); the outcomes and the commands that produced them are summarised here and in
`docs/hosts.md`, `docs/workers.md` and `tests/canary/README.md`.

**Retained evidence in this repository:** `docs/evidence/1.0.0/` — `v2-v3-host.txt`,
`v2b-v14.txt`, `v4-install.txt` (scratch-`HOME` install, symlinks, helper resolution, refusal of a
foreign target, and each host's own skill listing), `v5-claude-p.txt` (incl. the native pin older
than the alias: `claude-opus-5` accepted, the `opus` alias serving `claude-opus-5-5` rejected),
`v6-v7-cursor.txt`, `v9-survival.txt` (the late snapshots, 672–711 s, tied to the moment each
director session ended), `v11-canaries.txt` (the final report lines and commits of every canary).

`tests/run.sh` on the release revision: **226 passed, 0 failed** (T1–T10; T1 with shellcheck 0.10.0).

## Matrix

| Gate | Claude Code | Codex | Cursor `agent` | agy |
| --- | --- | --- | --- | --- |
| V2 host detection | ✓ interactive (this session) and `claude -p` (headless) | ✓ `host: codex`, director model from its rollout (`gpt-6-luna`, `gpt-6.1-sol`); a sandboxed nested run → `unknown` (fail closed) | ✓ `host: cursor` without a sandbox; inside its sandbox a hidden Cursor process + an outer `CLAUDECODE` → fixed to `unknown` | ✓ `host: agy`, interactive, session key `ANTIGRAVITY_CONVERSATION_ID` (V3 via tmux) |
| V2b git capability (objects, index file, refs, worktree, commit) | ✓ 5/5 (`claude -p`) | ✓ 5/5 (`danger-full-access`) | ✓ 5/5 (allowlist) | ✓ 5/5 (interactive, approved) |
| V4 install, listed by the host | ✓ via the `Skill` tool | ✓ | ✓ | ✓ (`agy /skills`) |
| V5 `claude -p` isolation | ✓ read-only critic (no Edit/Write/Bash, no plugin, no project hook), edits-only builder, resume keeps the role; native pin older than the alias verified | — | — | — |
| V6 Cursor critic read-only | — | — | ✓ write/shell/network/`$HOME` attempts refused, fingerprint `same` | — |
| V7 `init.model` mapping | ✓ `claude-<line>-<v>` | n/a (rollout) | ✓ Grok low…xhigh; Cursor Claude → quota | n/a (no served-model field) |
| V9 job survival across commands | ✓ | ✓ | ✓ | ✓ |
| V9 job survival ≥ 10 min after the director session ended | ✓ 672 s | ✓ 711 s | ✓ 686 s | ✓ 680 s |
| V11 plan-only canary | ✓ (`needs-decision`, real locale bug; resume + `adopt`) | ✓ `plan-only` | ✓ `plan-only` | ✓ (`needs-decision`, same bug) |
| V11 full build, tests, commit | ✓ (`a0108c8`, also the transport switch `55f7cdb`) | ✓ (`e18d5b2`) | ✓ (`03714ab`) | ✓ (`6040b24`) |
| V11 parallel split in worktrees | — | ✓ (`7c38644`, two Sonnet workers) | — | — |
| V11 director killed mid-build, `--resume` | ✓ (`a0108c8`) | ✓ (`76d1b6e`) | ✓ (`2d0dc4a`) | ✓ (`9b3d238`) |
| V11 transport switch (quota fault) | ✓ native → agy (shim) | n/a (Codex rebuilds `PATH`) | — | — |
| V12 Cursor builder reads a screenshot path | — | — | ✓ | — |
| V14 the director takes a screenshot and reads it | ✓ ("OTTER cc", green) | ✓ ("OTTER codex") | ✓ ("OTTER cursor"; `Shell(npx)`) | ✓ ("OTTER agy") |

**agy, director killed mid-build:** the interactive agy session was killed while the Sol build
job ran (the job stayed `running`); a new agy session ran `/route2 --resume --unattended`, adopted the
lock, finished the run, ran the tests and committed `9b3d238`; bookkeeping rotated, lock released.
On the way the run stopped twice, correctly: at the critique cap (`needs-decision`, row 3 — Grok kept
finding real shell defects: integer overflow, `set -u`, `LC_ALL=C` with `[[`) and once because the
agy director tried to read another repository's probe records and the access was refused (an agy
refusal ends its turn — `docs/hosts.md`).

## Limits stated, not hidden

- The interactive Agent-tool path of the transport switch follows the same SKILL.md steps but is
  not exercised by a canary (a fault cannot be injected into the harness).
- A Codex director cannot carry the `claude` shim (its shell rebuilds `PATH`), so the switch canary
  ran with a `claude -p` director.
- A descendant that detaches and execs before the recorder's first poll (one poll right after the
  spawn, then every second) is not seen; `unowned` reports same-command processes in the job's
  directory, and `route2-kill` blocks on members it cannot relate to the job's tests.
- Grok is provisional: it built nothing in these canaries; as a critic it found real defects.
- The `cc-sandbox` rung for `claude -p` builders is not adopted (unmeasured); they are edits-only.
