# copy-options.yazi

Smart paste dialog powered by rsync for advanced collision handling + remote support.

## Trigger

- Press **`p`** (recommended) — this replaces the plain paste with a choice dialog.

defined via `prepend_keymap` in `keymap.toml` (see below).

## The dialog (shown when you have yanked files)

press 'p', then a key popup appears with options.

| Key (lower or UPPER) | Meaning                              | What happens |
|----------------------|--------------------------------------|--------------|
| `p`                  | Default paste                        | Normal Yazi paste. Auto-renames on collision (file (1), file (2), ...). Fast, integrated. |
| `P`                  | Override (Yazi default)              | Native Yazi force/overwrite paste. Fast, integrated. |
| `o`                  | Override (local rsync)               | `rsync -aP ... target/` — overwrites existing files. |
| `s`                  | Skip existing (local)                | `rsync -aP --ignore-existing ...` |
| `y`                  | Override younger (local)             | `rsync -aP --update ...` (only copy when source is newer) |
| `r`                  | Remote                               | Pick from last-used remote (history of 9) or enter new (`user@host:/path/`). Then choose o/s/y strategy. Remembers your choices. |
| `d`                  | Dry-run                              | Pick a strategy (local o/s/y or remote). Runs rsync with `--dry-run` so you see exactly what *would* be transferred. |

**Sources are never deleted** (even if you used `x` to cut). This is purely a copy / smart-paste tool.

## Remote support + history

- Press `r` in the main dialog.
- You get a small picker with your most recent remotes (up to 9, newest first) numbered 1-9.
- Choose `n` to type a new one (the input is pre-filled with the previous remote for convenience).
- The remote you use (full `user@host:/some/dir/`) is saved for next time.
- Then you pick the collision strategy (o/s/y) for that remote copy.
- Same live output as local.

Requirements for remote: `rsync` + working ssh (ideally passwordless key auth, as with the classic rsync.yazi plugin).

## Live rsync output

Real transfers (local o/s/y, remote) are executed with:

```bash
ya.emit("shell", { "rsync -aP ... 2>&1 | tee <log>", block = true })
```

What this looks like:
- Yazi opens its shell / command execution view (full-width in the terminal).
- You see **live** rsync output: progress, current file, transfer stats, ETA, etc. (thanks to `-P`).
- When rsync finishes (success or error), control returns to Yazi and we refresh the view.

Dry-run (`d`) is different:
- It runs `rsync --dry-run -v --itemize-changes` via `Command` (captured, no visible command while it runs).
- Output is written to the log file (so the `l` key still gives you `less` with full search/scroll later).
- The result is shown immediately in a native centered popup (repurposed `ya.confirm` as an informational "OK" viewer with `ui.Text`). The dialog is centered; the text content flows left-aligned so the rsync `--itemize-changes` output stays readable.

This gives a more consistent UI feel for quick inspection while still providing the powerful `less` fallback via `l` for very long outputs.

The only non-rsync path is `p` = plain default paste (Yazi's native fast path, no extra terminal view needed).

## Nothing yanked?

If you press `p` with an empty yank buffer you get the option to view the last log.

## keymap.toml (created for you)

Example `keymap.toml` (place in your Yazi config dir, usually `~/.config/yazi/keymap.toml` or `$XDG_CONFIG_HOME/yazi/keymap.toml`):

```toml
[mgr]
prepend_keymap = [
  { on = "p", run = "plugin copy-options", desc = "Smart paste dialog (p=default/rename, P=override (Yazi), o=override (rsync), s=skip, y=younger, r=remote, d=dry-run)" },
]
```

Using `prepend_keymap` means your other default keys stay intact.
