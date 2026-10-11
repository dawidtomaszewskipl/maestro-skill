#!/usr/bin/env bash
# V11 (b)+(d): full build with a claude -p director; kill the director while the build job runs,
# then --resume --unattended and expect reconciliation, tests, commit.
set -u
D="${1:?canary repository}"
V="${2:?evidence directory}"
E="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)/bin/maestro-env"
TASK='add a function repeat to lib/str.sh: repeat <text> <n> prints <text> n times joined by single spaces (n=0 prints an empty line); when n is not a non-negative integer it prints an error to stderr and returns 2; with tests in tests/test_str.sh'
cd "$D" || exit 2
"$E" -- claude -p --model sonnet --permission-mode acceptEdits --allowedTools "Bash Read Write Edit Glob Grep Skill" \
  --output-format stream-json --verbose "/maestro --unattended --model=sonnet --critic=grok --rounds=3 --tests=covering $TASK" \
  < /dev/null > "$V/v11-cc-build-1.jsonl" 2> "$V/v11-cc-build-1.err" &
dir=$!
echo "$(date +%T) director pid $dir"
killed=0
for _ in $(seq 1800); do
  kill -0 "$dir" 2>/dev/null || break
  b="$(find .maestro/jobs -maxdepth 1 -name "*build*" -type d 2>/dev/null | head -1)"
  if [[ -n "$b" && -f "$b/meta.json" ]]; then
    sleep 8
    echo "$(date +%T) build job $(basename "$b") running; killing the director"
    kill "$dir"; wait "$dir" 2>/dev/null; killed=1
    echo "$(date +%T) after kill: $("${D}/.agents/skills/maestro/bin/maestro-wait" "$(basename "$b")" --peek | jq -c '{state, code}')"
    break
  fi
  sleep 2
done
[[ $killed == 1 ]] || { wait "$dir" 2>/dev/null; echo "$(date +%T) director finished before a build job appeared"; }
echo "$(date +%T) resume"
"$E" -- claude -p --model sonnet --permission-mode acceptEdits --allowedTools "Bash Read Write Edit Glob Grep Skill" \
  --output-format stream-json --verbose "/maestro --resume --unattended" \
  < /dev/null > "$V/v11-cc-build-2.jsonl" 2> "$V/v11-cc-build-2.err"
echo "$(date +%T) resume exit $?"
jq -r 'select(.type=="result") | .result' "$V/v11-cc-build-2.jsonl" | tail -30
git log --oneline | head -3; git status --short; bash tests/test_str.sh | tail -3
