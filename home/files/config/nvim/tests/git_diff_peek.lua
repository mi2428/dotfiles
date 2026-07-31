local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")
package.loaded["config.git_diff_peek"] = nil
if vim.loader and vim.loader.reset then
	vim.loader.reset()
end
local loaded_module = assert(package.searchpath("config.git_diff_peek", package.path))
local expected_module = vim.fs.joinpath(nvim_root, "lua/config/git_diff_peek.lua")
assert(
	vim.uv.fs_realpath(loaded_module) == vim.uv.fs_realpath(expected_module),
	("git_diff_peek loaded from %s, expected %s"):format(loaded_module, expected_module)
)
local mini_map = require("mini.map")
assert(package.loaded["mini.map"] == mini_map, "mini.map must be loaded for popup minimap QA")

local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()
local original_underlay_flag = vim.w[source_win].dotfiles_git_diff_peek_underlay
local original_disable_minimap = vim.w[source_win].dotfiles_disable_minimap
local original_hlchunk = vim.b[source_buf].dotfiles_disable_hlchunk
vim.api.nvim_buf_set_name(source_buf, "/tmp/dotfiles-git-diff-peek.lua")
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, {
	"local value = 1",
	"",
	"return value",
})
vim.api.nvim_win_set_cursor(source_win, { 3, 0 })

package.loaded.gitsigns = {
	diffthis = function(_, _, callback)
		local revision_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(revision_buf, "gitsigns:///tmp/.git//:dotfiles-git-diff-peek.lua")
		vim.api.nvim_buf_set_lines(revision_buf, 0, -1, false, {
			"local value = 0",
			"",
			"return value",
		})
		vim.bo[revision_buf].bufhidden = "wipe"
		vim.cmd("aboveleft vsplit")
		local revision_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(revision_win, revision_buf)
		vim.wo[revision_win].diff = true
		vim.wo[source_win].diff = true
		vim.api.nvim_set_current_win(source_win)
		callback()
	end,
}

local peek = require("config.git_diff_peek")
package.loaded["config.git_diff_peek"] = peek
assert(type(peek.apply_editor_chrome) == "function", "source git_diff_peek must expose apply_editor_chrome")
local module_source = assert(debug.getinfo(peek.apply_editor_chrome, "S").source):gsub("^@", "")
assert(
	vim.uv.fs_realpath(module_source) == vim.uv.fs_realpath(expected_module),
	("config.git_diff_peek loaded from %s, expected %s"):format(module_source, expected_module)
)

