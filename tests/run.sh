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

  # This machine's catalogs (2026-11-24: Codex 0.172.0, agy 1.5.16): GPT-6.2, Gemini 4 Carbon and Neon.
  M2="$FX/catalogs/machine-2026-11-24"
  out="$(MAESTRO_STATE="$WORK/c7" "$B/maestro-catalog" refresh --fixtures "$M2" --out "$WORK/c7/catalog.json")"
  cat2="$WORK/c7/catalog.json"
  cand2() { "$B/maestro-catalog" candidates "$1" "$2" --catalog "$cat2"; }
  jqt "machine 11-24: sol → gpt-6.2-sol first, then 6.1, 6, 5.6" "$(cand2 sol codex)" \
    '(map(.slugs.default)) == ["gpt-6.2-sol","gpt-6.1-sol","gpt-6-sol","gpt-5.6-sol"]'
  jqt "machine 11-24: astra → gpt-6.2-astra first, then gpt-6-astra" "$(cand2 astra codex)" '(map(.slugs.default)) == ["gpt-6.2-astra","gpt-6-astra"]'
  jqt "machine 11-24: carbon → gemini-4-carbon, low…high" "$(cand2 carbon agy)" \
    '.[0].version == [4] and .[0].slugs == {"medium":"gemini-4-carbon-medium","high":"gemini-4-carbon-high","low":"gemini-4-carbon-low"} and length == 1'
  jqt "machine 11-24: neon → gemini-4-neon, low…xhigh" "$(cand2 neon agy)" \
    '.[0].version == [4] and length == 1 and .[0].slugs == {"high":"gemini-4-neon-high","xhigh":"gemini-4-neon-xhigh","medium":"gemini-4-neon-medium","low":"gemini-4-neon-low"}'
  jqt "machine 11-24: gemini → hydrogen 4 (Carbon and Neon are not mixed in), then flash 3.8" "$(cand2 gemini agy)" \
    '(map(.version)) == [[4],[3,8]] and .[0].slugs == {"high":"gemini-4-hydrogen-high","xhigh":"gemini-4-hydrogen-xhigh","medium":"gemini-4-hydrogen-medium","low":"gemini-4-hydrogen-low"}
     and .[1].slugs == {"high":"gemini-3.8-flash-high","medium":"gemini-3.8-flash-medium","low":"gemini-3.8-flash-low"}'
  jqt "machine 11-24: argon unchanged" "$(cand2 argon agy)" '.[0].slugs.high == "gemini-4-argon-high"'
  jqt "machine 11-24: all three orchestrator slugs (the unsuffixed Carbon one too) and gpt-oss unmatched" "$(cat "$cat2")" \
    '(.transports.agy.unmatched | sort) == ["gemini-pro-orchestrator","gemini-pro-orchestrator-argon","gemini-pro-orchestrator-neon","gpt-oss-120b-medium"] and .transports.codex.unmatched == []'
  jqt "machine 11-24: codex client 0.172.0, identity from the cache" "$out" '.sources.codex.client_version == "0.172.0" and .sources.codex.identity == "fixture-identity"'
  pickm2() { MAESTRO_STATE="$WORK/c7" "$B/maestro-catalog" pick "$@" --catalog "$cat2"; }
  jqt "machine 11-24: pick neon xhigh → the full slug" "$(pickm2 neon agy --effort xhigh)" '.action == "probe" and .slug == "gemini-4-neon-xhigh" and .version == "4"'
  jqt "machine 11-24: pick carbon high → the full slug" "$(pickm2 carbon agy --effort high)" '.slug == "gemini-4-carbon-high"'
  jqt "machine 11-24: carbon has no xhigh" "$(pickm2 carbon agy --effort xhigh)" '.action == "none"'
  jqt "machine 11-24: pick sol → gpt-6.2-sol until the account probe says otherwise" "$(pickm2 sol codex --effort medium)" '.action == "probe" and .slug == "gpt-6.2-sol"'
  jqt "machine 11-24: pin 6.1 keeps gpt-6.1-sol" "$(pickm2 sol codex --pin 6.1)" '.slug == "gpt-6.1-sol"'
  jqt "machine 11-24: an orchestrator slug cannot be pinned to neon" "$(pickm2 neon agy --pin-slug gemini-pro-orchestrator-neon)" '.action == "none" and (.reason | test("not a neon model"))'
  jqt "machine 11-24: a neon slug cannot be pinned to gemini" "$(pickm2 gemini agy --pin-slug gemini-4-neon-high)" '.action == "none"'

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
  # ud <job> [options…]: maestro-wait --until-done → $ud_out, $ud_rc, $ud_s (seconds it took).
  ud() { local t0; t0="$(date +%s)"; ud_rc=0; ud_out="$("$B/maestro-wait" "$1" --until-done "${@:2}")" || ud_rc=$?; ud_s=$(( $(date +%s) - t0 )); }
  run --job j0 -- bash -c 'exit 0' >/dev/null; sleep 1.5
  jqt "exit 0 → exited 0" "$("$B/maestro-wait" j0 --max 10)" '.state == "exited" and .code == "0"'
  jqt "meta.json: run, host from the lock record, no empty strings" "$(cat .maestro/jobs/j0/meta.json)" \
    '.run_id == "r" and .host == "test" and .session_key == null'
  jqt "… and the ledger row takes run and host from it" \
    "$("$B/maestro-ledger" --dry-run --job j0 --stage build --cli codex --transport codex --family openai --model m)" \
    '.run_id == "r" and .host == "test" and .exit_code == "0"'
  run --job j1 -- bash -c 'exit 3' >/dev/null
  jqt "non-zero → exited 3" "$("$B/maestro-wait" j1 --max 10)" '.state == "exited" and .code == "3"'
  # --until-done: no cap of its own (MAESTRO_WAIT_MAX does not apply), the final state, exit 0.
  run --job ju0 -- bash -c 'sleep 4; exit 7' >/dev/null
  MAESTRO_WAIT_MAX=0 ud ju0
  jqt "--until-done: an exiting job → its final state" "$ud_out" '.state == "exited" and .code == "7"'
  eq "… exit 0, one line, after the job ended (MAESTRO_WAIT_MAX ignored)" "0 1 1" "$ud_rc $(wc -l <<<"$ud_out") $(( ud_s >= 3 ))"
  out="$("$B/maestro-wait" ju0 --until-done --peek 2>&1)" && rc=0 || rc=$?
  eq "--until-done with --peek is refused" 2 "$rc"
  run --job j2 -- no-such-command-xyz >/dev/null
  jqt "launch failure" "$(st j2)" '.state == "exited" and .code == "launch-failed"'
  out="$(run --job j1 -- true 2>&1)"; eq "duplicate job id refused" 1 "$(grep -c 'never reused' <<<"$out")"
  printf '#!/bin/bash\n(sleep 90 &)\nexit 0\n' > "$REPO/linger.sh"; chmod +x "$REPO/linger.sh"
  run --job j3 -- ./linger.sh >/dev/null; sleep 3
  jqt "exit 0 with a surviving descendant → lingering" "$(st j3)" '.state == "lingering" and (.live_members | length) == 1'
  ud j3
  jqt "--until-done returns on lingering (only maestro-kill ends it)" "$ud_out" '.state == "lingering"'
  eq "… exit 0, at once" "0 1" "$ud_rc $(( ud_s < 5 ))"
  run --job j4 -- bash -c 'sleep 30' >/dev/null; sleep 1.5
  jqt "running" "$(st j4)" '.state == "running"'
  ud j4 --max 3
  jqt "--until-done keeps waiting while running" "$ud_out" '.state == "running"'
  eq "… for the whole --max, then exit 3 (no final state)" "3 1" "$ud_rc $(( ud_s >= 3 ))"
  pid4="$(jq -r .pid .maestro/jobs/j4/meta.json)"; kill -9 "$pid4"; sleep 2.5
  jqt "leader killed by a signal → exited signal:9" "$(st j4)" '.state == "exited" and .code == "signal:9"'
  # Orphaned: the wrapper and the leader die, a member survives.
  printf '#!/bin/bash\nsleep 25 &\nsleep 25\n' > "$REPO/orph.sh"; chmod +x "$REPO/orph.sh"
  run --job j5 -- ./orph.sh >/dev/null; sleep 2.5
  w5="$(jq -r .wrapper_pid .maestro/jobs/j5/meta.json)"; p5="$(jq -r .pid .maestro/jobs/j5/meta.json)"
  kill -9 "$w5" "$p5"; sleep 1
  jqt "leader and wrapper gone, member alive → orphaned" "$(st j5)" '.state == "orphaned"'
  ud j5
  jqt "--until-done returns on orphaned" "$ud_out" '.state == "orphaned"'
  eq "… exit 0, at once" "0 1" "$ud_rc $(( ud_s < 5 ))"
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
  MAESTRO_PROC="$WORK/noproc" ud j10
  jqt "--until-done returns on uncertain without a live leader" "$ud_out" '.state == "uncertain" and (.leader_alive // false) == false'
  eq "… exit 0, at once" "0 1" "$ud_rc $(( ud_s < 5 ))"
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
  MAESTRO_PROC="$UP" ud j18 --max 3
  jqt "--until-done keeps waiting on uncertain with a live leader" "$ud_out" '.state == "uncertain" and .leader_alive == true'
  eq "… for the whole --max, then exit 3" "3 1" "$ud_rc $(( ud_s >= 3 ))"
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
  jqt "decide critique: reject → not approved" "$(dc "$(crit reject "[$FND]" '[]' '[]')" --decide critique --ids "")" \
    '.valid and .decision.approved == false and (.decision.reasons | index("verdict reject") != null)'
  out="$(dc "$(crit approve '[]' "[$FND]" '[]')" --decide critique --ids "")"; rc=$?
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
    "$(dc "$(crit revise '[]' '[]' '[{"id":"r1-m1","status":"resolved","note":"n"},{"id":"r1-m1","status":"not_resolved","note":"n"}]')" --decide critique --ids r1-m1)" '.valid == false and (.errors[0] | test("listed twice"))'
  jqt "decide critique: empty trigger → invalid" "$(dc "$(crit revise '[]' "[$(jq -c '.trigger = "  "' <<<"$FND")]" '[]')" --decide critique --ids "")" \
    '.valid == false and .stage == "decide" and (.errors[0] | test("major_findings\\[0\\].trigger: empty"))'
  jqt "decide: a schema failure is never approved" "$("$B/maestro-validate" "$S" "$V/wrong-enum.txt" --decide critique --ids "")" \
    '.valid == false and .stage == "schema" and .decision.approved == false'
  jqt "decide: an envelope failure is never approved" "$("$B/maestro-validate" "$S" "$V/agy-canceled.json" --envelope agy --decide critique --ids "")" \
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
  jqt "decide arbiter: no verdicts → not approved" "$(da '{"verdicts":[],"assumptions":[]}' --decide arbiter --ids "")" '.valid and .decision == {approved: false, reasons: ["no verdicts"]}'
  jqt "decide arbiter: a disputed id without a verdict → invalid" \
    "$(da '{"verdicts":[{"id":"r1-m1","decision":"downgraded","reason":"r"}],"assumptions":[]}' --decide arbiter --ids r1-m1,r2-m1)" \
    '.valid == false and .stage == "decide" and (.errors[0] | test("r2-m1 sent but not answered")) and .decision.approved == false'
  jqt "decide: the wrong schema for the decision → invalid, not a jq error" "$(da '{"verdicts":[],"assumptions":[]}' --decide critique --ids "")" '.valid == false and .stage == "decide"'
  if "$B/maestro-validate" "$S" "$V/valid.txt" --decide gate >/dev/null 2>&1; then bad "decide: unknown kind refused"; else ok "decide: unknown kind refused"; fi
  if "$B/maestro-validate" "$S" "$V/valid.txt" --ids r1-m1 >/dev/null 2>&1; then bad "--ids without --decide refused"; else ok "--ids without --decide refused"; fi
  # the advice schema (--advisor) and the length and cardinality keywords
  ADV="$ROOT/docs/schemas/advice-schema.json"
  adv() { jq -cn '{advice: "use one CTE", agrees_with_plan: true, risks: [{text: "t", applies_to: "PLAN 2"}], questions_back: [], assumptions: []} | '"${1:-.}" > "$WORK/advice.json"
          "$B/maestro-validate" "$ADV" "$WORK/advice.json" --envelope raw; }
  RISK='{text: "r", applies_to: "s"}'
  jqt "advice schema: every object closed, every property required" \
    "$(jq '[ .. | objects | select(.type == "object") | (.additionalProperties == false and ((.properties | keys) == (.required | sort))) ] | all' "$ADV")" '. == true'
  jqt "advice schema: a valid answer" "$(adv)" '.valid and .errors == []'
  jqt "advice schema: five risks and three questions back are still valid" "$(adv ".risks = [$RISK,$RISK,$RISK,$RISK,$RISK] | .questions_back = [\"a\",\"b\",\"c\"] | .agrees_with_plan = false")" '.valid'
  jqt "advice schema: empty advice → invalid (minLength)" "$(adv '.advice = ""')" '.valid == false and .stage == "schema" and .errors == ["$.advice: 0 characters, below minLength 1"]'
  jqt "advice schema: advice over 3000 characters → invalid (maxLength)" "$(adv '.advice = ([range(3001)] | map("x") | add)')" '.valid == false and .errors == ["$.advice: 3001 characters, above maxLength 3000"]'
  jqt "advice schema: exactly 3000 characters → valid" "$(adv '.advice = ([range(3000)] | map("é") | add)')" '.valid'
  jqt "advice schema: six risks → invalid (maxItems)" "$(adv ".risks = [$RISK,$RISK,$RISK,$RISK,$RISK,$RISK]")" '.valid == false and .errors == ["$.risks: 6 items, above maxItems 5"]'
  jqt "advice schema: four questions back → invalid (maxItems)" "$(adv '.questions_back = ["a","b","c","d"]')" '.valid == false and .errors == ["$.questions_back: 4 items, above maxItems 3"]'
  jqt "advice schema: assumptions missing → invalid" "$(adv 'del(.assumptions)')" '.valid == false and .errors == ["$: missing required assumptions"]'
  jqt "advice schema: an unknown key → invalid" "$(adv '.verdict = "approve"')" '.valid == false and .errors == ["$: unexpected key verdict"]'
  jqt "advice schema: agrees_with_plan must be a boolean" "$(adv '.agrees_with_plan = "yes"')" '.valid == false and (.errors[0] | test("agrees_with_plan: expected boolean"))'
  jqt "advice schema: a risk without applies_to → invalid" "$(adv '.risks = [{text: "r"}]')" '.valid == false and .errors == ["$.risks[0]: missing required applies_to"]'
  adv >/dev/null; jq -c '{status: "SUCCESS", response: "", structured_output: .}' "$WORK/advice.json" > "$WORK/advice-agy.json"
  jqt "advice schema: through an agy envelope (structured_output)" "$("$B/maestro-validate" "$ADV" "$WORK/advice-agy.json" --envelope agy)" '.valid and .verdict.advice == "use one CTE"'
  printf '{"type":"array","minItems":1,"items":{"type":"string","minLength":2}}' > "$WORK/min-schema.json"
  printf '{"x":[]}' > "$WORK/min0.json"; printf '{"x":["a","bb"]}' > "$WORK/min1.json"
  printf '{"type":"object","properties":{"x":%s}}' "$(cat "$WORK/min-schema.json")" > "$WORK/min-obj.json"
  jqt "validate: minItems is honoured (generic)" "$("$B/maestro-validate" "$WORK/min-obj.json" "$WORK/min0.json")" '.valid == false and .errors == ["$.x: 0 items, below minItems 1"]'
  jqt "validate: minLength on array items (generic)" "$("$B/maestro-validate" "$WORK/min-obj.json" "$WORK/min1.json")" '.valid == false and .errors == ["$.x[0]: 1 characters, below minLength 2"]'
  jqt "no other schema uses the length or cardinality keywords (their checks are unchanged)" \
    "$(jq -s '[ .[] | .. | objects | select(has("minLength") or has("maxLength") or has("minItems") or has("maxItems")) ] | length' \
        "$ROOT/docs/schemas/critique-schema.json" "$ROOT/docs/schemas/gate-schema.json" "$ROOT/docs/schemas/review-schema.json" "$ROOT/docs/schemas/arbiter-schema.json")" '. == 0'
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
  # --advisor: the pre-call snapshot and the advice file live in the git dir, which no fingerprint covers
  GD="$(git rev-parse --git-dir)/maestro"; mkdir -p "$GD" .maestro
  printf '# plan\n' > .maestro/PLAN.md
  "$B/maestro-fp" snapshot > "$GD/fp-adv-1.json"
  printf 'ADVISORY, NOT BINDING\n' > "$GD/advice-adv-1.md"; printf 'x' > "$GD/fp-adv-2.json"
  jqt "advisor: snapshot and advice file in the git dir are not hashed by maestro-fp" "$("$B/maestro-fp" compare "$GD/fp-adv-1.json")" '.result == "same"'
  jqt "… while a change to PLAN.md after that snapshot is still caught" "$(printf 'edited\n' >> .maestro/PLAN.md; "$B/maestro-fp" compare "$GD/fp-adv-1.json")" \
    '.result == "changed" and (.diffs | index("protected .maestro inputs") != null)'
  printf '# plan copy\n' > .maestro/plan-advise-r1.md; printf 'diff\n' > .maestro/diff-advise-r1.patch
  "$B/maestro-fp" snapshot > "$GD/fp-adv-2.json"
  jqt "advisor: an edit of the advisor-facing plan copy (.maestro/plan-advise-r1.md) is caught" \
    "$(printf 'x\n' >> .maestro/plan-advise-r1.md; "$B/maestro-fp" compare "$GD/fp-adv-2.json")" '.result == "changed" and (.diffs | index("protected .maestro inputs") != null)'
  "$B/maestro-fp" snapshot > "$GD/fp-adv-2.json"
  jqt "advisor: an edit of the restricted patch (.maestro/diff-advise-r1.patch) is caught" \
    "$(printf 'x\n' >> .maestro/diff-advise-r1.patch; "$B/maestro-fp" compare "$GD/fp-adv-2.json")" '.result == "changed"'
  "$B/maestro-fp" snapshot > "$GD/fp-adv-2.json"; mkdir -p .maestro/tmp
  jqt "advisor: only the Agent advisor's raw answer in tmp/ is outside the fingerprint" \
    "$(printf '{}' > .maestro/tmp/answer-adv-r-1-a1.json; "$B/maestro-fp" compare "$GD/fp-adv-2.json")" '.result == "same"'
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
  # carbon and neon are explicit-only: eligible changes no automatic choice, naming them does
  ALLX='["opus","fable","sonnet","haiku","astra","sol","luna","terra","argon","carbon","neon","gemini","self"]'
  jqt "explicit-only eligible: claude build still → sol" "$(roles '{"builder":"opus","eligible":'"$ALLX"'}')" '.critics == ["sol"] and .reviewer == "sol"'
  jqt "explicit-only eligible: claude build, hs still → astra + argon" "$(roles '{"builder":"opus","high_stakes":true,"eligible":'"$ALLX"'}')" '.critics == ["astra","argon"]'
  jqt "explicit-only eligible: openai build, hs still → opus + argon" "$(roles '{"builder":"sol","high_stakes":true,"eligible":'"$ALLX"'}')" '.critics == ["opus","argon"]'
  jqt "explicit-only eligible: argon out, hs → astra + gemini (never neon)" "$(roles '{"builder":"opus","high_stakes":true,"eligible":["opus","astra","sol","carbon","neon","gemini"]}')" '.critics == ["astra","gemini"]'
  jqt "explicit-only eligible: only carbon/neon of google → google not counted, no second critic" "$(roles '{"builder":"opus","high_stakes":true,"eligible":["opus","astra","sol","carbon","neon"]}')" \
    '.critics == ["astra"] and (.notes | any(test("no second critic"))) and (.notes | any(test("explicit-only")))'
  jqt "explicit-only: sol build, eligible sol/astra/neon, no names → Astra critic, degraded, no stop" "$(roles '{"builder":"sol","eligible":["sol","astra","neon"]}')" \
    '.critics == ["astra"] and .reviewer == "astra" and .degraded == "openai" and .stop == null'
  jqt "explicit-only: --reviewer=neon is the reviewer only; the critic stays Astra, degraded" "$(roles '{"builder":"sol","eligible":["sol","astra","neon"],"named_reviewer":"neon"}')" \
    '.critics == ["astra"] and .reviewer == "neon" and .degraded == "openai" and .stop == null and (.notes | any(test("neon is provisional")))'
  jqt "explicit-only: a policy reviewer neon likewise" "$(roles '{"builder":"sol","eligible":["sol","astra","neon"],"policy_reviewer":"neon"}')" '.critics == ["astra"] and .reviewer == "neon" and .degraded == "openai"'
  jqt "explicit-only: --critic=neon of an openai build is accepted; it is not reused as reviewer (Astra, degraded review)" "$(roles '{"builder":"sol","eligible":["sol","astra","neon"],"named_critics":["neon"]}')" \
    '.critics == ["neon"] and .reviewer == "astra" and .degraded == null and .stop == null and (.notes | any(test("neon is provisional"))) and (.notes | any(test("named for critique only .degraded")))'
  jqt "explicit-only: --critic=neon with Opus available → Opus reviews, not neon" "$(roles '{"builder":"sol","eligible":["sol","opus","neon"],"named_critics":["neon"]}')" \
    '.critics == ["neon"] and .reviewer == "opus" and .stop == null'
  jqt "explicit-only: policy critic neon with Opus available → Opus reviews" "$(roles '{"builder":"sol","eligible":["sol","opus","neon"],"policy_critic":"neon"}')" \
    '.critics == ["neon"] and .reviewer == "opus" and (.notes | index("critic=neon (policy)") != null)'
  jqt "explicit-only: --critic=neon and --reviewer=neon → neon reviews" "$(roles '{"builder":"sol","eligible":["sol","opus","neon"],"named_critics":["neon"],"named_reviewer":"neon"}')" '.critics == ["neon"] and .reviewer == "neon"'
  jqt "explicit-only: --critic=neon and policy reviewer neon → neon reviews" "$(roles '{"builder":"sol","eligible":["sol","opus","neon"],"named_critics":["neon"],"policy_reviewer":"neon"}')" '.reviewer == "neon"'
  jqt "explicit-only: --critic=neon, no other reviewer eligible → reviewer null, said" "$(roles '{"builder":"sol","eligible":["sol","neon"],"named_critics":["neon"]}')" \
    '.critics == ["neon"] and .reviewer == null and .stop == null and (.notes | any(test("no cross reviewer")))'
  jqt "explicit-only: hs sol build, --critic=neon, fable budget → critics neon+fable, Fable (a selected critic) reviews" \
    "$(roles '{"builder":"sol","high_stakes":true,"fable_budget":true,"eligible":["sol","fable","neon"],"named_critics":["neon"]}')" \
    '.critics == ["neon","fable"] and .reviewer == "fable" and .stop == null'
  jqt "explicit-only: same, not high stakes → the ordinary critic order (no fable in it): no reviewer, said" \
    "$(roles '{"builder":"sol","fable_budget":true,"eligible":["sol","fable","neon"],"named_critics":["neon"]}')" \
    '.critics == ["neon"] and .reviewer == null and .stop == null and (.notes | any(test("no cross reviewer")))'
  jqt "explicit-only: hs, --critic=neon, Opus added second → Opus reviews" \
    "$(roles '{"builder":"sol","high_stakes":true,"eligible":["sol","opus","neon","argon"],"named_critics":["neon"]}')" '.critics == ["neon","opus"] and .reviewer == "opus"'
  jqt "explicit-only: --critic=carbon of a claude build → sol reviews" "$(roles '{"builder":"opus","named_critics":["carbon"],"eligible":'"$ALLX"'}')" '.critics == ["carbon"] and .reviewer == "sol"'
  jqt "explicit-only: a policy critic carbon counts for the critic choice" "$(roles '{"builder":"sol","eligible":["sol","astra","carbon"],"policy_critic":"carbon"}')" '.critics == ["carbon"] and .degraded == null'
  jqt "explicit-only: --critic=carbon of a claude build" "$(roles '{"builder":"opus","named_critics":["carbon"],"eligible":'"$ALLX"'}')" '.critics == ["carbon"] and .stop == null'
  jqt "explicit-only: a neon build counts as google (named by --model) → sol" "$(roles '{"builder":"neon","eligible":["neon","sol","astra"]}')" '.critics == ["sol"] and .degraded == null'
  jqt "explicit-only: neon build, google only → argon (degraded)" "$(roles '{"builder":"neon","eligible":["neon","argon"]}')" '.critics == ["argon"] and .degraded == "google"'
  jqt "explicit-only: --critic=neon of a google build → stop (family rule)" "$(roles '{"builder":"gemini","named_critics":["neon"],"eligible":'"$ALLX"'}')" '.stop.reason | test("shares the builder")'
  jqt "named reviewer from the builder family → stop" "$(roles '{"builder":"sol","named_reviewer":"astra","eligible":'"$ALLX"'}')" '.stop.reason | test("named reviewer astra shares")'
  jqt "named reviewer not available → stop" "$(roles '{"builder":"sol","named_reviewer":"carbon","eligible":["sol","opus"]}')" '.stop.reason | test("not available")'
  jqt "named reviewer beats the policy reviewer" "$(roles '{"builder":"opus","named_reviewer":"argon","policy_reviewer":"gemini","eligible":'"$ALLX"'}')" '.critics == ["sol"] and .reviewer == "argon"'
  jqt "arbiter: carbon/neon eligible change nothing → argon" "$("$B/maestro-roles" --arbiter <<<'{"builder":"opus","critics_with_findings":["sol"],"eligible":'"$ALLX"'}')" '.arbiter == "argon"'
  jqt "arbiter: argon and gemini out, only neon left in google → no google arbiter" "$("$B/maestro-roles" --arbiter <<<'{"builder":"opus","critics_with_findings":["sol"],"eligible":["opus","sol","neon","carbon"]}')" '.arbiter == null and .stop != null'
  jqt "row 6: carbon/neon never chosen" "$("$B/maestro-roles" --row6 <<<'{"eligible":["neon","carbon"]}')" 'has("implementer") and .implementer == null and .stop.row == 2'
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
  jqt "slots.json: carbon and neon are google, agy-only, provisional and explicit-only; nothing else is explicit-only" \
    "$(jq -c 'del(._comment) | [to_entries[] | select(.value.explicit_only) | {k: .key, f: .value.family, t: .value.transports, p: .value.provisional}]' "$B/slots.json")" \
    '. == [{"k":"carbon","f":"google","t":["agy"],"p":true},{"k":"neon","f":"google","t":["agy"],"p":true}]'
  jqt "transports: no slot and no order → halt, not a jq error" "$("$B/maestro-roles" --transports <<<'{"available":{}}')" '.action == "halt"'
  jqt "transports: the order comes from slots.json" "$("$B/maestro-roles" --transports <<<'{"slot":"fable","available":{"native":false,"api":true}}')" '.transport == "api"'
  r6() { "$B/maestro-roles" --row6 <<<"$1"; }
  jqt "row 6: self when the director is known" "$(r6 '{"eligible":["self","sonnet"],"director_family":"claude","director_line":"opus"}')" '.implementer == "self"'
  jqt "row 6: director line unknown → sonnet" "$(r6 '{"eligible":["self","sonnet","sol"],"director_family":"claude"}')" '.implementer == "sonnet"'
  jqt "row 6: only gemini eligible → gemini" "$(r6 '{"eligible":["gemini"]}')" '.implementer == "gemini"'
  jqt "row 6: nothing eligible → halt" "$(r6 '{"eligible":["haiku"]}')" 'has("implementer") and .implementer == null and .stop.row == 2'
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
  # the advisor (SKILL.md, "Advisor"): optional, never a gate, moves no critic or reviewer
  jqt "advisor: off without advisor_on (advisor null, no notes)" "$(roles '{"builder":"opus","eligible":'"$ALL"',"named_advisor":"astra"}')" '.advisor == null and .notes == []'
  jqt "advisor: auto, claude build → sol (the critic order)" "$(roles '{"builder":"opus","eligible":'"$ALL"',"advisor_on":true}')" '.advisor == "sol" and .critics == ["sol"] and .reviewer == "sol" and .notes == []'
  jqt "advisor: auto, claude build, high stakes → astra" "$(roles '{"builder":"opus","high_stakes":true,"eligible":'"$ALL"',"advisor_on":true}')" '.advisor == "astra" and .critics == ["astra","argon"]'
  jqt "advisor: auto, openai build → opus" "$(roles '{"builder":"sol","eligible":'"$ALL"',"advisor_on":true}')" '.advisor == "opus"'
  jqt "advisor: auto, google build, high stakes → astra" "$(roles '{"builder":"gemini","high_stakes":true,"eligible":'"$ALL"',"advisor_on":true}')" '.advisor == "astra"'
  jqt "advisor: review on → avoids the reviewer family when it can (claude build: argon, reviewer sol)" \
    "$(roles '{"builder":"opus","eligible":'"$ALL"',"advisor_on":true,"review_active":true}')" '.advisor == "argon" and .reviewer == "sol" and .critics == ["sol"] and (.notes | any(test("argon is provisional")))'
  jqt "advisor: review on, high stakes → argon (reviewer astra)" "$(roles '{"builder":"opus","high_stakes":true,"eligible":'"$ALL"',"advisor_on":true,"review_active":true}')" '.advisor == "argon" and .reviewer == "astra"'
  jqt "advisor: review on, only the reviewer's family left → that slot, both notes" \
    "$(roles '{"builder":"opus","eligible":["opus","sol"],"advisor_on":true,"review_active":true}')" \
    '.advisor == "sol" and .reviewer == "sol" and (.notes | index("advisor and reviewer share a family") != null) and (.notes | index("reviewer anchored: the advisor shaped the build") != null)'
  jqt "advisor: review off → no reviewer-based avoidance and no anchoring note" \
    "$(roles '{"builder":"opus","eligible":["opus","sol","argon"],"advisor_on":true}')" '.advisor == "sol" and .reviewer == "sol" and .notes == []'
  jqt "advisor: one family (degraded) → no advisor, said, critique unchanged" "$(roles '{"builder":"opus","eligible":["opus","fable","sonnet"],"advisor_on":true}')" \
    '.advisor == null and .critics == ["fable"] and .degraded == "claude" and .stop == null and (.notes | index("no advisor: only the builder'"'"'s family is eligible") != null)'
  jqt "advisor: named, the builder's family → allowed, noted" "$(roles '{"builder":"opus","eligible":'"$ALL"',"advisor_on":true,"named_advisor":"sonnet"}')" \
    '.advisor == "sonnet" and .critics == ["sol"] and .reviewer == "sol" and (.notes | any(test("advisor shares the builder.s family \\(named\\)")))'
  jqt "advisor: named explicit-only neon → the advisor only: no google critic, not the reviewer" \
    "$(roles '{"builder":"opus","high_stakes":true,"eligible":["opus","astra","sol","carbon","neon"],"advisor_on":true,"named_advisor":"neon"}')" \
    '.advisor == "neon" and .critics == ["astra"] and .reviewer == "astra" and (.notes | any(test("no second critic"))) and (.notes | any(test("neon is provisional")))'
  jqt "advisor: a denied but available slot named as advisor is never a critic or reviewer" \
    "$(roles '{"builder":"opus","eligible":["opus","astra","argon"],"advisor_eligible":["opus","astra","argon","sol"],"available":["opus","astra","argon","sol"],"advisor_on":true,"named_advisor":"sol"}')" \
    '.advisor == "sol" and .critics == ["astra"] and .reviewer == "astra" and .stop == null'
  jqt "advisor: a denied slot named as advisor with no available transport → stop (a flag never beats unavailability)" \
    "$(roles '{"builder":"opus","eligible":["opus","astra","argon"],"advisor_eligible":["opus","astra","argon","sol"],"available":["opus","astra","argon"],"advisor_on":true,"named_advisor":"sol"}')" \
    '.advisor == null and (.stop.reason | test("named advisor sol is not available this run .policy denies it and no transport of it is available."))'
  jqt "advisor: advisor_eligible without available → a slot outside eligible is not taken" \
    "$(roles '{"builder":"opus","eligible":["opus","astra"],"advisor_eligible":["opus","astra","sol"],"advisor_on":true,"named_advisor":"sol"}')" '.advisor == null and .stop != null'
  jqt "advisor: a policy advisor outside eligible is not taken even if available (policy never beats its own deny)" \
    "$(roles '{"builder":"opus","eligible":["opus","astra"],"advisor_eligible":["opus","astra","sol"],"available":["opus","astra","sol"],"advisor_on":true,"policy_advisor":"sol"}')" \
    '.advisor == "astra" and (.notes | index("policy advisor sol is not available: auto") != null)'
  jqt "advisor: named, not available → stop, advisor null" "$(roles '{"builder":"opus","eligible":["opus","sol"],"advisor_on":true,"named_advisor":"argon"}')" \
    '.advisor == null and (.stop.reason | test("named advisor argon is not available"))'
  jqt "advisor: every stop carries advisor null" "$(roles '{"builder":"opus","named_critics":["sonnet"],"eligible":'"$ALL"',"advisor_on":true}')" '.stop != null and has("advisor") and .advisor == null'
  jqt "advisor: a policy advisor, eligible → used, marked (policy)" "$(roles '{"builder":"opus","eligible":'"$ALL"',"advisor_on":true,"policy_advisor":"gemini"}')" \
    '.advisor == "gemini" and (.notes | index("advisor=gemini (policy)") != null) and .critics == ["sol"]'
  jqt "advisor: a policy advisor of the builder's family → allowed, noted" "$(roles '{"builder":"opus","eligible":'"$ALL"',"advisor_on":true,"policy_advisor":"fable"}')" \
    '.advisor == "fable" and (.notes | any(test("advisor shares the builder.s family \\(policy\\)")))'
  jqt "advisor: a policy advisor not available → auto, with a note" "$(roles '{"builder":"opus","eligible":["opus","sol"],"advisor_on":true,"policy_advisor":"argon"}')" \
    '.advisor == "sol" and .stop == null and (.notes | index("policy advisor argon is not available: auto") != null)'
  jqt "advisor: the named advisor beats the policy one" "$(roles '{"builder":"opus","eligible":'"$ALL"',"advisor_on":true,"policy_advisor":"gemini","named_advisor":"astra"}')" '.advisor == "astra"'
  jqt "advisor: builder self → off, noted" "$(roles '{"builder":"self","director_family":"claude","director_line":"opus","eligible":["self","sol"],"advisor_on":true,"named_advisor":"sol"}')" \
    '.advisor == null and .critics == ["sol"] and (.notes | index("advisor off: the director builds") != null)'
  jqt "advisor: reviewer and critics are the same with and without it" \
    "$(jq -nc --argjson a "$(roles '{"builder":"sol","high_stakes":true,"fable_budget":true,"eligible":'"$ALL"'}')" \
               --argjson b "$(roles '{"builder":"sol","high_stakes":true,"fable_budget":true,"eligible":'"$ALL"',"advisor_on":true,"review_active":true}')" \
               '[$a.critics, $a.reviewer, $a.degraded] == [$b.critics, $b.reviewer, $b.degraded]')" '. == true'
  jqt "advisor: swap to the advisor's family → re-resolved (sol build: opus, not an openai slot)" \
    "$(roles '{"builder":"sol","eligible":'"$ALL"',"advisor_on":true}')" '.advisor == "opus" and .critics == ["opus"]'
  jqt "advisor: a swap that leaves no other family → advisor off, noted (the checkpoint keeps its counts: T9)" \
    "$(roles '{"builder":"sol","eligible":["sol","astra"],"advisor_on":true}')" '.advisor == null and .stop == null and (.notes | any(test("^no advisor")))'
  jqt "advisor: swap, a named advisor now of the builder's family stays, noted" "$(roles '{"builder":"astra","eligible":'"$ALL"',"advisor_on":true,"named_advisor":"sol"}')" \
    '.advisor == "sol" and (.notes | any(test("shares the builder")))'
  jqt "advisor: explicit-only carbon and neon are never chosen automatically" \
    "$(roles '{"builder":"sol","eligible":["sol","astra","carbon","neon"],"advisor_on":true}')" '.advisor == null and .critics == ["astra"] and (.notes | any(test("^no advisor")))'
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
  # set / add-session patch the front matter in place. The fixture is the example of
  # docs/checkpoint.md itself (comments, flow maps, block and inline lists) between "---" lines,
  # with a body that repeats a key.
  REPO5="$(new_repo)"; cd "$REPO5" || exit 2
  g5="$("$B/maestro-lock" acquire --run r --token t --host test | jq -r .fence)"
  CP=.maestro/CHECKPOINT.md
  S() { "$B/maestro-state" --gen "$g5" "$@"; }
  cpsha() { sha256sum "$CP" | cut -c1-64; }
  keys_changed() { diff "$1" "$CP" | sed -n 's/^< *\([A-Za-z0-9_]*\):.*/\1/p' | sort | tr '\n' ' '; }   # keys of the lines that differ
  rc_of() { "$@" >/dev/null 2>&1; echo $?; }
  naud() { grep -c '"file":"CHECKPOINT.md"' .maestro/audit.jsonl; }                                   # its audit entries
  { printf -- '---\n'; awk '/^```yaml/ && !d { f = 1; next } /^```/ && f { f = 0; d = 1 } f' "$ROOT/docs/checkpoint.md"
    printf -- '---\n\n## Done\nstage: this body line is not front matter\n'; } > "$WORK/cp0"
  eq "set before any checkpoint is refused (the first one is a write)" 2 "$(rc_of S set stage=plan)"
  S write CHECKPOINT.md < "$WORK/cp0" >/dev/null
  n0="$(naud)"
  jqt "set on an audited checkpoint" "$(S set stage=review)" '.result == "written" and .file == "CHECKPOINT.md"'
  eq "set: only that line and written_at differ, the comment stays" "stage written_at |1" \
    "$(keys_changed "$WORK/cp0")|$(grep -c '^stage: review            # interview | assign' "$CP")"
  eq "set: same number of lines, the body untouched" "$(wc -l < "$WORK/cp0") 1" "$(wc -l < "$CP") $(grep -c '^stage: this body line' "$CP")"
  jqt "set: one audit entry more, and the file verifies" "$(tail -1 .maestro/audit.jsonl)" \
    ".file == \"CHECKPOINT.md\" and .sha256_after == \"$(cpsha)\" and $(naud) == $((n0 + 1))"
  jqt "set: verify ok" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "ok"'
  wa="$(sed -n 's/^written_at: //p' "$CP")"
  if [[ "$wa" != "2026-09-06T11:02:14+02:00" && "$wa" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}[+-][0-9]{2}:[0-9]{2}$ ]]; then ok "set stamps written_at with now"; else bad "set stamps written_at with now" "$wa"; fi
  cp "$CP" "$WORK/cp1"
  S set round=2 tree_state=clean fix_cap=4 current_task=2 tree.head=abc1234 plan_sha256=deadbeef written_at=2030-01-01T00:00:00+00:00 >/dev/null
  eq "set with several keys" "current_task fix_cap plan_sha256 round tree tree_state written_at " "$(keys_changed "$WORK/cp1")"
  eq "set: bare stays bare, quoted stays quoted, a comment stays, an explicit written_at wins" \
    'round: 2|1|1|plan_sha256: "deadbeef"|written_at: 2030-01-01T00:00:00+00:00' \
    "$(grep '^round: ' "$CP")|$(grep -c '^tree_state: clean   # clean | dirty-worker' "$CP")|$(grep -c '^fix_cap: 4              # fix-loop cap' "$CP")|$(grep '^plan_sha256: ' "$CP")|$(grep '^written_at: ' "$CP")"
  eq "set <parent>.<key> inside a one-line flow map" "tree: {branch: feature/tags-crud, head: abc1234, fingerprint: 9f2c41…}" "$(grep '^tree: ' "$CP")"
  v='say "hi": then C:\go, 100% # not a comment'
  S set "next_action=$v" "tests.cmd=a, b: {c}" >/dev/null
  eq "a value with a colon, quotes and a backslash round-trips" "$v" "$(sed -n 's/^next_action: //p' "$CP" | jq -r .)"
  eq "… and inside a flow map" 'tests: {cmd: "a, b: {c}", last_result: "1104/1104", duration_s: 412, T_slow_s: 417}' "$(grep '^tests: ' "$CP")"
  S set next_action=no tree_state=on >/dev/null
  eq "set: YAML 1.1 keywords are quoted (no, on)" 'next_action: "no"|tree_state: "on"' "$(grep -o '^next_action: [^ ]*' "$CP")|$(grep -o '^tree_state: [^ ]*' "$CP")"
  S set "next_action=10:30" >/dev/null
  eq "set: a sexagesimal-looking value is quoted" 'next_action: "10:30"' "$(grep -o '^next_action: [^ ]*' "$CP")"
  S set tree_state=clean >/dev/null
  acp() { grep -o '^advisor_checkpoints: {[^}]*}' "$CP"; }
  eq "advisor: the example's advisor_checkpoints is off and zero; roster.advisor is empty" \
    'advisor_checkpoints: {status: unused, max: 0, used: 0, skipped: 0, pending: "", fp_at_resume: "", ro_off: ""}|1' "$(acp)|$(grep -c '^  advisor:     {slot: "", ' "$CP")"
  S set advisor_checkpoints.status=active advisor_checkpoints.max=2 >/dev/null
  S set advisor_checkpoints.used=1 advisor_checkpoints.pending=adv-1:requested >/dev/null
  eq "advisor: requested — used rises with it" 'advisor_checkpoints: {status: active, max: 2, used: 1, skipped: 0, pending: "adv-1:requested", fp_at_resume: "", ro_off: ""}' "$(acp)"
  S set advisor_checkpoints.pending=adv-1:advised >/dev/null
  S set "advisor_checkpoints.pending=adv-1:resuming:r.build.r1.a2" >/dev/null
  eq "advisor: resuming names the continuation's job id, written before the dispatch" \
    'advisor_checkpoints: {status: active, max: 2, used: 1, skipped: 0, pending: "adv-1:resuming:r.build.r1.a2", fp_at_resume: "", ro_off: ""}' "$(acp)"
  S set advisor_checkpoints.pending= >/dev/null
  jqt "… requested → advised → resuming → cleared: the checkpoint verifies" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "ok"'
  S set advisor_checkpoints.used=2 advisor_checkpoints.skipped=1 advisor_checkpoints.pending=adv-2:advised >/dev/null
  S set "advisor_checkpoints.pending=adv-2:resuming:agent:a3f9" >/dev/null; S set advisor_checkpoints.pending= >/dev/null
  S set advisor_checkpoints.status=disabled >/dev/null
  eq "advisor: a swap turns it off; max, used and skipped are kept for the report" \
    'advisor_checkpoints: {status: disabled, max: 2, used: 2, skipped: 1, pending: "", fp_at_resume: "", ro_off: ""}' "$(acp)"
  jqt "… and the checkpoint verifies" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "ok"'
  # resume with pending requested and a changed fingerprint: step 0 records only; step 5 acts
  S set advisor_checkpoints.status=active advisor_checkpoints.max=3 advisor_checkpoints.used=3 advisor_checkpoints.pending=adv-3:requested >/dev/null
  S set advisor_checkpoints.fp_at_resume=changed advisor_checkpoints.ro_off=codex >/dev/null           # step 0
  eq "advisor resume, step 0: the result and the ineligible transport are recorded; no skip, pending still requested" \
    'advisor_checkpoints: {status: active, max: 3, used: 3, skipped: 1, pending: "adv-3:requested", fp_at_resume: "changed", ro_off: "codex"}' "$(acp)"
  S set advisor_checkpoints.skipped=2 advisor_checkpoints.pending=adv-3:advised >/dev/null           # step 5, after steps 1-4
  S set "advisor_checkpoints.pending=adv-3:resuming:r.build.r1.a2" advisor_checkpoints.fp_at_resume= >/dev/null
  eq "advisor resume, step 5: one skip, advised → resuming; fp_at_resume consumed, ro_off kept" \
    'advisor_checkpoints: {status: active, max: 3, used: 3, skipped: 2, pending: "adv-3:resuming:r.build.r1.a2", fp_at_resume: "", ro_off: "codex"}' "$(acp)"
  # a recorded `changed` is authoritative across restarts: step 0 compares only when fp_at_resume is empty
  GD9="$(git rev-parse --git-dir)/maestro"; mkdir -p "$GD9"; cp "$ROOT/docs/schemas/advice-schema.json" .maestro/
  S set advisor_checkpoints.used=4 advisor_checkpoints.max=4 advisor_checkpoints.pending=adv-4:requested advisor_checkpoints.fp_at_resume= >/dev/null
  "$B/maestro-fp" snapshot > "$GD9/fp-adv-4.json"
  printf '{"type":"object"}\n' > .maestro/advice-schema.json                       # the advisor edits the schema
  step0() {  # the documented step 0: compare when nothing or `same` is recorded; `changed` stays
    local cur; cur="$(sed -n 's/^advisor_checkpoints: .*fp_at_resume: "\{0,1\}\([a-z]*\)"\{0,1\},.*/\1/p' "$CP")"
    [[ -n "$cur" && "$cur" != same ]] && return 0
    S set "advisor_checkpoints.fp_at_resume=$("$B/maestro-fp" compare "$GD9/fp-adv-${1:-4}.json" | jq -r .result)" >/dev/null
  }
  fpr() { sed -n 's/^advisor_checkpoints: .*fp_at_resume: \("[a-z]*"\).*/\1/p' "$CP"; }
  sk0="$(sed -n 's/^advisor_checkpoints: .*skipped: \([0-9]*\),.*/\1/p' "$CP")"
  step0                                                                             # first resume
  cp "$ROOT/docs/schemas/advice-schema.json" .maestro/                              # step 2's preflight restores it; then a restart
  jqt "advisor resume: after preflight restored the schema a fresh compare would say same…" "$("$B/maestro-fp" compare "$GD9/fp-adv-4.json")" '.result == "same"'
  step0                                                                             # second resume
  eq "… but the second resume keeps the recorded changed (not recomputed, not overwritten)" '"changed"' \
    "$(sed -n 's/^advisor_checkpoints: .*fp_at_resume: \("[a-z]*"\).*/\1/p' "$CP")"
  S set advisor_checkpoints.skipped=$((sk0 + 1)) advisor_checkpoints.pending=adv-4:advised advisor_checkpoints.fp_at_resume= >/dev/null   # step 5, once
  eq "… and step 5 records exactly one skip, clearing fp_at_resume with the pending change" "$((sk0 + 1))|\"\"|adv-4:advised" \
    "$(sed -n 's/^advisor_checkpoints: .*skipped: \([0-9]*\),.*/\1/p' "$CP")|$(sed -n 's/^advisor_checkpoints: .*fp_at_resume: \("[a-z]*"\).*/\1/p' "$CP")|$(sed -n 's/^advisor_checkpoints: .*pending: "\([^"]*\)".*/\1/p' "$CP")"
  # a recorded `same` is re-verified on every later resume: a plan edit between two resumes is caught
  printf '# plan\n' > .maestro/PLAN.md
  S set advisor_checkpoints.pending=adv-5:requested >/dev/null; "$B/maestro-fp" snapshot > "$GD9/fp-adv-5.json"
  step0 5
  eq "advisor resume: first resume, nothing touched → same" '"same"' "$(fpr)"
  printf 'edited between two resumes\n' >> .maestro/PLAN.md
  step0 5
  eq "advisor resume: second resume after a PLAN.md edit → compared again: changed (the saved answer is discarded)" '"changed"' "$(fpr)"
  printf '# plan\n' > .maestro/PLAN.md; step0 5
  eq "… and that changed stays, even once the plan is back as it was" '"changed"' "$(fpr)"
  S set advisor_checkpoints.fp_at_resume= >/dev/null
  S set "advisor_checkpoints.pending=adv-3:resuming:r.build.r1.a2" >/dev/null; rm -f "$GD9/fp-adv-4.json" "$GD9/fp-adv-5.json"
  # reconcile the continuation named in resuming:<job id>: an existing job is read, an absent one was never sent
  "$B/maestro-run" --gen "$g5" --job r.build.r1.a2 --run r --role build -- true >/dev/null; sleep 1.5
  jqt "advisor resume: resuming:<job id> names an existing job → reconciled as the builder's continuation" \
    "$("$B/maestro-wait" "$(sed -n 's/^advisor_checkpoints: .*pending: "adv-3:resuming:\([^"]*\)".*/\1/p' "$CP")" --peek)" '.job_id == "r.build.r1.a2" and .state == "exited"'
  out="$("$B/maestro-wait" r.build.r1.a3 --peek 2>&1)"; rc=$?
  if [[ $rc -eq 2 && "$out" == *"no job r.build.r1.a3"* ]]; then ok "advisor resume: an absent continuation job → \"no job\", exit 2: never dispatched, send the saved advice"
  else bad "advisor resume: an absent continuation job → no job, exit 2" "rc=$rc $out"; fi
  S set advisor_checkpoints.pending= >/dev/null
  jqt "… and the checkpoint verifies" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "ok"'
  h="$(cpsha)"; n1="$(naud)"
  eq "a newline in a value is refused" 2 "$(rc_of S set "next_action=one"$'\n'"stage: report")"
  eq "an unknown key is refused" 2 "$(rc_of S set nope=1)"
  jqt "… with a message that says set never adds a key" "$(S set nope=1 2>&1 | jq -Rc '{m: .}')" '.m | test("nope.*not in the front matter")'
  eq "one unknown key among good ones: nothing is written" 2 "$(rc_of S set stage=fix nope=1)"
  eq "a key that holds a block, a list or a multi-line map is refused" "2 2 2 2 2" \
    "$(rc_of S set roster=x) $(rc_of S set blockers=x) $(rc_of S set sessions=x) $(rc_of S set runtime.doctor_ok=false) $(rc_of S set decisions.current=x)"
  eq "a key absent from a flow map, two levels and a bare word are refused" "2 2 2" "$(rc_of S set tree.nope=1) $(rc_of S set a.b.c=1) $(rc_of S set stage)"
  eq "set without --gen is refused" 2 "$(rc_of "$B/maestro-state" set stage=fix)"
  eq "add-session with an unknown transport is refused" 2 "$(rc_of S add-session cursor '{"id":"x"}')"
  eq "add-session: not an object, a newline in a string, or two records are refused" "2 2 2" "$(rc_of S add-session codex '[1]') $(rc_of S add-session codex '{"id":"a\nb"}') $(rc_of S add-session codex '{"id":"a"} {"id":"b"}')"
  eq "every refusal left the file and the audit as they were" "$h $n1" "$(cpsha) $(naud)"
  # A superseded fence: the lock is released and taken again.
  "$B/maestro-lock" release --token t --gen "$g5" >/dev/null; old="$g5"
  g5="$("$B/maestro-lock" acquire --run r --token t --host test | jq -r .fence)"
  eq "set with a stale fence → exit 4" 4 "$(rc_of "$B/maestro-state" --gen "$old" set stage=fix)"
  eq "add-session with a stale fence → exit 4" 4 "$(rc_of "$B/maestro-state" --gen "$old" add-session claude '{"id":"x"}')"
  eq "… and the file is untouched" "$h $n1" "$(cpsha) $(naud)"
  # add-session: a block list with multi-line records, an inline list, an empty [] list.
  cp "$CP" "$WORK/cp2"
  rec='{"id":"01b0","role":"fix","job":"r.fix.r1.a1","config_mode":"isolated","rung":1,"tools":"Read,Edit","worktree":"","baseline":"1234567","pinned":true}'
  want='- {id: 01b0, role: fix, job: r.fix.r1.a1, config_mode: isolated, rung: 1, tools: "Read,Edit", worktree: "", baseline: "1234567", pinned: true}'
  jqt "add-session into a block list" "$(S add-session codex "$rec")" '.result == "written"'
  eq "… after the last record's last line, before its comments" "       worktree: \"\", baseline: \"\", fingerprint: \"\"}|    $want|# rollout_offset" \
    "$(grep -B1 -A1 -F -- "$want" "$CP" | sed '3s/^ *\(# rollout_offset\).*/\1/' | paste -sd'|')"
  S add-session agy "$rec" >/dev/null
  eq "add-session into an inline list: it becomes a block list" "  agy:|    - {id: b538f8bb-9a0e-4978-bc3d-988ccef298eb, role: critic, slug: gemini-4-argon-medium, job: …}|    $want" \
    "$(grep -A2 '^  agy:' "$CP" | paste -sd'|')"
  S add-session claude "$rec" >/dev/null; S add-session claude '{"id":"02c0"}' >/dev/null
  eq "add-session into an empty [] list, the key's comment kept; a second one follows" \
    "  claude:             # Agent-tool subagent ids, continued with SendMessage within the session;|    $want|    - {id: 02c0}" \
    "$(grep -A2 '^  claude:' "$CP" | paste -sd'|')"
  eq "add-session: nothing but the session lines and written_at changed" "agy claude written_at " "$(keys_changed "$WORK/cp2")"
  if [[ "$(grep '^written_at: ' "$CP")" != "written_at: 2030-01-01T00:00:00+00:00" ]]; then ok "add-session stamps written_at"; else bad "add-session stamps written_at"; fi
  jqt "after add-session the file verifies" "$("$B/maestro-state" verify CHECKPOINT.md)" '.result == "ok"'
  printf 'edited by hand\n' >> "$CP"
  h="$(cpsha)"
  jqt "set on a file changed outside maestro is refused" "$(S set stage=fix 2>/dev/null)" '.result == "tampered"'
  eq "… with exit 5, and so is add-session" "5 5" "$(rc_of S set stage=fix) $(rc_of S add-session claude '{"id":"x"}')"
  eq "… and the tampered file is not rewritten" "$h" "$(cpsha)"
  # Without "---" lines the whole file is front matter; a file with no written_at is patched unstamped.
  REPO6="$(new_repo)"; cd "$REPO6" || exit 2
  g5="$("$B/maestro-lock" acquire --run r --token t --host test | jq -r .fence)"
  printf 'stage: plan\nnote:\nsessions:\n  codex:\n  claude_cli: [{id: a,\n    role: b}]\nlast: x' | S write CHECKPOINT.md >/dev/null
  S set stage=build "note=it's" 2>/dev/null >/dev/null; S add-session codex '{"id":"c1"}' >/dev/null 2>&1
  eq "no front-matter fence, no written_at, no final newline: patched as is" 'stage: build|note: "it'"'"'s"|sessions:|  codex:|    - {id: c1}|  claude_cli: [{id: a,|    role: b}]|last: x' \
    "$(paste -sd'|' "$CP")$(tail -c1 "$CP" | tr -d 'x')"
  eq "a list that does not close on its line is refused" 2 "$(rc_of S add-session claude_cli '{"id":"c2"}')"
  eq "a transport key that is not there is refused" 2 "$(rc_of S add-session agy '{"id":"c2"}')"
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
  jqt "no meta.json (a job not launched by maestro-run): run and host from the lock" "$row" '.run_id == "r" and .host == "test"'
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
  mkdir -p .maestro/jobs/adv1
  printf '{"type":"thread.started","thread_id":"tadv"}\n{"type":"turn.completed","usage":{"input_tokens":7,"output_tokens":2}}\n' > .maestro/jobs/adv1/out
  jqt "advisor: a row with stage advise is appended" \
    "$("$B/maestro-ledger" --gen "$g" --job adv1 --stage advise --cli codex --transport codex --family openai --model gpt-6.2-astra --effort high)" '.result == "written"'
  jqt "… the report prints it as its own stage" "$("$B/maestro-ledger" report --run r --json)" \
    '[.rows[] | select(.stage == "advise")] | length == 1 and .[0].who == "gpt-6.2-astra@high" and .[0].input == 7'
  md="$("$B/maestro-ledger" report --run r)"
  if [[ "$md" == *"| advise | gpt-6.2-astra@high | codex | 1 |"* ]]; then ok "… as its own line of the Markdown table"; else bad "… as its own line of the Markdown table" "$md"; fi
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
  eq "brief: a repo path with & is printed as is" "/home/a&b" "$("$B/maestro-brief" open --role critic --transport agy --repo '/home/a&b' | grep -o '/home/a&b' | head -1)"
  eq "brief: no agy opening for a Codex critic" "" "$("$B/maestro-brief" open --role critic --transport codex)"
  out="$("$B/maestro-brief" close --role builder --transport codex --schema "$ROOT/docs/schemas/gate-schema.json" 2>&1; echo "rc=$?")"
  if [[ "$out" == *"read-only role"* && "$out" == *rc=2* ]]; then ok "brief: --schema refused for a writer"; else bad "brief: --schema refused for a writer" "$out"; fi
  # the advisor block (--advisor): builder and fix briefs with the checkpoints left
  out="$("$B/maestro-brief" close --role builder --transport codex --advisor-checkpoints 2)"
  # shellcheck disable=SC2016  # literal backticks
  if [[ "$out" == *"(requests left: 2)"* && "$out" == *'`ADVICE_REQUEST`'* && "$out" == *'`END_ADVICE_REQUEST`'* && "$out" == *"timeout"* && "$out" != *"<N>"* ]]; then
    ok "brief: advisor block in a Codex builder brief, with the count"; else bad "brief: advisor block in a Codex builder brief, with the count" "$out"; fi
  out="$("$B/maestro-brief" close --role fix --transport agy --advisor-checkpoints 1 --unattended)"
  if [[ "$out" == *"(requests left: 1)"* && "$out" == *"edit files only"* && "$(tail -1 <<<"$out")" == *"do not decide it"* ]]; then
    ok "brief: advisor block in an edits-only fix brief, before the unattended line"; else bad "brief: advisor block in an edits-only fix brief" "$out"; fi
  out="$("$B/maestro-brief" close --role builder --transport native)"; rc=$?
  if [[ $rc -eq 0 && "$out" == "Do not ask questions."*"timeout"* && "$out" != *"ADVICE_REQUEST"* ]]; then
    ok "brief: no advisor block without --advisor-checkpoints"; else bad "brief: no advisor block without --advisor-checkpoints" "rc=$rc $out"; fi
  for t in native claude-cli api codex agy; do
    out="$("$B/maestro-brief" close --role advisor --transport "$t")"; rc=$?
    if [[ $rc -eq 0 && "$out" == "Do not ask questions."* && $(wc -l <<<"$out") -eq 1 ]]; then ok "brief: advisor close on $t = the closing block alone (read-only)"
    else bad "brief: advisor close on $t = the closing block alone (read-only)" "rc=$rc $out"; fi
  done
  for t in claude-cli api; do
    out="$("$B/maestro-brief" close --role advisor --transport "$t" --schema "$ROOT/docs/schemas/advice-schema.json" --unattended)"; rc=$?
    if [[ $rc -eq 0 && "$out" == *'"minLength": 1'* && "$out" == *"Your final message must be the JSON object only."* && "$(tail -1 <<<"$out")" == *"do not decide it"* ]]; then
      ok "brief: a $t advisor gets the advice schema quoted, then the unattended line"; else bad "brief: a $t advisor gets the advice schema quoted" "rc=$rc $out"; fi
  done
  for t in native codex agy; do
    out="$("$B/maestro-brief" close --role advisor --transport "$t" --schema "$ROOT/docs/schemas/advice-schema.json" 2>&1)"; rc=$?
    if [[ $rc -eq 2 && "$out" == *"--schema is for a claude-cli or api read-only role"* ]]; then ok "brief: no --schema for a $t advisor (its line carries the schema, or you quote it)"
    else bad "brief: no --schema for a $t advisor" "rc=$rc $out"; fi
  done
  eq "brief: advisor open — the agy paragraph on agy, nothing on the others" "1 0 0 0 0" \
    "$("$B/maestro-brief" open --role advisor --transport agy --repo /r | grep -c 'inside /r') $(for t in native claude-cli api codex; do "$B/maestro-brief" open --role advisor --transport "$t" | wc -c; done | paste -sd' ')"
  eq "brief: the inline agy variant for an advisor after a denied read" 1 "$("$B/maestro-brief" open --role advisor --transport agy --inline | grep -c 'Do NOT call any tools')"
  eq "brief: --advisor-checkpoints refused for a read-only role, a drafter, 0 and 4" "2 2 2 2" \
    "$("$B/maestro-brief" close --role critic --transport codex --advisor-checkpoints 1 >/dev/null 2>&1; echo $?) $("$B/maestro-brief" close --role drafter --transport codex --advisor-checkpoints 1 >/dev/null 2>&1; echo $?) $("$B/maestro-brief" close --role builder --transport codex --advisor-checkpoints 0 >/dev/null 2>&1; echo $?) $("$B/maestro-brief" close --role builder --transport codex --advisor-checkpoints 4 >/dev/null 2>&1; echo $?)"
  out="$("$B/maestro-brief" close --role advisor --transport claude-cli --schema "$ROOT/docs/schemas/advice-schema.json")"
  if [[ "$out" == *'"maxItems": 5'* && "$out" == *"Your final message must be the JSON object only."* && "$out" != *"edit files only"* ]]; then
    ok "brief: a claude -p advisor gets the schema quoted (read-only)"; else bad "brief: a claude -p advisor gets the schema quoted" "$out"; fi
  eq "brief: an agy advisor opens with the read-inside paragraph; a Codex advisor gets only the closing block" "1 1" \
    "$("$B/maestro-brief" open --role advisor --transport agy --repo /r | grep -c 'inside /r') $("$B/maestro-brief" close --role advisor --transport codex | wc -l)"
  eq "brief: the triage header in SKILL.md and docs/briefs.md agree" "1 1" \
    "$(grep -c 'ADVISORY, NOT BINDING — the approved plan and the spec win' "$ROOT/SKILL.md") $(grep -c '^> ADVISORY, NOT BINDING — the approved plan and the spec win.$' "$ROOT/docs/briefs.md")"
  # every flag maestro-flags knows is documented in SKILL.md "Flags" and in docs/guide or the README
  missing="" nflags=0
  for n in $(grep -A1 '\["model","review","critic"' "$B/maestro-flags" | grep -oE '"[a-z-]+"' | tr -d '"'); do
    nflags=$((nflags + 1)); grep -qE -- "--$n\b" "$ROOT/SKILL.md" || missing+="--$n "
  done
  eq "every flag maestro-flags knows is in SKILL.md (15 flags read from its source)" "15|" "$nflags|$missing"
  # the advisor sees no verdict; the resume order; the transport-switch exception
  # shellcheck disable=SC2016  # literal backticks
  eq "docs: PLAN.md's critique record heading is named in SKILL.md and the advisor brief uses the copy without it" "1 1 1" \
    "$(grep -c '`## Critique record`, last in the' "$ROOT/SKILL.md") $(grep -c 'PLAN.md keeps every critique and verdict text under one exact heading, `## Critique record`' "$ROOT/docs/briefs.md") $(grep -c '^> Plan: <the copy of PLAN.md without its `## Critique record` section>' "$ROOT/docs/briefs.md")"
  # shellcheck disable=SC2016  # literal backticks
  RS="$(sed -n '/^### Resume with `pending` set/,/^## /p' "$ROOT/docs/checkpoint.md")"
  eq "docs: on resume the advisor's fingerprint compare comes before maestro-preflight --resume" 1 "$(tr '\n' ' ' <<<"$RS" | grep -c 'and \*\*before\*\* `maestro-preflight')"
  # shellcheck disable=SC2016  # literal backticks
  eq "docs: step 0 only records the result (fp_at_resume, ro_off); step 5 acts; nothing dispatched before" "1 1 1 1" \
    "$(tr '\n' ' ' <<<"$RS" | grep -c 'That is all: no skip is counted, no advice file is written, `pending` stays `requested`.') $(grep -c 'Nothing is dispatched before step 5.' <<<"$RS") $(grep -c '^\*\*Step 5 — settle `pending`, then continue.\*\*' <<<"$RS") $(grep -c '^- `requested`, `fp_at_resume: changed`' <<<"$RS")"
  eq "docs: an absent resuming:<job id> job is maestro-wait's \"no job\" (exit 2)" 1 "$(grep -c '\*"no job <id>"\* (exit 2) → it was never dispatched' <<<"$RS")"
  # the advisor's inputs are protected; the diff is restricted and read by the director
  # shellcheck disable=SC2016  # literal backticks
  eq "docs: no advisor input in the excluded tmp/ (only the Agent advisor's raw answer)" "0 1 1" \
    "$(grep -rc 'tmp/plan-advise' "$ROOT/SKILL.md" "$ROOT"/docs/*.md | awk -F: '{n += $2} END {print n}') $(grep -c '`.maestro/plan-advise-r<N>.md` and' "$ROOT/docs/briefs.md") $(grep -c '\*\*only\*\* an Agent-tool advisor.s raw answer' "$ROOT/docs/checkpoint.md")"
  # shellcheck disable=SC2016  # literal backticks
  eq "docs: the advisor-facing diff is restricted to the plan's implementation files and read by the director; no mechanical filter" "1 1 1 1 0" \
    "$(grep -c 'restricted to the implementation files the' "$ROOT/docs/briefs.md") $(grep -c '\*\*Before every advisor call — the initial build included — you read that patch before sending' "$ROOT/docs/briefs.md") $(grep -c 'No mechanical filter can find every quotation of' "$ROOT/docs/briefs.md") $(grep -c '^> The current change: <the restricted patch, or its path> CHANGELOG.md and quoted review text were withheld.$' "$ROOT/docs/briefs.md") $(grep -rc 'filter-diff' "$ROOT/SKILL.md" "$ROOT"/docs/*.md "$ROOT/CHANGELOG.md" "$B/maestro-brief" | awk -F: '{n += $2} END {print n}')"
  eq "brief: maestro-brief has no filter-diff subcommand" 2 "$("$B/maestro-brief" filter-diff --quotes /dev/null >/dev/null 2>&1; echo $?)"
  eq "docs: setup resolves the policy advisor with maestro-roles before offering it; a dropped one is not offered" "1 1" \
    "$(grep -c 'First resolve the policy preference against the setup roster' "$ROOT/docs/setup.md") $(grep -c 'The policy slot drops out' "$ROOT/docs/setup.md")"
  eq "docs: the advisor exception is in A16a, the transport switch (hosts.md) and SKILL.md" "1 1 1" \
    "$(grep -c '^| A16a .*Exception, an advisor call' "$ROOT/docs/unattended.md") $(grep -c '^\*\*Not for an advisor call\*\*' "$ROOT/docs/hosts.md") $(grep -c 'The one exception is an advisor call' "$ROOT/SKILL.md")"
  # shellcheck disable=SC2016  # literal backticks
  eq "the advisor's flags are in the READMEs and docs/policy.md names its keys" "1 1 3" \
    "$(grep -c -- '--advisor <task>' "$ROOT/README.md") $(grep -c -- '--advisor <zadanie>' "$ROOT/README_pl.md") $(grep -cE '^\| `(advisor|advisor_checkpoints) = |, `advise` \|' "$ROOT/docs/policy.md")"
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
  jqt "codex advisor: the read-only profile → OK" "$(idc --role advisor --model gpt-6.1-sol --effort high)" '.result == "OK" and .effective_config.sandbox == "read-only"'
  jqt "codex: wrong effort → MISMATCH" "$(idc --role critic --model gpt-6.1-sol --effort medium)" '.result == "MISMATCH" and (.mismatches | index("effort=high") != null)'
  jqt "codex: a critic on a writer profile → MISMATCH" "$(idc --role builder --root /r --model gpt-6.1-sol --effort high)" '.result == "MISMATCH"'
  ro_tc workspace-write gpt-6.1-sol medium /r >> "$RO"
  jqt "codex resume: the record after the offset is the one checked" "$(idc --role builder --root /r --offset 2 --model gpt-6.1-sol --effort medium)" '.result == "OK"'
  jqt "codex resume: a writer outside its root → MISMATCH" "$(idc --role builder --root /other --offset 2 --model gpt-6.1-sol --effort medium)" '.mismatches | any(test("writable="))'
  jqt "codex advisor on a writer profile → MISMATCH" "$(idc --role advisor --offset 2 --model gpt-6.1-sol --effort medium)" '.result == "MISMATCH" and (.mismatches | any(test("sandbox=workspace-write")))'
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
  eq "preflight: .maestro/ excluded once, schemas copied (advice-schema.json the fifth)" "1 5 1" "$(grep -cxF '.maestro/' "$(git rev-parse --git-path info/exclude)") $(find .maestro -maxdepth 1 -name '*-schema.json' | wc -l) $(find .maestro -maxdepth 1 -name advice-schema.json | wc -l)"
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
  # --advisor on --resume: compare against the saved snapshot BEFORE preflight, which restores the schemas
  GDP="$(git rev-parse --git-dir)/maestro"; mkdir -p "$GDP"
  pf --resume >/dev/null; "$B/maestro-fp" snapshot > "$GDP/fp-adv-1.json"
  printf '{"type":"object"}\n' > .maestro/advice-schema.json          # what a misbehaving advisor could do
  jqt "advisor resume: compare first → the edited advice schema is caught" "$("$B/maestro-fp" compare "$GDP/fp-adv-1.json")" \
    '.result == "changed" and (.diffs | index("protected .maestro inputs") != null)'
  pf --resume >/dev/null
  jqt "… after preflight --resume (schemas copied back) the same compare says same: so it must come first" \
    "$("$B/maestro-fp" compare "$GDP/fp-adv-1.json")" '.result == "same"'
  rm -f "$GDP/fp-adv-1.json"
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
  jqt "bare --cascade leaves the drafter to policy (default)" "$(fl --cascade t)" '.flags.cascade == "default"'
  jqt "--cascade=haiku names the drafter" "$(fl --cascade=haiku t)" '.flags.cascade == "haiku"'
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
  # --advisor
  jqt "--advisor bare → auto, one checkpoint left to policy" "$(fl --advisor t)" '.flags.advisor == "auto" and .flags.advisor_checkpoints == null and .errors == []'
  jqt "--advisor=astra" "$(fl --advisor=astra t)" '.flags.advisor == {slot: "astra", transport: null}'
  jqt "--advisor=neon (explicit-only, named)" "$(fl --advisor=neon t)" '.flags.advisor == {slot: "neon", transport: null} and .errors == []'
  jqt "--advisor=astra@codex --advisor-checkpoints=2" "$(fl --advisor=astra@codex --advisor-checkpoints=2 t)" '.flags.advisor == {slot: "astra", transport: "codex"} and .flags.advisor_checkpoints == 2 and .errors == []'
  jqt "no --advisor → advisor and advisor_checkpoints null" "$(fl t)" '.flags.advisor == null and .flags.advisor_checkpoints == null'
  jqt "--sdk --advisor (auto, no transport) is legal" "$(fl --sdk --advisor t)" '.errors == []'
  jqt "--advisor with --model=opus and --unattended is legal" "$(fl --advisor --model=opus --unattended t)" '.errors == []'
  for c in "--advisor=:--advisor needs" "--advisor=self:self only builds" "--advisor=grok:unknown slot grok" "--advisor=sol@agy:has no transport agy" \
           "--advisor-checkpoints=0:--advisor-checkpoints is 1 to 3" "--advisor-checkpoints=4 --advisor:--advisor-checkpoints is 1 to 3" \
           "--advisor-checkpoints --advisor:--advisor-checkpoints is 1 to 3" "--advisor --advisor=sol:--advisor given twice" \
           "--advisr:did you mean --advisor?" "--advisor-checkpoint=2:did you mean --advisor-checkpoints?"; do
    a="${c%%:*}" want="${c#*:}"
    # shellcheck disable=SC2086
    out="$(fl $a t)"; rc=$?
    if [[ $rc -ne 0 ]] && jq -e --arg w "$want" '.errors | any(contains($w))' >/dev/null <<<"$out"; then ok "flag error: $a"; else bad "flag error: $a" "$out"; fi
  done
  for c in "--advisor-checkpoints=2:--advisor-checkpoints without --advisor" "--advisor --plan-only:--advisor with --plan-only" \
           "--advisor --cascade:--advisor with --cascade" "--advisor=sol --cascade=haiku:--advisor with --cascade" \
           "--advisor --model=self:--advisor with --model=self" "--sdk --advisor=opus@native:--sdk with a forced @native" \
           "--resume --advisor:--resume with --advisor"; do
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
  printf -- '---\nskill: maestro\nrun_id: rs\nstage: critique\ndecisions:\n  current:\n    decision_id: d-1\n    question: x\n  history: []\n---\n' > "$WORK/cp-block.md"
  "$B/maestro-state" --gen "$g" adopt CHECKPOINT.md --reason t >/dev/null 2>&1 || true
  cp "$WORK/cp-block.md" .maestro/CHECKPOINT.md
  jqt "status: an open decision written as a block map counts" "$("$B/maestro-status" --json)" '.decisions_open == 1'
  jqt "status: --peek works with a malformed MAESTRO_WAIT_MAX" "$(MAESTRO_WAIT_MAX=1.5 "$B/maestro-wait" rs.build.r2.a1 --peek)" '.state == "exited"' 
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
  printf '%s\n' '{"type":"rate_limit_event","rate_limit_info":{"rateLimitType":"five_hour","utilization":0.2}}' >> "$LS/jobs/j1/out"
  jqt "limits: a later five-hour event does not hide a fuller seven-day window" \
    "$(MAESTRO_STATE="$LS" CODEX_HOME="$LS/codex" "$B/maestro-limits")" '.claude.utilization == 0.93 and .claude.window == "seven_day"'
  touch -d '-8 hours' "$LS/jobs/j1/out"
  jqt "limits: an old record is stale" "$(MAESTRO_STATE="$LS" CODEX_HOME="$LS/codex" "$B/maestro-limits")" '.claude.stale == true and (.warnings[0] | test("min old"))'
  jqt "limits: no sources → reasons, no warnings" "$(MAESTRO_STATE="$WORK/none-l" CODEX_HOME="$WORK/none-c" "$B/maestro-limits")" \
    '.claude.utilization == null and .codex.utilization == null and .warnings == []'
fi

# =============================================================================================
if group T18 "policy"; then
  PD="$WORK/policy"; mkdir -p "$PD"
  pol() { "$B/maestro-policy" resolve --repo "$PD/repo.toml" --user "$PD/user.toml" "$@"; }
  prepo() { printf '%s\n' "$@" > "$PD/repo.toml"; }
  puser() { printf '%s\n' "$@" > "$PD/user.toml"; }
  out="$(pol)"
  jqt "policy: no files → the defaults" "$out" \
    '.files == {repo: null, user: null} and .stops == [] and .warnings == []
     and .effective == {deny: [], implementer: null, critic: null, reviewer: null, cascade_drafter: "luna", critique_rounds: 2,
           advisor: null, advisor_checkpoints: 1,
           effort: {critique: "medium", high_stakes_critique: "high", build: "medium", review: "high", draft: "medium", advise: "high"},
           families: {claude: "on", openai: "on", google: "on"}, transports_deny: [], pin: {},
           api: {fallback: false, max_usd_per_run: 20}}
     and (.sources | to_entries | all(.value == "default")) and .sources["effort.build"] == "default"'
  jqt "policy: the annotated example resolves clean" "$("$B/maestro-policy" resolve --repo "$ROOT/docs/examples/maestro.policy.toml" --user "$PD/none.toml")" \
    '.stops == [] and .warnings == [] and .effective.implementer == "sol" and .effective.deny == ["fable","haiku"]
     and .effective.pin == {sol: "6.1"} and .effective.families.google == "off" and .effective.api.fallback == true
     and .effective.effort.high_stakes_critique == {claude: "high", openai: "xhigh", google: "high"}
     and .effective.transports_deny == ["opus@agy","sonnet@api"]'

  # per-key precedence: flags > repo > user > defaults
  puser 'implementer = "opus"' 'critic = "sol"' 'critique_rounds = 5' 'deny = ["fable", "haiku"]' \
        '[families]' 'google = "off"' 'openai = "off"' '[transports]' 'deny = ["opus@agy"]' \
        '[pin]' 'sol = "6.1"' 'opus = { native = "claude-opus-5-5" }' '[api]' 'fallback = true' 'max_usd_per_run = 5'
  prepo 'implementer = "sol"' 'critique_rounds = 3' 'deny = ["terra"]' \
        '[families]' 'openai = "on"' '[pin]' 'sol = { codex = "gpt-6.1-sol" }' '[api]' 'max_usd_per_run = 7.5'
  out="$(pol)"
  jqt "policy: scalars per key (repo over user, user where repo is silent)" "$out" \
    '.effective.implementer == "sol" and .sources.implementer == "repo" and .effective.critic == "sol" and .sources.critic == "user"
     and .effective.critique_rounds == 3 and .sources.critique_rounds == "repo" and .sources.reviewer == "default"'
  jqt "policy: a higher deny list replaces the lower one" "$out" '.effective.deny == ["terra"] and .sources.deny == "repo"'
  jqt "policy: transports.deny from the only level that sets it" "$out" '.effective.transports_deny == ["opus@agy"] and .sources["transports.deny"] == "user"'
  jqt "policy: families per key, on lifts a lower off" "$out" \
    '.effective.families == {claude: "on", openai: "on", google: "off"} and .sources["families.openai"] == "repo" and .sources["families.google"] == "user"'
  jqt "policy: pin per slot" "$out" \
    '.effective.pin == {opus: {native: "claude-opus-5-5"}, sol: {codex: "gpt-6.1-sol"}} and .sources["pin.sol"] == "repo" and .sources["pin.opus"] == "user"'
  jqt "policy: api per key" "$out" '.effective.api == {fallback: true, max_usd_per_run: 7.5} and .sources["api.fallback"] == "user" and .sources["api.max_usd_per_run"] == "repo"'
  jqt "policy: files are reported, no stops" "$out" '.files == {repo: "'"$PD"'/repo.toml", user: "'"$PD"'/user.toml"} and .stops == []'
  fl="$("$B/maestro-flags" "--model=opus@agy --rounds=4 --critic=argon --critic=astra --reviewer=terra do it" 2>/dev/null)"
  out="$(pol --flags "$(jq -c .flags <<<"$fl")")"
  jqt "policy: flags beat both files" "$out" \
    '.effective.implementer == "opus" and .effective.critique_rounds == 4 and .effective.reviewer == "terra"
     and .sources.implementer == "flags" and .sources.critique_rounds == "flags" and .sources.critic == "flags" and .sources.reviewer == "flags"'
  jqt "policy: an explicit slot or transport beats a denial, with a warning" "$out" \
    '(.warnings | any(test("^--reviewer=terra: denied"))) and (.warnings | any(test("^opus@agy: transport denied")))'
  jqt "policy: maestro-flags whole line is taken too" "$(pol --flags "$fl")" '.sources.implementer == "flags"'
  prepo 'deny = []'
  jqt "policy: an empty deny list clears the lower one" "$(pol)" '.effective.deny == [] and .sources.deny == "repo" and .effective.implementer == "opus"'

  # effort: per stage, per family
  puser '[effort]' 'review = "low"' 'build = { openai = "ultra", google = "low" }' 'critique = "max"'
  prepo '[effort]' 'review = { openai = "xhigh" }' 'critique = { google = "xhigh" }' 'draft = "low"'
  out="$(pol)"
  jqt "effort: a repo family value over the user single value" "$out" \
    '.effective.effort.review == {claude: "low", openai: "xhigh", google: "low"}
     and .sources["effort.review.openai"] == "repo" and .sources["effort.review.claude"] == "user" and (.sources | has("effort.review") | not)'
  jqt "effort: user family values, the default for the family left out" "$out" \
    '.effective.effort.build == {claude: "medium", openai: "ultra", google: "low"} and .sources["effort.build.claude"] == "default"'
  jqt "effort: single values stay single" "$out" \
    '.effective.effort.draft == "low" and .sources["effort.draft"] == "repo" and .effective.effort.high_stakes_critique == "high"
     and .effective.effort.critique == {claude: "max", openai: "max", google: "xhigh"} and .stops == []'
  puser '[effort]' 'review = { openai = "ultra" }'
  prepo '[effort]' 'review = "medium"'
  jqt "effort: a repo single value beats a user family value" "$(pol)" '.effective.effort.review == "medium" and .sources["effort.review"] == "repo"'

  # validation: only the winning value of a key is checked
  rm -f "$PD/user.toml"
  stop1() { prepo "${@:3}"; jqt "$1" "$(pol)" '(.stops | length) == 1 and (.stops[0] | test("'"$2"'"))'; }
  stop1 "stop: unknown slot" "deny: unknown slot gemini-pro" 'deny = ["opus", "gemini-pro"]'
  stop1 "stop: a transport the slot does not have" "transports.deny: haiku has no transport agy" '[transports]' 'deny = ["haiku@agy"]'
  stop1 "stop: a malformed pair" "is not <slot>@<transport>" '[transports]' 'deny = ["opus"]'
  stop1 "stop: an effort that is no level" "effort.build: .hgih. is not an effort level" '[effort]' 'build = "hgih"'
  stop1 "stop: ultra for google" "effort.review.google: ultra is outside the google range" '[effort]' 'review = { google = "ultra" }'
  stop1 "stop: max for google" "outside the google range" '[effort]' 'review = { google = "max" }'
  stop1 "stop: ultra as a single shared value" "effort.review: ultra is an openai level" '[effort]' 'review = "ultra"'
  stop1 "stop: an unknown effort family" "effort.review.mistral: unknown family" '[effort]' 'review = { mistral = "low" }'
  stop1 "stop: critique_rounds 9" "critique_rounds: 9 is outside 1–8" 'critique_rounds = 9'
  stop1 "stop: critique_rounds true" "critique_rounds: true is outside" 'critique_rounds = true'
  stop1 "stop: cascade_drafter sol" "cascade_drafter: must be one of luna, haiku, gemini" 'cascade_drafter = "sol"'
  stop1 "stop: an unknown family" "families.mistral: unknown family" '[families]' 'mistral = "off"'
  stop1 "stop: a family value that is not on or off" "families.google: must be" '[families]' 'google = "maybe"'
  stop1 "stop: self as critic" "critic: self only builds" 'critic = "self"'
  stop1 "stop: an unquoted pin version" "pin.sol: the version must be a quoted string" '[pin]' 'sol = 6.1'
  stop1 "stop: a pin on a transport the slot lacks" "pin.sol: sol has no transport agy" '[pin]' 'sol = { agy = "gpt-6.1-sol" }'
  stop1 "stop: a pin slug of another line" "pin.sol: codex: .* is not a sol slug" '[pin]' 'sol = { codex = "gpt-6-astra" }'
  stop1 "stop: a pin for an unknown slot" "pin.gpt: unknown slot" '[pin]' 'gpt = "5"'
  stop1 "stop: api.max_usd_per_run not a number" "api.max_usd_per_run: must be a number" '[api]' 'max_usd_per_run = "20"'
  stop1 "stop: a TOML date where a number belongs" "critique_rounds: .2026-11-14. is outside" 'critique_rounds = 2026-11-14'
  stop1 "stop: a TOML date as an effort" "effort.build: .2026-11-14. is not an effort level" '[effort]' 'build = 2026-11-14'
  stop1 "stop: a TOML date in transports.deny" "is not <slot>@<transport>" '[transports]' 'deny = [2026-11-14]'
  stop1 "stop: an infinite budget" "api.max_usd_per_run: must be a number" '[api]' 'max_usd_per_run = inf'
  stop1 "stop: a table key given a scalar" "effort must be a table" 'effort = "high"'
  stop1 "stop: a policy implementer that is denied" "implementer fable .repo policy. is not eligible: denied" 'implementer = "fable"' 'deny = ["fable"]'
  stop1 "stop: a policy implementer of a family switched off" "implementer sol .* families.openai is off" 'implementer = "sol"' '[families]' 'openai = "off"'
  stop1 "stop: a policy drafter of a family switched off" "cascade_drafter gemini .* families.google is off" 'cascade_drafter = "gemini"' '[families]' 'google = "off"'
  prepo 'deny = ["luna"]' 'implementer = "self"' '[families]' 'claude = false'
  jqt "policy: a denied default drafter is no stop; self survives families.claude off; false reads as off" "$(pol)" \
    '.stops == [] and .effective.families.claude == "off" and .effective.implementer == "self"'
  prepo 'critic = "argon"' '[families]' 'google = "off"'
  jqt "policy: an ineligible critic preference is dropped with a warning" "$(pol)" '.stops == [] and (.warnings | any(test("policy critic argon dropped: families.google is off")))'
  jqt "policy: --model and --critic beat a family switch, with a warning" \
    "$(pol --flags '{"model":{"slot":"gemini","transport":null},"critics":[{"slot":"argon","transport":null}]}')" \
    '(.warnings | any(test("^--model=gemini: families.google is off"))) and (.warnings | any(test("^--critic=argon: families.google is off"))) and .stops == []'
  puser 'implementer = "gpt-5"' 'critique_rounds = 12'
  prepo 'implementer = "sol"' 'critique_rounds = 3'
  jqt "policy: precedence first — a losing value is not validated" "$(pol)" '.stops == [] and .effective.implementer == "sol"'
  rm -f "$PD/user.toml"

  # the names 2.0.0 removed stop, wherever they stand
  stop1 "removed: the slot grok" "deny: the slot grok was removed in 2.0.0" 'deny = ["grok"]'
  stop1 "removed: the key cursor_fast" "the key cursor_fast was removed in 2.0.0" 'cursor_fast = false'
  stop1 "removed: families.xai" "families.xai: the family xai was removed in 2.0.0" '[families]' 'xai = "on"'
  stop1 "removed: effort.<stage>.xai" "effort.build.xai: the family xai was removed" '[effort]' 'build = { xai = "high" }'
  stop1 "removed: a <slot>@cursor pair" "fable@cursor: the transport cursor was removed in 2.0.0" '[transports]' 'deny = ["fable@cursor"]'
  stop1 "removed: a cursor pin" "pin.opus: the transport cursor was removed" '[pin]' 'opus = { cursor = "claude-opus-5" }'
  puser 'cursor_fast = true' 'deny = ["grok"]'; prepo 'deny = ["opus"]'
  jqt "removed: a removed name stops even where the higher file wins" "$(pol)" '(.stops | length) == 2 and (.stops | all(test("^user policy .*removed in 2.0.0"))) and .effective.deny == ["opus"]'
  rm -f "$PD/user.toml"

  # unknown keys warn and are ignored
  prepo 'implementer = "sol"' 'colour = "red"' '[effort]' 'deploy = "high"' '[api]' 'region = "eu"' '[transports]' 'allow = []'
  jqt "policy: unknown keys warn, the rest applies" "$(pol)" \
    '.stops == [] and .effective.implementer == "sol" and (.warnings | length) == 4
     and (.warnings | map(capture("unknown key (?<k>[a-z._]+)").k) | sort) == ["api.region","colour","effort.deploy","transports.allow"]'

  # malformed TOML, a YAML file left behind
  prepo 'implementer = sol'
  jqt "policy: malformed TOML is a stop with the parser's message" "$(pol)" \
    '(.stops | length) == 1 and (.stops[0] | test("repo policy .*repo.toml.: malformed TOML: Invalid value \\(at line 1, column 15\\)")) and .effective.implementer == null and .files.repo != null'
  prepo 'implementer = "sol"'; printf 'implementer: opus\n' > "$PD/repo.yml"
  jqt "policy: a .yml next to the policy is a stop" "$(pol)" '.stops == ["convert to TOML: '"$PD"'/repo.yml → '"$PD"'/repo.toml"] and .effective.implementer == "sol"'
  rm -f "$PD/repo.yml" "$PD/repo.toml"

  # default locations: <repo top>/maestro.policy.toml and $XDG_CONFIG_HOME/maestro/policy.toml
  REPO="$(new_repo)"; XC="$WORK/xdg"; mkdir -p "$REPO/sub" "$XC/maestro"
  printf 'implementer = "sol"\n' > "$REPO/maestro.policy.toml"; printf 'critic = "opus"\n' > "$XC/maestro/policy.toml"
  out="$(cd "$REPO/sub" && XDG_CONFIG_HOME="$XC" "$B/maestro-policy" resolve)"
  jqt "policy: default files, from a subdirectory" "$out" \
    '.files == {repo: "'"$REPO"'/maestro.policy.toml", user: "'"$XC"'/maestro/policy.toml"} and .sources.implementer == "repo" and .sources.critic == "user"'
  : > "$REPO/maestro.policy.yml"; rm "$XC/maestro/policy.toml"; : > "$XC/maestro/policy.yml"
  out="$(cd "$REPO" && XDG_CONFIG_HOME="$XC" "$B/maestro-policy" resolve)"
  jqt "policy: 1.x YAML files at the default places stop" "$out" \
    '.stops == ["convert to TOML: '"$XC"'/maestro/policy.yml → '"$XC"'/maestro/policy.toml", "convert to TOML: '"$REPO"'/maestro.policy.yml → '"$REPO"'/maestro.policy.toml"] and .files.user == null'
  mkdir -p "$WORK/norepo"
  out="$(cd "$WORK/norepo" && GIT_CEILING_DIRECTORIES="$WORK" XDG_CONFIG_HOME="$WORK/none-x" "$B/maestro-policy" resolve)"
  jqt "policy: outside a repository → defaults, no stop" "$out" '.files == {repo: null, user: null} and .stops == []'
  "$B/maestro-policy" resolve --flags '{oops' >/dev/null 2>&1; eq "policy: bad --flags is a usage error" 2 $?
  "$B/maestro-policy" merge >/dev/null 2>&1; eq "policy: unknown command is a usage error" 2 $?
  prepo 'critique_rounds = 99'; pol >/dev/null; eq "policy: exit 0 with stops" 0 $?

  # roles-input: what the policy contributes to maestro-roles
  ri() { "$B/maestro-policy" roles-input --repo "$PD/repo.toml" --user "$PD/user.toml" "$@"; }
  prepo 'deny = ["fable", "haiku"]' 'critic = "opus"' 'reviewer = "argon"' '[families]' 'google = "off"' '[transports]' 'deny = ["opus@agy", "sonnet@api", "sonnet@agy"]'
  out="$(ri)"
  jqt "roles-input: critic, reviewer (an ineligible one dropped), the exclusion filter" "$out" \
    '.policy_critic == "opus" and .policy_reviewer == null and .named_critics == [] and .named_reviewer == null
     and .exclude == {slots: ["fable","haiku","argon","carbon","neon","gemini"], denied: ["fable","haiku"], families_off: ["google"], kept_by_flag: [], advisor_kept: []}
     and .explicit_only == []
     and .transports_denied == {opus: ["agy"], sonnet: ["api","agy"]} and .fable_budget == false and .stops == []
     and (.warnings | any(test("policy reviewer argon dropped"))) and (.unmapped | any(test("^fable_budget")))'
  out="$(ri --flags '{"model":{"slot":"fable","transport":null},"critics":[{"slot":"sol","transport":null},{"slot":"haiku","transport":null}],"reviewer":{"slot":"sol","transport":null}}')"
  jqt "roles-input: flag-named slots stay eligible; named critics replace the policy critic" "$out" \
    '.policy_critic == null and .named_critics == ["sol","haiku"] and .named_reviewer == "sol"
     and .exclude.slots == ["argon","carbon","neon","gemini"] and .exclude.kept_by_flag == ["fable","haiku"] and (has("fable_budget") | not)'
  # …and maestro-roles takes it: the policy critic wins over the table's first choice
  rin="$(jq -c '{builder: "sol", eligible: (["opus","sonnet","fable","sol","astra","argon","gemini"] - .exclude.slots), policy_critic, policy_reviewer, named_critics}' <<<"$(ri)")"
  jqt "roles-input → maestro-roles" "$("$B/maestro-roles" <<<"$rin")" '.critics == ["opus"] and .stop == null and (.notes | index("critic=opus (policy)") != null)'
  prepo 'reviewer = "neon"'
  out="$(ri)"
  jqt "roles-input: a policy reviewer neon is passed on; carbon and neon stay eligible as explicit-only" "$out" \
    '.policy_reviewer == "neon" and .explicit_only == ["carbon","neon"] and (.exclude.slots | index("neon")) == null and .stops == []'
  rin="$(jq -c '{builder: "sol", eligible: (["sol","astra","carbon","neon"] - .exclude.slots), policy_critic, policy_reviewer, named_critics, named_reviewer}' <<<"$out")"
  jqt "roles-input → maestro-roles: reviewer neon, critic still Astra (degraded)" "$("$B/maestro-roles" <<<"$rin")" '.critics == ["astra"] and .reviewer == "neon" and .degraded == "openai"'
  out="$(ri --flags "$("$B/maestro-flags" "--critic=neon --reviewer=carbon t")")"
  jqt "roles-input: --critic=neon and --reviewer=carbon are accepted names" "$out" '.named_critics == ["neon"] and .named_reviewer == "carbon" and .stops == []'
  cd "$ROOT" || exit 2
  prepo 'cascade_drafter = "gemini"'; puser
  jqt "policy: bare --cascade with the policy drafter as implementer → stop" \
    "$(pol --flags "$("$B/maestro-flags" "--cascade --model=gemini t")")" '.stops | any(test("drafter gemini .* is the implementer"))'
  prepo 'deny = ["haiku"]'
  jqt "policy: --cascade=<denied slot> is kept with an explicit-wins warning" \
    "$("$B/maestro-policy" roles-input --repo "$PD/repo.toml" --user "$PD/user.toml" --flags "$("$B/maestro-flags" "--cascade=haiku t")")" \
    '(.exclude.kept_by_flag | index("haiku") != null) and (.warnings | any(test("--cascade=haiku")))'
  # the advisor keys: advisor (names, never enables), advisor_checkpoints, effort.advise
  prepo 'advisor = "astra"' 'advisor_checkpoints = 2' '[effort]' 'advise = "xhigh"'
  puser 'advisor = "opus"' 'advisor_checkpoints = 3' '[effort]' 'advise = "low"'
  out="$(pol)"
  jqt "policy: advisor, advisor_checkpoints and effort.advise from repo over user" "$out" \
    '.effective.advisor == "astra" and .effective.advisor_checkpoints == 2 and .effective.effort.advise == "xhigh"
     and .sources.advisor == "repo" and .sources.advisor_checkpoints == "repo" and .sources["effort.advise"] == "repo" and .stops == []'
  prepo
  jqt "policy: … from the user file where the repo is silent" "$(pol)" '.effective.advisor == "opus" and .effective.advisor_checkpoints == 3 and .effective.effort.advise == "low" and .sources.advisor == "user"'
  jqt "policy: --advisor=<slot> and --advisor-checkpoints beat both files" "$(pol --flags "$("$B/maestro-flags" "--advisor=argon --advisor-checkpoints=1 t")")" \
    '.effective.advisor == "argon" and .effective.advisor_checkpoints == 1 and .sources.advisor == "flags" and .sources.advisor_checkpoints == "flags"'
  jqt "policy: a bare --advisor keeps the policy advisor" "$(pol --flags "$("$B/maestro-flags" "--advisor t")")" '.effective.advisor == "opus" and .sources.advisor == "user"'
  out="$(ri)"
  jqt "roles-input: a policy advisor alone enables nothing (advisor_on false)" "$out" '.advisor_on == false and .policy_advisor == "opus" and .named_advisor == null'
  jqt "roles-input: … and maestro-roles then returns no advisor" \
    "$("$B/maestro-roles" <<<"$(jq -c '{builder: "sol", eligible: ["sol","opus"], advisor_on, named_advisor, policy_advisor}' <<<"$out")")" '.advisor == null and .critics == ["opus"]'
  out="$(ri --flags "$("$B/maestro-flags" "--advisor t")")"
  jqt "roles-input: bare --advisor → advisor_on, the policy advisor passed on" "$out" '.advisor_on == true and .policy_advisor == "opus" and .named_advisor == null'
  jqt "roles-input → maestro-roles: the policy advisor is used, marked (policy)" \
    "$("$B/maestro-roles" <<<"$(jq -c '{builder: "sol", eligible: ["sol","opus","argon"], advisor_on, named_advisor, policy_advisor}' <<<"$out")")" \
    '.advisor == "opus" and (.notes | index("advisor=opus (policy)") != null)'
  puser 'advisor = "sol"' 'deny = ["sol"]'
  out="$(ri --flags "$("$B/maestro-flags" "--advisor t")")"
  jqt "roles-input: a denied policy advisor is dropped with a warning" "$out" '.policy_advisor == null and (.warnings | any(test("policy advisor sol dropped: denied"))) and .exclude.advisor_kept == []'
  out="$(ri --flags "$("$B/maestro-flags" "--advisor=sol t")")"
  jqt "roles-input: a denied slot named by --advisor is kept for the advisor role only" "$out" \
    '.named_advisor == "sol" and .exclude.advisor_kept == ["sol"] and .exclude.kept_by_flag == [] and (.exclude.slots | index("sol") != null)
     and (.warnings | any(test("^--advisor=sol: denied by policy — explicit wins, for the advisor role only")))'
  # the director's recipe: eligible = available - exclude.slots; advisor_eligible = eligible + exclude.advisor_kept
  pipe() { jq -c --argjson av "$1" '{builder: "opus", eligible: ($av - .exclude.slots), advisor_eligible: (($av - .exclude.slots) + .exclude.advisor_kept),
                 available: $av, advisor_on, named_advisor, policy_advisor}' <<<"$out" | "$B/maestro-roles"; }
  noadv="$(jq -nc '{builder: "opus", eligible: ["opus","astra"]}' | "$B/maestro-roles")"
  jqt "roles-input → maestro-roles: denied but available sol advises; astra critiques and reviews as without it" "$(pipe '["opus","sol","astra"]')" \
    '.advisor == "sol" and .stop == null and .critics == ["astra"] and .reviewer == "astra" and .critics == '"$(jq -c .critics <<<"$noadv")"
  jqt "roles-input → maestro-roles: denied AND unavailable sol (Codex down, no openai slot available) → stop" "$(pipe '["opus","argon"]')" \
    '.advisor == null and (.stop.reason | test("named advisor sol is not available"))'
  jqt "roles-input → maestro-roles: denied sol, Codex unavailable, astra gone too → stop, not advisor sol" "$(pipe '["opus","gemini"]')" '.advisor == null and .stop != null'
  # setup step 1b: the policy advisor is offered by name only when maestro-roles keeps it
  puser 'advisor = "sol"'
  out="$(ri --flags "$("$B/maestro-flags" "--advisor t")")"
  r1b="$("$B/maestro-roles" <<<"$(jq -c '{builder: "opus", eligible: ["opus","argon"], available: ["opus","argon"], advisor_on, named_advisor, policy_advisor}' <<<"$out")")"
  jqt "setup 1b: policy advisor sol, Codex unavailable, argon eligible → auto picks argon, noted (offer auto, not --advisor=sol)" "$r1b" \
    '.advisor == "argon" and .stop == null and (.notes | index("policy advisor sol is not available: auto") != null)'
  jqt "setup 1b: … while --advisor=sol for the same roster would halt the run" \
    "$("$B/maestro-roles" <<<'{"builder":"opus","eligible":["opus","argon"],"available":["opus","argon"],"advisor_on":true,"named_advisor":"sol"}')" '.advisor == null and .stop != null'
  puser 'advisor = "sol"' 'deny = ["sol"]'
  out="$(ri --flags "$("$B/maestro-flags" "--advisor t")")"
  r1b="$("$B/maestro-roles" <<<"$(jq -c '{builder: "opus", eligible: (["opus","sol","argon"] - .exclude.slots), available: ["opus","sol","argon"], advisor_on, named_advisor, policy_advisor}' <<<"$out")")"
  jqt "setup 1b: policy advisor sol denied by policy → dropped (warning), auto picks argon" "$out" '.policy_advisor == null and (.warnings | any(test("policy advisor sol dropped: denied")))'
  jqt "setup 1b: … and maestro-roles gives argon, not sol" "$r1b" '.advisor == "argon" and .stop == null'
  # auto never promises a slot at step 1b: the result depends on review_active, which step 2 decides
  s1b() { jq -c --argjson ra "$1" '{builder: "opus", eligible: (["opus","sol","astra","argon"] - .exclude.slots), available: ["opus","sol","astra","argon"],
                                    advisor_on, named_advisor, policy_advisor, review_active: $ra}' <<<"$out" | "$B/maestro-roles"; }
  jqt "setup 1b → step 2: Opus builds, sol denied, no review → auto resolves to astra" "$(s1b false)" '.advisor == "astra" and .reviewer == "astra"'
  jqt "setup 1b → step 2: … with --review=cross (reviewer astra) → auto resolves to argon: name it only after step 2" \
    "$(s1b true)" '.advisor == "argon" and .reviewer == "astra"'
  jqt "setup 1b → step 2: Opus builds, astra the only cross-family slot, --review=cross → astra advises and reviews, anchored" \
    "$(jq -nc '{builder: "opus", eligible: ["opus","sonnet","astra"], available: ["opus","sonnet","astra"], advisor_on: true, review_active: true}' | "$B/maestro-roles")" \
    '.advisor == "astra" and .reviewer == "astra" and .critics == ["astra"] and .stop == null
     and (.notes | index("advisor and reviewer share a family") != null) and (.notes | index("reviewer anchored: the advisor shaped the build") != null)'
  # shellcheck disable=SC2016  # literal backticks
  eq "docs: setup says reviewer avoidance is a preference and keeps the anchoring warning" 1 "$(grep -c '^- \*\*Avoiding the reviewer.s family is a preference\*\*' "$ROOT/docs/setup.md")"
  # shellcheck disable=SC2016  # literal backticks
  eq "docs: setup offers auto without naming a slot and names the resolved one after step 2" "1 1" \
    "$(grep -c '^- \*\*`auto` never promises a slot.\*\*' "$ROOT/docs/setup.md") $(grep -c 'with `review_active` known and \*\*name the resolved slot\*\*' "$ROOT/docs/setup.md")"
  puser 'advisor = "sol"'
  out="$(ri --flags "$("$B/maestro-flags" "--advisor t")")"
  jqt "setup 1b: policy advisor sol eligible → kept, marked (policy): offer it by name" \
    "$("$B/maestro-roles" <<<"$(jq -c '{builder: "opus", eligible: ["opus","sol","argon"], available: ["opus","sol","argon"], advisor_on, named_advisor, policy_advisor}' <<<"$out")")" \
    '.advisor == "sol" and (.notes | index("advisor=sol (policy)") != null)'
  rm -f "$PD/user.toml"
  stop1 "stop: advisor_checkpoints 4" "advisor_checkpoints: 4 is outside 1–3" 'advisor_checkpoints = 4'
  stop1 "stop: advisor_checkpoints 0" "advisor_checkpoints: 0 is outside 1–3" 'advisor_checkpoints = 0'
  stop1 "stop: an unknown advisor slot" "advisor: unknown slot gpt-6" 'advisor = "gpt-6"'
  stop1 "stop: self as advisor" "advisor: self only builds" 'advisor = "self"'
  stop1 "stop: effort.advise ultra as a single value" "effort.advise: ultra is an openai level" '[effort]' 'advise = "ultra"'
  prepo; puser
fi

_gtime
printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then printf '  %s\n' "${failed[@]}"; exit 1; fi
