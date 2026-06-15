-- copy-options.yazi / main.lua
--
-- Smart paste dialog + rsync collision options.
-- p = default Yazi paste (auto-rename)
-- o/s/y = rsync with different collision handling
-- r = remote with history
-- d = dry-run (shown persistently)
-- l = view last rsync log (persistent review)

-- Portable state directory for history + logs.
-- Resolution order:
--   1. opts.state_dir passed to :setup() (most flexible)
--   2. COPY_OPTIONS_STATE_DIR or YAZI_COPY_OPTIONS_STATE_DIR env var (power users / containers)
--   3. $XDG_STATE_HOME/yazi/plugins/copy-options.yazi
--   4. $HOME/.local/state/yazi/plugins/copy-options.yazi (or Windows equivalent)
local _state_dir_override = nil

local function get_state_dir()
    if _state_dir_override then
        return _state_dir_override
    end

    local env = os.getenv("COPY_OPTIONS_STATE_DIR")
        or os.getenv("YAZI_COPY_OPTIONS_STATE_DIR")
    if env and env ~= "" then
        return env
    end

    local xdg = os.getenv("XDG_STATE_HOME")
    if xdg and xdg ~= "" then
        return xdg .. "/yazi/plugins/copy-options.yazi"
    end

    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
    -- Basic Windows fallback (rsync is rare on Windows, but better than nothing)
    if home ~= "" and ya.target_family and ya.target_family() == "windows" then
        local local_app = os.getenv("LOCALAPPDATA") or (home .. "\\AppData\\Local")
        return local_app .. "\\yazi\\plugins\\copy-options.yazi"
    end
    return home .. "/.local/state/yazi/plugins/copy-options.yazi"
end

local STATE_DIR = get_state_dir()
local LOG_FILE = STATE_DIR .. "/last_rsync.log"
local HISTORY_FILE = STATE_DIR .. "/.remote_history"