local function visible_minimap_windows()
	local result = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		local config = vim.api.nvim_win_get_config(win)
		if vim.bo[buf].filetype == "minimap" and not config.hide then
			result[#result + 1] = win
		end
	end
	return result
end

mini_map.open()
local tab = vim.api.nvim_get_current_tabpage()
assert(
	vim.wait(1500, function()
		local native = mini_map.current.win_data[tab]
		return native and vim.api.nvim_win_is_valid(native) and #visible_minimap_windows() == 1
	end, 20),
	"the fixture must expose one ordinary visible minimap before popup open"
)
local baseline_native = mini_map.current.win_data[tab]
local baseline_display = visible_minimap_windows()[1]
local baseline_native_config = vim.deepcopy(vim.api.nvim_win_get_config(baseline_native))
local baseline_display_config = vim.deepcopy(vim.api.nvim_win_get_config(baseline_display))
peek.toggle()

local source_float
local revision_float
local root_float
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	local config = vim.api.nvim_win_get_config(win)
	local buf = vim.api.nvim_win_get_buf(win)
	if config.relative ~= "" and vim.wo[win].diff then
		if buf == source_buf then
			source_float = win
		elseif vim.startswith(vim.api.nvim_buf_get_name(buf), "gitsigns://") then
			revision_float = win
		end
	elseif config.relative == "editor" and vim.bo[buf].filetype == "snacks_layout_box" then
		root_float = win
	end
end

assert(source_float, "the worktree diff pane must be a floating window")
assert(revision_float, "the revision diff pane must be a floating window")
assert(root_float, "the diff panes must have a shared floating layout root")
assert(not vim.wo[source_win].diff, "the underlying editor window must leave diff mode")
assert(
	vim.api.nvim_win_get_config(source_float).relative == "win"
		and vim.api.nvim_win_get_config(revision_float).relative == "win",
	"both diff panes must be placed inside the shared popup"
)
assert(vim.api.nvim_get_current_win() == source_float, "the popup must focus the editable worktree pane")
assert(vim.api.nvim_win_get_cursor(source_float)[1] == 3, "the worktree pane must preserve the source cursor")

local function option_snapshot(win)
	return {
		foldcolumn = vim.wo[win].foldcolumn,
		foldenable = vim.wo[win].foldenable,
		foldlevel = vim.wo[win].foldlevel,
		foldmethod = vim.wo[win].foldmethod,
		signcolumn = vim.wo[win].signcolumn,
		statuscolumn = vim.wo[win].statuscolumn,
		number = vim.wo[win].number,
		relativenumber = vim.wo[win].relativenumber,
		numberwidth = vim.wo[win].numberwidth,
		winbar = vim.wo[win].winbar,
		winhighlight = vim.wo[win].winhighlight,
		fillchars = vim.wo[win].fillchars,
		cursorline = vim.wo[win].cursorline,
		cursorlineopt = vim.wo[win].cursorlineopt,
	}
end

local function common_style_snapshot(win)
	local style = option_snapshot(win)
	style.winhighlight = nil
	return style
end

local function winhighlight_target(win, source)
	for entry in vim.wo[win].winhighlight:gmatch("[^,]+") do
		local lhs, rhs = entry:match("^([^:]+):(.+)$")
		if lhs == source then
			return rhs
		end
	end
end

local function rendered_winbar(win)
	return vim.api.nvim_win_call(win, function()
		return vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = win }).str
	end)
end

local function upvalue(fn, expected_name)
	for index = 1, math.huge do
		local name, value = debug.getupvalue(fn, index)
		if not name then
			break
		end
		if name == expected_name then
			return value
		end
	end
	error("missing upvalue: " .. expected_name)
end

assert(vim.o.foldlevelstart == 99, "popup styling must not change the global foldlevelstart")
for _, win in ipairs({ source_float, revision_float }) do
	local style = option_snapshot(win)
	assert(
		vim.w[win].dotfiles_git_diff_peek_child == true,
		("only popup children must carry the explicit child flag: win=%d value=%s"):format(
			win,
			vim.inspect(vim.w[win].dotfiles_git_diff_peek_child)
		)
	)
	assert(style.foldcolumn == "1", "popup children must use a fixed one-cell fold rail")
	assert(style.foldenable and style.foldlevel == 0 and style.foldmethod == "diff", "popup fold options mismatch")
	assert(style.signcolumn == "no", "popup children must use the custom statuscolumn without signcolumn")
	assert(style.number and style.relativenumber and style.numberwidth == 3, "popup number options mismatch")
	assert(style.statuscolumn ~= "", "popup children must retain the custom statuscolumn")
	assert(style.cursorline and style.cursorlineopt == "number", "popup cursorline options mismatch")
	assert(winhighlight_target(win, "Normal") == "Normal", "popup Normal must use the editor scene")
	assert(winhighlight_target(win, "NormalNC") == "NormalNC", "popup NormalNC must use the editor scene")
	assert(winhighlight_target(win, "WinBar") == "WinBar", "popup WinBar must use the editor scene")
	assert(winhighlight_target(win, "WinBarNC") == "WinBarNC", "popup WinBarNC must use the editor scene")
	assert(style.fillchars:find("diff: ", 1, true), "popup children must use blank diff filler")
	assert(style.winbar:find("dropbar", 1, true), "popup children must retain the Dropbar winbar expression")
