local M = {}

local sidebar_width = 40
local source_windows = {}
local sync_generation = 0
local picker_sources = { "explorer", "diffview_files" }

local function window_filetype(win)
	return vim.bo[vim.api.nvim_win_get_buf(win)].filetype
end

local function valid_window_in_tab(win, tab)
	return win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_tabpage(win) == tab
end

local function find_window(tab, filetype)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if window_filetype(win) == filetype then
			return win
		end
	end
end

local function explorer_picker(tab)
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		return
	end
	for _, source in ipairs(picker_sources) do
		local got_pickers, pickers = pcall(snacks.picker.get, { source = source, tab = false })
		if got_pickers then
			for _, picker in ipairs(pickers) do
				local root = picker.layout and picker.layout.root
				if root and valid_window_in_tab(root.win, tab) then
					return picker
				end
			end
		end
	end
end

local function explorer_window(tab, picker)
	local root = picker and picker.layout and picker.layout.root
	if root and valid_window_in_tab(root.win, tab) then
		return root.win
	end
end

local function is_editor_window(win)
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	local filetype = vim.bo[buf].filetype
	return vim.bo[buf].buftype == ""
		and filetype ~= "aerial"
		and filetype ~= "aerial-nav"
		and filetype ~= "minimap"
		and not filetype:match("^snacks_")
end

local function remember_source_window(tab)
	local current = vim.api.nvim_get_current_win()
	if is_editor_window(current) then
		source_windows[tab] = current
		return current
	end
	if window_filetype(current) == "aerial" then
		local ok, source = pcall(vim.api.nvim_win_get_var, current, "source_win")
		if ok and valid_window_in_tab(source, tab) then
			source_windows[tab] = source
			return source
		end
	end
end

local function source_window(tab)
	local remembered = remember_source_window(tab) or source_windows[tab]
	if valid_window_in_tab(remembered, tab) and is_editor_window(remembered) then
		return remembered
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		if is_editor_window(win) then
			source_windows[tab] = win
			return win
		end
	end
end

local function load_aerial()
	local ok, aerial = pcall(require, "aerial")
	if ok then
		return aerial
	end

	local lazy_ok, lazy = pcall(require, "lazy")
	if lazy_ok then
		pcall(lazy.load, { plugins = { "aerial.nvim" } })
		ok, aerial = pcall(require, "aerial")
		if ok then
			return aerial
		end
	end
end

local function update_explorer_layout(picker)
	if picker and picker.layout and not picker.closed then
		pcall(picker.layout.update, picker.layout)
	end
end

function M.sync(tab)
	tab = tab or vim.api.nvim_get_current_tabpage()
	if not vim.api.nvim_tabpage_is_valid(tab) then
		return
	end

	local picker = explorer_picker(tab)
	local explorer = explorer_window(tab, picker)
	local aerial = find_window(tab, "aerial")
	local focused = vim.api.nvim_get_current_win()

	if explorer and aerial then
		local explorer_position = vim.fn.win_screenpos(explorer)
		local aerial_position = vim.fn.win_screenpos(aerial)
		local stacked = explorer_position[2] == aerial_position[2] and explorer_position[1] < aerial_position[1]
		if not stacked then
			local moved = pcall(vim.api.nvim_win_set_config, aerial, { split = "below", win = explorer })
			if not moved then
				return
			end
		end
		pcall(vim.api.nvim_win_set_width, explorer, sidebar_width)
		local combined_height = vim.api.nvim_win_get_height(explorer) + vim.api.nvim_win_get_height(aerial)
		pcall(vim.api.nvim_win_set_height, explorer, math.ceil(combined_height / 2))
	elseif explorer then
		pcall(vim.api.nvim_win_set_width, explorer, sidebar_width)
	elseif aerial then
		pcall(vim.api.nvim_win_set_width, aerial, sidebar_width)
	end

	update_explorer_layout(picker)
	if vim.api.nvim_win_is_valid(focused) then
		pcall(vim.api.nvim_set_current_win, focused)
	end
end

local function schedule_sync(tab)
	sync_generation = sync_generation + 1
	local generation = sync_generation
	for _, delay in ipairs({ 0, 20 }) do
		vim.defer_fn(function()
			if generation == sync_generation then
				M.sync(tab)
			end
		end, delay)
	end
end

function M.toggle_explorer()
	local tab = vim.api.nvim_get_current_tabpage()
	remember_source_window(tab)
	require("snacks").explorer()
	schedule_sync(tab)
end

function M.open_aerial(opts)
	opts = opts or {}
	local tab = vim.api.nvim_get_current_tabpage()
	if find_window(tab, "aerial") then
		schedule_sync(tab)
		return true
	end

	local source = opts.source_win
	if not (valid_window_in_tab(source, tab) and is_editor_window(source)) then
		source = source_window(tab)
	end
	if not source then
		vim.notify("No editor window available for Aerial", vim.log.levels.WARN)
		return false
	end

	local aerial = load_aerial()
	if not aerial then
		vim.notify("Unable to load Aerial", vim.log.levels.ERROR)
		return false
	end

	source_windows[tab] = source
	local focused = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(source)
	aerial.open({ direction = "right", focus = opts.focus == true })
	if opts.focus ~= true and vim.api.nvim_win_is_valid(focused) then
		vim.api.nvim_set_current_win(focused)
	end
	schedule_sync(tab)
	return true
end

function M.toggle_aerial()
	local tab = vim.api.nvim_get_current_tabpage()
	if find_window(tab, "aerial") then
		require("aerial").close_all()
		schedule_sync(tab)
		return
	end

	M.open_aerial({ focus = true })
end

function M.setup()
	local group = vim.api.nvim_create_augroup("dotfiles-sidebar-stack", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = { "aerial", "snacks_layout_box" },
		callback = function()
			schedule_sync(vim.api.nvim_get_current_tabpage())
		end,
	})
	vim.api.nvim_create_autocmd({ "VimResized", "WinClosed" }, {
		group = group,
		callback = function()
			schedule_sync(vim.api.nvim_get_current_tabpage())
		end,
	})
end

return M
