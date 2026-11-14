#!/usr/bin/env bash
# maestro test suite — no model calls (docs: README "Tests").
#
#   tests/run.sh [T1 T2 …]      run all groups, or the named ones
#
# Needs bash ≥ 5, jq, git, util-linux; T1 needs shellcheck ($SHELLCHECK or on PATH).
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ROOT="$(dirname "$HERE")"
B="$ROOT/bin"
FX="$HERE/fixtures"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/maestro-tests.XXXXXX")"
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
_gstart=0 _gname=""
_gtime() { [[ -n "$_gname" ]] && printf '  (%s: %d s)\n' "$_gname" $((SECONDS - _gstart)); return 0; }
group() { want "$1" || return 1; _gtime; _gname="$1" _gstart=$SECONDS; printf '\n%s — %s\n' "$1" "$2"; }

new_repo() {  # a scratch git repo with one commit; prints its path
  local d; d="$(mktemp -d "$WORK/repo.XXXXXX")"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '.maestro/\n' >> "$(git -C "$d" rev-parse --absolute-git-dir)/info/exclude"   # as stage 0 step 2 does
  printf '%s\n' "$d"
}

# =============================================================================================
if group T1 "lint"; then
  SC="${SHELLCHECK:-shellcheck}"
  if command -v "$SC" >/dev/null 2>&1; then
    out="$(cd "$ROOT" && "$SC" bin/maestro-* bin/_lib.sh install.sh tests/*.sh tests/canary/*.sh tests/canary/shim/claude 2>&1)"
    eq "shellcheck clean" "" "$out"
  else
    bad "shellcheck available" "set SHELLCHECK or install shellcheck"
  fi
  for f in "$B"/maestro-* "$ROOT/install.sh" "$HERE"/*.sh; do
    [[ -f "$f" ]] || continue
    if bash -n "$f" 2>/dev/null; then ok "bash -n $(basename "$f")"; else bad "bash -n $(basename "$f")"; fi
  done
fi

# =============================================================================================
if group T2 "catalog"; then
  cmp_() { "$B/maestro-catalog" compare "$1" "$2"; }
  eq "6.1 < 6.10"  -1 "$(cmp_ 6.1 6.10)"
  eq "5.5 < 5.10"  -1 "$(cmp_ 5.5 5.10)"
  eq "[5] = [5,0]"  0 "$(cmp_ 5 5.0)"
  eq "[6,1] > [6]"  1 "$(cmp_ 6.1 6)"
  eq "[7] > [6,10]" 1 "$(cmp_ 7 6.10)"
  eq "6.9 < 6.10"  -1 "$(cmp_ 6.9 6.10)"

  # This machine's catalogs (2026-11-14: Codex 0.169.0, agy 1.5.9).
  M="$FX/catalogs/machine-2026-11-14"
  out="$(MAESTRO_STATE="$WORK/c1" "$B/maestro-catalog" refresh --fixtures "$M" --out "$WORK/c1/catalog.json")"
  jqt "machine: sol newest 6.1" "$out" '.slots.codex.sol[0] == "6.1"'
  jqt "machine: astra 6" "$out" '.slots.codex.astra == ["6"]'
  jqt "machine: gemini 4 (Hydrogen) before 3.8 (Flash)" "$out" '.slots.agy.gemini == ["4","3.8"]'
  jqt "machine: argon 4, agy opus and sonnet 5.5" "$out" '.slots.agy.argon == ["4"] and .slots.agy.opus == ["5.5"] and .slots.agy.sonnet == ["5.5"]'
  jqt "machine: only codex and agy are sources" "$out" '(.sources | keys) == ["agy","codex"] and (.slots | keys) == ["agy","codex"]'
  cat_="$WORK/c1/catalog.json"
  jqt "machine: hydrogen slugs up to xhigh" "$(cat "$cat_")" \
    '.transports.agy.slots.gemini[0].slugs == {"high":"gemini-4-hydrogen-high","xhigh":"gemini-4-hydrogen-xhigh","medium":"gemini-4-hydrogen-medium","low":"gemini-4-hydrogen-low"}'
  jqt "machine: orchestrator and gpt-oss unmatched" "$(cat "$cat_")" \
    '(.transports.agy.unmatched | index("gemini-pro-orchestrator-g1-pro") != null) and (.transports.agy.unmatched | index("gpt-oss-120b-medium") != null)'
  jqt "machine: codex identity from the cache" "$(cat "$cat_")" '.sources.codex.identity == "fixture-identity"'
  pickm() { MAESTRO_STATE="$WORK/c1" "$B/maestro-catalog" pick "$@" --catalog "$cat_"; }
  jqt "machine: pick gemini xhigh → hydrogen" "$(pickm gemini agy --effort xhigh)" '.slug == "gemini-4-hydrogen-xhigh" and .version == "4"'
  jqt "machine: argon has no xhigh" "$(pickm argon agy --effort xhigh)" '.action == "none"'
  jqt "machine: flash 3.8 by pin" "$(pickm gemini agy --pin 3.8 --effort high)" '.slug == "gemini-3.8-flash-high"'
  jqt "machine: hydrogen by exact slug" "$(pickm gemini agy --pin-slug gemini-4-hydrogen-low)" '.slug == "gemini-4-hydrogen-low"'
  jqt "machine: orchestrator cannot be pinned to gemini" "$(pickm gemini agy --pin-slug gemini-pro-orchestrator-g1-pro)" '.action == "none" and (.reason | test("not a gemini model"))'

  # Synthetic catalogs: integer generations, multi-digit components, excluded suffixes.
  S="$WORK/syn"; mkdir -p "$S"
  jq -n '{models: ([ "gpt-6.1-sol","gpt-6.10-sol","gpt-6.9-sol","gpt-7-sol","gpt-6.2-sol-preview","gpt-6-astra","gpt-reserve" ]
                    | map({slug: ., visibility: "list", supported_reasoning_levels: [{effort: "low"},{effort: "medium"}]}))}' > "$S/codex-models.json"
  printf 'Fetching available models...\ngemini-3.8-flash-high\tG\ngemini-4-flash-high\tG4\ngemini-4-hydrogen-high\tH4\ngemini-4-flash-low\tG4l\ngemini-4-flash-preview-high\tP\ngemini-4-argon-low\tA\ngemini-4-argon-high\tA\ngemini-4-argon-preview-high\tAP\nclaude-opus-5-10-high\tO\nclaude-opus-5-5-high\tO\n' > "$S/agy-models.txt"
  out="$(MAESTRO_STATE="$WORK/c2" "$B/maestro-catalog" refresh --fixtures "$S" --out "$WORK/c2/catalog.json")"
  jqt "synthetic: sol order 7, 6.10, 6.9, 6.1" "$out" '.slots.codex.sol == ["7","6.10","6.9","6.1"]'
  jqt "synthetic: gemini 4 before 3.8" "$out" '.slots.agy.gemini == ["4","3.8"]'
  jqt "synthetic: argon is its own line, not gemini" "$out" '.slots.agy.argon == ["4"]'
  jqt "synthetic: at one version Hydrogen wins and Flash slugs of that version are not mixed in" "$(cat "$WORK/c2/catalog.json")" \
    '.transports.agy.slots.gemini[0].slugs == {"high":"gemini-4-hydrogen-high"}'
  jqt "synthetic: opus 5.10 before 5.5" "$out" '.slots.agy.opus == ["5.10","5.5"]'
  jqt "synthetic: preview and dated slugs unmatched" "$(cat "$WORK/c2/catalog.json")" \
    '(.transports.codex.unmatched | index("gpt-6.2-sol-preview") != null) and (.transports.agy.unmatched | index("gemini-4-flash-preview-high") != null) and (.transports.agy.unmatched | index("gemini-4-argon-preview-high") != null)'
  # Bundled fallback: no live catalog and no cache.
  Bd="$WORK/bundled"; mkdir -p "$Bd"
  jqt "no live catalog, no cache, no bundled → acquisition failure" \
    "$(MAESTRO_STATE="$WORK/c5" "$B/maestro-catalog" refresh --fixtures "$Bd" --out "$WORK/c5/catalog.json")" '.sources.codex.error != null'
  jq -n '{models: [{slug: "gpt-6-sol", visibility: "list"}]}' > "$Bd/codex-bundled.json"
  jqt "bundled fallback → mode bundled (degraded discovery)" \
    "$(MAESTRO_STATE="$WORK/c6" "$B/maestro-catalog" refresh --fixtures "$Bd" --out "$WORK/c6/catalog.json")" '.sources.codex.mode == "bundled" and .slots.codex.sol == ["6"]'

  # Acquisition failures vs empty lines.
  E="$WORK/e"; mkdir -p "$E"; printf 'Fetching available models...\n' > "$E/agy-models.txt"; printf '{not json' > "$E/codex-models.json"
  out="$(MAESTRO_STATE="$WORK/c3" "$B/maestro-catalog" refresh --fixtures "$E" --out "$WORK/c3/catalog.json")"
  jqt "banner-only agy = acquisition failure" "$out" '.sources.agy.error != null and .slots.agy == null'
  jqt "malformed codex = acquisition failure" "$out" '.sources.codex.error != null and .slots.codex == null'
  # Stale cache fallback.
  C="$WORK/cache"; mkdir -p "$C"
  jq -n '{identity: "x", client_version: "0.0.1", fetched_at: "2020-01-01T00:00:00Z",
          models: [{slug: "gpt-6.1-sol", visibility: "list"}]}' > "$C/codex-cache.json"
  out="$(MAESTRO_STATE="$WORK/c4" "$B/maestro-catalog" refresh --fixtures "$C" --out "$WORK/c4/catalog.json")"
  jqt "stale cache: mode cache, stale true" "$out" '.sources.codex.mode == "cache" and .sources.codex.stale == true'

  # Pick: walk-down, pins, scoped denials.
  P="$WORK/c2"
  pick() { MAESTRO_STATE="$P" "$B/maestro-catalog" pick "$@" --catalog "$P/catalog.json"; }
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
  jqt "pick: exact pin of an excluded slug (preview)" "$(pick sol codex --pin-slug gpt-6.2-sol-preview)" \
    '.slug == "gpt-6.2-sol-preview" and .excluded == true and .identity.tag == "gpt-6.2-sol-preview"'
  jqt "pick: exact pin of a slug the catalog does not list → none" "$(pick sol codex --pin-slug gpt-9-sol-preview)" '.action == "none"'
  jq '.transports.agy.unmatched += ["kimi-k3-high"]' "$P/catalog.json" > "$P/ck.json"
  jqt "pick: an excluded slug of another model cannot be pinned to gemini" \
    "$(MAESTRO_STATE="$P" "$B/maestro-catalog" pick gemini agy --pin-slug kimi-k3-high --catalog "$P/ck.json")" '.action == "none" and (.reason | test("not a gemini model"))'
  jqt "pick: effort with no slug → none" "$(pick gemini agy --effort max)" '.action == "none"'
  jqt "pick: argon high on agy" "$(pick argon agy --effort high)" '.action == "probe" and .slug == "gemini-4-argon-high"'
  jqt "pick: an argon preview can be pinned to argon" "$(pick argon agy --pin-slug gemini-4-argon-preview-high)" '.excluded == true and .slug == "gemini-4-argon-preview-high"'
  jqt "pick: an argon slug cannot be pinned to gemini" "$(pick gemini agy --pin-slug gemini-4-argon-preview-high)" '.action == "none" and (.reason | test("not a gemini model"))'
  jqt "pick: line without candidates → none + previous" \
    "$(jq '.previous = {luna: {codex: "6"}}' "$P/catalog.json" > "$P/cp.json"; MAESTRO_STATE="$P" "$B/maestro-catalog" pick luna codex --catalog "$P/cp.json")" \
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
  host() { env -i PATH="$PATH" HOME="$HOME" MAESTRO_PROC="$1" MAESTRO_HOST_START_PID="$2" "${@:3}" "$B/maestro-host"; }
  CC=/home/u/.local/share/claude/versions/2.1.325
  CX=/home/u/.codex/packages/standalone/releases/0.169.0/bin/codex
  R="$WORK/proc1"; mkproc "$R" 100 1 "$CC" claude; mkproc "$R" 200 100 /usr/bin/bash bash
  jqt "claude-code interactive" "$(host "$R" 200 CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s1)" \
    '.host == "claude-code" and .interactive == true and .session_key == "s1" and .director_family == "claude"'
  R="$WORK/proc2"; mkproc "$R" 100 1 "$CC" claude; mkproc "$R" 300 100 "$CX" codex exec -m x; mkproc "$R" 400 300 /usr/bin/bash bash
  jqt "codex directing inside claude code → unsupported" \
    "$(host "$R" 400 CLAUDECODE=1 CODEX_THREAD_ID=t1)" '.host == "unsupported" and .director_family == null and (.evidence | any(test("codex")))'
  R="$WORK/proc4"; mkproc "$R" 300 1 "$CX" codex; mkproc "$R" 350 300 "$CC" claude -p hi; mkproc "$R" 400 350 /usr/bin/bash bash
  jqt "claude -p started from a codex shell → claude-code, headless" "$(host "$R" 400 CODEX_THREAD_ID=t1 CLAUDECODE=1)" '.host == "claude-code" and .interactive == false'
  jqt "nearest claude without CLAUDECODE → unknown" "$(host "$R" 400 CODEX_THREAD_ID=t1)" '.host == "unknown"'
  jqt "markers only, CLAUDECODE alone → claude-code" "$(host "$WORK/none" 400 CLAUDECODE=1)" '.host == "claude-code" and .interactive == null and (.evidence | any(test("markers-only")))'
  jqt "markers only, another CLI's marker too → unknown" "$(host "$WORK/none" 400 CODEX_THREAD_ID=t1 CLAUDECODE=1)" '.host == "unknown"'
  jqt "markers only, a codex marker alone → unknown" "$(host "$WORK/none" 400 CODEX_THREAD_ID=t1)" '.host == "unknown"'
  jqt "zero signals → unknown" "$(host "$WORK/none" 400)" '.host == "unknown"'
  # A sandbox can hide the CLI that really runs this shell; the nearest visible one is then an outer one.
  R="$WORK/proc6"; mkproc "$R" 100 1 "$CC" claude daemon run; mkproc "$R" 200 100 /usr/bin/bash bash
  jqt "hidden codex under a visible claude: markers of both → unknown" \
    "$(host "$R" 200 CLAUDECODE=1 CODEX_THREAD_ID=t1)" '.host == "unknown" and (.evidence | any(test("incomplete")))'
  R="$WORK/proc5"; mkproc "$R" 500 1 /home/u/.local/bin/agy agy; mkproc "$R" 510 500 /usr/bin/bash bash
  jqt "agy directing → unsupported" "$(host "$R" 510 ANTIGRAVITY_AGENT=1 ANTIGRAVITY_CONVERSATION_ID=s)" '.host == "unsupported"'
  # Identity of a pid: start time, gone, or unreadable — never unreadable read as gone.
  ID="$WORK/procid"; mkdir -p "$ID/900"; printf '900 (x) S 1 900 900 0 -1 0 0 0 0 0 0 0 0 20 0 1 0 0 4242 0 0\n' > "$ID/900/stat"
  mkdir -p "$ID/901"; printf 'x\n' > "$ID/901/stat"; chmod 000 "$ID/901/stat"
  eq "pid identity: readable → start time" 4242 "$(MAESTRO_PROC="$ID" bash -c '. "$1/_lib.sh"; mae_pid_identity 900' _ "$B")"
  eq "pid identity: entry present, stat unreadable → unreadable" unreadable "$(MAESTRO_PROC="$ID" bash -c '. "$1/_lib.sh"; mae_pid_identity 901' _ "$B")"
  eq "pid identity: no entry → gone" gone "$(MAESTRO_PROC="$ID" bash -c '. "$1/_lib.sh"; mae_pid_identity 902' _ "$B")"
  chmod 600 "$ID/901/stat"
fi

# =============================================================================================
if group T4 "jobs"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  L() { "$B/maestro-lock" "$@"; }
  gen="$(L acquire --run r --token t --host test | jq -r .fence)"
  run() { "$B/maestro-run" --gen "$gen" --run r --role build "$@"; }
  st() { "$B/maestro-wait" "$1" --peek; }
  run --job j0 -- bash -c 'exit 0' >/dev/null; sleep 1.5
  jqt "exit 0 → exited 0" "$("$B/maestro-wait" j0 --max 10)" '.state == "exited" and .code == "0"'
  run --job j1 -- bash -c 'exit 3' >/dev/null
  jqt "non-zero → exited 3" "$("$B/maestro-wait" j1 --max 10)" '.state == "exited" and .code == "3"'
  run --job j2 -- no-such-command-xyz >/dev/null
  jqt "launch failure" "$(st j2)" '.state == "exited" and .code == "launch-failed"'
  out="$(run --job j1 -- true 2>&1)"; eq "duplicate job id refused" 1 "$(grep -c 'never reused' <<<"$out")"
  printf '#!/bin/bash\n(sleep 90 &)\nexit 0\n' > "$REPO/linger.sh"; chmod +x "$REPO/linger.sh"
  run --job j3 -- ./linger.sh >/dev/null; sleep 3
  jqt "exit 0 with a surviving descendant → lingering" "$(st j3)" '.state == "lingering" and (.live_members | length) == 1'
  run --job j4 -- bash -c 'sleep 30' >/dev/null; sleep 1.5
  jqt "running" "$(st j4)" '.state == "running"'
  pid4="$(jq -r .pid .maestro/jobs/j4/meta.json)"; kill -9 "$pid4"; sleep 2.5
  jqt "leader killed by a signal → exited signal:9" "$(st j4)" '.state == "exited" and .code == "signal:9"'
  # Orphaned: the wrapper and the leader die, a member survives.
  printf '#!/bin/bash\nsleep 25 &\nsleep 25\n' > "$REPO/orph.sh"; chmod +x "$REPO/orph.sh"
  run --job j5 -- ./orph.sh >/dev/null; sleep 2.5
  w5="$(jq -r .wrapper_pid .maestro/jobs/j5/meta.json)"; p5="$(jq -r .pid .maestro/jobs/j5/meta.json)"
  kill -9 "$w5" "$p5"; sleep 1
  jqt "leader and wrapper gone, member alive → orphaned" "$(st j5)" '.state == "orphaned"'
  # Kill: lingering member is terminated; result done.
  r1="$("$B/maestro-kill" j3 --gen "$gen" --grace 1)"; sleep 1.5
  r2="$("$B/maestro-kill" j3 --gen "$gen" --grace 1)"
  jqt "kill a lingering member: signalled, then done" "[$r1,$r2]" '.[0].result == "signalled" and .[1].result == "done"'
  "$B/maestro-kill" j5 --gen "$gen" --grace 1 >/dev/null; sleep 1.5; "$B/maestro-kill" j5 --gen "$gen" --grace 1 >/dev/null
  jqt "orphaned member killed → done/lost" "$("$B/maestro-kill" j5 --gen "$gen")" '.result == "done"'
  # Tests are never signalled; protected subtrees wait.
  mkdir -p "$REPO/vendor/bin"; printf '#!/bin/sh\nexec sleep 8\n' > "$REPO/vendor/bin/pest"; chmod +x "$REPO/vendor/bin/pest"
  printf '#!/bin/bash\nsh -c "vendor/bin/pest --parallel" &\nsleep 30\n' > "$REPO/b.sh"; chmod +x "$REPO/b.sh"
  run --job j6 --test-runner vendor/bin/pest -- ./b.sh >/dev/null; sleep 2.5
  jqt "test subtree protected → waiting-tests" "$("$B/maestro-kill" j6 --gen "$gen")" '.result == "waiting-tests"'
  sleep 7
  jqt "after the test ends the rest is signalled" "$("$B/maestro-kill" j6 --gen "$gen" --grace 1)" '.result == "signalled"'
  sleep 1.5; "$B/maestro-kill" j6 --gen "$gen" >/dev/null
  # An unrelated process with the same cwd and command line is not a member, and is reported.
  printf '#!/bin/bash\nsleep 20\n' > "$REPO/same.sh"; chmod +x "$REPO/same.sh"
  run --job j7 -- ./same.sh >/dev/null
  (cd "$REPO" && setsid ./same.sh >/dev/null 2>&1 &) ; sleep 2.5
  out="$(st j7)"
  jqt "unrelated same-command process: not a member, reported unowned" "$out" \
    '(.unowned | length) >= 1 and ([.unowned[].pid] - [.live_members[].pid] | length) == (.unowned | length)'
  "$B/maestro-kill" j7 --gen "$gen" --grace 1 >/dev/null; sleep 1.5; "$B/maestro-kill" j7 --gen "$gen" >/dev/null
  for u in $(jq -r '.unowned[].pid' <<<"$out"); do kill "$u" 2>/dev/null || true; done
  # Test jobs are never killed.
  run --job j8 --kind test -- bash -c 'sleep 2' >/dev/null
  jqt "a test job is never killed" "$("$B/maestro-kill" j8 --gen "$gen")" '.result == "refused"'
  # Progress: stdout growth counts; a repeated identical stderr line does not.
  printf '#!/bin/bash\nfor i in 1 2 3 4 5 6; do echo "same error" >&2; sleep 1; done\n' > "$REPO/err.sh"; chmod +x "$REPO/err.sh"
  run --job j9 -- ./err.sh >/dev/null; sleep 1.5
  a="$("$B/maestro-wait" j9 --max 0)"; sleep 2.5; b2="$("$B/maestro-wait" j9 --max 0)"
  jqt "repeated identical error line is not progress" "[$a,$b2]" '.[1].progress_source == null'
  # shellcheck disable=SC2016  # the script body is written verbatim
  printf '#!/bin/bash\nfor i in 1 2 3 4 5 6 7 8 9 10; do echo "$i"; sleep 1; done\n' > "$REPO/count.sh"; chmod +x "$REPO/count.sh"
  run --job j10 -- ./count.sh >/dev/null; sleep 1.5
  "$B/maestro-wait" j10 --max 0 >/dev/null; sleep 1.2
  jqt "stdout growth is progress" "$("$B/maestro-wait" j10 --max 0)" '.progress_source == "stdout"'
  # PID reuse: a recorded pid now held by an unrelated process (start time differs) is not a member.
  sleep 30 & other=$!
  run --job j11 -- sleep 3 >/dev/null; sleep 1.5
  printf '{"pid":%s,"starttime":"1","ppid":1,"pgid":1,"argv":"sleep 30","cwd":"/","exe":"/usr/bin/sleep"}\n' "$other" >> .maestro/jobs/j11/members.jsonl
  jqt "a reused pid (start time differs) is not a member" "$(st j11)" "[.live_members[].pid] | index($other) == null"
  sleep 2.5
  jqt "… and does not keep the job alive" "$(st j11)" '.state == "exited"'
  kill "$other" 2>/dev/null; wait "$other" 2>/dev/null
  # A member that setsid's after it was recorded stays a member.
  printf '#!/bin/bash\n(sleep 2; exec setsid sleep 25) &\nexit 0\n' > "$REPO/esc.sh"; chmod +x "$REPO/esc.sh"
  run --job j12 -- ./esc.sh >/dev/null; sleep 4
  jqt "a member that setsid's later is still a member (lingering)" "$(st j12)" '.state == "lingering" and (.live_members | length) >= 1'
  "$B/maestro-kill" j12 --gen "$gen" --grace 1 >/dev/null; sleep 1.5; "$B/maestro-kill" j12 --gen "$gen" >/dev/null
  # A member that detaches and exec's a different program stays a member.
  printf '#!/bin/bash\n(sleep 2; exec tail -f /dev/null) &\nexit 0\n' > "$REPO/dex.sh"; chmod +x "$REPO/dex.sh"
  run --job j13 -- ./dex.sh >/dev/null; sleep 4
  o13="$(st j13)"; m13="$(jq -r '.live_members[0].pid // empty' <<<"$o13")"
  if [[ "$(jq -r .state <<<"$o13")" == lingering && -n "$m13" && "$(readlink "/proc/$m13/exe")" == *tail ]]; then
    ok "detach + exec to another program: still a member (same pid and start time, now tail)"
  else bad "detach + exec to another program: still a member" "$o13"; fi
  "$B/maestro-kill" j13 --gen "$gen" --grace 1 >/dev/null; sleep 1.5; "$B/maestro-kill" j13 --gen "$gen" >/dev/null
  # The leader exec's into the test runner, which starts differently named workers: all protected.
  printf '#!/bin/sh\nsh -c "sleep 15" &\nsh -c "sleep 15" &\nwait\n' > "$REPO/vendor/bin/pest"; chmod +x "$REPO/vendor/bin/pest"
  printf '#!/bin/bash\nsleep 1\nexec vendor/bin/pest --parallel\n' > "$REPO/launch.sh"; chmod +x "$REPO/launch.sh"
  run --job j14 --test-runner vendor/bin/pest -- ./launch.sh >/dev/null; sleep 3
  jqt "leader exec'd into the test runner: waiting-tests, nothing signalled" "$("$B/maestro-kill" j14 --gen "$gen")" \
    '.result == "waiting-tests" and (.protected | length) >= 3'
  for _ in $(seq 30); do [[ "$(st j14 | jq -r .state)" == running ]] || break; sleep 1; done
  jqt "after the tests end the job is done" "$("$B/maestro-kill" j14 --gen "$gen")" '.result == "done"'
  # Recorder-level pid reuse: a recorded pid now reused (different start time) is not used as a
  # seed, so neither it nor its children join the job.
  FP="$WORK/fakeproc"; mkdir -p "$FP"
  fake() { mkdir -p "$FP/$1"; printf '%s (x) S %s %s %s 0 -1 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 0\n' "$1" "$2" "$3" "$3" "$4" > "$FP/$1/stat"; printf 'x\0' > "$FP/$1/cmdline"; }
  fake 500 1 500 1000; fake 600 1 600 2222; fake 601 600 600 2300
  mkdir -p "$WORK/rj"; printf '{"pid":600,"starttime":"1111","ppid":500,"pgid":500}\n' > "$WORK/rj/members.jsonl"
  MAESTRO_PROC="$FP" "$B/maestro-run" __record_once "$WORK/rj" 500
  if grep -q '"pid":601' "$WORK/rj/members.jsonl" || [[ "$(grep -c '"pid":600' "$WORK/rj/members.jsonl")" != 1 ]]; then
    bad "recorder: a reused pid seeds nothing" "$(cat "$WORK/rj/members.jsonl")"
  else ok "recorder: a reused pid seeds nothing"; fi
  fake 700 500 500 3000
  MAESTRO_PROC="$FP" "$B/maestro-run" __record_once "$WORK/rj" 500
  if grep -q '"pid":700' "$WORK/rj/members.jsonl"; then ok "recorder: a real child of the root is recorded"; else bad "recorder: a real child of the root is recorded"; fi
  # Detach + exec OUT of the process group after being recorded: still a member.
  printf '#!/bin/bash\n(sleep 2; exec setsid tail -f /dev/null) &\nexit 0\n' > "$REPO/dexg.sh"; chmod +x "$REPO/dexg.sh"
  run --job j15 -- ./dexg.sh >/dev/null; sleep 4
  o15="$(st j15)"; m15="$(jq -r '.live_members[0].pid // empty' <<<"$o15")"
  if [[ "$(jq -r .state <<<"$o15")" == lingering && -n "$m15" && "$(readlink "/proc/$m15/exe")" == *tail \
        && "$(awk '{print $5}' "/proc/$m15/stat")" != "$(jq -r .pgid .maestro/jobs/j15/meta.json)" ]]; then
    ok "detach + exec out of the process group: still a member"
  else bad "detach + exec out of the process group: still a member" "$o15"; fi
  "$B/maestro-kill" j15 --gen "$gen" --grace 1 >/dev/null; sleep 1.5; "$B/maestro-kill" j15 --gen "$gen" >/dev/null
  # Recovered members (in the job's process group but missing from members.jsonl).
  printf '#!/bin/bash\nsleep 60 &\nwait\n' > "$REPO/rec.sh"; chmod +x "$REPO/rec.sh"
  run --job j16 -- ./rec.sh >/dev/null; sleep 3
  grep -v '"argv":"sleep 60"' .maestro/jobs/j16/members.jsonl > "$WORK/m16" || true; cp "$WORK/m16" .maestro/jobs/j16/members.jsonl
  jqt "a recovered member whose current ancestry reaches a recorded member is classifiable" \
    "$("$B/maestro-kill" j16 --gen "$gen" --grace 1)" '.result == "signalled"'
  sleep 1.5; "$B/maestro-kill" j16 --gen "$gen" >/dev/null
  printf '#!/bin/bash\n(sleep 60 &)\nsleep 60\n' > "$REPO/rec2.sh"; chmod +x "$REPO/rec2.sh"
  run --job j17 -- ./rec2.sh >/dev/null; sleep 3
  grep -v '"argv":"sleep 60","cwd' .maestro/jobs/j17/members.jsonl > "$WORK/m17" || true
  # keep the leader, drop the re-parented sleep's record
  jq -c --argjson l "$(jq .pid .maestro/jobs/j17/meta.json)" 'select(.pid == $l or (.argv | test("sleep 60") | not))' .maestro/jobs/j17/members.jsonl > "$WORK/m17"
  cp "$WORK/m17" .maestro/jobs/j17/members.jsonl
  jqt "a recovered member whose ancestry is unknown (re-parented to init) blocks" \
    "$("$B/maestro-kill" j17 --gen "$gen" --grace 1)" '.result == "blocked"'
  for m in $(jq -r '.live_members[].pid' <<<"$(st j17)"); do kill "$m" 2>/dev/null; done
  pkill -P "$(jq -r .wrapper_pid .maestro/jobs/j17/meta.json)" 2>/dev/null; kill "$(jq -r .pid .maestro/jobs/j17/meta.json)" 2>/dev/null
  for p in $(pgrep -x sleep); do [[ "$(readlink "/proc/$p/cwd")" == "$REPO" ]] && kill "$p" 2>/dev/null; done
  # Uncertainty propagates: a job whose live set cannot be read is never "done".
  jqt "maestro-kill on an uncertain job → blocked, nothing signalled" \
    "$(MAESTRO_PROC="$WORK/noproc" "$B/maestro-kill" j10 --gen "$gen")" '.result == "blocked"'
  # Unreadable /proc → uncertain.
  jqt "unreadable /proc → uncertain" "$(MAESTRO_PROC="$WORK/noproc" "$B/maestro-wait" j10 --peek)" '.state == "uncertain"'
  # A live leader does not outrank an unreadable member. Fake /proc with pids above pid_max (no
  # real process can be signalled): leader L alive, recorded member L+1 alive, and a recovered
  # process L+2 in the job's group whose stat was readable during the group scan but is not when
  # its identity is read (the entry L+3 carries L+2's stat line — the scan takes the pid from the
  # line itself — while L+2/stat is unreadable).
  UP="$WORK/unrproc"; L0=4194400
  ufake() { mkdir -p "$UP/$1"; printf '%s (x) S %s %s %s 0 -1 0 0 0 0 0 0 0 0 20 0 1 0 0 %s 0 0\n' "$2" "$3" "$4" "$4" "$5" > "$UP/$1/stat"; printf 'x\0' > "$UP/$1/cmdline"; }
  ufake 1 1 0 1 1; ufake "$L0" "$L0" 1 "$L0" 5000; ufake "$((L0 + 1))" "$((L0 + 1))" "$L0" "$L0" 5001
  ufake "$((L0 + 2))" "$((L0 + 2))" "$((L0 + 1))" "$L0" 5002; chmod 000 "$UP/$((L0 + 2))/stat"
  ufake "$((L0 + 3))" "$((L0 + 2))" "$((L0 + 1))" "$L0" 5002
  mkdir -p .maestro/jobs/j18
  jq -cn --argjson l "$L0" --arg cwd "$REPO" --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{job_id: "j18", kind: "build", pid: $l, pid_starttime: "5000",
     wrapper_pid: ($l - 1), pgid: $l, cwd: $cwd, cmd: ["./x.sh"], started_at: $t}' > .maestro/jobs/j18/meta.json
  # The leader's record names the (gone) wrapper as its parent, so the recorded member is
  # classifiable: without the uncertainty the kill would proceed — the test tells the two apart.
  { printf '{"pid":%s,"starttime":"5000","ppid":%s,"pgid":%s,"argv":"./x.sh","cwd":"%s","exe":"/usr/bin/bash"}\n' "$L0" "$((L0 - 1))" "$L0" "$REPO"
    printf '{"pid":%s,"starttime":"5001","ppid":%s,"pgid":%s,"argv":"x","cwd":"%s","exe":"/usr/bin/x"}\n' "$((L0 + 1))" "$L0" "$L0" "$REPO"; } > .maestro/jobs/j18/members.jsonl
  jqt "live leader + unreadable recovered member → uncertain, leader_alive" \
    "$(MAESTRO_PROC="$UP" "$B/maestro-wait" j18 --peek)" '.state == "uncertain" and .leader_alive == true'
  t0="$(date +%s)"; o18="$(MAESTRO_PROC="$UP" "$B/maestro-wait" j18 --max 3)"
  jqt "… maestro-wait keeps blocking while the leader lives" "$o18" '.state == "uncertain"'
  if (( $(date +%s) - t0 >= 3 )); then ok "… for the whole --max"; else bad "… for the whole --max" "returned after $(( $(date +%s) - t0 )) s"; fi
  jqt "… maestro-kill → blocked, nothing signalled" \
    "$(MAESTRO_PROC="$UP" "$B/maestro-kill" j18 --gen "$gen" --grace 1)" '.result == "blocked"'
  if [[ -e .maestro/jobs/j18/kill.state ]]; then bad "… kill.state unchanged" "$(cat .maestro/jobs/j18/kill.state)"; else ok "… kill.state unchanged"; fi
  # The fenced step itself (as if the outer look had passed) also refuses on the same snapshot.
  jqt "… the fenced step refuses too" \
    "$(MAESTRO_PROC="$UP" "$B/maestro-lock" exec --gen "$gen" -- "$B/maestro-kill" __step "$REPO/.maestro/jobs/j18" TERM)" '.result == "blocked"'
  if [[ -e .maestro/jobs/j18/kill.state ]]; then bad "… and leaves kill.state alone" "$(cat .maestro/jobs/j18/kill.state)"; else ok "… and leaves kill.state alone"; fi
  chmod 600 "$UP/$((L0 + 2))/stat"
  jqt "once readable: running (the recovered process joins the live set)" \
    "$(MAESTRO_PROC="$UP" "$B/maestro-wait" j18 --peek)" '.state == "running" and ([.live_members[].pid] | index('"$((L0 + 2))"') != null)'
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T5 "verdict validation"; then
  S="$ROOT/docs/schemas/critique-schema.json"
  V="$FX/verdicts"
  v() { "$B/maestro-validate" "$S" "$V/$1" --envelope "${2:-raw}" ${3:+--role "$3"}; }
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
  jq '. + {finished_reason: "print_timeout"}' "$FX/verdicts/agy-success.json" > "$WORK/agy-timeout.json"
  jqt "agy finished_reason print_timeout → envelope failure" "$("$B/maestro-validate" "$ROOT/docs/schemas/critique-schema.json" "$WORK/agy-timeout.json" --envelope agy)" '.valid == false and (.errors[0] | test("print_timeout"))'
  jqt "agy structured_output only (empty response) → valid" "$(v agy-structured-only.json agy)" '.valid'
  jqt "agy structured_output wins over a response with trailing prose" "$(v agy-structured-prose.json agy)" '.valid'
  jqt "agy structured_output null → falls back to response" "$(v agy-structured-null.json agy)" '.valid'
  jqt "agy structured_output with denied_actions → envelope failure" "$(v agy-structured-denied.json agy)" '.valid == false and .stage == "envelope"'
  jqt "agy structured_output with status CANCELED → envelope failure" "$(v agy-structured-canceled.json agy)" '.valid == false and .stage == "envelope"'
  jqt "claude structured_output → valid" "$(v claude-structured.jsonl claude)" '.valid'
  jqt "claude read-only role with a permission denial → envelope failure" "$(v claude-denied.jsonl claude read-only)" '.valid == false and .stage == "envelope"'
  jqt "claude error result → envelope failure" "$(v claude-error.jsonl claude)" '.valid == false and .stage == "envelope"'
  jqt "api transport (Agent SDK) structured_output → valid" "$(v sdk-structured.jsonl claude read-only)" '.valid'
  jqt "api budget spent → envelope failure" "$(v sdk-budget.jsonl claude)" '.valid == false and .stage == "envelope"'
  # severity rubric and delta rounds: trigger, prior_findings, --decide (docs/briefs.md, "Plan critique")
  AS="$ROOT/docs/schemas/arbiter-schema.json"
  FND='{"section":"2","claim_in_plan":"c","problem":"p","trigger":"an empty CSV file","evidence":"e","fix":"f"}'
  crit() { jq -cn --arg v "$1" --argjson b "$2" --argjson m "$3" --argjson p "$4" \
    '{verdict: $v, blocking_findings: $b, major_findings: $m, prior_findings: $p, non_blocking_notes: [], assumptions: []}'; }
  dc() { printf '%s' "$1" > "$WORK/decide.json"; shift; "$B/maestro-validate" "$S" "$WORK/decide.json" "$@"; }
  da() { printf '%s' "$1" > "$WORK/decide.json"; shift; "$B/maestro-validate" "$AS" "$WORK/decide.json" "$@"; }
  jqt "every schema: strings only, every property required, additionalProperties false" \
    "$(jq -s '[ .[] | .. | objects | select(.type == "object")
               | (.additionalProperties == false and ((.properties | keys) == (.required | sort))) ] | all' "$S" "$AS")" '. == true'
  jqt "critique and arbiter schemas declare no integer and no nullable field" \
    "$(jq -s '[ .[] | .. | objects | .type? | select(. != null) ] | all(type == "string" and IN("object", "array", "string"))' "$S" "$AS")" '. == true'
  jqt "missing prior_findings → invalid" "$(dc '{"verdict":"approve","blocking_findings":[],"major_findings":[],"non_blocking_notes":[],"assumptions":[]}')" \
    '.valid == false and (.errors | any(test("missing required prior_findings")))'
  jqt "a finding without trigger → invalid" "$(dc "$(crit revise '[]' "[$(jq -c 'del(.trigger)' <<<"$FND")]" '[]')")" \
    '.valid == false and .stage == "schema" and (.errors | any(test("major_findings\\[0\\]: missing required trigger")))'
  jqt "a blocking finding without trigger → invalid" "$(dc "$(crit revise "[$(jq -c 'del(.trigger)' <<<"$FND")]" '[]' '[]')")" \
    '.valid == false and (.errors | any(test("blocking_findings\\[0\\]: missing required trigger")))'
  jqt "a finding with trigger → valid; no decision without --decide" "$(dc "$(crit revise '[]' "[$FND]" '[]')")" '.valid and (has("decision") | not)'
  jqt "prior_findings status outside the enum → invalid" "$(dc "$(crit revise '[]' '[]' '[{"id":"r1-m1","status":"partly","note":"n"}]')")" \
    '.valid == false and (.errors | any(test("prior_findings\\[0\\].status.*not in enum")))'
  jqt "decide critique: approve, nothing open → approved" "$(dc "$(crit approve '[]' '[]' '[]')" --decide critique --ids "")" \
    '.valid and .stage == "schema" and .errors == [] and .decision == {approved: true, reasons: []}'
  jqt "decide critique: approve, every prior resolved → approved" \
    "$(dc "$(crit approve '[]' '[]' '[{"id":"r1-m1","status":"resolved","note":"n"},{"id":"r1-b1","status":"resolved","note":"n"}]')" --decide critique --ids r1-m1,r1-b1)" '.valid and .decision.approved'
  out="$(dc "$(crit revise '[]' "[$FND]" '[{"id":"r1-m1","status":"not_resolved","note":"n"}]')" --decide critique --ids r1-m1)"; rc=$?
  jqt "decide critique: revise → valid, not approved, reasons named" "$out" \
    '.valid and .decision.approved == false and .decision.reasons == ["verdict revise", "1 major finding", "prior finding r1-m1 not resolved"]'
  eq "decide critique: a valid revise exits 0" 0 "$rc"
  jqt "decide critique: reject → not approved" "$(dc "$(crit reject "[$FND]" '[]' '[]')" --decide critique)" \
    '.valid and .decision.approved == false and (.decision.reasons | index("verdict reject") != null)'
  out="$(dc "$(crit approve '[]' "[$FND]" '[]')" --decide critique)"; rc=$?
  jqt "decide critique: approve that lists a finding → invalid, with the reason" "$out" \
    '.valid == false and .stage == "decide" and (.errors[0] | test("approve with .* 1 major finding listed")) and .decision.approved == false and .verdict.verdict == "approve"'
  eq "decide critique: an inconsistent approve exits 1" 1 "$rc"
  jqt "decide critique: approve with a not_resolved prior finding → invalid" \
    "$(dc "$(crit approve '[]' '[]' '[{"id":"r1-m1","status":"not_resolved","note":"n"}]')" --decide critique --ids r1-m1)" \
    '.valid == false and .stage == "decide" and (.errors[0] | test("r1-m1 not resolved")) and .decision.approved == false'
  jqt "decide critique: round 2 answer that skips a sent id → invalid (no vacuous approval)" \
    "$(dc "$(crit approve '[]' '[]' '[]')" --decide critique --ids r1-m1)" '.valid == false and (.errors[0] | test("r1-m1 sent but not answered")) and .decision.approved == false'
  jqt "decide critique: an id that was not sent → invalid" \
    "$(dc "$(crit approve '[]' '[]' '[{"id":"r9-m9","status":"resolved","note":"n"}]')" --decide critique --ids "")" '.valid == false and (.errors[0] | test("r9-m9 was not sent"))'
  jqt "decide critique: an id listed twice → invalid" \
    "$(dc "$(crit revise '[]' '[]' '[{"id":"r1-m1","status":"resolved","note":"n"},{"id":"r1-m1","status":"not_resolved","note":"n"}]')" --decide critique)" '.valid == false and (.errors[0] | test("listed twice"))'
  jqt "decide critique: empty trigger → invalid" "$(dc "$(crit revise '[]' "[$(jq -c '.trigger = "  "' <<<"$FND")]" '[]')" --decide critique)" \
    '.valid == false and .stage == "decide" and (.errors[0] | test("major_findings\\[0\\].trigger: empty"))'
  jqt "decide: a schema failure is never approved" "$("$B/maestro-validate" "$S" "$V/wrong-enum.txt" --decide critique)" \
    '.valid == false and .stage == "schema" and .decision.approved == false'
  jqt "decide: an envelope failure is never approved" "$("$B/maestro-validate" "$S" "$V/agy-canceled.json" --envelope agy --decide critique)" \
    '.valid == false and .stage == "envelope" and .decision.approved == false'
  jqt "decide critique through an agy envelope" "$("$B/maestro-validate" "$S" "$V/agy-structured-only.json" --envelope agy --decide critique --ids "")" '.valid and .decision.approved'
  jqt "arbiter schema: valid" "$(da '{"verdicts":[{"id":"r1-m1","decision":"upheld","reason":"r"}],"assumptions":[]}')" '.valid'
  jqt "arbiter schema: decision outside the enum → invalid" "$(da '{"verdicts":[{"id":"r1-m1","decision":"maybe","reason":"r"}],"assumptions":[]}')" '.valid == false and (.errors[0] | test("not in enum"))'
  jqt "arbiter schema: missing reason → invalid" "$(da '{"verdicts":[{"id":"r1-m1","decision":"upheld"}],"assumptions":[]}')" '.valid == false and (.errors[0] | test("missing required reason"))'
  jqt "decide arbiter: every verdict downgraded → approved" \
    "$(da '{"verdicts":[{"id":"r1-m1","decision":"downgraded","reason":"r"},{"id":"r2-m1","decision":"downgraded","reason":"r"}],"assumptions":[]}' --decide arbiter --ids r1-m1,r2-m1)" \
    '.valid and .decision == {approved: true, reasons: []}'
  jqt "decide arbiter: one upheld → not approved, named" \
    "$(da '{"verdicts":[{"id":"r1-m1","decision":"downgraded","reason":"r"},{"id":"r2-m1","decision":"upheld","reason":"r"}],"assumptions":[]}' --decide arbiter --ids r1-m1,r2-m1)" \
    '.valid and .decision == {approved: false, reasons: ["r2-m1 upheld"]}'
  jqt "decide arbiter: no verdicts → not approved" "$(da '{"verdicts":[],"assumptions":[]}' --decide arbiter)" '.valid and .decision == {approved: false, reasons: ["no verdicts"]}'
  jqt "decide arbiter: a disputed id without a verdict → invalid" \
    "$(da '{"verdicts":[{"id":"r1-m1","decision":"downgraded","reason":"r"}],"assumptions":[]}' --decide arbiter --ids r1-m1,r2-m1)" \
    '.valid == false and .stage == "decide" and (.errors[0] | test("r2-m1 sent but not answered")) and .decision.approved == false'
  jqt "decide: the wrong schema for the decision → invalid, not a jq error" "$(da '{"verdicts":[],"assumptions":[]}' --decide critique)" '.valid == false and .stage == "decide"'
  if "$B/maestro-validate" "$S" "$V/valid.txt" --decide gate >/dev/null 2>&1; then bad "decide: unknown kind refused"; else ok "decide: unknown kind refused"; fi
  if "$B/maestro-validate" "$S" "$V/valid.txt" --ids r1-m1 >/dev/null 2>&1; then bad "--ids without --decide refused"; else ok "--ids without --decide refused"; fi
fi

# =============================================================================================
if group T6 "read-only fingerprint (checkout)"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  printf 'a\n' > f.txt; git add f.txt; git -c user.email=t@t -c user.name=t commit -qm f
  printf 'b\n' >> f.txt     # already dirty
  "$B/maestro-fp" snapshot > "$WORK/fp0.json"
  jqt "unchanged → same" "$("$B/maestro-fp" compare "$WORK/fp0.json")" '.result == "same"'
  printf 'c\n' >> f.txt     # dirty file changes again, status unchanged
  jqt "content change of an already-dirty file → changed" "$("$B/maestro-fp" compare "$WORK/fp0.json")" \
    '.result == "changed" and (.diffs | index("tracked changes (git diff HEAD)") != null)'
  "$B/maestro-fp" snapshot > "$WORK/fp1.json"; printf 'x' > new.txt
  jqt "new untracked file → changed" "$("$B/maestro-fp" compare "$WORK/fp1.json")" '.diffs | index("untracked files") != null'
  rm -f new.txt; "$B/maestro-fp" snapshot > "$WORK/fp2.json"; git add f.txt
  jqt "staging → changed" "$("$B/maestro-fp" compare "$WORK/fp2.json")" '.diffs | index("staged changes") != null'
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T7 "role resolution"; then
  ALL='["opus","fable","sonnet","haiku","astra","sol","luna","terra","argon","gemini","self"]'
  NOARGON='["opus","fable","sonnet","haiku","astra","sol","luna","terra","gemini","self"]'
  roles() { "$B/maestro-roles" <<<"$1"; }
  jqt "claude build → sol" "$(roles '{"builder":"opus","eligible":'"$ALL"'}')" '.critics == ["sol"] and .reviewer == "sol"'
  jqt "claude build, high stakes → astra + argon" "$(roles '{"builder":"opus","high_stakes":true,"eligible":'"$ALL"'}')" '.critics == ["astra","argon"]'
  jqt "claude build, high stakes, argon not eligible → astra + gemini" "$(roles '{"builder":"opus","high_stakes":true,"eligible":'"$NOARGON"'}')" '.critics == ["astra","gemini"]'
  jqt "openai build → opus" "$(roles '{"builder":"sol","eligible":'"$ALL"'}')" '.critics == ["opus"]'
  jqt "openai build, hs, fable budget → fable + argon" "$(roles '{"builder":"sol","high_stakes":true,"fable_budget":true,"eligible":'"$ALL"'}')" '.critics == ["fable","argon"]'
  jqt "openai build, hs, no fable budget → opus + argon" "$(roles '{"builder":"sol","high_stakes":true,"eligible":'"$ALL"'}')" '.critics == ["opus","argon"]'
  jqt "google build → sol" "$(roles '{"builder":"gemini","eligible":'"$ALL"'}')" '.critics == ["sol"]'
  jqt "argon build is google: argon and gemini never critique it" "$(roles '{"builder":"argon","high_stakes":true,"eligible":'"$ALL"'}')" '.critics == ["astra","opus"]'
  jqt "three families: cascade (luna) + high stakes → one google critic, no second, said" "$(roles '{"builder":"opus","drafter":"luna","high_stakes":true,"eligible":'"$ALL"'}')" \
    '.critics == ["argon"] and (.notes | any(test("no second critic")))'
  jqt "three families: google build, hs → openai then claude" "$(roles '{"builder":"gemini","high_stakes":true,"eligible":'"$ALL"'}')" '.critics == ["astra","opus"]'
  jqt "three families: openai build, hs, google out → one claude critic" "$(roles '{"builder":"sol","high_stakes":true,"eligible":["opus","sol","astra"]}')" '.critics == ["opus"] and (.notes | any(test("no second critic")))'
  jqt "cascade removes the drafter family" "$(roles '{"builder":"opus","drafter":"luna","eligible":'"$ALL"'}')" '.critics == ["argon"]'
  jqt "gemini drafter removes argon too" "$(roles '{"builder":"opus","drafter":"gemini","eligible":'"$ALL"'}')" '.critics == ["sol"]'
  jqt "cascade unsatisfiable → stop" "$(roles '{"builder":"opus","drafter":"luna","eligible":["opus","luna","sonnet"]}')" '.stop.remedy == "drop the cascade or change the drafter"'
  jqt "cascade unsatisfiable, high stakes → drop the cascade" "$(roles '{"builder":"opus","drafter":"luna","high_stakes":true,"eligible":["opus","luna","sonnet"]}')" '.stop.remedy == "drop the cascade"'
  jqt "two families, high stakes → no second critic, said" "$(roles '{"builder":"opus","high_stakes":true,"eligible":["opus","sol","astra"]}')" '.critics == ["astra"] and (.notes | any(test("no second critic")))'
  jqt "claude only: opus build → fable" "$(roles '{"builder":"opus","eligible":["opus","fable","sonnet"]}')" '.critics == ["fable"] and .degraded == "claude"'
  jqt "claude only: fable denied → sonnet" "$(roles '{"builder":"opus","eligible":["opus","sonnet"]}')" '.critics == ["sonnet"]'
  jqt "claude only: fable build → opus" "$(roles '{"builder":"fable","eligible":["opus","fable"]}')" '.critics == ["opus"]'
  jqt "openai only: sol build → astra (the exception, noted)" "$(roles '{"builder":"sol","eligible":["astra","sol","luna"]}')" '.critics == ["astra"] and (.notes | any(test("Astra critiques")))'
  jqt "openai only: astra build → sol" "$(roles '{"builder":"astra","eligible":["astra","sol"]}')" '.critics == ["sol"]'
  jqt "google only, one line → stop" "$(roles '{"builder":"gemini","eligible":["gemini"]}')" '.stop != null'
  jqt "google only: gemini build → argon (degraded)" "$(roles '{"builder":"gemini","eligible":["argon","gemini"]}')" '.critics == ["argon"] and .degraded == "google"'
  jqt "google only: argon build → gemini (degraded)" "$(roles '{"builder":"argon","eligible":["argon","gemini"]}')" '.critics == ["gemini"] and .degraded == "google"'
  jqt "named critic from the builder family → stop" "$(roles '{"builder":"opus","named_critics":["sonnet"],"eligible":'"$ALL"'}')" '.stop != null'
  jqt "two named critics, one family, high stakes → stop" "$(roles '{"builder":"opus","high_stakes":true,"named_critics":["sol","astra"],"eligible":'"$ALL"'}')" '.stop != null'
  jqt "named critics win over policy" "$(roles '{"builder":"opus","named_critics":["argon"],"policy_critic":"gemini","eligible":'"$ALL"'}')" '.critics == ["argon"]'
  jqt "policy critic used when legal" "$(roles '{"builder":"opus","policy_critic":"gemini","eligible":'"$ALL"'}')" '.critics == ["gemini"]'
  jqt "policy critic from the builder family is dropped" "$(roles '{"builder":"opus","policy_critic":"sonnet","eligible":'"$ALL"'}')" '.critics == ["sol"]'
  jqt "self with unknown director family → stop" "$(roles '{"builder":"self","director_family":null,"eligible":["sol"]}')" '.stop != null'
  jqt "self as a known claude director (family and line) → sol" "$(roles '{"builder":"self","director_family":"claude","director_line":"opus","eligible":["self","sol"]}')" '.critics == ["sol"]'
  jqt "self with known family but unknown line → stop" "$(roles '{"builder":"self","director_family":"claude","eligible":["self","sol"]}')" '.stop != null'
  jqt "named critic not available → stop" "$(roles '{"builder":"opus","named_critics":["argon"],"eligible":["opus","sol"]}')" '.stop.reason | test("not available")'
  jqt "high stakes, one named critic → a second family added" "$(roles '{"builder":"opus","high_stakes":true,"named_critics":["sol"],"eligible":["opus","sol","gemini"]}')" '.critics == ["sol","gemini"]'
  jqt "named argon critic of a claude build" "$(roles '{"builder":"opus","named_critics":["argon"],"eligible":'"$ALL"'}')" '.critics == ["argon"] and .reviewer == "argon" and (.notes | any(test("argon is provisional")))'
  jqt "no builder → a structured stop, not a jq error" "$(roles '{"eligible":["sol"]}')" '.stop.reason | test("unknown")'
  # the arbiter at the critique cap (docs/briefs.md, "Arbiter at the cap")
  arb() { "$B/maestro-roles" --arbiter <<<"$1"; }
  jqt "arbiter: claude builder, openai critic → argon" "$(arb '{"builder":"opus","drafter":null,"high_stakes":false,"critics_with_findings":["sol"],"eligible":'"$ALL"'}')" \
    '.arbiter == "argon" and .stop == null and (.reason | test("third family google")) and (.reason | test("provisional"))'
  jqt "arbiter: argon not eligible → gemini" "$(arb '{"builder":"opus","critics_with_findings":["sol"],"eligible":'"$NOARGON"'}')" '.arbiter == "gemini" and .stop == null'
  jqt "arbiter: google out → null + stop" "$(arb '{"builder":"opus","critics_with_findings":["sol"],"eligible":["opus","fable","sonnet","haiku","astra","sol","luna","terra","self"]}')" \
    '.arbiter == null and (.stop.reason | test("no eligible third family")) and .reason == .stop.reason'
  jqt "arbiter: cascade drafter family excluded → null + stop" "$(arb '{"builder":"opus","drafter":"gemini","critics_with_findings":["sol"],"eligible":'"$ALL"'}')" \
    '.arbiter == null and (.stop.reason | test("drafter google"))'
  jqt "arbiter: drafter of the builder family changes nothing" "$(arb '{"builder":"sol","drafter":"luna","critics_with_findings":["argon"],"eligible":'"$ALL"'}')" '.arbiter == "opus"'
  jqt "arbiter: high stakes → stop" "$(arb '{"builder":"opus","high_stakes":true,"critics_with_findings":["sol"],"eligible":'"$ALL"'}')" '.arbiter == null and (.stop.reason | test("high stakes"))'
  jqt "arbiter: two critic families with findings, both cross-family → no third, stop" "$(arb '{"builder":"opus","critics_with_findings":["sol","argon"],"eligible":'"$ALL"'}')" '.arbiter == null and .stop != null'
  jqt "arbiter: two critic families with findings (one the builder family) → the third" "$(arb '{"builder":"sonnet","critics_with_findings":["fable","sol"],"eligible":'"$ALL"'}')" '.arbiter == "argon"'
  jqt "arbiter: two critics of one family → the third" "$(arb '{"builder":"opus","critics_with_findings":["sol","astra"],"eligible":'"$ALL"'}')" '.arbiter == "argon"'
  jqt "arbiter: openai builder, google critic → opus" "$(arb '{"builder":"sol","critics_with_findings":["gemini"],"eligible":'"$ALL"'}')" '.arbiter == "opus"'
  jqt "arbiter: google builder, openai critic, opus not eligible → fable" "$(arb '{"builder":"gemini","critics_with_findings":["sol"],"eligible":["gemini","sol","fable","sonnet","haiku"]}')" '.arbiter == "fable"'
  jqt "arbiter: claude builder, google critic, sol not eligible → astra" "$(arb '{"builder":"opus","critics_with_findings":["argon"],"eligible":["opus","argon","astra","luna"]}')" '.arbiter == "astra"'
  jqt "arbiter: only luna, terra, haiku left → null (not in the order)" "$(arb '{"builder":"opus","critics_with_findings":["argon"],"eligible":["opus","argon","luna","terra"]}')" '.arbiter == null and .stop != null'
  jqt "arbiter: self builder uses the director family" "$(arb '{"builder":"self","director_family":"claude","critics_with_findings":["argon"],"eligible":'"$ALL"'}')" '.arbiter == "sol"'
  jqt "arbiter: self with unknown family → stop, not a jq error" "$(arb '{"builder":"self","critics_with_findings":["argon"],"eligible":'"$ALL"'}')" '.arbiter == null and (.stop.reason | test("unknown"))'
  jqt "arbiter: no critic with findings → stop" "$(arb '{"builder":"opus","critics_with_findings":[],"eligible":'"$ALL"'}')" '.arbiter == null and .stop != null'
  jqt "arbiter: every slot in the order belongs to its family in slots.json" \
    "$(jq -c '[.sol.family, .astra.family, .argon.family, .gemini.family, .opus.family, .fable.family, .sonnet.family]' "$B/slots.json")" \
    '. == ["openai","openai","google","google","claude","claude","claude"]'
  jqt "transports: no slot and no order → halt, not a jq error" "$("$B/maestro-roles" --transports <<<'{"available":{}}')" '.action == "halt"'
  jqt "transports: the order comes from slots.json" "$("$B/maestro-roles" --transports <<<'{"slot":"fable","available":{"native":false,"api":true}}')" '.transport == "api"'
  r6() { "$B/maestro-roles" --row6 <<<"$1"; }
  jqt "row 6: self when the director is known" "$(r6 '{"eligible":["self","sonnet"],"director_family":"claude","director_line":"opus"}')" '.implementer == "self"'
  jqt "row 6: director line unknown → sonnet" "$(r6 '{"eligible":["self","sonnet","sol"],"director_family":"claude"}')" '.implementer == "sonnet"'
  jqt "row 6: only gemini eligible → gemini" "$(r6 '{"eligible":["gemini"]}')" '.implementer == "gemini"'
  jqt "row 6: nothing eligible → halt" "$(r6 '{"eligible":["haiku"]}')" '.implementer == null and .stop.row == 2'
  eq "native canonical pin older than the alias: opus 5 → claude-opus-5" claude-opus-5 "$("$B/maestro-catalog" native-id opus 5)"
  eq "native canonical pin opus 5.5 → claude-opus-5-5" claude-opus-5-5 "$("$B/maestro-catalog" native-id opus 5.5)"
  printf '{"type":"system","subtype":"init","model":"claude-opus-5"}\n' > "$WORK/pin-exact.jsonl"
  printf '{"type":"system","subtype":"init","model":"claude-opus-5-5"}\n' > "$WORK/pin-alias.jsonl"
  jqt "older native pin: a probe serving exactly claude-opus-5 is accepted" "$("$B/maestro-catalog" native-verify claude-opus-5 "$WORK/pin-exact.jsonl")" '.accepted == true'
  jqt "older native pin: an alias serving claude-opus-5-5 is rejected (no alias fallback)" "$("$B/maestro-catalog" native-verify claude-opus-5 "$WORK/pin-alias.jsonl")" '.accepted == false and .served == "claude-opus-5-5"'
  tr_() { "$B/maestro-roles" --transports <<<"$1"; }
  O='"order":["native","agy","api"]'
  jqt "transports: first eligible" "$(tr_ '{"slot":"opus",'"$O"',"available":{"native":true,"agy":true,"api":true}}')" '.action == "use" and .transport == "native"'
  jqt "transports: first-use quota on native → agy" "$(tr_ '{"slot":"opus",'"$O"',"available":{"native":false,"agy":true,"api":false}}')" '.transport == "agy" and .skipped == ["native","api"]'
  jqt "transports: runtime quota, agy denied → switch to api (same version)" "$(tr_ '{"slot":"opus",'"$O"',"available":{"native":true,"agy":true,"api":true},"denied":["agy"],"event":"runtime-failure","failed":"native","frozen_version":"5.5","versions":{"agy":"5.5","api":"5.5"}}')" '.action == "switch" and .transport == "api"'
  jqt "transports: next serves another version → swap, row 5" "$(tr_ '{"slot":"opus",'"$O"',"available":{"agy":false,"api":true},"event":"runtime-failure","failed":"native","frozen_version":"5.5","versions":{"api":"5"}}')" '.action == "swap" and .row == 5'
  jqt "transports: forced @agy failing at run time never falls through" "$(tr_ '{"slot":"opus",'"$O"',"available":{"agy":true},"forced":"agy","event":"runtime-failure","failed":"agy"}')" '.action == "halt" and .row == 5'
  jqt "transports: forced @agy unavailable → halt row 2" "$(tr_ '{"slot":"opus",'"$O"',"available":{"agy":false},"forced":"agy"}')" '.action == "halt" and .row == 2'
  jqt "transports: forced @agy denied by policy → used with a warning" "$(tr_ '{"slot":"opus",'"$O"',"available":{"agy":true},"denied":["agy"],"forced":"agy"}')" '.action == "use" and (.reason | test("warning"))'
  jqt "transports: explicit --model, all transports denied → first available" "$(tr_ '{"slot":"fable","order":["native","api"],"available":{"native":true,"api":true},"denied":["native","api"],"explicit":true}')" '.action == "use" and .transport == "native"'
  jqt "transports: nothing eligible → halt row 2" "$(tr_ '{"slot":"haiku","order":["native"],"available":{"native":false}}')" '.action == "halt" and .row == 2'
  jqt "transports: @transport the slot does not have → halt" "$(tr_ '{"slot":"haiku","order":["native"],"available":{},"forced":"agy"}')" '.action == "halt"'
  OA='"order":["native","agy","api"]'
  jqt "transports: api fallback — native quota at run time, agy out → switch to api" \
    "$(tr_ '{"slot":"opus",'"$OA"',"available":{"native":true,"agy":false,"api":true},"event":"runtime-failure","failed":"native","frozen_version":"5.5","versions":{"api":"5.5"}}')" \
    '.action == "switch" and .transport == "api"'
  jqt "transports: api last — never chosen while native is available" "$(tr_ '{"slot":"opus",'"$OA"',"available":{"native":true,"agy":true,"api":true}}')" '.transport == "native"'
  jqt "transports: --sdk (forced api) failing at run time never falls back to the subscription" \
    "$(tr_ '{"slot":"opus",'"$OA"',"available":{"native":true,"api":true},"forced":"api","event":"runtime-failure","failed":"api"}')" '.action == "halt" and .row == 5'
  jqt "transports: fable (native → api) quota at run time, no api → swap row 5" \
    "$(tr_ '{"slot":"fable","order":["native","api"],"available":{"native":true,"api":false},"event":"runtime-failure","failed":"native","frozen_version":"5.2"}')" '.action == "swap" and .row == 5'
  jqt "transports: haiku with api fallback → api after native" \
    "$(tr_ '{"slot":"haiku","order":["native","api"],"available":{"native":false,"api":true}}')" '.action == "use" and .transport == "api"'
fi

# =============================================================================================
if group T8 "lock"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  L() { "$B/maestro-lock" "$@"; }
  st_of() { awk '{print $22}' "/proc/$1/stat"; }
  sleep 300 & live=$!
  a="$(L acquire --run r1 --token t1 --host test --pid "$live" --starttime "$(st_of "$live")")"
  f1="$(jq -r .fence <<<"$a")"
  jqt "acquire returns generation and fence" "$a" '.result == "acquired" and .generation == 1 and (.fence | startswith("1."))'
  jqt "the lock file never holds the fence" "$(cat .maestro/lock)" 'has("fence") | not'
  jqt "holder of the fence → re-entrant, same fence" "$(L acquire --run r1 --token t1 --host test --fence "$f1")" ".result == \"reentrant\" and .fence == \"$f1\""
  jqt "same token and liveness but no fence → held" "$(L acquire --run r1 --token t1 --host test --pid "$live" --starttime "$(st_of "$live")")" '.result == "held"'
  jqt "other run, live owner → held" "$(L acquire --run r2 --token t2 --host test --pid $$ --starttime "$(st_of $$)")" '.result == "held"'
  jqt "resume of the same run while the owner is live → held" "$(L acquire --run r1 --token t1 --host test --resume --pid $$ --starttime x)" '.result == "held"'
  out="$(L exec --gen 1 -- touch "$WORK/gen-only" 2>&1; echo "rc=$?")"
  if [[ ! -e "$WORK/gen-only" && "$out" == *"rc=4"* ]]; then ok "the generation alone (readable) grants no mutation"; else bad "generation alone refused" "$out"; fi
  # The owner dies; two simultaneous PID-based resumes: exactly one acquires.
  kill "$live"; wait "$live" 2>/dev/null
  sleep 300 & d1=$!; sleep 300 & d2=$!
  ( L acquire --run r1 --token t1 --host test --resume --pid "$d1" --starttime "$(st_of "$d1")" > "$WORK/res1" ) & r1p=$!
  ( L acquire --run r1 --token t1 --host test --resume --pid "$d2" --starttime "$(st_of "$d2")" > "$WORK/res2" ) & r2p=$!
  wait "$r1p" "$r2p" 2>/dev/null
  eq "two simultaneous PID resumes: one acquires, one held" "1 1" \
    "$(cat "$WORK/res1" "$WORK/res2" | jq -s '[.[] | select(.result == "acquired")] | length') $(cat "$WORK/res1" "$WORK/res2" | jq -s '[.[] | select(.result == "held")] | length')"
  win="$(cat "$WORK/res1" "$WORK/res2" | jq -rs '.[] | select(.result == "acquired") | .fence')"
  g="$win"
  eq "generation advanced to 2" 2 "$(L show | jq -r .generation)"
  out="$(L exec --gen "$f1" -- touch "$WORK/should-not-exist" 2>&1; echo "rc=$?")"
  if [[ ! -e "$WORK/should-not-exist" && "$out" == *"rc=4"* ]]; then ok "superseded fence: exec refused, command not run"; else bad "superseded fence refused" "$out"; fi
  out="$(L exec --gen "$g" -- "$B/maestro-lock" exec --gen "$g" -- touch "$WORK/nested-ok" 2>&1; echo "rc=$?")"
  if [[ -e "$WORK/nested-ok" && "$out" == *"rc=0"* ]]; then ok "nested maestro-lock exec inside a live fence runs (no deadlock)"; else bad "nested exec inside a live fence runs" "$out"; fi
  out="$(L exec --gen "$g" -- "$B/maestro-lock" exec --gen "$f1" -- touch "$WORK/nested-stale" 2>&1; echo "rc=$?")"
  if [[ ! -e "$WORK/nested-stale" && "$out" == *"rc=4"* ]]; then ok "nested exec with a superseded fence refused"; else bad "nested exec with a superseded fence refused" "$out"; fi
  out="$(MAESTRO_IN_FENCE=1 MAESTRO_FENCE_HOLDER="999999999:1" L exec --gen "$g" -- touch "$WORK/nested-gone" 2>&1; echo "rc=$?")"
  if [[ ! -e "$WORK/nested-gone" && "$out" == *"section is gone"* ]]; then ok "nested exec after the fenced section ended refused"; else bad "nested exec after the section ended refused" "$out"; fi
  out="$(MAESTRO_IN_FENCE=1 MAESTRO_FENCE_HOLDER="$$:$(st_of $$)" L exec --gen "$g" -- touch "$WORK/nested-fake" 2>&1; echo "rc=$?")"
  if [[ ! -e "$WORK/nested-fake" && "$out" == *"section is gone"* ]]; then ok "a live holder that is not this lock's flock is refused"; else bad "fake holder refused" "$out"; fi
  jqt "a helper given --gen inside maestro-lock exec works (maestro-state)" \
    "$(printf '{"n":1}\n' | L exec --gen "$g" -- "$B/maestro-state" --gen "$g" append ledger.jsonl)" '.result == "written"'
  eq "a worker launched inside the fence does not inherit it (maestro-env)" 0 \
    "$(L exec --gen "$g" -- "$B/maestro-env" -- env | grep -c -E '^MAESTRO_(IN_FENCE|FENCE_HOLDER)=' || true)"
  eq "a worker never inherits an API key, token or base URL (maestro-env)" 0 \
    "$(ANTHROPIC_API_KEY=k ANTHROPIC_AUTH_TOKEN=t ANTHROPIC_BASE_URL=u "$B/maestro-env" -- env | grep -c '^ANTHROPIC_' || true)"
  # catalog refresh --gen: sources read outside the lock, the write inside the fence.
  jqt "catalog refresh --gen writes the catalog" \
    "$("$B/maestro-catalog" refresh --gen "$g" --fixtures "$FX/catalogs/machine-2026-11-14")" '.slots.codex.sol[0] == "6.1"'
  h0="$(sha256sum .maestro/catalog.json | cut -c1-64)"
  out="$("$B/maestro-catalog" refresh --gen "$f1" --fixtures "$FX/catalogs/machine-2026-11-14" 2>&1; echo "rc=$?")"
  if [[ "$out" == *"rc=4"* && "$(sha256sum .maestro/catalog.json | cut -c1-64)" == "$h0" ]]; then
    ok "catalog refresh with a superseded fence leaves the catalog untouched"
  else bad "catalog refresh with a superseded fence refused" "$out"; fi
  # During a live job: bookkeeping writable, the wrapper holds no lock fd.
  "$B/maestro-run" --gen "$g" --job lj --run r1 --role build -- sleep 6 >/dev/null; sleep 1
  w="$(jq -r .wrapper_pid .maestro/jobs/lj/meta.json)"
  held=0
  for fd in "/proc/$w/fd"/*; do [[ "$(readlink "$fd" 2>/dev/null)" == *lock.flock ]] && held=1; done
  if (( held )); then bad "wrapper holds no lock fd"; else ok "wrapper holds no lock fd"; fi
  jqt "ledger write during a live job" "$(printf '{"x":1}\n' | "$B/maestro-state" --gen "$g" append ledger.jsonl)" '.result == "written"'
  jqt "the audit records the generation, never the fence" "$(tail -1 .maestro/audit.jsonl)" '(.gen | tostring) == "2"'
  # A kill waiting for a protected test does not block other fenced calls.
  mkdir -p vendor/bin; printf '#!/bin/sh\nexec sleep 6\n' > vendor/bin/pest; chmod +x vendor/bin/pest
  printf '#!/bin/bash\nsh -c "vendor/bin/pest" &\nsleep 20\n' > b.sh; chmod +x b.sh
  "$B/maestro-run" --gen "$g" --job kt --run r1 --role build --test-runner vendor/bin/pest -- ./b.sh >/dev/null; sleep 2
  "$B/maestro-kill" kt --gen "$g" >/dev/null
  t0="$(date +%s)"; printf '{"y":1}\n' | "$B/maestro-state" --gen "$g" append ledger.jsonl >/dev/null; t1="$(date +%s)"
  if (( t1 - t0 <= 3 )); then ok "fenced write not blocked by a test wait"; else bad "fenced write not blocked by a test wait" "$((t1 - t0)) s"; fi
  sleep 6; "$B/maestro-kill" kt --gen "$g" --grace 1 >/dev/null; sleep 1.5; "$B/maestro-kill" kt --gen "$g" >/dev/null
  # A stale owner's own --resume adopts its running job.
  REPO5="$(new_repo)"; cd "$REPO5" || exit 2
  sleep 300 & own=$!
  fo="$(L acquire --run ra --token tra --host test --pid "$own" --starttime "$(st_of "$own")" | jq -r .fence)"
  "$B/maestro-run" --gen "$fo" --job ra.build.r1.a1 --run ra --role build -- sleep 30 >/dev/null; sleep 1
  kill "$own"; wait "$own" 2>/dev/null
  out="$(L acquire --run x --tokn t --host h 2>&1; echo "rc=$?")"
  if [[ "$out" == *"unknown option --tokn"* && "$out" == *rc=2* ]]; then ok "lock: an unknown option is refused"; else bad "lock: an unknown option is refused" "$out"; fi
  jqt "resume of a stale owner adopts its running job" "$(L acquire --run ra --token tra --host test --resume)" \
    '.result == "acquired" and (.adopted_jobs | index("ra.build.r1.a1") != null)'
  fr="$(L show | jq -r .generation)"; : "$fr"
  pkill -P "$(jq -r .wrapper_pid .maestro/jobs/ra.build.r1.a1/meta.json)" 2>/dev/null || true
  cd "$REPO" || exit 2
  # Another run vs a stale lock with a running job → blocked.
  kill "$d1" "$d2" 2>/dev/null; wait "$d1" "$d2" 2>/dev/null
  "$B/maestro-run" --gen "$g" --job bj --run r1 --role build -- sleep 8 >/dev/null; sleep 1
  jqt "different run vs stale lock with a running job → blocked" "$(L acquire --run r9 --token t9 --host test)" '.result == "blocked"'
  sleep 8
  jqt "different run takes over once the job ended" "$(L acquire --run r9 --token t9 --host test)" '.result == "acquired"'
  # Heartbeat liveness: two simultaneous heartbeat resumes of a stale owner → exactly one acquires.
  REPO2="$(new_repo)"; cd "$REPO2" || exit 2
  L acquire --run h1 --token th --host test >/dev/null
  jqt "heartbeat owner is live" "$(L acquire --run h2 --token t2 --host test)" '.result == "held"'
  touch -d '2 hours ago' .maestro/lock.heartbeat
  ( L acquire --run h1 --token th --host test --resume > "$WORK/hb1" ) & p1=$!
  ( L acquire --run h1 --token th --host test --resume > "$WORK/hb2" ) & p2=$!
  wait "$p1" "$p2" 2>/dev/null
  eq "two simultaneous heartbeat resumes: one acquires, one held" "1 1" \
    "$(cat "$WORK/hb1" "$WORK/hb2" | jq -s '[.[] | select(.result == "acquired")] | length') $(cat "$WORK/hb1" "$WORK/hb2" | jq -s '[.[] | select(.result == "held")] | length')"
  lose="$(cat "$WORK/hb1" "$WORK/hb2" | jq -rs '.[] | select(.result == "held") | .owner.generation')"
  out="$(L exec --gen "$lose.guess" -- touch "$WORK/loser-mutation" 2>&1; echo "rc=$?")"
  if [[ ! -e "$WORK/loser-mutation" && "$out" == *"rc=4"* ]]; then ok "the losing resume cannot mutate"; else bad "the losing resume cannot mutate" "$out"; fi
  hw="$(cat "$WORK/hb1" "$WORK/hb2" | jq -rs '.[] | select(.result == "acquired") | .fence')"
  touch -d '2 hours ago' .maestro/lock.heartbeat
  jqt "stale heartbeat → takeover by another run" "$(L acquire --run h2 --token t2 --host test)" '.result == "acquired"'
  out="$(L exec --gen "$hw" -- touch "$WORK/stale-hb" 2>&1; echo "rc=$?")"
  if [[ ! -e "$WORK/stale-hb" && "$out" == *"rc=4"* ]]; then ok "superseded heartbeat owner cannot mutate"; else bad "superseded heartbeat owner" "$out"; fi
  hf="$(L show >/dev/null; L acquire --run h2 --token t2 --host test --fence "9.wrong" | jq -r '.result')"
  eq "a wrong fence is not re-entry" held "$hf"
  touch .maestro/lock.heartbeat
  g2gen="$(L show | jq -r .generation)"
  owner="$(cd "$REPO2" && L acquire --run h3 --token t3 --host test | jq -r .result)"
  eq "live heartbeat owner keeps the lock" held "$owner"
  cd "$ROOT" || exit 2
  # Release and the monotonic generation.
  REPO3="$(new_repo)"; cd "$REPO3" || exit 2
  f="$(L acquire --run x --token tx --host test | jq -r .fence)"
  jqt "release needs the fence" "$(L release --token tx --gen "${f%%.*}.nope" 2>&1 | jq -Rc '{m: .}')" '.m | test("superseded|not the current")'
  jqt "release with the fence" "$(L release --token tx --gen "$f")" '.result == "released"'
  jqt "generation survives release" "$(L acquire --run y --token ty --host test)" '.generation == 2'
  : "$g2gen"
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T9 "audit and .maestro fingerprint"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  g="$("$B/maestro-lock" acquire --run r --token t --host test | jq -r .fence)"
  printf 'stage: plan\n' | "$B/maestro-state" --gen "$g" write CHECKPOINT.md >/dev/null
  printf '# plan\n' > .maestro/PLAN.md
  "$B/maestro-fp" snapshot > "$WORK/a.json"
  printf 'stage: critique\nsession: abc\n' | "$B/maestro-state" --gen "$g" write CHECKPOINT.md >/dev/null
  printf '{"row":1}\n' | "$B/maestro-state" --gen "$g" append ledger.jsonl >/dev/null
  jqt "innocent call: audited bookkeeping writes → same" "$("$B/maestro-fp" compare "$WORK/a.json")" '.result == "same"'
  mkdir -p .maestro/tmp; printf 'draft\n' > .maestro/tmp/CHECKPOINT.md     # a director's draft in tmp/
  jqt "a draft named CHECKPOINT.md under tmp/ is not bookkeeping" "$("$B/maestro-fp" compare "$WORK/a.json")" '.result == "same"'
  printf 'hacked\n' >> .maestro/CHECKPOINT.md
  jqt "a critic edits the checkpoint → detected" "$("$B/maestro-fp" compare "$WORK/a.json")" '.result == "changed"'
  out="$(printf 'stage: build\n' | "$B/maestro-state" --gen "$g" write CHECKPOINT.md 2>&1; echo "rc=$?")"
  if [[ "$out" == *tampered*rc=5* ]]; then ok "tampering before a legitimate write → that write stops"; else bad "tampering before a legitimate write → that write stops" "$out"; fi
  REPO2="$(new_repo)"; cd "$REPO2" || exit 2
  g="$("$B/maestro-lock" acquire --run r --token t --host test | jq -r .fence)"
  printf '# plan\n' > .maestro/PLAN.md; "$B/maestro-fp" snapshot > "$WORK/b.json"
  printf 'changed\n' >> .maestro/PLAN.md
  jqt "protected input (.maestro/PLAN.md) changed → detected" "$("$B/maestro-fp" compare "$WORK/b.json")" '.diffs | index("protected .maestro inputs") != null'
  # Interruption between publish and audit append: the next verify fails closed.
  printf 'x\n' | "$B/maestro-state" --gen "$g" write CHECKPOINT.md >/dev/null
  printf 'y\n' > .maestro/CHECKPOINT.md     # published without its audit entry
  jqt "publish without audit → verify fails closed" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "tampered"'
  # Only an explicit adoption makes an unaudited file legitimate again.
  printf 'y\n' | "$B/maestro-state" --gen "$g" write CHECKPOINT.md >/dev/null 2>&1
  jqt "after a refused write the file is still unaudited" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "tampered"'
  jqt "adopt needs a reason" "$("$B/maestro-state" --gen "$g" adopt CHECKPOINT.md 2>&1 | jq -Rc '{msg: .}')" '.msg | test("reason")'
  # Whether a user is there to have inspected the file comes from maestro-host: fake an
  # interactive and a headless Claude Code (pid 100) above this shell (pid 200).
  hproc() {
    local r="$WORK/$1"; shift
    mkdir -p "$r/100" "$r/200"
    printf '100 (x) S 1 100 100 0 -1 0 0 0 0 0 0 0 0 20 0 1 0 1100 0 0\n' > "$r/100/stat"
    printf '200 (x) S 100 200 200 0 -1 0 0 0 0 0 0 0 0 20 0 1 0 1200 0 0\n' > "$r/200/stat"
    printf '%s\0' "$@" > "$r/100/cmdline"; printf 'bash\0' > "$r/200/cmdline"
    ln -sfn /home/u/.local/share/claude/versions/2.1.296 "$r/100/exe"; ln -sfn /usr/bin/bash "$r/200/exe"
    printf '%s' "$r"
  }
  as_host() { MAESTRO_PROC="$1" MAESTRO_HOST_START_PID=200 CLAUDECODE=1 "${@:2}"; }
  HI="$(hproc adopt-interactive claude)"; HH="$(hproc adopt-headless claude -p hi)"
  o="$(as_host "$HH" "$B/maestro-state" --gen "$g" adopt CHECKPOINT.md --reason "director's own call"; echo "rc=$?")"
  jqt "adopt under a headless host is refused" "${o%rc=*}" '.result == "refused" and (.reason | test("headless"))'
  eq "refused adopt exits 1" "rc=1" "rc=${o##*rc=}"
  jqt "a refused adopt leaves the file unaudited" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "tampered"'
  HC="$(hproc adopt-codex codex exec x)"; ln -sfn /home/u/.codex/bin/codex "$HC/100/exe"
  jqt "adopt when another agent CLI directs is refused" "$(as_host "$HC" "$B/maestro-state" --gen "$g" adopt CHECKPOINT.md --reason x)" '.result == "refused"'
  jqt "adopt with a reason" "$(as_host "$HI" "$B/maestro-state" --gen "$g" adopt CHECKPOINT.md --reason "user inspected it")" '.result == "adopted"'
  jqt "adopted file verifies" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "ok"'
  jqt "the adoption is marked in the audit" "$(tail -1 .maestro/audit.jsonl)" '.adopted == true and .reason == "user inspected it"'
  if grep -qF "${g#*.}" .maestro/audit.jsonl; then bad "no audit path discloses the fence secret"; else ok "no audit path discloses the fence secret"; fi
  # Lifecycle: delete, archive, rotate — and a fresh checkpoint afterwards without adopt.
  REPO4="$(new_repo)"; cd "$REPO4" || exit 2
  g4="$("$B/maestro-lock" acquire --run r --token t --host test | jq -r .fence)"
  printf 'pending\n' | "$B/maestro-state" --gen "$g4" write pending-decision.md >/dev/null
  jqt "delete an audited file" "$("$B/maestro-state" --gen "$g4" delete pending-decision.md)" '.result == "written"'
  jqt "deleted file verifies as absent" "$("$B/maestro-state" verify pending-decision.md)" '.result == "ok"'
  jqt "recreating a deleted file needs no adopt" "$(printf 'again\n' | "$B/maestro-state" --gen "$g4" write pending-decision.md)" '.result == "written"'
  printf 'cp1\n' | "$B/maestro-state" --gen "$g4" write CHECKPOINT.md >/dev/null
  printf '{"r":1}\n' | "$B/maestro-state" --gen "$g4" append ledger.jsonl >/dev/null
  jqt "rotate at the end of a run" "$("$B/maestro-state" --gen "$g4" rotate --to run-1)" '.result == "rotated"'
  if [[ -f .maestro/archive/run-1/CHECKPOINT.md && -f .maestro/archive/run-1/audit.jsonl && ! -f .maestro/CHECKPOINT.md ]]; then ok "rotate moved checkpoint and audit to the archive"; else bad "rotate moved checkpoint and audit"; fi
  jqt "after rotate a new run writes a fresh checkpoint without adopt" "$(printf 'cp2\n' | "$B/maestro-state" --gen "$g4" write CHECKPOINT.md)" '.result == "written"'
  jqt "the ledger stays audited across the rotation" "$("$B/maestro-state" verify ledger.jsonl)" '.result == "ok"'
  printf 'x\n' >> .maestro/ledger.jsonl
  jqt "rotate refuses while an audited file was tampered with" "$("$B/maestro-state" --gen "$g4" rotate --to run-2)" '.result == "tampered"'
  cd "$REPO2" || exit 2
  # Audit prefix rewritten → detected.
  "$B/maestro-fp" snapshot > "$WORK/c.json"; sed -i '1s/.*/{"file":"x"}/' .maestro/audit.jsonl
  jqt "audit prefix rewritten → detected" "$("$B/maestro-fp" compare "$WORK/c.json")" '.diffs | index("audit.jsonl prefix") != null'
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T10 "ledger rows from job output"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  g="$("$B/maestro-lock" acquire --run r --token t --host test | jq -r .fence)"
  mkdir -p .maestro/jobs/j1 .maestro/jobs/j2
  printf '%s\n' '{"type":"system","subtype":"init","model":"claude-sonnet-5-5","session_id":"c1"}' \
    '{"type":"result","subtype":"success","is_error":false,"result":"x","session_id":"c1","duration_ms":2000,"usage":{"input_tokens":5,"cache_read_input_tokens":2,"cache_creation_input_tokens":1,"output_tokens":3},"modelUsage":{"claude-sonnet-5-5":{}}}' > .maestro/jobs/j1/out
  printf 0 > .maestro/jobs/j1/exit
  printf '{"run_id":"r","host":"claude-code"}' > .maestro/jobs/j1/meta.json
  row="$("$B/maestro-ledger" --dry-run --job j1 --stage critique --cli claude-cli --transport native --family claude --model sonnet)"
  jqt "claude -p row: usage, served model, run and host from meta" "$row" \
    '.input_tokens == 5 and .output_tokens == 3 and .model_served == "claude-sonnet-5-5" and .run_id == "r" and .host == "claude-code" and .exit_code == "0"'
  printf '{"type":"thread.started","thread_id":"t1"}\n{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":3,"reasoning_output_tokens":1}}\n' > .maestro/jobs/j2/out
  row="$("$B/maestro-ledger" --dry-run --job j2 --stage build --cli codex --transport codex --family openai --model gpt-6.1-sol)"
  jqt "codex row: usage, session, total" "$row" '.session_id == "t1" and .input_tokens == 10 and .reasoning_tokens == 1 and .total_tokens == 13'
  jqt "no meta.json (interactive Claude Code job): run and host from the lock" "$row" '.run_id == "r" and .host == "test"'
  row="$("$B/maestro-ledger" --dry-run --cli claude-agent --stage build --round 1 --transport native --family claude \
          --model opus --served claude-opus-5-5 --agent-id ac8f --total-tokens 327499 --tool-uses 94 --duration-ms 1521500)"
  jqt "Agent-tool row without a served model (the completion names none) → null" \
    "$("$B/maestro-ledger" --dry-run --cli claude-agent --stage build --transport native --family claude --model sonnet --agent-id a1 --total-tokens 40180 --tool-uses 3 --duration-ms 7319)" \
    '.model_served == null and .total_tokens == 40180 and .duration_s == 7.319'
  jqt "Agent-tool row: no job, harness totals, served model, run and host from the lock" "$row" \
    '.cli == "claude-agent" and .job_id == null and .total_tokens == 327499 and .input_tokens == null and .tool_uses == 94
     and .duration_s == 1521.5 and .model_served == "claude-opus-5-5" and .session_id == "ac8f" and .status == "success"
     and .run_id == "r" and .host == "test" and .round == 1'
  out="$("$B/maestro-ledger" --dry-run --cli claude-agent --stage build --model opus --served x --agent-id a 2>&1; echo "rc=$?")"
  if [[ "$out" == *"needs --agent-id and --total-tokens"* && "$out" == *"rc=2"* ]]; then ok "Agent-tool row without its numbers refused"; else bad "Agent-tool row without its numbers refused" "$out"; fi
  jqt "Agent-tool row appends through maestro-state" "$("$B/maestro-ledger" --gen "$g" --cli claude-agent --stage build --transport native --family claude --model sonnet --served claude-sonnet-5-5 --agent-id ace4 --total-tokens 114960)" '.result == "written"'
  jqt "… --run/--host override the lock" \
    "$("$B/maestro-ledger" --dry-run --job j2 --stage build --cli codex --transport codex --family openai --model m --run r9 --host claude-code)" \
    '.run_id == "r9" and .host == "claude-code"'
  jqt "append goes through maestro-state" "$("$B/maestro-ledger" --gen "$g" --job j2 --stage build --cli codex --transport codex --family openai --model gpt-6.1-sol)" '.result == "written"'
  jqt "ledger verifies" "$("$B/maestro-state" verify ledger.jsonl)" '.result == "ok"'
  mkdir -p .maestro/jobs/j3
  printf '{"type":"thread.started","thread_id":"t1"}\n{"type":"turn.completed","usage":{"input_tokens":25,"cached_input_tokens":10,"output_tokens":8,"reasoning_output_tokens":3}}\n' > .maestro/jobs/j3/out
  row="$("$B/maestro-ledger" --dry-run --job j3 --stage fix --cli codex --transport codex --family openai --model gpt-6.1-sol)"
  jqt "codex resume of the same thread: delta in the token fields, raw kept" "$row" \
    '.input_tokens == 15 and .output_tokens == 5 and .reasoning_tokens == 2 and .raw_cumulative.input_tokens == 25 and .status == "completed"'
  "$B/maestro-ledger" --gen "$g" --job j3 --stage fix --cli codex --transport codex --family openai --model gpt-6.1-sol >/dev/null
  mkdir -p .maestro/jobs/j5; cp .maestro/jobs/j3/out .maestro/jobs/j5/out
  jqt "equal cumulative counters → zero delta" "$("$B/maestro-ledger" --dry-run --job j5 --stage fix --cli codex --transport codex --family openai --model gpt-6.1-sol)" '.input_tokens == 0 and .output_tokens == 0'
  mkdir -p .maestro/jobs/j6
  printf '{"type":"thread.started","thread_id":"t1"}\n{"type":"turn.completed","usage":{"input_tokens":4,"output_tokens":2}}\n' > .maestro/jobs/j6/out
  jqt "counters that went down → reset recorded, raw values kept" "$("$B/maestro-ledger" --dry-run --job j6 --stage fix --cli codex --transport codex --family openai --model gpt-6.1-sol)" '.counter_reset == true and .input_tokens == 4'
  jqt "effective_config kept as an object; service tier recorded" \
    "$("$B/maestro-ledger" --dry-run --job j2 --stage build --cli codex --transport codex --family openai --model gpt-6.1-sol --effective-config '{"model":"gpt-6.1-sol","sandbox":"read-only"}' --service-tier priority)" \
    '.effective_config.sandbox == "read-only" and .service_tier_requested == "priority"'
  # success 100/20 → failed call without usage → success 150/30 on one thread: 100, null, 50.
  for k in a b c; do mkdir -p ".maestro/jobs/t$k"; done
  printf '{"type":"thread.started","thread_id":"tz"}\n{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":20}}\n' > .maestro/jobs/ta/out
  printf '{"type":"thread.started","thread_id":"tz"}\n{"type":"turn.failed","error":{"message":"stream error"}}\n' > .maestro/jobs/tb/out
  printf '{"type":"thread.started","thread_id":"tz"}\n{"type":"turn.completed","usage":{"input_tokens":150,"output_tokens":30}}\n' > .maestro/jobs/tc/out
  for k in a b c; do "$B/maestro-ledger" --gen "$g" --job "t$k" --stage fix --cli codex --transport codex --family openai --model gpt-6.1-sol >/dev/null; done
  jqt "success → usage-less failure → success: 100, null, 50 (no double count)" \
    "$(jq -sc '[.[] | select(.session_id == "tz") | .input_tokens]' .maestro/ledger.jsonl)" '. == [100, null, 50]'
  jqt "the failed call keeps no baseline" "$(jq -sc '[.[] | select(.session_id == "tz") | (.raw_cumulative != null)]' .maestro/ledger.jsonl)" '. == [true, false, true]'
  # Partially missing counters: each counter keeps its own baseline.
  for k in d e f; do mkdir -p ".maestro/jobs/p$k"; done
  printf '{"type":"thread.started","thread_id":"tp"}\n{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":20,"cached_input_tokens":50,"reasoning_output_tokens":5}}\n' > .maestro/jobs/pd/out
  printf '{"type":"thread.started","thread_id":"tp"}\n{"type":"turn.completed","usage":{"input_tokens":120,"cached_input_tokens":60}}\n' > .maestro/jobs/pe/out
  printf '{"type":"thread.started","thread_id":"tp"}\n{"type":"turn.completed","usage":{"input_tokens":150,"output_tokens":30,"cached_input_tokens":70,"reasoning_output_tokens":9}}\n' > .maestro/jobs/pf/out
  for k in d e f; do "$B/maestro-ledger" --gen "$g" --job "p$k" --stage fix --cli codex --transport codex --family openai --model gpt-6.1-sol >/dev/null; done
  rows="$(jq -sc '[.[] | select(.session_id == "tp") | {i: .input_tokens, o: .output_tokens, c: .cached_input_tokens, r: .reasoning_tokens}]' .maestro/ledger.jsonl)"
  jqt "partially missing counters: input 100,20,30" "$rows" '[.[].i] == [100,20,30]'
  jqt "partially missing counters: output 20,null,10 (no overcount)" "$rows" '[.[].o] == [20,null,10]'
  jqt "partially missing counters: cache 50,10,10" "$rows" '[.[].c] == [50,10,10]'
  jqt "partially missing counters: reasoning 5,null,4" "$rows" '[.[].r] == [5,null,4]'
  jqt "effective_config text fallback keeps the text" \
    "$("$B/maestro-ledger" --dry-run --job j2 --stage build --cli codex --transport codex --family openai --model m --effective-config 'OK read-only')" '.effective_config == "OK read-only"'
  mkdir -p .maestro/jobs/j4; cp "$FX/verdicts/agy-denied.json" .maestro/jobs/j4/out
  row="$("$B/maestro-ledger" --dry-run --job j4 --stage critique --cli agy --transport agy --family google --model gemini-3.8-flash-medium)"
  jqt "agy row: status and denied actions recorded" "$row" '.status == "SUCCESS" and .denied_actions == ["mcp"]'
  mkdir -p .maestro/jobs/k1 .maestro/jobs/k2
  cp "$FX/verdicts/sdk-structured.jsonl" .maestro/jobs/k1/out; cp "$FX/verdicts/sdk-budget.jsonl" .maestro/jobs/k2/out
  row="$("$B/maestro-ledger" --dry-run --job k1 --stage critique --cli claude-sdk --transport api --family claude --model claude-opus-5-5)"
  jqt "api row: usage, served model, cost_usd from total_cost_usd" "$row" \
    '.cli == "claude-sdk" and .transport == "api" and .input_tokens == 12000 and .cached_input_tokens == 30000
     and .model_served == "claude-opus-5-5" and .cost_usd == 0.4125 and .session_id == "sdk1" and .duration_s == 42'
  jqt "non-api rows carry cost_usd null" "$("$B/maestro-ledger" --dry-run --job j1 --stage critique --cli claude-cli --transport native --family claude --model m)" '.cost_usd == null'
  mkdir -p .maestro/jobs/cw; cp .maestro/jobs/j2/out .maestro/jobs/cw/out
  printf '{"run_id":"r","host":"claude-code","started_at":"%s"}' "$(date -u -d '-42 seconds' +%Y-%m-%dT%H:%M:%SZ)" > .maestro/jobs/cw/meta.json
  printf 0 > .maestro/jobs/cw/exit
  jqt "codex row: wall time from meta started_at to the exit file" \
    "$("$B/maestro-ledger" --dry-run --job cw --stage critique --cli codex --transport codex --family openai --model gpt-6.1-sol)" '.duration_s >= 41 and .duration_s <= 44'
  "$B/maestro-ledger" --gen "$g" --job k1 --stage critique --cli claude-sdk --transport api --family claude --model claude-opus-5-5 >/dev/null
  "$B/maestro-ledger" --gen "$g" --job k1 --stage build --cli claude-sdk --transport api --family claude --model claude-opus-5-5 >/dev/null
  rep="$("$B/maestro-ledger" report --run r --json)"
  jqt "report: rows grouped by stage and model, api spend summed" "$rep" \
    '.calls >= 2 and (.rows | any(.stage == "critique" and .who == "claude-opus-5-5" and .transport == "api")) and .api_usd > 0'
  md="$("$B/maestro-ledger" report --run r)"
  if [[ "$md" == *"| Stage | Who |"* && "$md" == *"api spend: \$"* && "$md" == *"not subscription cost"* ]]; then ok "report: Markdown table"; else bad "report: Markdown table" "$md"; fi
  jqt "report: unknown numbers stay null, never 0" "$("$B/maestro-ledger" report --run nope --json)" '.calls == 0 and .rows == []' 
  "$B/maestro-ledger" --gen "$g" --job k2 --stage build --cli claude-sdk --transport api --family claude --model claude-opus-5-5 >/dev/null
  jqt "cost: the run's api spend summed" "$("$B/maestro-ledger" cost --run r --transport api)" '.cost_usd == 0.825 and .rows == 3'
  jqt "cost: another run spent nothing" "$("$B/maestro-ledger" cost --run other --transport api)" '.cost_usd == 0 and .rows == 0'
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T11 "api transport runner (maestro-sdk, no model turn)"; then
  if ! command -v node >/dev/null 2>&1; then
    bad "node available" "the api transport needs Node ≥ 18"
  else
    K="$WORK/key"; printf 'sk-test\n' > "$K"; chmod 600 "$K"; printf 'brief\n' > "$WORK/brief.md"
    sdk() { MAESTRO_API_KEY_FILE="$K" "$B/maestro-sdk" "$@" 2>&1; }
    base=(--model claude-opus-5-5 --effort medium --permission-mode dontAsk --max-budget-usd 2 --prompt-file "$WORK/brief.md")
    row="$(sdk "${base[@]}" --tools "Read,Grep,Glob" --allowed-tools "Read,Grep,Glob" --json-schema "$ROOT/docs/schemas/critique-schema.json" --dry-run)"
    jqt "dry run: role flags map onto SDK options, isolation on" "$row" \
      '.options.tools == ["Read","Grep","Glob"] and .options.allowedTools == ["Read","Grep","Glob"] and .options.permissionMode == "dontAsk"
       and .options.settingSources == [] and .options.mcpServers == {} and .options.strictMcpConfig == true
       and .options.maxBudgetUsd == 2 and .options.outputFormat == "json_schema" and .options.model == "claude-opus-5-5"'
    jqt "dry run: no key in the output" "$row" '(tostring | test("sk-test")) | not'
    jqt "empty --tools disables every tool" "$(sdk "${base[@]}" --tools "" --dry-run)" '.options.tools == []'
    jqt "inherited auth variables are dropped, the key set" "$(ANTHROPIC_AUTH_TOKEN=t CLAUDE_CODE_OAUTH_TOKEN=o sdk "${base[@]}" --tools "" --dry-run)" \
      '(.env_dropped | index("ANTHROPIC_AUTH_TOKEN") != null and index("CLAUDE_CODE_OAUTH_TOKEN") != null) and (.env_set | index("ANTHROPIC_API_KEY") != null)'
    out="$(sdk --model opus --effort medium --tools "" --permission-mode dontAsk --max-budget-usd 1 --prompt-file "$WORK/brief.md" --dry-run; echo "rc=$?")"
    if [[ "$out" == *"must be a full id"* && "$out" == *"rc=2"* ]]; then ok "an alias is refused (the bundled CLI's alias table lags)"; else bad "an alias is refused" "$out"; fi
    out="$(sdk --model claude-opus-5-5 --effort medium --permission-mode bypassPermissions --max-budget-usd 2 --prompt-file "$WORK/brief.md" --tools "" --dry-run; echo "rc=$?")"
    if [[ "$out" == *"rc=2"* ]]; then ok "bypassPermissions is refused"; else bad "bypassPermissions is refused" "$out"; fi
    out="$(sdk --model claude-opus-5-5 --effort medium --tools "" --permission-mode dontAsk --prompt-file "$WORK/brief.md" --dry-run; echo "rc=$?")"
    if [[ "$out" == *"--max-budget-usd is required"* ]]; then ok "a launch without a budget is refused"; else bad "a launch without a budget is refused" "$out"; fi
    chmod 644 "$K"
    out="$(sdk "${base[@]}" --tools "" --dry-run; echo "rc=$?")"
    if [[ "$out" == *"chmod 600"* && "$out" == *"rc=3"* ]]; then ok "a key file readable by others is refused"; else bad "a key file readable by others is refused" "$out"; fi
    chmod 600 "$K"
    out="$(MAESTRO_API_KEY_FILE="$WORK/none" "$B/maestro-sdk" "${base[@]}" --tools "" --dry-run 2>&1; echo "rc=$?")"
    if [[ "$out" == *"no API key file"* && "$out" == *"rc=3"* ]]; then ok "a missing key file is refused"; else bad "a missing key file is refused" "$out"; fi
    out="$(sdk --model claude-opus-5-5 --effort medium --permission-mode dontAsk --max-budget-usd 0 --prompt-file "$WORK/brief.md" --tools ""; echo "rc=$?")"
    jqt "budget 0 → error_max_budget_usd without a model turn" "$(head -1 <<<"$out")" '.subtype == "error_max_budget_usd" and .is_error == true'
    if [[ "$out" == *"rc=1"* ]]; then ok "… exit 1"; else bad "… exit 1" "$out"; fi
    jqt "check: availability reported with reasons" "$(MAESTRO_API_KEY_FILE="$WORK/none" "$B/maestro-sdk" --check)" \
      '.available == false and (.reasons | any(test("no key file")))'
  fi
