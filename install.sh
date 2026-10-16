#!/usr/bin/env bash
# Install the maestro skill for Claude Code, Codex, Cursor and agy.
#
#   ./install.sh [--hosts=claude-code,codex,cursor,agy] [--sdk] [<project>]
#   ./install.sh --check[=live] [<project>]
#
# --sdk also installs the Claude Agent SDK (pinned in sdk/package-lock.json) for the `api`
# transport: `npm ci` in the installed sdk/ — needs Node >= 18 and network. Without it the
# transport stays unavailable and stage 0 says so (README, "API credit").
#
# Global (default): copies SKILL.md, docs/, bin/ and sdk/ into ~/.agents/skills/maestro — read by Codex
# and Cursor — and links ~/.claude/skills/maestro (Claude Code) and the agy skill directory to it.
# With <project>: the same under <project>/.agents/skills/maestro and <project>/.claude/skills/maestro.
# Never touches the older /route skill (…/skills/route).
#
# --check lists where maestro is installed; --check=live also asks each host to list its skills
# (one cheap headless call per host: agy needs no model turn, the others do).
set -euo pipefail

src="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
hosts="claude-code,codex,cursor,agy"
check="" project="" sdk=0
for a in "$@"; do
  case "$a" in
    --hosts=*) hosts="${a#--hosts=}" ;;
    --sdk) sdk=1 ;;
    --check) check=files ;;
    --check=live) check=live ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    -*) echo "install.sh: unknown option $a" >&2; exit 2 ;;
    *) project="$(cd "$a" 2>/dev/null && pwd)" || { echo "install.sh: no such directory: $a" >&2; exit 2; } ;;
  esac
done
has() { [[ ",$hosts," == *",$1,"* ]]; }

if [[ -n "$project" ]]; then
  base="$project"
else
  base="$HOME"
fi
canon="$base/.agents/skills/maestro"
claude_link="$base/.claude/skills/maestro"
# agy: its bundled docs name ~/.gemini/config/skills; workspace installs use .agents/skills (the
# canonical copy itself), so a project install needs no separate agy link.
agy_link=""
[[ -z "$project" ]] && agy_link="$HOME/.gemini/config/skills/maestro"

is_maestro_dir() { [[ -f "$1/SKILL.md" ]] && grep -q '^name: maestro$' "$1/SKILL.md"; }

if [[ -n "$check" ]]; then
  for p in "$canon" "$claude_link" ${agy_link:+"$agy_link"}; do
    if [[ -L "$p" ]]; then printf '%-55s -> %s\n' "$p" "$(readlink "$p")"
    elif is_maestro_dir "$p"; then printf '%-55s installed (%s)\n' "$p" "$(git -C "$src" describe --always 2>/dev/null || echo copy)"
    else printf '%-55s missing\n' "$p"; fi
  done
  if [[ "$check" == live ]]; then
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    cwd="${project:-$PWD}"
    if command -v agy >/dev/null 2>&1; then
      agy --add-dir "$cwd" --output-format json --print-timeout 2m -p "/skills" < /dev/null > "$tmp/agy.json" 2>/dev/null || true
      if grep -q maestro "$tmp/agy.json"; then echo "agy: lists maestro"; else echo "agy: maestro NOT listed"; fi
    fi
    q="List the names of the skills available to you, one per line, nothing else."
    if command -v codex >/dev/null 2>&1; then
      codex exec -m gpt-6-luna -s read-only --ignore-user-config -c model_reasoning_effort=low -C "$cwd" -o "$tmp/codex.txt" "$q" < /dev/null > /dev/null 2>&1 || true
      if grep -q maestro "$tmp/codex.txt" 2>/dev/null; then echo "codex: lists maestro"; else echo "codex: maestro NOT listed"; fi
    fi
    if command -v agent >/dev/null 2>&1; then
      (cd "$cwd" && agent -p --mode ask --trust --model grok-4.7-low --output-format json "$q" < /dev/null > "$tmp/cursor.json" 2>/dev/null) || true
      if grep -q maestro "$tmp/cursor.json"; then echo "cursor: lists maestro"; else echo "cursor: maestro NOT listed"; fi
    fi
    if command -v claude >/dev/null 2>&1; then
      (cd "$cwd" && claude -p --model haiku --tools "Skill" --permission-mode dontAsk "$q" < /dev/null > "$tmp/claude.txt" 2>/dev/null) || true
      if grep -q maestro "$tmp/claude.txt"; then echo "claude-code: lists maestro"; else echo "claude-code: maestro NOT listed"; fi
    fi
  fi
  exit 0
