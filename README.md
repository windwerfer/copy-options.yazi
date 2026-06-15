# copy-options.yazi

Smart paste dialog powered by rsync for advanced collision handling + remote support.

## Trigger

- Press **`p`** (recommended) — this replaces the plain paste with a choice dialog.
- Press **`R`** — alternative trigger (same dialog).

Both are defined via `prepend_keymap` in `keymap.toml` (see below).

## The dialog (shown when you have yanked files)

A notification first appears with the **exact target** (your current folder) and the legend:

```
p = default paste (auto-rename on collision)
o = override
s = skip existing
y = override younger
r = remote (last + history of 9)
d = dry-run
```

Then a `ya.which` key popup appears. Press the corresponding key.

| Key (lower or UPPER) | Meaning                              | What happens |
|----------------------|--------------------------------------|--------------|
| `p` / `P`            | Default paste                        | Normal Yazi paste. Auto-renames on collision (file (1), file (2), ...). Fast, integrated. |
| `o` / `O`            | Override (local)                     | `rsync -aP ... target/` — overwrites existing files. |
| `s` / `S`            | Skip existing (local)                | `rsync -aP --ignore-existing ...` |
| `y` / `Y`            | Override younger (local)             | `rsync -aP --update ...` (only copy when source is newer) |
| `r` / `R`            | Remote                               | Pick from last-used remote (history of 9) or enter new (`user@host:/path/`). Then choose o/s/y strategy. Remembers your choices. |
| `d` / `D`            | Dry-run                              | Pick a strategy (local o/s/y or remote). Runs rsync with `--dry-run` so you see exactly what *would* be transferred. |

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
- Output is written to the log file.
- Then the same `less` viewer used by the `l` key is opened so you get a full scrollable/searchable result (much better for long file lists than a fixed dialog).

This design gives you excellent visibility for both live progress and detailed dry-run inspection.

The only non-rsync path is `p` = plain default paste (Yazi's native fast path, no extra terminal view needed).

## Nothing yanked?

If you press `p` / `R` with an empty yank buffer you get a clear notification:

> Nothing yanked yet

## keymap.toml (created for you)

Example `keymap.toml` (place in your Yazi config dir, usually `~/.config/yazi/keymap.toml` or `$XDG_CONFIG_HOME/yazi/keymap.toml`):

```toml
[mgr]
prepend_keymap = [
  { on = "p", run = "plugin copy-options", desc = "Smart paste dialog (p=default/rename, o=override, s=skip, y=younger, r=remote, d=dry-run)" },
  { on = "R", run = "plugin copy-options", desc = "Smart paste / rsync collision options dialog" },
]
```

Using `prepend_keymap` means your other default keys stay intact.

## Files written

- `plugins/copy-options.yazi/main.lua`
- `plugins/copy-options.yazi/README.md` (this file)
- `keymap.toml` (the bindings — you add the entries above)

State / runtime files (created on first use):
- `~/.local/state/yazi/plugins/copy-options.yazi/.remote_history` (plain text, up to 9 recent remotes)
- `~/.local/state/yazi/plugins/copy-options.yazi/last_rsync.log` (last rsync output, for the `l` viewer)

These locations respect `XDG_STATE_HOME` when set, and can be overridden with the `COPY_OPTIONS_STATE_DIR` environment variable or via `setup()`. See AGENTS.md for more.

## Tips

- For very large transfers the live shell view is excellent because you get real rsync feedback.
- Dry-run (`d`) is fantastic before a big remote sync.
- If you still want the absolute original `p` behavior without any dialog, you can change the keymap binding or add a different key that directly does `paste`.

## What do we think of the design?

- `p` as the single entry point for "I want to paste the yanked stuff, but let me decide how" is very ergonomic.
- The dialog (notify + ya.which) gives you the target + all options in one glance.
- History of 9 + prefill is useful without being over-engineered.
- Live output via the shell layer is the right trade-off for visibility.
- No source deletion keeps it safe.
- Uppercase support + clear legend covers different typing habits.

Everything stays keyboard-driven and inside Yazi's plugin model.

Enjoy!
