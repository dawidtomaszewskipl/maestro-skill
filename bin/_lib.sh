# shellcheck shell=bash
# Shared helpers for route2's bin/ scripts. Sourced, never executed.
#
# Conventions: every script is bash >= 5 with `set -euo pipefail`, prints machine-readable JSON on
# stdout when it reports, human text on stderr, and exits non-zero only on a real error.

# --help / -h on any helper prints its header comment (the usage) and exits.
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{/^#/s/^# \{0,1\}//p}' "$0"
  exit 0
fi

R2_BIN="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
R2_ROOT="$(dirname "$R2_BIN")"
export R2_BIN R2_ROOT

r2_die() { printf 'route2: %s\n' "$*" >&2; exit 2; }
r2_warn() { printf 'route2: %s\n' "$*" >&2; }
r2_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The state directory: $ROUTE2_STATE if set (tests), else <repo top>/.route2.
r2_state_dir() {
  if [[ -n "${ROUTE2_STATE:-}" ]]; then
    printf '%s\n' "$ROUTE2_STATE"
  else
    local top
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || r2_die "not inside a git repository"
    printf '%s/.route2\n' "$top"
  fi
}

# /proc root, overridable for fixtures.
r2_proc() { printf '%s\n' "${ROUTE2_PROC:-/proc}"; }

r2_sha256_file() {
  if [[ -f "$1" ]]; then sha256sum "$1" | cut -d' ' -f1; else printf 'absent\n'; fi
}

# Atomic write: r2_atomic_write <path>  (content on stdin)
r2_atomic_write() {
  local dest="$1" tmp
  tmp="$(mktemp "${dest}.tmp.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$dest"
}

# Process start time (field 22 of /proc/<pid>/stat), empty if the process is gone or unreadable.
r2_pid_starttime() {
  local pid="$1" stat
  stat="$(cat "$(r2_proc)/$pid/stat" 2>/dev/null)" || return 0
  # The comm field may contain spaces and parentheses: cut after the last ')'.
  stat="${stat##*) }"
  # After the cut, field 1 is state (field 3 overall); starttime is field 22 overall → 20 here.
  awk '{print $20}' <<<"$stat"
}

r2_pid_ppid() {
  local pid="$1" stat
  stat="$(cat "$(r2_proc)/$pid/stat" 2>/dev/null)" || return 0
  stat="${stat##*) }"
  awk '{print $2}' <<<"$stat"
}

r2_pid_pgid() {
  local pid="$1" stat
  stat="$(cat "$(r2_proc)/$pid/stat" 2>/dev/null)" || return 0
  stat="${stat##*) }"
  awk '{print $3}' <<<"$stat"
}

# Alive and the same process (start time unchanged)?  r2_pid_same <pid> <starttime>
r2_pid_same() {
  local now
  now="$(r2_pid_starttime "$1")"
  [[ -n "$now" && "$now" == "$2" ]]
}

# NUL-separated cmdline as one space-joined line ("" if unreadable).
r2_pid_cmdline() {
  { tr '\0' ' ' < "$(r2_proc)/$1/cmdline"; } 2>/dev/null | sed 's/ $//' || true
}

r2_pid_exe() { readlink "$(r2_proc)/$1/exe" 2>/dev/null || true; }
r2_pid_cwd() { readlink "$(r2_proc)/$1/cwd" 2>/dev/null || true; }

# PIDs owned by the current user (own UID only; other users' entries are skipped quietly).
r2_own_pids() {
  local uid p d
  uid="$(id -u)"
  for d in "$(r2_proc)"/[0-9]*; do
    p="${d##*/}"
    [[ -O "$d" || "$(stat -c %u "$d" 2>/dev/null)" == "$uid" ]] || continue
    printf '%s\n' "$p"
  done
}

# --- fence ------------------------------------------------------------------------------------
# Every mutating script self-wraps through `route2-lock exec --gen N -- <script> __locked …`.
# Inside the fence ROUTE2_IN_FENCE=1 is exported; a nested `route2-lock exec` refuses instead of
# deadlocking (the flock is held by the outer flock(1) process on its own descriptor).
r2_in_fence() { [[ "${ROUTE2_IN_FENCE:-}" == "1" ]]; }

# --- audit of director bookkeeping (docs/checkpoint.md, "Audit") -----------------------------
# .route2/audit.jsonl: {file, sha256_after, gen, at}, append-only. `file` is relative to the state
# directory. Verify-before-write: the file's current hash must equal its last audit entry (absent
# file + no entry is fine). A mismatch means something outside route2-state changed the file.
r2_audit_last() {
  local sd="$1" rel="$2"
  [[ -f "$sd/audit.jsonl" ]] || { echo ""; return 0; }
  jq -r --arg f "$rel" 'select(.file == $f) | .sha256_after' "$sd/audit.jsonl" | tail -1
}

r2_audit_verify() {
  local sd="$1" rel="$2" last cur
  last="$(r2_audit_last "$sd" "$rel")"
  cur="$(r2_sha256_file "$sd/$rel")"
  if [[ -z "$last" ]]; then
    [[ "$cur" == "absent" ]] && return 0
    r2_warn "audit: $rel exists but has no audit entry"; return 1
  fi
  [[ "$last" == "$cur" ]] && return 0
  r2_warn "audit: $rel changed outside route2 (expected ${last:0:12}, found ${cur:0:12})"
  return 1
}

r2_audit_record() {
  local sd="$1" rel="$2" gen="${3%%.*}"     # a fence "<gen>.<secret>": only the generation is written
  jq -cn --arg f "$rel" --arg s "$(r2_sha256_file "$sd/$rel")" --arg g "$gen" --arg at "$(r2_now)" \
    '{file: $f, sha256_after: $s, gen: ($g | tonumber? // $g), at: $at}' >> "$sd/audit.jsonl"
}

# "pid ppid pgid" for every process whose stat is readable, one line each. `cat` keeps going past
# a file that vanished or cannot be opened (awk would stop at the first one); the pid is taken
# from the stat line itself, so no file name is needed.
r2_proc_table() {
  cat "$(r2_proc)"/[0-9]*/stat 2>/dev/null \
    | awk '{ pid = $1; line = $0; sub(/^.*\) /, "", line); split(line, f, " ");
             if (pid ~ /^[0-9]+$/ && f[2] ~ /^[0-9]+$/ && f[3] ~ /^[0-9]+$/) print pid, f[2], f[3] }'
}

# The identity of a pid right now: its start time, "gone" (no /proc entry), or "unreadable" (the
# entry exists but its stat cannot be read). Callers must never treat "unreadable" as "gone".
r2_pid_identity() {
  local st
  st="$(r2_pid_starttime "$1")"
  if [[ -n "$st" ]]; then printf '%s\n' "$st"
  elif [[ -e "$(r2_proc)/$1" ]]; then echo unreadable
  else echo gone; fi
}
