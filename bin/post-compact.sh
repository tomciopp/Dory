#!/usr/bin/env bash
set -euo pipefail

# 1. Resolve repo root
ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONTEXT_DIR="$ROOT_DIR/.claude"
CONTEXT_FILE="$CONTEXT_DIR/session-context.md"

# 2. Exit silently if no saved context exists
[[ -e "$CONTEXT_FILE" ]] || exit 0

# 3. Atomically claim the file so only one hook run consumes it
TMP_FILE=$(mktemp "$CONTEXT_DIR/.session-context.consume.XXXXXX")
trap 'rm -f "$TMP_FILE"' EXIT
if ! mv -- "$CONTEXT_FILE" "$TMP_FILE" 2>/dev/null; then
  exit 0
fi

# 4. Exit silently if the claimed file is empty
[[ -s "$TMP_FILE" ]] || exit 0

# 5. Emit JSON with strict re-priming instructions
jq -n --rawfile text "$TMP_FILE" '{
  "systemMessage": "── context restored, type anything to confirm goals ──",
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": (
      "IMPORTANT: Context has just been restored after compaction. " +
      "Before responding to anything else, your very first response must: " +
      "1) State the current goal in one sentence. " +
      "2) List the plan to accomplish it. " +
      "3) Ask the user to confirm everything looks correct before continuing.\n\n" +
      "Restored pre-compaction context:\n\n" +
      $text
    )
  }
}'