end
assert(option_snapshot(source_float).statuscolumn == option_snapshot(revision_float).statuscolumn)
assert(option_snapshot(source_float).winbar == option_snapshot(revision_float).winbar)
assert(vim.w[source_float].dotfiles_git_diff_peek_role == "worktree")
assert(vim.w[revision_float].dotfiles_git_diff_peek_role == "revision")
assert(vim.w[source_win].dotfiles_git_diff_peek_underlay == true, "the underlay must relinquish minimap ownership")
assert(vim.w[source_float].dotfiles_disable_minimap == false, "the worktree child must own the minimap")
assert(vim.w[revision_float].dotfiles_disable_minimap == true, "the revision child must not own a minimap")

local ui_specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/ui.lua"))
local dropbar_spec = vim.iter(ui_specs):find(function(spec)
	return spec[1] == "Bekaboo/dropbar.nvim"
end)
assert(dropbar_spec and dropbar_spec.opts and dropbar_spec.opts.bar, "source Dropbar spec is missing")
assert(dropbar_spec.opts.bar.enable(source_buf, source_float) == true, "source Dropbar spec must allow popup children")
assert(dropbar_spec.opts.bar.enable(vim.api.nvim_win_get_buf(root_float), root_float) == false)

local minimap_specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/minimap.lua"))
local is_code_window = upvalue(upvalue(minimap_specs[1].config, "setup_code_layout"), "is_code_window")
assert(is_code_window(source_float) == true, "source minimap spec must allow the worktree child")
assert(is_code_window(revision_float) == false, "source minimap spec must reject the revision child")
assert(is_code_window(source_win) == false, "source minimap spec must reject the underlay")

local arbitrary_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(arbitrary_buf, 0, -1, false, { "arbitrary normal float" })
vim.bo[arbitrary_buf].filetype = "lua"
local arbitrary_float = vim.api.nvim_open_win(arbitrary_buf, false, {
	relative = "editor",
	row = 1,
	col = 1,
	width = 24,
	height = 2,
	style = "minimal",
})
assert(vim.w[arbitrary_float].dotfiles_git_diff_peek_child ~= true)
assert(dropbar_spec.opts.bar.enable(arbitrary_buf, arbitrary_float) == false)
assert(is_code_window(arbitrary_float) == false)
vim.api.nvim_win_close(arbitrary_float, true)
vim.api.nvim_buf_delete(arbitrary_buf, { force = true })

local bar = require("dropbar.utils.bar")
local rendered_source
local rendered_revision
assert(
	vim.wait(1000, function()
		rendered_source = rendered_winbar(source_float)
		rendered_revision = rendered_winbar(revision_float)
		return rendered_source ~= ""
			and rendered_revision ~= ""
			and bar.get({ win = source_float }) ~= nil
			and bar.get({ win = revision_float }) ~= nil
	end, 20),
	"Dropbar must attach a bar object to both popup children"
)
assert(rendered_source ~= "", "the worktree popup must render Dropbar breadcrumbs")
assert(rendered_revision ~= "", "the revision popup must render Dropbar breadcrumbs")

local function popup_minimap_ready()
	local minimaps = visible_minimap_windows()
	if #minimaps ~= 1 then
		return false
	end
	local native = mini_map.current.win_data[tab]
	if not native or not vim.api.nvim_win_is_valid(native) then
		return false
	end
	local minimap_config = vim.api.nvim_win_get_config(minimaps[1])
	local native_config = vim.api.nvim_win_get_config(native)
	local child_config = vim.api.nvim_win_get_config(source_float)
	local child_position = vim.api.nvim_win_get_position(source_float)
	return minimap_config.width == 12
		and minimap_config.zindex > (child_config.zindex or 0)
		and minimap_config.row == child_position[1]
		and minimap_config.height > 0
		and minimap_config.height <= vim.api.nvim_win_get_height(source_float)
		and minimap_config.col + minimap_config.width == child_position[2] + vim.api.nvim_win_get_width(source_float)
		and native_config.hide == true
		and native_config.anchor == "NE"
		and native_config.col == child_position[2] + vim.api.nvim_win_get_width(source_float)
		and native_config.height == vim.api.nvim_win_get_height(source_float)
		and native_config.zindex > (child_config.zindex or 0)
