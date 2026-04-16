# Claude Code Compaction Hooks

Preserves session context across Claude Code's compaction events. When Claude Code compacts the conversation history, key goals and problem state are saved before compaction and re-injected after — prompting Claude to confirm the current goal and plan before resuming work.

## How It Works

```
Long session fills context window
         │
         ▼
  PreCompact fires
  └─ Saves last 500 transcript lines to .claude/session-context.md
         │
         ▼
  Compaction happens (lossy summary)
         │
         ▼
  SessionStart fires (source: "compact")
  └─ Reads and deletes session-context.md
  └─ Injects restored context + re-priming instructions
         │
         ▼
  Claude's first response states goal, lists plan,
  and asks user to confirm before continuing
```

## Files

```
.claude/
  hooks/
    pre-compact.sh       # Saves context before compaction
    post-compact.sh      # Restores context after compaction
```

Managed settings are deployed to:
- **macOS**: `/Library/Application Support/ClaudeCode/managed-settings.json`
- **Linux/WSL**: `/etc/claude-code/managed-settings.json`
- **Windows**: `C:\Program Files\ClaudeCode\managed-settings.json`

## Installation

### 1. Copy the hook scripts

```bash
mkdir -p .claude/hooks
cp pre-compact.sh .claude/hooks/pre-compact.sh
cp post-compact.sh .claude/hooks/post-compact.sh
chmod +x .claude/hooks/pre-compact.sh .claude/hooks/post-compact.sh
```

### 2. Deploy managed settings (requires admin)

Add the following to your managed settings file:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/pre-compact.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/post-compact.sh"
          }
        ]
      }
    ]
  }
}
```

If you are not in a managed environment, the same block can go in `~/.claude/settings.json` (user-wide) or `.claude/settings.json` (project-level).

### 3. Verify

Run `/status` inside Claude Code to confirm the hooks are active and sourced from the expected settings file.

## Scripts

### `pre-compact.sh`

Runs before compaction. Extracts the last 500 lines of the session transcript, filters to user and assistant messages, handles both string and array content blocks, and atomically writes the result to `.claude/session-context.md`.

Key behaviours:
- Anchors to the git repository root so the hook works from any subdirectory
- Validates that `transcript_path` is present and the file exists before proceeding
- Uses a same-directory `mktemp` + `mv` for an atomic write, preventing a partial file from being consumed by the post-compact hook
- Cleans up temp files via `trap` regardless of exit path

### `post-compact.sh`

Runs on `SessionStart` with `source: compact`. Reads `.claude/session-context.md` and emits it as `additionalContext` alongside instructions that require Claude to state the current goal, list the plan, and ask for user confirmation before doing anything else.

Key behaviours:
- Anchors to the git repository root
- Atomically claims the context file via `mv` so parallel hook runs cannot double-inject
- Exits silently if no context file exists or if the claimed file is empty
- Deletes the context file after consuming it so stale context is never re-injected on a later non-compaction resume

## Design Decisions

**Why `SessionStart` with `compact` matcher instead of `PostCompact`?**
`PostCompact` has no decision control — any output is ignored. `SessionStart` fired after compaction supports `additionalContext`, which is the correct injection point.

**Why same-directory `mktemp`?**
`mv` is only atomic when source and destination are on the same filesystem. Creating the temp file in `.claude/` guarantees this, even on network mounts.

**Why `mv` to claim the file in `post-compact.sh`?**
If Claude Code ever fires hooks in parallel, two runs could both see the file. The first `mv` succeeds; the second gets a `2>/dev/null`-suppressed error and exits cleanly. This prevents double-injection without needing a lock file.

**Why not rely on `PostCompact` for user-facing output?**
The docs confirm PostCompact is for side effects and logging only. Context injection must happen at `SessionStart`.

## Requirements

- Claude Code with hooks support
- `jq` available in the shell environment
- `git` available (falls back to `pwd` for non-git projects)
- Admin access to deploy managed settings (or use user/project settings for personal use)

## Notes

For goals and constraints that must survive compaction verbatim regardless of this hook system, add them to `CLAUDE.md` — that file is always reloaded fresh after compaction and is not subject to summarisation.