fi

# =============================================================================================
if group T12 "docs consistency"; then
  DOCS=("$ROOT/SKILL.md" "$ROOT"/docs/*.md "$ROOT"/docs/guide/*.md "$ROOT"/README*.md)
  # every helper named in SKILL.md and the docs exists (run ids, stashes and repo names excluded)
  missing=""
  while read -r h; do [[ -x "$B/$h" ]] || missing+="$h "; done < <(grep -ohE '\bmaestro-[a-z]+\b' "${DOCS[@]}" \
    | grep -vxE 'maestro-(a|c|draft|integrated|skill|tests|probe|checks)' | sort -u)
  eq "every helper named in the docs exists" "" "$missing"
  # every `SKILL.md "<section>"` reference names a heading or a bold paragraph lead of SKILL.md
  missing=""
  while read -r sec; do
    { grep -E '^#+ ' "$ROOT/SKILL.md" | grep -qF -- "$sec"; } || grep -qF -- "**$sec" "$ROOT/SKILL.md" || missing+="[$sec] "
  done < <(grep -ohE 'SKILL\.md,? "[^"]+"' "$ROOT"/docs/*.md "$ROOT"/docs/guide/*.md | sed -E 's/^SKILL\.md,? "(.*)"$/\1/' | sort -u)
  eq "every SKILL.md section reference resolves" "" "$missing"
  # every A-entry SKILL.md points at exists in docs/unattended.md
  missing=""
  while read -r a; do grep -qE "^\| $a \|" "$ROOT/docs/unattended.md" || missing+="$a "; done \
    < <(grep -ohE '\bA[0-9]+[a-z]?\b' "$ROOT/SKILL.md" | sort -u)
  eq "every A-entry named in SKILL.md exists" "" "$missing"
  # every docs/ page SKILL.md points at exists
  missing=""
  while read -r d; do [[ -e "$ROOT/$d" ]] || missing+="$d "; done < <(grep -ohE 'docs/[a-z/_-]+\.(md|json)' "$ROOT/SKILL.md" | sort -u)
  eq "every docs/ page SKILL.md names exists" "" "$missing"
  # SKILL.md's roster table agrees with bin/slots.json (family and transport order of every slot)
  roster="$(awk -F'|' '/^\| `[a-z]+` \|/ { gsub(/[` ]/, "", $2); gsub(/^ +| +$/, "", $4); gsub(/ /, "", $5); print $2 "|" tolower($4) "|" $5 }' "$ROOT/SKILL.md" | grep -v '^self|' | sort)"
  want="$(jq -r 'del(._comment) | to_entries[] | "\(.key)|\(.value.family)|\(.value.transports | join("→"))"' "$B/slots.json" | sort)"
  eq "SKILL.md roster = bin/slots.json" "$want" "$roster"
  # every fixed block maestro-brief prints appears verbatim in docs/briefs.md (blockquotes joined)
  norm() { sed -E 's/^> ?//; s/\*"/"/g; s/"\*/"/g' | tr -s ' \n' '  '; }
  doc="$(norm < "$ROOT/docs/briefs.md")" missing=""
  while IFS= read -r blk; do
    [[ "$doc" == *"$(norm <<<"$blk" | sed 's/ $//')"* ]] || missing+="[${blk:0:40}…] "
  done < <("$B/maestro-brief" --print-blocks)
  eq "maestro-brief blocks = docs/briefs.md" "" "$missing"
  out="$("$B/maestro-brief" close --role builder --transport claude-cli --unattended)"
  if [[ "$out" == *"edit files only"* && "$out" != *"timeout"* && "$out" == *"do not decide it"* ]]; then ok "brief: edits-only builder, unattended"; else bad "brief: edits-only builder, unattended" "$out"; fi
  out="$("$B/maestro-brief" close --role fix --transport codex --worktree)"
  if [[ "$out" == *"Do not run tests; the director will."* && "$out" != *"timeout"* ]]; then ok "brief: worktree writer"; else bad "brief: worktree writer" "$out"; fi
  eq "brief: no agy opening for a Codex critic" "" "$("$B/maestro-brief" open --role critic --transport codex)"
  out="$("$B/maestro-brief" close --role builder --transport codex --schema "$ROOT/docs/schemas/gate-schema.json" 2>&1; echo "rc=$?")"
  if [[ "$out" == *"read-only role"* && "$out" == *rc=2* ]]; then ok "brief: --schema refused for a writer"; else bad "brief: --schema refused for a writer" "$out"; fi
  # Removed in 2.0.0: the third-party transport, its model line and family, non-Claude-Code hosts.
  # Allowed: CHANGELOG history, maestro-host's detection of other agent CLIs (to refuse them),
  # maestro-flags' message for the removed --host flag, and one "Removed in 2.0.0" line per page.
  # shellcheck disable=SC2016  # a literal $maestro (Codex's skill trigger), case-sensitive: $MAESTRO is ours
  hits="$(cd "$ROOT" && { git grep --untracked -niE 'cursor|grok|xai|agent -p|--host=' -- . \
            ':!CHANGELOG.md' ':!bin/maestro-host' ':!tests/run.sh' ':!tests/fixtures'
          git grep --untracked -nE '\$maestro\b' -- . ':!CHANGELOG.md' ':!tests/run.sh'; } \
          | grep -vE 'Removed in 2\.0\.0|Usunięte w 2\.0\.0' | grep -vE '^bin/maestro-flags:.*--host was removed' || true)"
  eq "nothing left of the removed transport and hosts" "" "$hits"
