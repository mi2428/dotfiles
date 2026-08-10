local M = {}
local migemo

local function default_dictionary()
	return vim.fs.joinpath(vim.fn.stdpath("data"), "migemo-compact-dict")
end

local function load_migemo()
	if not migemo then
		pcall(vim.cmd.packadd, "luamigemo")
		local ok, loaded = pcall(require, "luamigemo")
		migemo = ok and loaded or nil
	end
	return migemo
end

function M.search(query, dictionary)
	local loaded_migemo = load_migemo()
	if not loaded_migemo then
		vim.notify("luamigemo is unavailable", vim.log.levels.ERROR)
		return false
	end

	local loaded, engine = pcall(loaded_migemo.get, dictionary or default_dictionary())
	if not loaded then
		vim.notify("Migemo dictionary is unavailable: " .. tostring(engine), vim.log.levels.ERROR)
		return false
	end

	local pattern = [[\m]] .. engine:query(query, loaded_migemo.RXOP_VIM)
	if vim.fn.search(pattern) == 0 then
		vim.notify("No Migemo match for: " .. query, vim.log.levels.INFO)
		return false
	end
	vim.fn.setreg("/", pattern)
	vim.v.searchforward = 1
	vim.o.hlsearch = true
	return true
end

function M.setup(opts)
	opts = opts or {}
	load_migemo()
	vim.api.nvim_create_user_command("Kensaku", function(command)
		M.search(command.args, opts.dictionary)
	end, { nargs = "+", desc = "Search the current buffer with Migemo" })
end

return M
