#!/usr/bin/env bash
# V2b: the git capabilities a maestro director needs, in a scratch repository ($1).
set -u
cd "$1" || exit 2
r="v2b-$$-$RANDOM"; gd="$(git rev-parse --absolute-git-dir)"
res() { printf '%-14s %s\n' "$1" "$2"; }
trap 'rm -f "$gd/maestro-probe-$r"; git update-ref -d "refs/maestro/probe-$r" 2>/dev/null; git worktree remove --force ".maestro/worktrees/probe-$r" 2>/dev/null' EXIT
if b=$(printf 'probe\n' | git hash-object -w --stdin); then res objects "ok $b"; else res objects FAIL; fi
if GIT_INDEX_FILE="$gd/maestro-probe-$r" git read-tree HEAD; then res index-file ok; else res index-file FAIL; fi
if git update-ref "refs/maestro/probe-$r" HEAD && git update-ref -d "refs/maestro/probe-$r"; then res refs ok; else res refs FAIL; fi
mkdir -p .maestro/worktrees
if git worktree add -q --detach ".maestro/worktrees/probe-$r" HEAD && git worktree remove --force ".maestro/worktrees/probe-$r"; then res worktree ok; else res worktree FAIL; fi
echo "v2b $(date +%s)" > v2b.txt
if git add v2b.txt && git -c user.email=v2b@maestro -c user.name=v2b commit -qm "v2b probe commit" && git reset -q --hard HEAD~1; then res commit ok; else res commit FAIL; fi