local get_state = ya.sync(function()
    local srcs = {}
    for _, url in pairs(cx.yanked) do
        srcs[#srcs + 1] = tostring(url)
    end
    local cwd = tostring(cx.active.current.cwd)
    return srcs, cwd
end)

local function ensure_state_dir()
    -- Use os.execute + shell for mkdir -p (simple and cross-platform enough).
    -- We use a real absolute path (no literal ~) so quoting works reliably.
    os.execute("mkdir -p " .. ya.quote(STATE_DIR) .. " 2>/dev/null")
end

local function load_remote_history()
    ensure_state_dir()
    local f = io.open(HISTORY_FILE, "r")
    if not f then return {} end
    local hist = {}
    for l in f:lines() do
        local line = l:gsub("^%s*(.-)%s*$", "%1")
        if #line > 0 then
            hist[#hist + 1] = line
        end
    end
    f:close()
    return hist
end

local function save_remote_history(remote)
    if not remote or remote == "" then return end
    local hist = load_remote_history()
    local new_hist = { remote }
    for _, v in ipairs(hist) do
        if v ~= remote then new_hist[#new_hist + 1] = v end
    end
    while #new_hist > 9 do table.remove(new_hist) end

    ensure_state_dir()
    local f = io.open(HISTORY_FILE, "w")
    if f then
        for _, v in ipairs(new_hist) do f:write(v .. "\n") end
        f:close()
    end
end

-- Build rsync argument list. For dry-run we add rich output flags.
local function build_rsync_args(srcs, dest, strat_flag, is_dry)
    local args = { "-aP" }
    if strat_flag then table.insert(args, strat_flag) end
    if is_dry then
        table.insert(args, "--dry-run")
        -- These make dry-run actually useful to look at
        table.insert(args, "-v")
        table.insert(args, "--itemize-changes")
    end
    for _, s in ipairs(srcs) do
        table.insert(args, s)
    end
    table.insert(args, dest)
    return args
end

local M = {}

function M:setup(opts)
    if opts and opts.state_dir and opts.state_dir ~= "" then
        _state_dir_override = opts.state_dir
        -- Recompute derived paths after override
        STATE_DIR = get_state_dir()
        LOG_FILE = STATE_DIR .. "/last_rsync.log"
        HISTORY_FILE = STATE_DIR .. "/.remote_history"
    end
end

M.entry = function()
    ya.emit("escape", { visual = true })

    local function view_last_log()
        ensure_state_dir()
        -- Use less if available, otherwise cat. Block so user can read and Esc/ q to leave.
        local viewer = "less -R " .. ya.quote(LOG_FILE) .. " 2>/dev/null || cat " .. ya.quote(LOG_FILE)
        ya.emit("shell", { viewer, block = true })
    end

    local srcs, target = get_state()

    if #srcs == 0 then
        -- Nothing to copy: only offer the log viewer
        local cands = {
            { on = "l", desc = "View last rsync log / result" },
        }
        local choice = ya.which { cands = cands }
        if not choice then return end
        local key = cands[choice].on
        if key == "l" then
            view_last_log()
        end
        return
    end

    if not target:match("/$") then target = target .. "/" end

    local cands = {
        { on = "p", desc = "Default paste (auto-rename on collision)" },
        { on = "P", desc = "Override (Yazi default paste)" },
        { on = "o", desc = "Override (local rsync)" },
        { on = "s", desc = "Skip existing (local rsync)" },
        { on = "y", desc = "Override younger (local rsync)" },
        { on = "r", desc = "Remote rsync (last used + history)" },
        { on = "d", desc = "Dry-run (pick strategy)" },
        { on = "l", desc = "View last rsync log / result" },
    }

    local choice = ya.which { cands = cands }
    if not choice then return end

    local key = cands[choice].on

    if key == "p" then
        ya.emit("paste", {})
        ya.emit("yank", { clear = true })
        return
    end

    if key == "P" then
        ya.emit("paste", { force = true })
        ya.emit("yank", { clear = true })
        return
    end

    if key == "l" then
        view_last_log()
        return
    end

    -- rsync paths
    local strat_flag = nil
    local final_dest = target
    local need_remote = (key == "r")
    local need_strat_after_remote = (key == "r")
    local is_dry = (key == "d")

    if key == "d" then
        local dry_cands = {
            { on = "o", desc = "Dry-run: override (local)" },
            { on = "s", desc = "Dry-run: skip existing (local)" },
            { on = "y", desc = "Dry-run: override younger (local)" },
            { on = "r", desc = "Dry-run: remote" },
        }
        local dc = ya.which { cands = dry_cands }
        if not dc then return end
        local dkey = dry_cands[dc].on
        is_dry = true
        if dkey == "r" then
            need_remote = true
            need_strat_after_remote = true
        else
            if dkey == "s" then
                strat_flag = "--ignore-existing"
            elseif dkey == "y" then
                strat_flag = "--update"
            end
        end
    elseif key == "r" then
        need_remote = true
        need_strat_after_remote = true
    elseif key == "o" then
        strat_flag = nil
    elseif key == "s" then
        strat_flag = "--ignore-existing"
    elseif key == "y" then
        strat_flag = "--update"
    end

    if need_remote then
        local hist = load_remote_history()
        local h_cands = {}
        for i = 1, math.min(#hist, 9) do
            h_cands[#h_cands + 1] = { on = tostring(i), desc = hist[i] }
        end
        h_cands[#h_cands + 1] = { on = "n", desc = "Enter new remote (e.g. user@host:/path/)" }

        local hc = ya.which { cands = h_cands }
        if not hc then return end

        local remote
        if hc <= #hist then
            remote = hist[hc]
        else
            local value, event = ya.input {
                title = "Remote destination",
                value = hist[1] or "",
                pos = { "center", w = 55 },
            }
            if event ~= 1 or not value or value == "" then return end
            remote = value
        end
        save_remote_history(remote)
        final_dest = remote

        if need_strat_after_remote then
            local rstrat = ya.which {
                cands = {
                    { on = "o", desc = "Remote: override" },
                    { on = "s", desc = "Remote: skip existing" },
                    { on = "y", desc = "Remote: override younger" },
                },
            }
            if not rstrat then return end
            local rk = ({ "o", "s", "y" })[rstrat]
            if rk == "s" then
                strat_flag = "--ignore-existing"
            elseif rk == "y" then
                strat_flag = "--update"
            end
        end
    end

    ensure_state_dir()

    if is_dry then
        -- Capture output (silently) so we can present the full --dry-run result
        -- in a native popup. We still write to the log so the "l" key works.
        local args = build_rsync_args(srcs, final_dest, strat_flag, true)
        local output = Command("rsync")
            :arg(args)
            :stdout(Command.PIPED)
            :stderr(Command.PIPED)
            :output()

        local full = (output and output.stdout or "") .. "\n" .. (output and output.stderr or "")

        -- Save for the "l" viewer too
        local f = io.open(LOG_FILE, "w")
        if f then
            f:write(full); f:close()
        end

        -- Show as a native Yazi popup (stays in the UI, no shell takeover).
        -- We repurpose ya.confirm as an "OK / info" dialog for viewing results.
        -- The dialog itself is centered (left-docked pos isn't supported for confirm).
        -- Content is left-aligned so the rsync --itemize output stays readable.
        ya.confirm {
            pos = { "center", w = 92, h = 32 },
            title = "Dry-run result — [Enter] / [Esc] to close",
            body = ui.Text(full):wrap(ui.Wrap.YES),
        }
    else
        -- Real copy / remote: live view is best for progress.
        -- We also tee to the log so you can review later with "l" if needed.
        local args = build_rsync_args(srcs, final_dest, strat_flag, false)
        -- Rebuild a safe command line for the shell emitter + tee
        local quoted_args = {}
        for _, a in ipairs(args) do
            table.insert(quoted_args, ya.quote(a))
        end
        local cmdline = "rsync " .. table.concat(quoted_args, " ") ..
            " 2>&1 | tee " .. ya.quote(LOG_FILE)

        ya.emit("shell", { cmdline, block = true })
        ya.emit("refresh", {})
        ya.emit("yank", { clear = true })

        ya.notify {
            title = "copy-options",
            content = "copy successfully (p+l to display log)",
            level = "info",
            timeout = 3,
        }
    end
end

return M
