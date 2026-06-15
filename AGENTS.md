# AGENTS.md — Project instructions for AI agents

This file provides context, conventions, and guidance for any AI (Grok, Claude, Cursor, etc.) working on the copy-options.yazi plugin. It is the primary source of truth for architectural decisions and should be kept up to date.

**When you make changes that affect design, user experience, state handling, key flows, or important conventions, update this file in the same session.**

## What this plugin is

A Yazi file manager plugin that replaces the plain `paste` action with a rich collision-handling dialog.

- Primary entry: `p` (and `R` as secondary).
- Gives the user immediate choice of paste strategy instead of Yazi's default auto-rename behavior.
- Uses `rsync -aP` under the hood for the advanced strategies so that you get progress, resume-friendly behavior, and rich collision control.
- Supports local strategies + remote (ssh) targets with a rolling history of the last 9 remotes.
- Provides dry-run inspection and a persistent last-rsync-log viewer.

Sources are **never** deleted (even when using cut `x`); this is a copy-oriented smart-paste tool.

## Current architecture & important implementation notes

### Entry point & dialog model
- Single `entry()` function in [main.lua](main.lua).
- Uses `ya.which` (twice or three times in some flows) to drive a keyboard-only decision tree.
- First level always shows the full legend via an immediate `ya.notify` (title + content with the key meanings). The actual picker has short descriptions.
- `p` path short-circuits to native `ya.emit("paste", {})` for speed and zero extra behavior.
- All other paths (o/s/y/r/d) and the secondary dry-run strategy picker eventually lead to either:
  - `ya.emit("shell", { cmdline, block = true })` for live visible rsync (preferred for real work), or
  - Captured `Command("rsync")` + `ya.confirm` big scrollable text for dry-run results.
- "l" (view last log) re-uses the same captured/tee'd log file via `less -R` (or cat) inside a blocking shell.

### State & persistence (updated 2026)
- Remote history (max 9, MRU) and the last rsync log live under a computed `STATE_DIR`.
- Resolution (in order):
  1. `opts.state_dir` passed to `require("copy-options"):setup({ state_dir = "..." })` — highest priority, fully user-configurable from `init.lua`.
  2. `COPY_OPTIONS_STATE_DIR` or `YAZI_COPY_OPTIONS_STATE_DIR` environment variable (great for containers, /opt setups, testing).
  3. `$XDG_STATE_HOME/yazi/plugins/copy-options.yazi`
  4. `~/.local/state/yazi/plugins/copy-options.yazi` (with basic Windows `LOCALAPPDATA` fallback).
- Derived files:
  - `last_rsync.log`
  - `.remote_history`
- `ensure_state_dir()` still uses `os.execute("mkdir -p " .. ya.quote(STATE_DIR))`.
- Both files are plain text. The log contains combined stdout+stderr from the most recent rsync (real transfer or dry-run).
- The previous completely hardcoded path was replaced with the above portable scheme. The old `~/.config/...` location some versions used was also superseded (we now prefer XDG_STATE_HOME for this kind of runtime/user-choice data).

### Remote handling
- "r" (or dry-run → r) first shows a small numbered picker of recent remotes + `n` for new.
- New remote input pre-fills with the most recent one for convenience.
- After choosing/typing the remote, a second `ya.which` asks for the collision strategy (o/s/y) for that remote copy.
- The remote string is stored exactly as typed (`user@host:/path/`). No validation or normalization is performed.

### rsync command construction
- Always `-aP` (archive + partial/progress).
- Strategy flags:
  - none → override / clobber
  - `--ignore-existing` → skip
  - `--update` → younger / only if source newer
- For real transfers: the full command is rebuilt with `ya.quote` on every argument, then `... 2>&1 | tee <log>` is passed to `ya.emit("shell", ...)`.
- For dry-run: extra `-v --itemize-changes --dry-run` are added, output is captured with `Command():stdout(PIPED):stderr(PIPED)`, merged, written to the log file, and displayed in a large `ya.confirm` UI.Text dialog.
- After real (non-dry) rsync shell returns, a `refresh` is emitted.

### Error / edge handling
- Empty yank buffer → warn notify and early exit.
- User cancels any `ya.which` or `ya.input` → silent early return (current behavior).
- No special handling for rsync failures beyond whatever the shell view or the dry-run confirm shows.

## Naming & distribution

- The plugin is named **copy-options** (both the repo/directory and the Lua plugin name).
- When installed it lives as `~/.config/yazi/plugins/copy-options.yazi/`.
- Invocation: `plugin copy-options`.
- Standard Yazi plugin layout:
  ```
  copy-options.yazi/
  ├── main.lua
  ├── README.md
  ├── AGENTS.md
  └── (optional LICENSE etc.)
  ```

## Design principles (current)

- Keyboard-driven only. No mouse assumptions.
- Prefer visible live output (`shell` block) over fire-and-forget background jobs for transfers.
- Dry-run must be genuinely useful (hence the extra verbose flags and the persistent log + confirm viewer).
- Keep the fast path (`p`) as close to native Yazi paste as possible.
- History should be low-friction (9 items, prefill, numbered quick select).
- Safety: never delete source files.

## Key files

- [main.lua](main.lua) — all logic.
- [README.md](README.md) — user-facing documentation and keymap example. Contains a self-review section ("What do we think of the design?").
- [AGENTS.md](AGENTS.md) — this file (for AI agents).

## Testing notes for agents / humans

- Place/symlink the directory as `~/.config/yazi/plugins/copy-options.yazi/` (matching the dir name) and reload Yazi.
- State now goes to a proper XDG location by default (`~/.local/state/yazi/plugins/copy-options.yazi/` or `$XDG_STATE_HOME/...`). This is safe for development.
- To test the old non-standard path behavior, set `COPY_OPTIONS_STATE_DIR=/opt/download-cache/.config/yazi/plugins/copy-options.yazi` (or use `:setup({state_dir=...})`).
- Useful during development: the `l` key (view last log) + dry-run.
- Dry-run + `l` is the best way to verify rsync flag combinations without side effects.

## Things that would be nice to improve (non-exhaustive)

1. ~~Make state location portable~~ — Done (XDG + env + `setup()`).
2. Consider a richer `setup()` (history size, extra rsync flags, custom binary, etc.).
3. Better user feedback on cancel / error paths (many are currently silent early returns).
4. Possibly expose the current target more clearly in the first notify (already reasonably visible).
5. Review whether the multiple-yank case needs special handling (current code already walks `cx.yanked`).
6. (Optional) Add a tiny `plugin.toml` or `LICENSE` if publishing.

## When updating this file

- Add or revise sections when architecture, persistence strategy, dialog flow, naming, or design principles change.
- Document any new persistent files or changes to state resolution here.
- Because this file is automatically loaded by agents, keep the "Current architecture" and "State & persistence" sections accurate.

## Relation to other docs

- README.md is for end users.
- AGENTS.md is for agents and developers working with agents. Reference the README for user-facing instructions; keep this one focused on implementation context.

This file was created at the user's request. It is updated automatically by agents whenever they perform work that affects architecture, state handling, or important conventions (as happened during the 2026 portable-state + rename work).

---
Maintained together with the code. Last significant update: portable XDG state dir + full rename to copy-options + setup() support (2026).
