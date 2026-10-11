#!/usr/bin/env bash
# route2 test suite — no model calls (docs: README "Tests").
#
#   tests/run.sh [T1 T2 …]      run all groups, or the named ones
#
# Needs bash ≥ 5, jq, git, util-linux; T1 needs shellcheck ($SHELLCHECK or on PATH).
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT="$(dirname "$HERE")"
B="$ROOT/bin"
FX="$HERE/fixtures"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/route2-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0 failed=()
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); failed+=("$1"); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }
# eq <name> <expected> <actual>
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected: $2 | actual: $3"; fi; }
# jqt <name> <json> <jq boolean expression>
jqt()  { if jq -e "$3" >/dev/null 2>&1 <<<"$2"; then ok "$1"; else bad "$1" "$(head -c 400 <<<"$2") !~ $3"; fi; }

want() { [[ ${#SELECT[@]} -eq 0 || " ${SELECT[*]} " == *" $1 "* ]]; }
SELECT=("$@")
group() { want "$1" || return 1; printf '\n%s — %s\n' "$1" "$2"; }

new_repo() {  # a scratch git repo with one commit; prints its path
  local d; d="$(mktemp -d "$WORK/repo.XXXXXX")"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '.route2/\n' >> "$(git -C "$d" rev-parse --absolute-git-dir)/info/exclude"   # as stage 0 step 2 does
  printf '%s\n' "$d"
}

# =============================================================================================
if group T1 "lint"; then
  SC="${SHELLCHECK:-shellcheck}"
  if command -v "$SC" >/dev/null 2>&1; then
    out="$(cd "$ROOT" && "$SC" bin/route2-* bin/_lib.sh install.sh tests/*.sh 2>&1)"
    eq "shellcheck clean" "" "$out"
  else
    bad "shellcheck available" "set SHELLCHECK or install shellcheck"
  fi
  for f in "$B"/route2-* "$ROOT/install.sh" "$HERE"/*.sh; do
    [[ -f "$f" ]] || continue
    if bash -n "$f" 2>/dev/null; then ok "bash -n $(basename "$f")"; else bad "bash -n $(basename "$f")"; fi
  done
fi

# =============================================================================================
if group T2 "catalog"; then
  cmp_() { "$B/route2-catalog" compare "$1" "$2"; }
  eq "6.1 < 6.10"  -1 "$(cmp_ 6.1 6.10)"
  eq "5.5 < 5.10"  -1 "$(cmp_ 5.5 5.10)"
  eq "[5] = [5,0]"  0 "$(cmp_ 5 5.0)"
  eq "[6,1] > [6]"  1 "$(cmp_ 6.1 6)"
  eq "[7] > [6,10]" 1 "$(cmp_ 7 6.10)"
  eq "6.9 < 6.10"  -1 "$(cmp_ 6.9 6.10)"

  # This machine's catalogs (2026-10-11).
  M="$FX/catalogs/machine-2026-10-11"
  out="$(ROUTE2_STATE="$WORK/c1" "$B/route2-catalog" refresh --fixtures "$M" --out "$WORK/c1/catalog.json")"
  jqt "machine: sol newest 6.1" "$out" '.slots.codex.sol[0] == "6.1"'
  jqt "machine: astra 6" "$out" '.slots.codex.astra == ["6"]'
  jqt "machine: gemini 3.8 first" "$out" '.slots.agy.gemini[0] == "3.8"'
  jqt "machine: agy opus 5.5" "$out" '.slots.agy.opus == ["5.5"]'
  jqt "machine: grok 4.7 (cursor-grok-* excluded)" "$out" '.slots.cursor.grok == ["4.7"]'
  jqt "machine: cursor fable 5.1 first" "$out" '.slots.cursor.fable[0] == "5.1"'
  cat_="$WORK/c1/catalog.json"
  jqt "machine: cursor-grok-4.6-high is unmatched" "$(cat "$cat_")" '.transports.cursor.unmatched | index("cursor-grok-4.6-high") != null'
  jqt "machine: thinking duplicates unmatched" "$(cat "$cat_")" '.transports.cursor.unmatched | index("claude-opus-5-thinking-high") != null'
  jqt "machine: codex identity from the cache" "$(cat "$cat_")" '.sources.codex.identity == "fixture-identity"'

  # Synthetic catalogs: integer generations, multi-digit components, excluded suffixes.
  S="$WORK/syn"; mkdir -p "$S"
  jq -n '{models: ([ "gpt-6.1-sol","gpt-6.10-sol","gpt-6.9-sol","gpt-7-sol","gpt-6.2-sol-preview","gpt-6-astra","gpt-reserve" ]
                    | map({slug: ., visibility: "list", supported_reasoning_levels: [{effort: "low"},{effort: "medium"}]}))}' > "$S/codex-models.json"
  printf 'Fetching available models...\ngemini-3.8-flash-high\tG\ngemini-4-flash-high\tG4\ngemini-4-flash-preview-high\tP\nclaude-opus-5-10-high\tO\nclaude-opus-5-5-high\tO\n' > "$S/agy-models.txt"
  printf 'Available models\n\ngrok-4.7-high - Grok\ngrok-5-high - Grok 5\ngrok-5-high-fast - Grok 5 Fast\ncursor-grok-9-high - X\n\nTip: …\n' > "$S/cursor-models.txt"
  out="$(ROUTE2_STATE="$WORK/c2" "$B/route2-catalog" refresh --fixtures "$S" --out "$WORK/c2/catalog.json")"
  jqt "synthetic: sol order 7, 6.10, 6.9, 6.1" "$out" '.slots.codex.sol == ["7","6.10","6.9","6.1"]'
  jqt "synthetic: gemini 4 before 3.8" "$out" '.slots.agy.gemini == ["4","3.8"]'
  jqt "synthetic: opus 5.10 before 5.5" "$out" '.slots.agy.opus == ["5.10","5.5"]'
  jqt "synthetic: grok 5 first, fast kept apart" "$out" '.slots.cursor.grok == ["5","4.7"]'
  jqt "synthetic: preview and dated slugs unmatched" "$(cat "$WORK/c2/catalog.json")" \
    '(.transports.codex.unmatched | index("gpt-6.2-sol-preview") != null) and (.transports.agy.unmatched | index("gemini-4-flash-preview-high") != null)'
  jqt "synthetic: fast slugs recorded separately" "$(cat "$WORK/c2/catalog.json")" \
    '.transports.cursor.slots.grok[0].fast_slugs.high == "grok-5-high-fast" and .transports.cursor.slots.grok[0].slugs.high == "grok-5-high"'

  # Acquisition failures vs empty lines.
  E="$WORK/e"; mkdir -p "$E"; printf 'Fetching available models...\n' > "$E/agy-models.txt"; printf '{not json' > "$E/codex-models.json"
  out="$(ROUTE2_STATE="$WORK/c3" "$B/route2-catalog" refresh --fixtures "$E" --out "$WORK/c3/catalog.json")"
  jqt "banner-only agy = acquisition failure" "$out" '.sources.agy.error != null and .slots.agy == null'
  jqt "malformed codex = acquisition failure" "$out" '.sources.codex.error != null and .slots.codex == null'
  jqt "missing cursor fixture = acquisition failure" "$out" '.sources.cursor.error != null'
  # Stale cache fallback.
  C="$WORK/cache"; mkdir -p "$C"
  jq -n '{identity: "x", client_version: "0.0.1", fetched_at: "2020-01-01T00:00:00Z",
          models: [{slug: "gpt-6.1-sol", visibility: "list"}]}' > "$C/codex-cache.json"
  out="$(ROUTE2_STATE="$WORK/c4" "$B/route2-catalog" refresh --fixtures "$C" --out "$WORK/c4/catalog.json")"
  jqt "stale cache: mode cache, stale true" "$out" '.sources.codex.mode == "cache" and .sources.codex.stale == true'

  # Pick: walk-down, pins, scoped denials.
  P="$WORK/c2"
  pick() { ROUTE2_STATE="$P" "$B/route2-catalog" pick "$@" --catalog "$P/catalog.json"; }
  jqt "pick: newest sol needs a probe" "$(pick sol codex --effort medium)" '.action == "probe" and .slug == "gpt-7-sol"'
  jq -n --argjson ep "$(date +%s)" '{"codex:gpt-7-sol": {result: "denied", scope: {acct: "a"}, at_epoch: $ep},
        "codex:gpt-6.10-sol": {result: "ok", scope: {acct: "a"}, at_epoch: $ep}}' > "$P/model-probes.json"
  jqt "pick: denied newest → walk down to 6.10 (fresh ok → use)" "$(pick sol codex --scope '{"acct":"a"}' --probes "$P/model-probes.json")" \
    '.action == "use" and .slug == "gpt-6.10-sol" and .skipped == ["gpt-7-sol"]'
  jqt "pick: denial of another account does not count" "$(pick sol codex --scope '{"acct":"b"}' --probes "$P/model-probes.json")" \
    '.action == "probe" and .slug == "gpt-7-sol"'
  jq -n --argjson ep "$(( $(date +%s) - 2*86400 ))" '{"codex:gpt-7-sol": {result: "denied", scope: {acct: "a"}, at_epoch: $ep}}' > "$P/old.json"
  jqt "pick: a denial older than 24 h has expired" "$(pick sol codex --scope '{"acct":"a"}' --probes "$P/old.json")" '.slug == "gpt-7-sol"'
  jqt "pick: canonical pin 6.9" "$(pick sol codex --pin 6.9)" '.slug == "gpt-6.9-sol"'
  jqt "pick: exact slug pin" "$(pick sol codex --pin-slug gpt-6.1-sol)" '.slug == "gpt-6.1-sol"'
  jqt "pick: missing pin → none" "$(pick sol codex --pin 9)" '.action == "none" and (.reason | test("pinned version 9"))'
  jqt "pick: effort with no slug → none" "$(pick gemini agy --effort xhigh)" '.action == "none"'
  jqt "pick: line without candidates → none + previous" \
    "$(jq '.previous = {luna: {codex: "6"}}' "$P/catalog.json" > "$P/cp.json"; ROUTE2_STATE="$P" "$B/route2-catalog" pick luna codex --catalog "$P/cp.json")" \
    '.action == "none" and .previous == "6"'
fi

# =============================================================================================
if group T3 "host detection"; then
  # Fake /proc: mkproc <root> <pid> <ppid> <exe> <argv…>
  mkproc() {
    local r="$1" p="$2" pp="$3" exe="$4"; shift 4
    mkdir -p "$r/$p"
    printf '%s (x) S %s %s %s 0 -1 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 0\n' "$p" "$pp" "$p" "$p" "$((1000 + p))" > "$r/$p/stat"
    printf '%s\0' "$@" > "$r/$p/cmdline"
    ln -s "$exe" "$r/$p/exe"
  }
  host() { env -i PATH="$PATH" HOME="$HOME" ROUTE2_PROC="$1" ROUTE2_HOST_START_PID="$2" CODEX_HOME="$WORK/nocodex" "${@:3}" "$B/route2-host"; }
  CC=/home/u/.local/share/claude/versions/2.1.296
  CX=/home/u/.codex/packages/standalone/releases/0.162.1/bin/codex
  NODE=/home/u/.local/share/cursor-agent/versions/2026.10.01/node
  R="$WORK/proc1"; mkproc "$R" 100 1 "$CC" claude; mkproc "$R" 200 100 /usr/bin/bash bash
  jqt "claude-code interactive" "$(host "$R" 200 CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s1)" \
    '.host == "claude-code" and .interactive == true and .session_key == "s1" and .director_family == "claude"'
  R="$WORK/proc2"; mkproc "$R" 100 1 "$CC" claude; mkproc "$R" 300 100 "$CX" codex exec -m x; mkproc "$R" 400 300 /usr/bin/bash bash
  jqt "codex inside claude code (inherited CLAUDECODE is not a conflict)" \
    "$(host "$R" 400 CLAUDECODE=1 CODEX_THREAD_ID=t1)" '.host == "codex" and .interactive == false and .session_key == "t1"'
  R="$WORK/proc3"; mkproc "$R" 100 1 "$CC" claude; mkproc "$R" 300 100 "$NODE" /home/u/.local/bin/agent /home/u/.local/share/cursor-agent/versions/2026.10.01/index.js -p x; mkproc "$R" 400 300 /usr/bin/bash bash
  jqt "cursor inside claude code" "$(host "$R" 400 CLAUDECODE=1 CURSOR_AGENT=1 CURSOR_CONVERSATION_ID=c1)" \
    '.host == "cursor" and .interactive == false and .session_key == "c1"'
  R="$WORK/proc4"; mkproc "$R" 300 1 "$CX" codex; mkproc "$R" 350 300 "$CC" claude -p hi; mkproc "$R" 400 350 /usr/bin/bash bash
  jqt "claude -p inside codex" "$(host "$R" 400 CODEX_THREAD_ID=t1 CLAUDECODE=1)" '.host == "claude-code" and .interactive == false'
  jqt "nearest host without its marker → unknown" "$(host "$R" 400 CODEX_THREAD_ID=t1)" '.host == "unknown"'
  jqt "markers only, exactly one" "$(host "$WORK/none" 400 CODEX_THREAD_ID=t1)" '.host == "codex" and (.evidence | any(test("markers-only")))'
  jqt "markers only, several → unknown" "$(host "$WORK/none" 400 CODEX_THREAD_ID=t1 CLAUDECODE=1)" '.host == "unknown"'
  jqt "zero signals → unknown" "$(host "$WORK/none" 400)" '.host == "unknown"'
  # Measured 2026-10-11: Cursor's sandbox hides the Cursor process; the nearest visible host was
  # the Claude Code daemon that launched it.
  R="$WORK/proc6"; mkproc "$R" 100 1 "$CC" claude daemon run; mkproc "$R" 200 100 /usr/bin/bash bash
  jqt "hidden cursor under a visible claude: markers of both → unknown" \
    "$(host "$R" 200 CLAUDECODE=1 CURSOR_AGENT=1 CURSOR_CONVERSATION_ID=c1)" '.host == "unknown" and (.evidence | any(test("incomplete")))'
  R="$WORK/proc7"; mkproc "$R" 100 1 /usr/bin/bash bash
  jqt "hidden cursor, only its markers → cursor (markers-only)" \
    "$(host "$R" 100 CURSOR_AGENT=1 CURSOR_CONVERSATION_ID=c1)" '.host == "cursor"'
  R="$WORK/proc5"; mkproc "$R" 500 1 /home/u/.local/bin/agy agy; mkproc "$R" 510 500 /usr/bin/bash bash
  jqt "agy ancestor without its marker → unknown" "$(host "$R" 510)" '.host == "unknown"'
  jqt "agy ancestor with its marker (measured: ANTIGRAVITY_AGENT, ANTIGRAVITY_CONVERSATION_ID)" \
    "$(host "$R" 510 ANTIGRAVITY_AGENT=1 ANTIGRAVITY_CONVERSATION_ID=sess)" '.host == "agy" and .session_key == "sess" and .interactive == true'
  R="$WORK/proc8"; mkproc "$R" 500 1 /home/u/.local/bin/agy agy -p hi; mkproc "$R" 510 500 /usr/bin/bash bash
  jqt "agy print mode is headless" "$(host "$R" 510 ANTIGRAVITY_AGENT=1 ANTIGRAVITY_CONVERSATION_ID=s)" '.host == "agy" and .interactive == false'
fi

# =============================================================================================
if group T4 "jobs"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  L() { "$B/route2-lock" "$@"; }
  gen="$(L acquire --run r --token t --host test | jq -r .generation)"
  run() { "$B/route2-run" --gen "$gen" --run r --role build "$@"; }
  st() { "$B/route2-wait" "$1" --peek; }
  run --job j0 -- bash -c 'exit 0' >/dev/null; sleep 1.5
  jqt "exit 0 → exited 0" "$("$B/route2-wait" j0 --max 10)" '.state == "exited" and .code == "0"'
  run --job j1 -- bash -c 'exit 3' >/dev/null
  jqt "non-zero → exited 3" "$("$B/route2-wait" j1 --max 10)" '.state == "exited" and .code == "3"'
  run --job j2 -- no-such-command-xyz >/dev/null
  jqt "launch failure" "$(st j2)" '.state == "exited" and .code == "launch-failed"'
  out="$(run --job j1 -- true 2>&1)"; eq "duplicate job id refused" 1 "$(grep -c 'never reused' <<<"$out")"
  printf '#!/bin/bash\n(sleep 20 &)\nexit 0\n' > "$REPO/linger.sh"; chmod +x "$REPO/linger.sh"
  run --job j3 -- ./linger.sh >/dev/null; sleep 3
  jqt "exit 0 with a surviving descendant → lingering" "$(st j3)" '.state == "lingering" and (.live_members | length) == 1'
  run --job j4 -- bash -c 'sleep 30' >/dev/null; sleep 1.5
  jqt "running" "$(st j4)" '.state == "running"'
  pid4="$(jq -r .pid .route2/jobs/j4/meta.json)"; kill -9 "$pid4"; sleep 2.5
  jqt "leader killed by a signal → exited signal:9" "$(st j4)" '.state == "exited" and .code == "signal:9"'
  # Orphaned: the wrapper and the leader die, a member survives.
  printf '#!/bin/bash\nsleep 25 &\nsleep 25\n' > "$REPO/orph.sh"; chmod +x "$REPO/orph.sh"
  run --job j5 -- ./orph.sh >/dev/null; sleep 2.5
  w5="$(jq -r .wrapper_pid .route2/jobs/j5/meta.json)"; p5="$(jq -r .pid .route2/jobs/j5/meta.json)"
  kill -9 "$w5" "$p5"; sleep 1
  jqt "leader and wrapper gone, member alive → orphaned" "$(st j5)" '.state == "orphaned"'
  # Kill: lingering member is terminated; result done.
  r1="$("$B/route2-kill" j3 --gen "$gen" --grace 1)"; sleep 1.5
  r2="$("$B/route2-kill" j3 --gen "$gen" --grace 1)"
  jqt "kill a lingering member: signalled, then done" "[$r1,$r2]" '.[0].result == "signalled" and .[1].result == "done"'
  "$B/route2-kill" j5 --gen "$gen" --grace 1 >/dev/null; sleep 1.5; "$B/route2-kill" j5 --gen "$gen" --grace 1 >/dev/null
  jqt "orphaned member killed → done/lost" "$("$B/route2-kill" j5 --gen "$gen")" '.result == "done"'
  # Tests are never signalled; protected subtrees wait.
  mkdir -p "$REPO/vendor/bin"; printf '#!/bin/sh\nexec sleep 8\n' > "$REPO/vendor/bin/pest"; chmod +x "$REPO/vendor/bin/pest"
  printf '#!/bin/bash\nsh -c "vendor/bin/pest --parallel" &\nsleep 30\n' > "$REPO/b.sh"; chmod +x "$REPO/b.sh"
  run --job j6 --test-runner vendor/bin/pest -- ./b.sh >/dev/null; sleep 2.5
  jqt "test subtree protected → waiting-tests" "$("$B/route2-kill" j6 --gen "$gen")" '.result == "waiting-tests"'
  sleep 7
  jqt "after the test ends the rest is signalled" "$("$B/route2-kill" j6 --gen "$gen" --grace 1)" '.result == "signalled"'
  sleep 1.5; "$B/route2-kill" j6 --gen "$gen" >/dev/null
  # An unrelated process with the same cwd and command line is not a member, and is reported.
  printf '#!/bin/bash\nsleep 20\n' > "$REPO/same.sh"; chmod +x "$REPO/same.sh"
  run --job j7 -- ./same.sh >/dev/null
  (cd "$REPO" && setsid ./same.sh >/dev/null 2>&1 &) ; sleep 2.5
  out="$(st j7)"
  jqt "unrelated same-command process: not a member, reported unowned" "$out" \
    '(.unowned | length) >= 1 and ([.unowned[].pid] - [.live_members[].pid] | length) == (.unowned | length)'
  "$B/route2-kill" j7 --gen "$gen" --grace 1 >/dev/null; sleep 1.5; "$B/route2-kill" j7 --gen "$gen" >/dev/null
  for u in $(jq -r '.unowned[].pid' <<<"$out"); do kill "$u" 2>/dev/null || true; done
  # Test jobs are never killed.
  run --job j8 --kind test -- bash -c 'sleep 2' >/dev/null
  jqt "a test job is never killed" "$("$B/route2-kill" j8 --gen "$gen")" '.result == "refused"'
  # Progress: stdout growth counts; a repeated identical stderr line does not.
  printf '#!/bin/bash\nfor i in 1 2 3 4 5 6; do echo "same error" >&2; sleep 1; done\n' > "$REPO/err.sh"; chmod +x "$REPO/err.sh"
  run --job j9 -- ./err.sh >/dev/null; sleep 1.5
  a="$("$B/route2-wait" j9 --max 0)"; sleep 2.5; b2="$("$B/route2-wait" j9 --max 0)"
  jqt "repeated identical error line is not progress" "[$a,$b2]" '.[1].progress_source == null'
  # shellcheck disable=SC2016  # the script body is written verbatim
  printf '#!/bin/bash\nfor i in 1 2 3 4; do echo "$i"; sleep 1; done\n' > "$REPO/count.sh"; chmod +x "$REPO/count.sh"
  run --job j10 -- ./count.sh >/dev/null; sleep 1.5
  "$B/route2-wait" j10 --max 0 >/dev/null; sleep 1.2
  jqt "stdout growth is progress" "$("$B/route2-wait" j10 --max 0)" '.progress_source == "stdout"'
  # Unreadable /proc → uncertain.
  jqt "unreadable /proc → uncertain" "$(ROUTE2_PROC="$WORK/noproc" "$B/route2-wait" j10 --peek)" '.state == "uncertain"'
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T5 "verdict validation"; then
  S="$ROOT/docs/schemas/critique-schema.json"
  V="$FX/verdicts"
  v() { "$B/route2-validate" "$S" "$V/$1" --envelope "${2:-raw}" ${3:+--role "$3"}; }
  jqt "valid" "$(v valid.txt)" '.valid'
  jqt "missing key → invalid" "$(v missing-key.txt)" '.valid == false and .stage == "schema"'
  jqt "extra key → invalid" "$(v extra-key.txt)" '.valid == false and (.errors[0] | test("unexpected key"))'
  jqt "wrong enum → invalid" "$(v wrong-enum.txt)" '.valid == false and (.errors[0] | test("not in enum"))'
  jqt "wrong nested type → invalid" "$(v wrong-nested.txt)" '.valid == false and (.errors | any(test("blocking_findings\\[0\\]")))'
  jqt "prose + one object → valid" "$(v prose-then-object.txt)" '.valid'
  jqt "fenced → valid" "$(v fenced.txt)" '.valid'
  jqt "two objects → invalid" "$(v two-objects.txt)" '.valid == false and .stage == "extract"'
  jqt "object + trailing prose → invalid" "$(v trailing-prose.txt)" '.valid == false and .stage == "extract"'
  jqt "brace in prose, then one object → valid" "$(v brace-in-prose.txt)" '.valid'
  jqt "agy envelope SUCCESS" "$(v agy-success.json agy)" '.valid'
  jqt "agy CANCELED → envelope failure" "$(v agy-canceled.json agy)" '.valid == false and .stage == "envelope"'
  jqt "agy denied_actions → envelope failure" "$(v agy-denied.json agy)" '.valid == false and .stage == "envelope"'
  jqt "cursor stream-json with prose prefix → valid" "$(v cursor-stream.jsonl cursor)" '.valid'
  jqt "claude structured_output → valid" "$(v claude-structured.jsonl claude)" '.valid'
  jqt "claude read-only role with a permission denial → envelope failure" "$(v claude-denied.jsonl claude read-only)" '.valid == false and .stage == "envelope"'
  jqt "claude error result → envelope failure" "$(v claude-error.jsonl claude)" '.valid == false and .stage == "envelope"'
fi

# =============================================================================================
if group T6 "read-only fingerprint (checkout)"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  printf 'a\n' > f.txt; git add f.txt; git -c user.email=t@t -c user.name=t commit -qm f
  printf 'b\n' >> f.txt     # already dirty
  "$B/route2-fp" snapshot > "$WORK/fp0.json"
  jqt "unchanged → same" "$("$B/route2-fp" compare "$WORK/fp0.json")" '.result == "same"'
  printf 'c\n' >> f.txt     # dirty file changes again, status unchanged
  jqt "content change of an already-dirty file → changed" "$("$B/route2-fp" compare "$WORK/fp0.json")" \
    '.result == "changed" and (.diffs | index("tracked changes (git diff HEAD)") != null)'
  "$B/route2-fp" snapshot > "$WORK/fp1.json"; printf 'x' > new.txt
  jqt "new untracked file → changed" "$("$B/route2-fp" compare "$WORK/fp1.json")" '.diffs | index("untracked files") != null'
  rm -f new.txt; "$B/route2-fp" snapshot > "$WORK/fp2.json"; git add f.txt
  jqt "staging → changed" "$("$B/route2-fp" compare "$WORK/fp2.json")" '.diffs | index("staged changes") != null'
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T7 "role resolution"; then
  ALL='["opus","fable","sonnet","haiku","astra","sol","luna","terra","gemini","grok","self"]'
  roles() { "$B/route2-roles" <<<"$1"; }
  jqt "claude build → sol" "$(roles '{"builder":"opus","eligible":'"$ALL"'}')" '.critics == ["sol"] and .reviewer == "sol"'
  jqt "claude build, high stakes → astra + gemini" "$(roles '{"builder":"opus","high_stakes":true,"eligible":'"$ALL"'}')" '.critics == ["astra","gemini"]'
  jqt "openai build → opus" "$(roles '{"builder":"sol","eligible":'"$ALL"'}')" '.critics == ["opus"]'
  jqt "openai build, hs, fable budget → fable + gemini" "$(roles '{"builder":"sol","high_stakes":true,"fable_budget":true,"eligible":'"$ALL"'}')" '.critics == ["fable","gemini"]'
  jqt "openai build, hs, no fable budget → opus + gemini" "$(roles '{"builder":"sol","high_stakes":true,"eligible":'"$ALL"'}')" '.critics == ["opus","gemini"]'
  jqt "google build → sol" "$(roles '{"builder":"gemini","eligible":'"$ALL"'}')" '.critics == ["sol"]'
  jqt "xai build → sol, hs second critic claude" "$(roles '{"builder":"grok","high_stakes":true,"eligible":'"$ALL"'}')" '.critics == ["astra","opus"]'
  jqt "grok as critic is provisional" "$(roles '{"builder":"opus","eligible":["opus","grok"]}')" '.critics == ["grok"] and (.notes | any(test("provisional")))'
  jqt "cascade removes the drafter family" "$(roles '{"builder":"opus","drafter":"luna","eligible":'"$ALL"'}')" '.critics == ["gemini"]'
  jqt "cascade unsatisfiable → stop" "$(roles '{"builder":"opus","drafter":"luna","eligible":["opus","luna","sonnet"]}')" '.stop.remedy == "drop the cascade or change the drafter"'
  jqt "cascade unsatisfiable, high stakes → drop the cascade" "$(roles '{"builder":"opus","drafter":"luna","high_stakes":true,"eligible":["opus","luna","sonnet"]}')" '.stop.remedy == "drop the cascade"'
  jqt "two families, high stakes → no second critic, said" "$(roles '{"builder":"opus","high_stakes":true,"eligible":["opus","sol","astra"]}')" '.critics == ["astra"] and (.notes | any(test("no second critic")))'
  jqt "claude only: opus build → fable" "$(roles '{"builder":"opus","eligible":["opus","fable","sonnet"]}')" '.critics == ["fable"] and .degraded == "claude"'
  jqt "claude only: fable denied → sonnet" "$(roles '{"builder":"opus","eligible":["opus","sonnet"]}')" '.critics == ["sonnet"]'
  jqt "claude only: fable build → opus" "$(roles '{"builder":"fable","eligible":["opus","fable"]}')" '.critics == ["opus"]'
  jqt "openai only: sol build → astra (the exception, noted)" "$(roles '{"builder":"sol","eligible":["astra","sol","luna"]}')" '.critics == ["astra"] and (.notes | any(test("Astra critiques")))'
  jqt "openai only: astra build → sol" "$(roles '{"builder":"astra","eligible":["astra","sol"]}')" '.critics == ["sol"]'
  jqt "google only → stop" "$(roles '{"builder":"gemini","eligible":["gemini"]}')" '.stop != null'
  jqt "xai only → stop" "$(roles '{"builder":"grok","eligible":["grok"]}')" '.stop != null'
  jqt "named critic from the builder family → stop" "$(roles '{"builder":"opus","named_critics":["sonnet"],"eligible":'"$ALL"'}')" '.stop != null'
  jqt "two named critics, one family, high stakes → stop" "$(roles '{"builder":"opus","high_stakes":true,"named_critics":["sol","astra"],"eligible":'"$ALL"'}')" '.stop != null'
  jqt "named critics win over policy" "$(roles '{"builder":"opus","named_critics":["grok"],"policy_critic":"gemini","eligible":'"$ALL"'}')" '.critics == ["grok"]'
  jqt "policy critic used when legal" "$(roles '{"builder":"opus","policy_critic":"gemini","eligible":'"$ALL"'}')" '.critics == ["gemini"]'
  jqt "policy critic from the builder family is dropped" "$(roles '{"builder":"opus","policy_critic":"sonnet","eligible":'"$ALL"'}')" '.critics == ["sol"]'
  jqt "self with unknown director family → stop" "$(roles '{"builder":"self","director_family":null,"eligible":["sol"]}')" '.stop != null'
  jqt "self as a known claude director → sol" "$(roles '{"builder":"self","director_family":"claude","eligible":["self","sol"]}')" '.critics == ["sol"]'
fi

# =============================================================================================
if group T8 "lock"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  L() { "$B/route2-lock" "$@"; }
  sleep 300 & live=$!; lst="$(awk '{print $22}' "/proc/$live/stat")"
  a="$(L acquire --run r1 --token t1 --host test --pid "$live" --starttime "$lst")"
  jqt "acquire" "$a" '.result == "acquired" and .generation == 1'
  jqt "same owner → re-entrant, same generation" "$(L acquire --run r1 --token t1 --host test --pid "$live" --starttime "$lst")" '.result == "reentrant" and .generation == 1'
  out="$(L acquire --run r2 --token t2 --host test --pid $$ --starttime "$(awk '{print $22}' /proc/$$/stat)")"
  jqt "other run, live owner → held" "$out" '.result == "held"'
  jqt "resume of the same run while the owner is live → held" "$(L acquire --run r1 --token t1 --host test --resume --pid $$ --starttime x)" '.result == "held"'
  # The owner dies; two simultaneous resumes: exactly one acquires.
  kill "$live"; wait "$live" 2>/dev/null
  sleep 300 & d1=$!; sleep 300 & d2=$!
  ( L acquire --run r1 --token t1 --host test --resume --pid "$d1" --starttime "$(awk '{print $22}' "/proc/$d1/stat")" > "$WORK/res1" ) &
  r1p=$!
  ( L acquire --run r1 --token t1 --host test --resume --pid "$d2" --starttime "$(awk '{print $22}' "/proc/$d2/stat")" > "$WORK/res2" ) &
  r2p=$!
  wait "$r1p" "$r2p" 2>/dev/null
  n_acq="$(cat "$WORK/res1" "$WORK/res2" | jq -s '[.[] | select(.result == "acquired")] | length')"
  n_held="$(cat "$WORK/res1" "$WORK/res2" | jq -s '[.[] | select(.result == "held")] | length')"
  eq "two simultaneous resumes: one acquires, one held" "1 1" "$n_acq $n_held"
  g="$(L show | jq -r .generation)"
  eq "generation advanced to 2" 2 "$g"
  # A stale generation never mutates.
  out="$(L exec --gen 1 -- touch "$WORK/should-not-exist" 2>&1; echo "rc=$?")"
  if [[ ! -e "$WORK/should-not-exist" && "$out" == *"rc=4"* ]]; then ok "stale generation: exec refused, command not run"; else bad "stale generation: exec refused" "$out"; fi
  # Nested fence refused instead of deadlocking.
  out="$(L exec --gen "$g" -- "$B/route2-lock" exec --gen "$g" -- true 2>&1; echo "rc=$?")"
  if [[ "$out" == *nested*refused* ]]; then ok "nested route2-lock exec refused"; else bad "nested route2-lock exec refused" "$out"; fi
  # During a live job: bookkeeping writable, the wrapper holds no lock fd.
  "$B/route2-run" --gen "$g" --job lj --run r1 --role build -- bash -c 'sleep 6' >/dev/null; sleep 1
  w="$(jq -r .wrapper_pid .route2/jobs/lj/meta.json)"
  held=0
  for fd in "/proc/$w/fd"/*; do [[ "$(readlink "$fd" 2>/dev/null)" == *lock.flock ]] && held=1; done
  if (( held )); then bad "wrapper holds no lock fd"; else ok "wrapper holds no lock fd"; fi
  jqt "ledger write during a live job" "$(printf '{"x":1}\n' | "$B/route2-state" --gen "$g" append ledger.jsonl)" '.result == "written"'
  # A kill waiting for a protected test does not block other fenced calls.
  mkdir -p vendor/bin; printf '#!/bin/sh\nexec sleep 6\n' > vendor/bin/pest; chmod +x vendor/bin/pest
  printf '#!/bin/bash\nsh -c "vendor/bin/pest" &\nsleep 20\n' > b.sh; chmod +x b.sh
  "$B/route2-run" --gen "$g" --job kt --run r1 --role build --test-runner vendor/bin/pest -- ./b.sh >/dev/null; sleep 2
  "$B/route2-kill" kt --gen "$g" >/dev/null
  t0="$(date +%s)"; printf '{"y":1}\n' | "$B/route2-state" --gen "$g" append ledger.jsonl >/dev/null; t1="$(date +%s)"
  if (( t1 - t0 <= 3 )); then ok "fenced write not blocked by a test wait"; else bad "fenced write not blocked by a test wait" "$((t1 - t0)) s"; fi
  sleep 6; "$B/route2-kill" kt --gen "$g" --grace 1 >/dev/null; sleep 1.5; "$B/route2-kill" kt --gen "$g" >/dev/null
  # Another run vs a stale lock with a running job → blocked.
  kill "$d1" "$d2" 2>/dev/null; wait "$d1" "$d2" 2>/dev/null
  "$B/route2-run" --gen "$g" --job bj --run r1 --role build -- bash -c 'sleep 8' >/dev/null; sleep 1
  jqt "different run vs stale lock with a running job → blocked" "$(L acquire --run r9 --token t9 --host test)" '.result == "blocked"'
  sleep 8
  jqt "different run takes over once the job ended" "$(L acquire --run r9 --token t9 --host test)" '.result == "acquired"'
  # Heartbeat liveness when no host pid is known.
  REPO2="$(new_repo)"; cd "$REPO2" || exit 2
  L acquire --run h1 --token th --host test >/dev/null
  jqt "heartbeat owner is live" "$(L acquire --run h2 --token t2 --host test)" '.result == "held"'
  touch -d '2 hours ago' .route2/lock.heartbeat
  jqt "stale heartbeat → takeover" "$(L acquire --run h2 --token t2 --host test)" '.result == "acquired"'
  g2="$(L show | jq -r .generation)"
  jqt "release" "$(L release --token t2 --gen "$g2")" '.result == "released"'
  jqt "generation survives release" "$(L acquire --run h3 --token t3 --host test)" ".generation == $((g2 + 1))"
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T9 "audit and .route2 fingerprint"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  g="$("$B/route2-lock" acquire --run r --token t --host test | jq -r .generation)"
  printf 'stage: plan\n' | "$B/route2-state" --gen "$g" write CHECKPOINT.md >/dev/null
  printf '# plan\n' > .route2/PLAN.md
  "$B/route2-fp" snapshot > "$WORK/a.json"
  printf 'stage: critique\nsession: abc\n' | "$B/route2-state" --gen "$g" write CHECKPOINT.md >/dev/null
  printf '{"row":1}\n' | "$B/route2-state" --gen "$g" append ledger.jsonl >/dev/null
  jqt "innocent call: audited bookkeeping writes → same" "$("$B/route2-fp" compare "$WORK/a.json")" '.result == "same"'
  mkdir -p .route2/tmp; printf 'draft\n' > .route2/tmp/CHECKPOINT.md     # a director's draft in tmp/
  jqt "a draft named CHECKPOINT.md under tmp/ is not bookkeeping" "$("$B/route2-fp" compare "$WORK/a.json")" '.result == "same"'
  printf 'hacked\n' >> .route2/CHECKPOINT.md
  jqt "a critic edits the checkpoint → detected" "$("$B/route2-fp" compare "$WORK/a.json")" '.result == "changed"'
  out="$(printf 'stage: build\n' | "$B/route2-state" --gen "$g" write CHECKPOINT.md 2>&1; echo "rc=$?")"
  if [[ "$out" == *tampered*rc=5* ]]; then ok "tampering before a legitimate write → that write stops"; else bad "tampering before a legitimate write → that write stops" "$out"; fi
  REPO2="$(new_repo)"; cd "$REPO2" || exit 2
  g="$("$B/route2-lock" acquire --run r --token t --host test | jq -r .generation)"
  printf '# plan\n' > .route2/PLAN.md; "$B/route2-fp" snapshot > "$WORK/b.json"
  printf 'changed\n' >> .route2/PLAN.md
  jqt "protected input (.route2/PLAN.md) changed → detected" "$("$B/route2-fp" compare "$WORK/b.json")" '.diffs | index("protected .route2 inputs") != null'
  # Interruption between publish and audit append: the next verify fails closed.
  printf 'x\n' | "$B/route2-state" --gen "$g" write CHECKPOINT.md >/dev/null
  printf 'y\n' > .route2/CHECKPOINT.md     # published without its audit entry
  jqt "publish without audit → verify fails closed" "$("$B/route2-state" verify CHECKPOINT.md)" '.result == "tampered"'
  # Only an explicit adoption makes an unaudited file legitimate again.
  printf 'y\n' | "$B/route2-state" --gen "$g" write CHECKPOINT.md >/dev/null 2>&1
  jqt "after a refused write the file is still unaudited" "$("$B/route2-state" verify CHECKPOINT.md)" '.result == "tampered"'
  jqt "adopt needs a reason" "$("$B/route2-state" --gen "$g" adopt CHECKPOINT.md 2>&1 | jq -Rc '{msg: .}')" '.msg | test("reason")'
  jqt "adopt with a reason" "$("$B/route2-state" --gen "$g" adopt CHECKPOINT.md --reason "user inspected it")" '.result == "adopted"'
  jqt "adopted file verifies" "$("$B/route2-state" verify CHECKPOINT.md)" '.result == "ok"'
  jqt "the adoption is marked in the audit" "$(tail -1 .route2/audit.jsonl)" '.adopted == true and .reason == "user inspected it"'
  # Audit prefix rewritten → detected.
  "$B/route2-fp" snapshot > "$WORK/c.json"; sed -i '1s/.*/{"file":"x"}/' .route2/audit.jsonl
  jqt "audit prefix rewritten → detected" "$("$B/route2-fp" compare "$WORK/c.json")" '.diffs | index("audit.jsonl prefix") != null'
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T10 "ledger rows from job output"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  g="$("$B/route2-lock" acquire --run r --token t --host test | jq -r .generation)"
  mkdir -p .route2/jobs/j1 .route2/jobs/j2
  cp "$FX/verdicts/cursor-stream.jsonl" .route2/jobs/j1/out; printf 0 > .route2/jobs/j1/exit
  printf '{"run_id":"r","host":"codex"}' > .route2/jobs/j1/meta.json
  row="$("$B/route2-ledger" --dry-run --job j1 --stage critique --cli cursor-agent --transport cursor --family xai --model grok-4.7-medium)"
  jqt "cursor row: usage, served model, run and host from meta" "$row" \
    '.input_tokens == 1 and .output_tokens == 1 and .model_served == "Grok 4.7 256K Medium" and .run_id == "r" and .host == "codex" and .exit_code == "0"'
  printf '{"type":"thread.started","thread_id":"t1"}\n{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":3,"reasoning_output_tokens":1}}\n' > .route2/jobs/j2/out
  row="$("$B/route2-ledger" --dry-run --job j2 --stage build --cli codex --transport codex --family openai --model gpt-6.1-sol)"
  jqt "codex row: usage, session, total" "$row" '.session_id == "t1" and .input_tokens == 10 and .reasoning_tokens == 1 and .total_tokens == 13'
  jqt "append goes through route2-state" "$("$B/route2-ledger" --gen "$g" --job j2 --stage build --cli codex --transport codex --family openai --model gpt-6.1-sol)" '.result == "written"'
  jqt "ledger verifies" "$("$B/route2-state" verify ledger.jsonl)" '.result == "ok"'
  cd "$ROOT" || exit 2
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then printf '  %s\n' "${failed[@]}"; exit 1; fi