fi

# --- install ------------------------------------------------------------------------------------
if [[ -e "$canon" && ! -L "$canon" ]] && ! is_maestro_dir "$canon"; then
  echo "install.sh: $canon exists and is not a maestro install — refusing" >&2; exit 1
fi
if [[ -L "$canon" ]]; then echo "install.sh: $canon is a symlink — refusing (remove it first)" >&2; exit 1; fi
mkdir -p "$canon"
cp "$src/SKILL.md" "$canon/SKILL.md"
rm -rf "${canon:?}/docs" "${canon:?}/bin"
cp -R "$src/docs" "$canon/docs"
cp -R "$src/bin" "$canon/bin"
chmod +x "$canon"/bin/maestro-*
mkdir -p "$canon/sdk"   # node_modules survives a reinstall; the lock file decides whether it is current
cp "$src/sdk/package.json" "$src/sdk/package-lock.json" "$src/sdk/runner.mjs" "$canon/sdk/"
echo "Installed maestro -> $canon"
if [[ $sdk -eq 1 ]]; then
  command -v npm >/dev/null 2>&1 || { echo "install.sh: --sdk needs npm (Node >= 18)" >&2; exit 1; }
  npm ci --prefix "$canon/sdk" --omit=dev --ignore-scripts --no-audit --no-fund >/dev/null
  echo "Installed Agent SDK -> $canon/sdk/node_modules ($(jq -r '.packages["node_modules/@anthropic-ai/claude-agent-sdk"].version' "$canon/sdk/package-lock.json"))"
elif [[ -d "$canon/sdk/node_modules" ]]; then
  want="$(jq -r '.packages["node_modules/@anthropic-ai/claude-agent-sdk"].version' "$canon/sdk/package-lock.json")"
  have="$(jq -r .version "$canon/sdk/node_modules/@anthropic-ai/claude-agent-sdk/package.json" 2>/dev/null || echo none)"
  [[ "$want" == "$have" ]] || echo "install.sh: installed Agent SDK $have, the lock pins $want — rerun with --sdk" >&2
fi

link() {  # link <path> : symlink <path> -> $canon, refusing anything that is not ours
  local p="$1"
  mkdir -p "$(dirname "$p")"
  if [[ -L "$p" ]]; then
    if [[ "$(readlink -f "$p")" == "$(readlink -f "$canon")" ]]; then echo "Linked    $p (already)"; return; fi
    echo "install.sh: $p is a symlink to $(readlink "$p") — refusing" >&2; return 1
  fi
  if [[ -e "$p" ]]; then
    if is_maestro_dir "$p"; then rm -rf "$p"; else echo "install.sh: $p exists and is not maestro — refusing" >&2; return 1; fi
  fi
  ln -s "$canon" "$p"
  echo "Linked    $p -> $canon"
}
has claude-code && link "$claude_link"
if has agy && [[ -n "$agy_link" ]]; then link "$agy_link"; fi

cat <<EOF

Invoke it with:
  Claude Code  /maestro <task>
  Codex        \$maestro <task>
  Cursor       /maestro <task>        (agent CLI)
  agy          /maestro <task>        (interactive session; print mode cannot direct)
EOF
