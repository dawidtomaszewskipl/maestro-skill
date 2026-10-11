#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal regex and file bodies, written verbatim
# Create a canary repository with route2 installed into it. Refuses an existing directory.
set -eu
SRC="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
D="${ROUTE2_CANARY_ROOT:-$HOME/route2-canaries}/$1"
[[ -e "$D" ]] && { echo "exists: $D"; exit 1; }
mkdir -p "$D/lib" "$D/tests"; cd "$D"; git init -q -b main
printf '%s\n' '# shellcheck shell=bash' '# String helpers.' '' '# upper <text> — print <text> in upper case.' 'upper() { printf '"'"'%s\n'"'"' "${1^^}"; }' > lib/str.sh
cat > tests/test_str.sh <<'T'
#!/usr/bin/env bash
# Tests for lib/str.sh. Run: bash tests/test_str.sh
set -u
. "$(dirname "$0")/../lib/str.sh"
fail=0
check() { if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
check "upper" "ABC" "$(upper abc)"
exit $fail
T
printf '%s\n' '# strlib' 'Tiny bash string helpers. Tests: `bash tests/test_str.sh`.' > README.md
git add -A; git -c user.email=canary@route2 -c user.name=canary commit -qm "strlib: upper"
"$SRC/install.sh" "$D" >/dev/null
printf '.agents/\n.claude/\n.cursor/\n' >> "$(git rev-parse --absolute-git-dir)/info/exclude"
bash tests/test_str.sh >/dev/null && echo "ready: $D"
