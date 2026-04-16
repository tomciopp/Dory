#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONTEXT_FILE="$ROOT_DIR/.claude/session-context.md"
CONTEXT_DIR=$(dirname "$CONTEXT_FILE")

INPUT=$(cat)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')

if [[ -z "$TRANSCRIPT" ]]; then
  echo "Hook Error: No transcript_path provided." >&2
  exit 1
fi

if [[ ! -f "$TRANSCRIPT" ]]; then
  echo "Hook Error: Transcript file not found at $TRANSCRIPT" >&2
  exit 1
fi

if [[ ! -r "$TRANSCRIPT" ]]; then
  echo "Hook Error: Transcript file is not readable at $TRANSCRIPT" >&2
  exit 1
fi

mkdir -p "$CONTEXT_DIR"

TMP_CONTENT=$(mktemp)
OUT_FILE=$(mktemp "$CONTEXT_DIR/.session-context.XXXXXX")
trap 'rm -f "$TMP_CONTENT" "$OUT_FILE"' EXIT

tail -n 500 "$TRANSCRIPT" | jq -r '
    select(.type == "user" or .type == "assistant")
    | if (.content | type) == "string" then
        .content
      elif (.content | type) == "array" then
        [.content[] | select(.type == "text") | .text // empty] | join("\n")
      else
        empty
      end
  ' | awk 'NR <= 200 { print }' > "$TMP_CONTENT"

{
  printf "# Session Context (Pre-Compaction Snapshot)\n"
  printf "> Auto-saved before compaction on %s\n\n" "$(date)"
  printf "## Active Goals & Problem State\n"
  cat "$TMP_CONTENT"
} > "$OUT_FILE"

mv "$OUT_FILE" "$CONTEXT_FILE"

echo "✔ Pre-compact context updated at .claude/session-context.md" >&2
