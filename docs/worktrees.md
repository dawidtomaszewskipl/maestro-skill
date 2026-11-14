# Splits and worktrees

*What this page is for: how parallel writers work when the director splits a build. Read it when a
split is decided (SKILL.md, "Roster").*

**Never two write-mode workers in one checkout at once**: they collide on files and
`.git/index.lock`. Parallel writers each get a worktree, one builder family per split:

- Claude subagents in an interactive Claude Code: the `Agent` tool with `isolation: "worktree"`.
- Every other writer: a worktree you create before launch (`git worktree add --detach
  "$REPO/.maestro/worktrees/<part>" HEAD`, inside the fence), entered with `codex exec -C <wt>` or a
  `claude -p` (or `maestro-sdk --cwd <wt>`) whose cwd is the worktree. agy takes no part.

Probe it first: `maestro-preflight --gen N --worktree` (since Claude Code 2.1.323 the Bash sandbox
makes `git worktree add/remove` read-only — preflight names the remedy).

Every part starts from `HEAD` and must not depend on another part's integration. Its brief writes
every path and boundary relative to the worktree root — never the checkout's absolute paths, which
would send the edits into the checkout — and says *"Do not run tests; the director will"*
(parallel runs would share the `testing` database, and a fresh worktree has no `.env`, `vendor/` or
`node_modules/`). The checkpoint records each worktree with its session id, `baseline` SHA and
fingerprint.

**Integration — yours, one worktree at a time:** `git -C <worktree> add -A`, then `git -C
<worktree> diff --cached HEAD --binary`, applied in the checkout with `git apply` (inside the
fence, `maestro-lock exec --gen N -- …`). Then mark the integrated state with a commit **inside the
worktree** (`git -C <worktree> commit -m maestro-integrated`, never merged) whose SHA becomes its
`baseline`: the next integration after a fix round first checks `HEAD == baseline` and then takes
only what changed since. All this happens before your diff read, the tests (covering the
integrated result) and the review; until integrated, the checkpoint's `tree` does not cover it.

**Keep every worktree until the report**, then remove it (`git worktree remove --force`, `git
worktree prune`) and any branch. A single external worker owns the checkout while it runs; while
parallel workers run, they own only their worktrees and the checkout is yours, for integration only.