end

assert(vim.wait(2000, popup_minimap_ready, 20), "popup minimap display/native geometry did not stabilize")
assert(#visible_minimap_windows() == 1, "popup must have exactly one visible minimap")

local immediate_style = common_style_snapshot(source_float)
vim.wait(1200, function()
	return false
end, 20)
assert(
	vim.deep_equal(common_style_snapshot(source_float), immediate_style),
	"delayed popup lifecycle changed worktree common chrome"
)
assert(
	vim.deep_equal(common_style_snapshot(revision_float), common_style_snapshot(source_float)),
	"delayed popup common chrome parity drifted"
)
assert(winhighlight_target(source_float, "Normal") == winhighlight_target(revision_float, "Normal"))
assert(winhighlight_target(source_float, "NormalNC") == winhighlight_target(revision_float, "NormalNC"))
assert(winhighlight_target(source_float, "WinBar") == winhighlight_target(revision_float, "WinBar"))
assert(winhighlight_target(source_float, "WinBarNC") == winhighlight_target(revision_float, "WinBarNC"))
assert(winhighlight_target(source_float, "DiffChange") == "DiffviewDiffChangeAdd")
assert(winhighlight_target(source_float, "DiffText") == "DiffviewDiffTextAdd")
assert(winhighlight_target(revision_float, "DiffChange") == "DiffviewDiffChangeDelete")
assert(winhighlight_target(revision_float, "DiffText") == "DiffviewDiffTextDelete")
assert(vim.w[source_float].dotfiles_disable_minimap == false)
assert(vim.w[revision_float].dotfiles_disable_minimap == true)

local close_map = vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):find(function(mapping)
	return mapping.desc == "Close Git diff peek"
end)
assert(close_map, "the popup must install its temporary close mapping")

peek.toggle()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_get_current_win() == source_win
			and vim.iter(vim.api.nvim_list_wins()):all(function(win)
				return vim.api.nvim_win_get_config(win).relative == "" or not vim.wo[win].diff
			end)
			and vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
				return mapping.desc ~= "Close Git diff peek"
			end)
	end),
	"closing the popup must restore the source editor"
)
assert(
	vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):all(function(mapping)
		return mapping.desc ~= "Close Git diff peek"
	end),
	"the popup close mapping must be removed from the source buffer"
)
assert(
	vim.w[source_win].dotfiles_git_diff_peek_underlay == original_underlay_flag,
	"underlay ownership flag was not restored"
)
assert(vim.w[source_win].dotfiles_disable_minimap == original_disable_minimap, "underlay minimap flag was not restored")
assert(vim.b[source_buf].dotfiles_disable_hlchunk == original_hlchunk, "underlay hlchunk flag was not restored")
assert(
	vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)[3] == "return value",
	"popup cleanup changed buffer content"
)
assert(vim.api.nvim_win_get_cursor(source_win)[1] == 3, "popup cleanup changed the source cursor")
assert(
	vim.wait(1500, function()
		local native = mini_map.current.win_data[tab]
		local minimaps = visible_minimap_windows()
		if not native or not vim.api.nvim_win_is_valid(native) or #minimaps ~= 1 then
			return false
		end
		local native_config = vim.api.nvim_win_get_config(native)
		local display_config = vim.api.nvim_win_get_config(minimaps[1])
		return vim.deep_equal(native_config, baseline_native_config)
			and vim.deep_equal(display_config, baseline_display_config)
	end, 20),
	"popup cleanup did not restore ordinary minimap ownership and geometry"
)

print("Git diff peek popup regression: ok")
