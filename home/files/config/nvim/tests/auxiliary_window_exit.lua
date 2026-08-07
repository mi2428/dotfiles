local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

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

dofile(vim.fs.joinpath(nvim_root, "lua/config/autocmds.lua"))

local quit_autocmds = vim.api.nvim_get_autocmds({
	event = "QuitPre",
	group = "dotfiles-quit-with-only-auxiliary-windows",
})
assert(#quit_autocmds == 1, "auxiliary-window QuitPre autocmd was not registered exactly once")

local callback = quit_autocmds[1].callback
local is_user_editor_window = upvalue(callback, "is_user_editor_window")
local should_exit_after_quit = upvalue(callback, "should_exit_after_quit")
local exit_after_quit = upvalue(callback, "exit_after_quit")
local has_modified_user_buffer = upvalue(exit_after_quit, "has_modified_user_buffer")

local delete_autocmds = vim.api.nvim_get_autocmds({
	event = "BufDelete",
	group = "dotfiles-quit-after-last-buffer",
})
assert(#delete_autocmds == 1, "last-buffer BufDelete autocmd was not registered exactly once")
local delete_callback = delete_autocmds[1].callback
local is_user_buffer = upvalue(delete_callback, "is_user_buffer")
local has_user_buffer = upvalue(delete_callback, "has_user_buffer")

local source_win = vim.api.nvim_get_current_win()
local source_buf = vim.api.nvim_get_current_buf()
vim.bo[source_buf].filetype = "lua"
assert(is_user_buffer(source_buf), "a listed source buffer must be treated as a user buffer")
assert(has_user_buffer(), "the source buffer must be discoverable as a user buffer")

local initializing_oil_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(initializing_oil_buf, "oil:///tmp/")
vim.bo[initializing_oil_buf].filetype = "oil"
assert(not is_user_buffer(initializing_oil_buf), "an initializing Oil buffer must not look like a user file")
vim.api.nvim_buf_delete(initializing_oil_buf, { force = true })

local function close_window(win)
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
end

local function split(filetype, buftype)
	vim.api.nvim_set_current_win(source_win)
	vim.cmd("botright vnew")
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	vim.bo[buf].buftype = buftype or "nofile"
	vim.bo[buf].filetype = filetype
	vim.api.nvim_set_current_win(source_win)
	return win, buf
end

local function float(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].filetype = filetype
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = 0,
		col = 0,
		width = 10,
		height = 5,
		style = "minimal",
	})
	return win, buf
end

assert(is_user_editor_window(source_win), "a normal source window must be treated as an editor")
assert(not should_exit_after_quit(source_win), "a lone editor must use Neovim's normal quit behavior")

local oil_win, oil_buf = split("oil", "acwrite")
assert(is_user_editor_window(oil_win), "Oil must remain an editor window")
assert(not should_exit_after_quit(source_win), "an Oil window must prevent forced exit")
vim.bo[oil_buf].modified = true
assert(has_modified_user_buffer(), "modified Oil operations must prevent forced exit")
vim.bo[oil_buf].modified = false
close_window(oil_win)

local unknown_float = float("third_party_popup")
assert(not should_exit_after_quit(source_win), "an unrelated floating popup must not trigger forced exit")
close_window(unknown_float)

local minimap_win = float("minimap")
assert(not is_user_editor_window(minimap_win), "minimap must not be treated as an editor")
assert(should_exit_after_quit(source_win), "a floating minimap must trigger exit with the last editor")

local aerial_win = split("aerial")
assert(not is_user_editor_window(aerial_win), "Aerial must not be treated as an editor")
assert(should_exit_after_quit(source_win), "Aerial and minimap must not keep Neovim alive")

local code_win = split("lua", "")
assert(not should_exit_after_quit(source_win), "another code window must prevent automatic exit")
close_window(code_win)

close_window(aerial_win)
local aerial_nav_win = split("aerial-nav")
assert(should_exit_after_quit(source_win), "Aerial navigation must be treated as auxiliary")
close_window(aerial_nav_win)

local snacks_win = split("snacks_layout_box")
assert(should_exit_after_quit(source_win), "Snacks Explorer behavior must remain intact")
close_window(snacks_win)

local empty_win = split("", "")
assert(should_exit_after_quit(source_win), "an empty editor placeholder must not mask the minimap")
close_window(empty_win)

local minimap_buf = vim.api.nvim_win_get_buf(minimap_win)
vim.bo[minimap_buf].buftype = ""
vim.api.nvim_buf_set_lines(minimap_buf, 0, -1, false, { "generated minimap content" })
assert(not is_user_buffer(minimap_buf), "a generated minimap buffer must not be treated as user content")
assert(not has_modified_user_buffer(), "generated auxiliary buffers must not block automatic exit")
vim.bo[minimap_buf].modified = false

local hidden_user_buf = vim.api.nvim_create_buf(false, false)
vim.bo[hidden_user_buf].filetype = "lua"
vim.api.nvim_buf_set_lines(hidden_user_buf, 0, -1, false, { "unsaved user content" })
assert(has_modified_user_buffer(), "a hidden modified user buffer must prevent forced exit")
vim.bo[hidden_user_buf].modified = false
vim.api.nvim_buf_delete(hidden_user_buf, { force = true })

close_window(minimap_win)
print("auxiliary-window exit classification regression: ok")