fi

# =============================================================================================
if group T13 "effective identity"; then
  CH="$WORK/codexhome"; mkdir -p "$CH/sessions/2026/11/14"
  RO="$CH/sessions/2026/11/14/rollout-2026-11-14T10-00-00-th1.jsonl"
  ro_tc() {  # ro_tc <sandbox> <model> <effort> <writable root|""> [extra jq]
    jq -cn --arg sb "$1" --arg m "$2" --arg e "$3" --arg w "$4" '{type: "turn_context", payload: {model: $m, effort: $e,
      sandbox_policy: ({type: $sb} + (if $sb == "workspace-write" then {network_access: false} else {} end)),
      approval_policy: "never", approvals_reviewer: "user", cyber_access_program: "standard",
      permission_profile: {type: "managed", network: "restricted", file_system: {type: "restricted",
        entries: ([{path: {type: "special", value: {kind: "root"}}, access: "read"}]
                  + (if $w != "" then [{path: {type: "path", path: $w}, access: "write"},
                                       {path: {type: "special", value: {kind: "slash_tmp"}}, access: "write"}] else [] end))}}}}'"${5:-}"
  }
  idc() { CODEX_HOME="$CH" "$B/maestro-identity" codex --thread th1 --wait 0 "$@"; }
  { echo '{"type":"session_meta"}'; ro_tc read-only gpt-6.1-sol high ""; } > "$RO"
  jqt "codex critic, read-only rollout → OK" "$(idc --role critic --model gpt-6.1-sol --effort high)" '.result == "OK" and .effective_config.sandbox == "read-only"'
  jqt "codex: wrong effort → MISMATCH" "$(idc --role critic --model gpt-6.1-sol --effort medium)" '.result == "MISMATCH" and (.mismatches | index("effort=high") != null)'
  jqt "codex: a critic on a writer profile → MISMATCH" "$(idc --role builder --root /r --model gpt-6.1-sol --effort high)" '.result == "MISMATCH"'
  ro_tc workspace-write gpt-6.1-sol medium /r >> "$RO"
  jqt "codex resume: the record after the offset is the one checked" "$(idc --role builder --root /r --offset 2 --model gpt-6.1-sol --effort medium)" '.result == "OK"'
  jqt "codex resume: a writer outside its root → MISMATCH" "$(idc --role builder --root /other --offset 2 --model gpt-6.1-sol --effort medium)" '.mismatches | any(test("writable="))'
  jqt "codex: no record after the offset → MISSING" "$(idc --role critic --offset 3 --model gpt-6.1-sol --effort high)" '.result == "MISSING"'
  ro_tc read-only gpt-6.1-sol high "" ' | .payload.cyber_access_program = "extended"' >> "$RO"
  jqt "codex: cyber_access_program other than standard → MISMATCH" "$(idc --role critic --offset 3 --model gpt-6.1-sol --effort high)" '.mismatches | any(test("cyber_access_program"))'
  printf '{"type":"turn_context","payload":' >> "$RO"; printf '\n' >> "$RO"
  jqt "codex: truncated record → MISMATCH malformed" "$(idc --role critic --offset 4 --model gpt-6.1-sol --effort high)" '.result == "MISMATCH" and .mismatches == ["malformed turn_context"]'
  cp "$RO" "${RO%th1.jsonl}x-th1.jsonl"
  jqt "codex: two rollouts for one thread → MISSING" "$(idc --role critic --model gpt-6.1-sol --effort high)" '.result == "MISSING"'
  out="$(idc --role critic --model m --effort e --thread ../x 2>&1; echo "rc=$?")"
  if [[ "$out" == *rc=1* || "$out" == *rc=2* ]]; then ok "codex: exit non-zero when not OK"; else bad "codex: exit non-zero when not OK" "$out"; fi
  CI="$WORK/init.jsonl"
  mkinit() { jq -cn --argjson x "${1:-{\}}" '{type: "system", subtype: "init", model: "claude-sonnet-5-5", tools: ["Read","Grep","Glob"],
    mcp_servers: [], plugins: [{name: "b", source: "b@builtin"}], plugin_errors: [], permissionMode: "dontAsk", apiKeySource: "none"} + $x' > "$CI"; }
  idl() { "$B/maestro-identity" claude "$CI" --model claude-sonnet-5-5 --tools "Glob, Read,Grep" --permission-mode dontAsk "$@"; }
  mkinit; jqt "claude init: the role's set, subscription → OK" "$(idl)" '.result == "OK"'
  mkinit '{"plugin_errors":[{"plugin":"x","error":"load failed"}]}'; jqt "claude init: plugin_errors → MISMATCH" "$(idl)" '.mismatches == ["plugin_errors=1"]'
  mkinit '{"mcp_servers":[{"name":"gh","status":"connected"}]}'; jqt "claude init: an MCP server → MISMATCH" "$(idl)" '.mismatches == ["mcp_servers=gh"]'
  mkinit '{"plugins":[{"name":"p","source":"p@market"}]}'; jqt "claude init: a non-builtin plugin → MISMATCH" "$(idl)" '.mismatches | any(test("plugins="))'
  mkinit '{"tools":["Read","Grep","Glob","Bash"]}'; jqt "claude init: an extra tool → MISMATCH" "$(idl)" '.mismatches | any(test("tools="))'
  mkinit '{"apiKeySource":"ANTHROPIC_API_KEY"}'; jqt "claude init: an API key on native → MISMATCH" "$(idl)" '.mismatches == ["apiKeySource=ANTHROPIC_API_KEY"]'
  jqt "claude init: --api expects the key" "$(idl --api)" '.result == "OK"'
  mkinit '{"model":"claude-sonnet-5"}'; jqt "claude init: another model → MISMATCH" "$(idl)" '.mismatches == ["model=claude-sonnet-5"]'
  mkinit; jq -sc '. + [{type: "result", subtype: "success"}]' "$CI" > "$CI.arr"; mv "$CI.arr" "$CI"
  jqt "claude: a --output-format json array transcript is read too" "$(idl)" '.result == "OK"'
  printf '{"type":"result","subtype":"success"}\n' > "$CI"; jqt "claude: no init → MISSING" "$(idl)" '.result == "MISSING"'
  mkinit '{"tools":[]}'; jqt "claude init: --tools \"\" means none" "$("$B/maestro-identity" claude "$CI" --model claude-sonnet-5-5 --tools "" --permission-mode dontAsk)" '.result == "OK"'
