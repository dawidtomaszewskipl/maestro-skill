#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal regex and file bodies, written verbatim
# Answer agy's "Run this command?" prompts in tmux session $1 for a canary; log to $2.
# Approves unless the command matches a dangerous pattern; stops after $3 seconds of no prompt
# once the pane shows a final report line ("result:").
set -u
S="$1" LOG="$2" IDLE="${3:-900}"
bad='rm -rf (/|~|\$HOME)( |$)|sudo |mkfs|dd if=|git push|chmod -R 777 /|curl[^|]*\| *(ba)?sh'
last=$(date +%s)
while tmux has-session -t "$S" 2>/dev/null; do
  pane="$(tmux capture-pane -t "$S" -p -S -40)"
  if grep -q "Run this command?" <<<"$pane"; then
    cmd="$(sed -n '/Requesting permission for:/,/Run this command?/p' <<<"$pane" | sed '1d;$d' | tr -s ' ' | tr '\n' ' ')"
    if grep -qE "$bad" <<<"$cmd"; then
      echo "$(date +%T) DENY $cmd" >> "$LOG"; tmux send-keys -t "$S" Down Down Down Enter
    else
      echo "$(date +%T) OK   $cmd" >> "$LOG"; tmux send-keys -t "$S" Enter
    fi
    last=$(date +%s); sleep 3; continue
  fi
  if grep -qE "Allow (creation of|edits? to|changes to) this file\?|Apply (this|these) (edit|change)s?\?" <<<"$pane"; then
    if grep -qE "(^| )/(etc|usr|home/[^/]+/\.(ssh|config|gemini|codex|claude))/" <<<"$pane"; then
      echo "$(date +%T) DENY file write outside the canary" >> "$LOG"; tmux send-keys -t "$S" Down Enter
    else
      echo "$(date +%T) OK   file write" >> "$LOG"; tmux send-keys -t "$S" Enter
    fi
    last=$(date +%s); sleep 3; continue
  fi
  if grep -q "Allow access to this file?" <<<"$pane" && grep -q "outside workspace" <<<"$pane"; then
    echo "$(date +%T) DENY file access outside the workspace: $(grep -m1 -oE '(Read|Write): [^ ]+' <<<"$pane")" >> "$LOG"
    tmux send-keys -t "$S" Down Down Enter
    last=$(date +%s); sleep 3; continue
  fi
  if grep -q "Do you trust the contents" <<<"$pane"; then tmux send-keys -t "$S" Enter; sleep 3; continue; fi
  if (( $(date +%s) - last > IDLE )); then echo "$(date +%T) idle ${IDLE}s, stopping" >> "$LOG"; break; fi
  sleep 3
done
