#!/usr/bin/env bash
# Install the maestro skill for Claude Code (the only host that runs it as director since 2.0.0).
#
#   ./install.sh [--sdk] [<project>]
#   ./install.sh --check[=live] [<project>]
#
# --sdk also installs the Claude Agent SDK (pinned in sdk/package-lock.json) for the `api`
# transport: `npm ci` in the installed sdk/ — needs Node >= 18 and network. Without it the
# transport stays unavailable and stage 0 says so (README, "API credit").
#
# Global (default): copies SKILL.md, docs/, bin/ and sdk/ into ~/.claude/skills/maestro.
# With <project>: the same under <project>/.claude/skills/maestro.
# A symlink left there by a 1.x install (to ~/.agents/skills/maestro) is replaced by the copy; the
# old copy and the agy link are named, not deleted — remove them: Codex and agy workers still read
# those directories and would see the old 1.x skill.
#
# --check says where maestro is installed; --check=live also asks Claude Code to list its skills
# (one cheap headless Haiku turn).
set -euo pipefail

src="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
check="" project="" sdk=0
for a in "$@"; do
  case "$a" in
    --sdk) sdk=1 ;;
    --check) check=files ;;
    --check=live) check=live ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    -*) echo "install.sh: unknown option $a" >&2; exit 2 ;;
    *) project="$(cd "$a" 2>/dev/null && pwd)" || { echo "install.sh: no such directory: $a" >&2; exit 2; } ;;
  esac
done

base="${project:-$HOME}"
dest="$base/.claude/skills/maestro"
legacy=("$base/.agents/skills/maestro")
[[ -z "$project" ]] && legacy+=("$HOME/.gemini/config/skills/maestro")

is_maestro_dir() { [[ -f "$1/SKILL.md" ]] && grep -q '^name: maestro$' "$1/SKILL.md"; }

if [[ -n "$check" ]]; then
  if [[ -L "$dest" ]]; then printf '%-55s -> %s (1.x layout: rerun install.sh)\n' "$dest" "$(readlink "$dest")"
  elif is_maestro_dir "$dest"; then printf '%-55s installed\n' "$dest"
  else printf '%-55s missing\n' "$dest"; fi
  for p in "${legacy[@]}"; do [[ -e "$p" || -L "$p" ]] && printf '%-55s left over from 1.x: Codex/agy workers still load it — remove it\n' "$p"; done
  if [[ "$check" == live ]] && command -v claude >/dev/null 2>&1; then
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    q="List the names of the skills available to you, one per line, nothing else."
    (cd "${project:-$PWD}" && claude -p --model haiku --tools "Skill" --permission-mode dontAsk "$q" < /dev/null > "$tmp/claude.txt" 2>/dev/null) || true
    if grep -q maestro "$tmp/claude.txt"; then echo "claude-code: lists maestro"; else echo "claude-code: maestro NOT listed"; fi
  fi
  exit 0
fi

# --- install ------------------------------------------------------------------------------------
if [[ -L "$dest" ]]; then
  if is_maestro_dir "$(readlink -f "$dest")"; then rm "$dest"; echo "Removed   $dest (1.x symlink)"
  else echo "install.sh: $dest is a symlink to $(readlink "$dest") — refusing" >&2; exit 1; fi
fi
if [[ -e "$dest" ]] && ! is_maestro_dir "$dest"; then
  echo "install.sh: $dest exists and is not a maestro install — refusing" >&2; exit 1
fi
mkdir -p "$dest"
cp "$src/SKILL.md" "$dest/SKILL.md"
rm -rf "${dest:?}/docs" "${dest:?}/bin"
cp -R "$src/docs" "$dest/docs"
cp -R "$src/bin" "$dest/bin"
chmod +x "$dest"/bin/maestro-*
mkdir -p "$dest/sdk"   # node_modules survives a reinstall; the lock file decides whether it is current
cp "$src/sdk/package.json" "$src/sdk/package-lock.json" "$src/sdk/runner.mjs" "$dest/sdk/"
echo "Installed maestro -> $dest"
if [[ $sdk -eq 1 ]]; then
  command -v npm >/dev/null 2>&1 || { echo "install.sh: --sdk needs npm (Node >= 18)" >&2; exit 1; }
  npm ci --prefix "$dest/sdk" --omit=dev --ignore-scripts --no-audit --no-fund >/dev/null
  echo "Installed Agent SDK -> $dest/sdk/node_modules ($(jq -r '.packages["node_modules/@anthropic-ai/claude-agent-sdk"].version' "$dest/sdk/package-lock.json"))"
elif [[ -d "$dest/sdk/node_modules" ]]; then
  want="$(jq -r '.packages["node_modules/@anthropic-ai/claude-agent-sdk"].version' "$dest/sdk/package-lock.json")"
  have="$(jq -r .version "$dest/sdk/node_modules/@anthropic-ai/claude-agent-sdk/package.json" 2>/dev/null || echo none)"
  [[ "$want" == "$have" ]] || echo "install.sh: installed Agent SDK $have, the lock pins $want — rerun with --sdk" >&2
fi
for p in "${legacy[@]}"; do
  [[ -e "$p" || -L "$p" ]] && echo "Left over from 1.x: $p — Codex and agy workers still load this old skill; remove it (rm -r)"
done

cat <<EOF

Invoke it in Claude Code with:  /maestro <task>
Headless (nobody answers):      claude -p "/maestro --unattended <task>"
EOF