fi

# =============================================================================================
if group T14 "preflight"; then
  FB="$WORK/fakebin"; mkdir -p "$FB"
  soon="$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)"
  { echo '#!/bin/sh'; echo "[ \"\$1 \$2\" = 'auth status' ] && echo '{\"loggedIn\":true,\"authMethod\":\"claude.ai\",\"loginExpiresAt\":\"$soon\"}'"; } > "$FB/claude"
  cat > "$FB/codex" <<'SH'
#!/bin/sh
case "$1" in
  login) echo "Logged in using ChatGPT"; exit "${FAKE_CODEX_LOGIN_RC:-0}" ;;
  doctor) echo "21 ok · 0 warn · ${FAKE_CODEX_FAILS:-0} fail ok" ;;
  --version) echo "codex-cli 0.169.0" ;;
esac
SH
  cat > "$FB/agy" <<'SH'
#!/bin/sh
case "$1" in models) printf 'Fetching available models...\ngemini-4-hydrogen-high\tH\n' ;; --version) echo 1.5.9 ;; esac
SH
  chmod +x "$FB"/*
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  g="$("$B/maestro-lock" acquire --run r --token t --host test | jq -r .fence)"
  CHM="$WORK/pf-codexhome"; mkdir -p "$CHM"
  pf() { PATH="$FB:$PATH" CODEX_HOME="$CHM" "$B/maestro-preflight" --gen "$g" "$@"; }
  out="$(pf --interactive false)"
  jqt "preflight: every transport available, isolated config, no stops" "$out" \
    '.stops == [] and .transports.native.available and .transports.codex.available and .transports.codex.version == "0.169.0"
     and .transports.agy.available and .codex_config.mode == "isolated" and .git.objects and .git.index_file and .git.refs'
  jqt "preflight: a login that expires within a day is a warning" "$out" '.warnings | any(test("login expires"))'
  eq "preflight: .maestro/ excluded once, schemas copied" "1 4" "$(grep -cxF '.maestro/' "$(git rev-parse --git-path info/exclude)") $(find .maestro -maxdepth 1 -name '*-schema.json' | wc -l)"
  pf --interactive false >/dev/null
  eq "preflight: a second run does not add the exclude line again" 1 "$(grep -cxF '.maestro/' "$(git rev-parse --git-path info/exclude)")"
  printf 'model_provider = "corp"\n[mcp_servers.x]\nauth_token = "y"\n[profiles.p]\nopenai_base_url = "https://x"\n' > "$CHM/config.toml"
  jqt "preflight: a connection key in config.toml → pinned, named; mcp_servers keys ignored" "$(pf)" \
    '.codex_config.mode == "pinned" and .codex_config.pinned_by == ["model_provider","profiles.p.openai_base_url"]'
  rm "$CHM/config.toml"
  jqt "preflight: codex doctor failure → codex unavailable" "$(FAKE_CODEX_FAILS=2 pf)" '.transports.codex.available == false and (.transports.codex.reason | test("2 fail"))'
  jqt "preflight: codex logged out → unavailable" "$(FAKE_CODEX_LOGIN_RC=1 pf)" '.transports.codex.available == false'
  jqt "preflight: --no-codex skips it" "$(pf --no-codex)" '.transports.codex.reason == "off by policy"'
  mkdir -p .codex; printf 'default_permissions = "ro"\n' > .codex/config.toml
  out="$(pf)"
  jqt "preflight: a dirty tree is a stop" "$out" '.tree.clean == false and (.stops | any(test("not clean")))'
  jqt "preflight: project default_permissions is a warning" "$out" '.warnings | any(test("default_permissions"))'
  jqt "preflight: --resume reports a dirty tree without a stop" "$(pf --resume)" '.tree.clean == false and .stops == []'
  rm -rf .codex; mkdir -p .claude/skills/maestro; : > .claude/skills/maestro/SKILL.md
  jqt "preflight: an untracked project install of the skill is not a dirty tree" "$(pf)" '.tree.clean == true and .stops == []'
  rm -r .claude
  rm -rf .codex
  eq "preflight: no probe residue (refs, index files, state files)" "0 0 0" "$(git for-each-ref refs/maestro | wc -l) $(find "$(git rev-parse --absolute-git-dir)" -maxdepth 1 -name 'maestro-probe-*' | wc -l) $(find .maestro -maxdepth 1 -name 'probe-*' | wc -l)"
  UB="$WORK/unborn"; mkdir -p "$UB"; git -C "$UB" init -q -b main
  gu="$(cd "$UB" && "$B/maestro-lock" acquire --run u --token t --host test | jq -r .fence)"
  jqt "preflight: an unborn HEAD passes the git probes, the worktree probe is skipped with a warning" \
    "$(cd "$UB" && PATH="$FB:$PATH" CODEX_HOME="$CHM" "$B/maestro-preflight" --gen "$gu" --worktree)" \
    '.git == {objects: true, index_file: true, refs: true} and .stops == [] and (.warnings | any(test("unborn")))'
  chmod a-w "$(git rev-parse --absolute-git-dir)/refs/maestro" 2>/dev/null || { mkdir -p "$(git rev-parse --absolute-git-dir)/refs/maestro"; chmod a-w "$(git rev-parse --absolute-git-dir)/refs/maestro"; }
  jqt "preflight: a git write that fails is a stop (refs read-only)" "$(pf)" '.git.refs == false and (.stops | any(test("git refs write failed")))'
  chmod u+w "$(git rev-parse --absolute-git-dir)/refs/maestro"
  "$B/maestro-lock" acquire --run r2 --token t2 --host test >/dev/null 2>&1 || true
  out="$(PATH="$FB:$PATH" "$B/maestro-preflight" --gen 999.x 2>&1; echo "rc=$?")"
  if [[ "$out" == *rc=4* && "$out" == *superseded* ]]; then ok "preflight: a stale fence stops it (exit 4)"; else bad "preflight: a stale fence stops it (exit 4)" "$out"; fi
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T15 "flags"; then
  fl() { "$B/maestro-flags" "$@"; }
  jqt "flags anywhere, task text kept in order" "$(fl "add --model=opus@agy a thing --critic=sol,argon --rounds=3")" \
    '.task == "add a thing" and .flags.model == {slot: "opus", transport: "agy"} and (.flags.critics | map(.slot)) == ["sol","argon"] and .flags.rounds == 3 and .errors == []'
  jqt "a multi-line argument string keeps every line" "$(fl $'build a page\nwith OAuth --model=sol')" '.task == "build a page with OAuth" and .flags.model.slot == "sol"'
  jqt "a lone -- ends the flags: --words after it are task text" "$(fl "--model=opus -- add a --verbose option")" '.task == "add a --verbose option" and .flags.model.slot == "opus" and .errors == []'
  jqt "a near-miss flag gets a did-you-mean" "$(fl "--modle=opus x")" '.errors == ["unknown flag --modle=opus (did you mean --model?)"]'
  jqt "a far unknown flag names the -- escape" "$(fl "add a --verbose option")" '.errors[0] | test("lone --")'
  jqt "separate words work like one string" "$(fl --review x y)" '.flags.review == "full" and .task == "x y"'
  jqt "--reviewer alone implies --review=full" "$(fl --reviewer=sol t)" '.flags.review == "full" and .flags.reviewer.slot == "sol"'
  jqt "--tests=browser means covering,browser" "$(fl --tests=browser t)" '.flags.tests == {scope: "covering", browser: true}'
  jqt "--cascade defaults to luna" "$(fl --cascade t)" '.flags.cascade == "luna"'
  jqt "--resume: the rest is the answer" "$(fl --resume --unattended opcja 2)" '.flags.resume and .flags.unattended and .task == "opcja 2" and .errors == []'
  for c in "--model=grok:unknown slot grok" "--model=sonnet@cursor:has no transport cursor" "--model=fable@agy:has no transport agy" \
           "--critic=self:self only builds" "--model=self@native:self takes no" "--review=half:--review is full" \
           "--rounds=9:--rounds is 1 to 8" "--tests=covering,full:two scopes" "--tests=all:unknown value" \
           "--cascade=grok:drafter is luna" "--host=codex:--host was removed" "--frobnicate:unknown flag" \
           "--setup=yes:takes no value" "--model=opus --model=sol:given twice"; do
    a="${c%%:*}" want="${c#*:}"
    # shellcheck disable=SC2086  # "a" may hold two flags
    out="$(fl $a t)"; rc=$?
    if [[ $rc -ne 0 ]] && jq -e --arg w "$want" '.errors | any(contains($w))' >/dev/null <<<"$out"; then ok "flag error: $a"; else bad "flag error: $a" "$out"; fi
  done
  for c in "--plan-only --cascade:--plan-only with --cascade" "--plan-only --review:--plan-only with --review" \
           "--plan-only --reviewer=sol:--plan-only with --review" "--reviewer=sol --review=self:--reviewer with --review=self" \
           "--tests=full --skip-tests:--tests with --skip-tests" "--cascade --model=luna:--cascade with --model=luna" \
           "--cascade=haiku --model=haiku:--cascade with --model=haiku" "--cascade=gemini --model=gemini:--cascade: the drafter is the implementer" \
           "--cascade --skip-tests:--cascade with --skip-tests" "--setup --unattended:--setup with --unattended" \
           "--sdk --model=opus@native:--sdk with a forced @native" "--sdk --critic=sonnet@native:--sdk with a forced @native" \
           "--resume --rounds=2:--resume with --rounds"; do
    a="${c%%:*}" want="${c#*:}"
    # shellcheck disable=SC2086
    out="$(fl $a t)"; rc=$?
    if [[ $rc -ne 0 ]] && jq -e --arg w "$want" '.errors | any(contains("illegal combination: " + $w))' >/dev/null <<<"$out"; then ok "illegal: $a"; else bad "illegal: $a" "$out"; fi
  done
  jqt "every slot of slots.json parses as --model" "$(for x in $(jq -r 'del(._comment) | keys[]' "$B/slots.json"); do fl --model="$x" t | jq -c .errors; done | jq -sc 'add')" '. == []'
fi

# =============================================================================================
if group T16 "status"; then
  REPO="$(new_repo)"; cd "$REPO" || exit 2
  jqt "status: nothing in a fresh checkout" "$("$B/maestro-status" --json)" '.run_id == null and .lock == null and .jobs == []'
  eq "status: text for a fresh checkout" "no maestro run in this checkout" "$("$B/maestro-status")"
  g="$("$B/maestro-lock" acquire --run rs --token t --host test | jq -r .fence)"
  printf -- '---\nskill: maestro\nrun_id: rs\ntask: "add repeat"\nstage: build   # comment\nround: 2\nnext_action: "wait for the build"\ndecisions:\n  current: {id: d-rs-1, question: "x"}\n  history: []\n---\n' \
    | "$B/maestro-state" --gen "$g" write CHECKPOINT.md >/dev/null
  "$B/maestro-run" --gen "$g" --job rs.build.r2.a1 --run rs --role build -- sleep 5 >/dev/null
  printf '%s\n' '{"run_id":"rs","total_tokens":100,"transport":"codex"}' '{"run_id":"rs","total_tokens":50,"transport":"api","cost_usd":0.25}' '{"run_id":"other","total_tokens":9}' > .maestro/ledger.jsonl
  out="$("$B/maestro-status" --json)"
  jqt "status: checkpoint scalars, the open decision, the live job, ledger of this run, the lock" "$out" \
    '.run_id == "rs" and .task == "add repeat" and .stage == "build" and .round == 2 and .next_action == "wait for the build"
     and .decisions_open == 1 and (.jobs | length) == 1 and .jobs[0].state == "running"
     and .ledger == {calls: 2, total_tokens: 150, api_usd: 0.25} and .lock.run_id == "rs"'
  txt="$("$B/maestro-status")"
  if [[ "$txt" == *"stage build round 2"* && "$txt" == *"1 open decision"* && "$txt" == *"rs.build.r2.a1 running"* && "$txt" == *"api \$0.25"* ]]; then ok "status: text lines"; else bad "status: text lines" "$txt"; fi
  "$B/maestro-wait" rs.build.r2.a1 --max 20 >/dev/null
  cd "$ROOT" || exit 2
fi

# =============================================================================================
if group T17 "limits"; then
  LS="$WORK/limits"; mkdir -p "$LS/jobs/j1" "$LS/codex/sessions/2026/11/14"
  printf '%s\n' '{"type":"system","subtype":"init"}' \
    '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","resetsAt":1794805200,"rateLimitType":"seven_day","utilization":0.93}}' > "$LS/jobs/j1/out"
  printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1794902332},"secondary":{"used_percent":83.0,"window_minutes":10080,"resets_at":1794902999},"plan_type":"pro"}}}' \
    > "$LS/codex/sessions/2026/11/14/rollout-2026-11-14T10-00-00-x.jsonl"
  out="$(MAESTRO_STATE="$LS" CODEX_HOME="$LS/codex" "$B/maestro-limits")"
  jqt "limits: claude from the newest rate_limit_event" "$out" '.claude.utilization == 0.93 and .claude.window == "seven_day" and .claude.stale == false'
  jqt "limits: codex takes the fuller of its windows" "$out" '.codex.utilization == 0.83 and .codex.window == "168 h" and .codex.plan == "pro"'
  jqt "limits: agy unknown" "$out" '.agy.utilization == null'
  jqt "limits: >= 90% is a warning" "$out" '(.warnings | length) == 1 and (.warnings[0] | test("^claude at 93%"))'
  touch -d '-8 hours' "$LS/jobs/j1/out"
  jqt "limits: an old record is stale" "$(MAESTRO_STATE="$LS" CODEX_HOME="$LS/codex" "$B/maestro-limits")" '.claude.stale == true and (.warnings[0] | test("min old"))'
  jqt "limits: no sources → reasons, no warnings" "$(MAESTRO_STATE="$WORK/none-l" CODEX_HOME="$WORK/none-c" "$B/maestro-limits")" \
    '.claude.utilization == null and .codex.utilization == null and .warnings == []'
fi

_gtime
printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then printf '  %s\n' "${failed[@]}"; exit 1; fi
