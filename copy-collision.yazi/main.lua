-- copy-collision.yazi / main.lua
--
-- Smart paste dialog + rsync collision options.
--
-- Trigger with "p" (primary) or "R".
-- Inside the dialog:
--   p = default Yazi paste (auto-rename on collision)
--   o = override (rsync)
--   s = skip existing (rsync --ignore-existing)
--   y = override younger (rsync --update)
--   r = remote (with last-used + simple 9-entry history)
--   d = dry-run a strategy
--
-- Remote remembers your previous remotes (history of 9) and prefills input.
-- All rsync operations use live shell output (you see rsync progress/stats).
-- Source files are never deleted (even if you yanked with "x").
--
-- Requires rsync in PATH + ssh setup for remotes (passwordless recommended).

local CONFIG_ROOT = "/opt/download-cache/.config/yazi"
local STATE_DIR = CONFIG_ROOT .. "/plugins/copy-collision.yazi"

local get_state = ya.sync(function()
	local srcs = {}
	for _, url in pairs(cx.yanked) do
		srcs[#srcs + 1] = tostring(url)
	end
	local cwd = tostring(cx.active.current.cwd)
	return srcs, cwd
end)

local function ensure_state_dir()
	-- best effort mkdir for our state files
	os.execute("mkdir -p " .. ya.quote(STATE_DIR) .. " 2>/dev/null")
end

local function load_remote_history()
	ensure_state_dir()
	local path = STATE_DIR .. "/.remote_history"
	local f = io.open(path, "r")
	if not f then return {} end
	local hist = {}
	for l in f:lines() do
		local line = l:gsub("^%s*(.-)%s*$", "%1")
		if #line > 0 then
			-- dedup later on save; keep order as stored (newest first)
			hist[#hist + 1] = line
		end
	end
	f:close()
	return hist
end

local function save_remote_history(remote)
	if not remote or remote == "" then return end
	local hist = load_remote_history()
	-- move existing occurrence to front, or prepend
	local new_hist = { remote }
	for _, v in ipairs(hist) do
		if v ~= remote then
			new_hist[#new_hist + 1] = v
		end
	end
	-- trim to 9
	while #new_hist > 9 do table.remove(new_hist) end

	ensure_state_dir()
	local path = STATE_DIR .. "/.remote_history"
	local f = io.open(path, "w")
	if f then
		for _, v in ipairs(new_hist) do
			f:write(v .. "\n")
		end
		f:close()
	end
end

local function build_rsync_cmd(srcs, dest, strat_flag, dry_run)
	local args = { "-aP" }
	if strat_flag then
		table.insert(args, strat_flag)
	end
	if dry_run then
		table.insert(args, "--dry-run")
	end

	local quoted = {}
	for _, s in ipairs(srcs) do
		quoted[#quoted + 1] = ya.quote(s)
	end
	local qdest = ya.quote(dest)

	return "rsync " .. table.concat(args, " ") .. " " ..
	       table.concat(quoted, " ") .. " " .. qdest
end

return {
	entry = function()
		ya.emit("escape", { visual = true })

		local srcs, target = get_state()

		if #srcs == 0 then
			return ya.notify {
				title = "copy-collision",
				content = "Nothing yanked yet",
				level = "warn",
				timeout = 3,
			}
		end

		-- treat target as directory for paste-into semantics
		if not target:match("/$") then
			target = target .. "/"
		end



		-- Main choice menu (lowercase preferred, uppercase also listed so they work)
		local cands = {
			{ on = "p", desc = "Default paste (auto-rename on collision)" },
			{ on = "o", desc = "Override (local rsync)" },
			{ on = "s", desc = "Skip existing (local rsync)" },
			{ on = "y", desc = "Override younger (local rsync)" },
			{ on = "r", desc = "Remote rsync (last used + history)" },
			{ on = "d", desc = "Dry-run (pick strategy + optional remote)" },


		}

		local choice = ya.which { cands = cands }
		if not choice then return end

		local raw_key = cands[choice].on
		local key = raw_key:lower()

		local is_dry = (key == "d")
		local do_remote = (key == "r")

		-- Fast path: plain default paste (the Yazi built-in behavior)
		if key == "p" then
			ya.emit("paste", {})
			return
		end

		-- From here on we are doing an rsync variant (local, remote, or dry)
		local strat_flag = nil          -- nil = override, or the --flag
		local final_dest = target
		local need_remote = do_remote
		local need_strat_after_remote = false

		if key == "d" then
			-- Dry-run picker (can be local strategy or remote)
			local dry_cands = {
				{ on = "o", desc = "Dry-run: override (local)" },
				{ on = "s", desc = "Dry-run: skip existing (local)" },
				{ on = "y", desc = "Dry-run: override younger (local)" },
				{ on = "r", desc = "Dry-run: remote (choose remote + strategy)" },
			}
			local dc = ya.which { cands = dry_cands }
			if not dc then return end
			local dkey = dry_cands[dc].on:lower()

			is_dry = true
			if dkey == "r" then
				need_remote = true
				need_strat_after_remote = true   -- will pick strategy after picking remote
			else
				if dkey == "s" then strat_flag = "--ignore-existing"
				elseif dkey == "y" then strat_flag = "--update" end
				-- "o" => nil (full override simulation)
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

		-- Remote handling (history of 9 + new entry)
		if need_remote then
			local hist = load_remote_history()

			local h_cands = {}
			for i = 1, math.min(#hist, 9) do
				h_cands[#h_cands + 1] = {
					on = tostring(i),
					desc = hist[i],
				}
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

			-- If we still need to pick the collision strategy for this remote
			if need_strat_after_remote then
				local rstrat = ya.which {
					cands = {
						{ on = "o", desc = "Remote: override" },
						{ on = "s", desc = "Remote: skip existing" },
						{ on = "y", desc = "Remote: override younger" },
					},
				}
				if not rstrat then return end
				local rk = ({"o","s","y"})[rstrat]
				if rk == "s" then strat_flag = "--ignore-existing"
				elseif rk == "y" then strat_flag = "--update" end
				-- o => no extra flag
			end
		end

		-- Execute via live shell so user sees rsync output/progress in real time.
		-- (This is what "live rsync output" means: Yazi runs the command in its
		-- shell layer / terminal view and shows stdout/stderr until it finishes.)
		local cmd = build_rsync_cmd(srcs, final_dest, strat_flag, is_dry)
		ya.emit("shell", { cmd, block = true })

		-- Give Yazi a chance to notice any new/changed files
		ya.emit("refresh", {})
	end,
}
