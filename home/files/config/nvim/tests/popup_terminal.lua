local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/ui.lua"))
local snacks
for _, spec in ipairs(specs) do
	if spec[1] == "folke/snacks.nvim" then
		snacks = spec
		break
	end
end
assert(snacks, "Snacks plugin spec was not found")

local popup_key
for _, key in ipairs(snacks.keys or {}) do
	if key[1] == "<C-S-Bslash>" then
		popup_key = key
		break
	end
end
assert(popup_key, "floating terminal key is missing")
assert(vim.deep_equal(popup_key.mode, { "n", "t" }), "floating terminal must toggle in normal and terminal modes")
assert(popup_key.nowait == true, "floating terminal mapping must not wait while terminal input is active")

local terminal_key = assert(
	snacks.opts.terminal.win.keys.floating_terminal,
	"Snacks terminals must install a buffer-local floating terminal mapping"
)
assert(terminal_key[1] == "<C-S-Bslash>", "buffer-local terminal mapping uses the wrong key")
assert(terminal_key.mode == "t", "buffer-local floating terminal mapping must apply in terminal mode")
assert(type(terminal_key[2]) == "function", "buffer-local terminal mapping must use a Lua callback")

local raw_key_lhs = "<C-\\>"

local mapping_calls = 0
local original_popup_terminal = package.loaded["config.popup_terminal"]
package.loaded["config.popup_terminal"] = {
	toggle = function()
		mapping_calls = mapping_calls + 1
	end,
}
popup_key[2]()
terminal_key[2]()
vim.wait(1000, function()
	return mapping_calls == 2
end)
package.loaded["config.popup_terminal"] = original_popup_terminal
assert(mapping_calls == 2, "global and buffer-local mappings must call the dedicated floating terminal toggle")

local toggle_call
local toggle_calls = 0
local original_snacks = package.loaded.snacks
package.loaded.snacks = {
	terminal = {
		toggle = function(cmd, opts)
			toggle_calls = toggle_calls + 1
			toggle_call = { cmd = cmd, opts = opts }
			return "terminal"
		end,
	},
}
package.loaded["config.popup_terminal"] = nil
local result = require("config.popup_terminal").toggle()
package.loaded["config.popup_terminal"] = original_popup_terminal

assert(result == "terminal", "floating terminal must return the Snacks terminal instance")
assert(toggle_call.cmd == vim.o.shell, "floating terminal must use an explicit shell command")
assert(toggle_call.opts.count == 1, "floating terminal id must not depend on a mapping count")
assert(toggle_call.opts.win.position == "float", "floating terminal must use a popup window")
assert(toggle_call.opts.win.relative == "editor", "floating terminal must be centered relative to the editor")
assert(toggle_call.opts.win.width == 0.8, "floating terminal width must be 80%")
assert(toggle_call.opts.win.height == 0.8, "floating terminal height must be 80%")
assert(toggle_call.opts.win.wo.winbar == "", "floating terminal must not inherit the bottom terminal winbar")
assert(toggle_call.opts.win.wo.winfixheight == false, "floating terminal must not inherit split height locking")
assert(toggle_call.opts.win.wo.winfixwidth == false, "floating terminal must not lock its popup width")

local raw_key =
	assert(toggle_call.opts.win.keys.raw_control_backslash, "popup must install a raw control-backslash fallback")
assert(raw_key[1] == raw_key_lhs, "raw fallback uses the wrong key")
assert(raw_key.mode == "t", "raw fallback must apply in terminal mode")
assert(raw_key.nowait == true, "raw fallback must not wait for terminal input")
assert(type(raw_key[2]) == "function", "raw fallback must use a Lua callback")

local non_popup_buffer = vim.api.nvim_create_buf(false, true)
local non_popup_before = vim.api.nvim_buf_call(non_popup_buffer, function()
	return vim.fn.maparg(raw_key_lhs, "t", false, true)
end)
assert(vim.tbl_isempty(non_popup_before), "raw fallback must not be global before opening the popup")

raw_key[2]()
assert(toggle_calls == 1, "raw fallback must defer popup close until terminal input is released")
vim.wait(1000, function()
	return toggle_calls == 2
end)
assert(toggle_calls == 2, "raw fallback must toggle the popup after terminal input is released")

local non_popup_after = vim.api.nvim_buf_call(non_popup_buffer, function()
	return vim.fn.maparg(raw_key_lhs, "t", false, true)
end)
assert(vim.tbl_isempty(non_popup_after), "raw fallback must not leak to non-popup terminal buffers")
vim.api.nvim_buf_delete(non_popup_buffer, { force = true })
package.loaded.snacks = original_snacks

local snacks_root = vim.env.SNACKS_ROOT or vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "snacks.nvim")
assert(vim.fn.isdirectory(snacks_root) == 1, "SNACKS_ROOT must point to an installed snacks.nvim checkout")
vim.opt.runtimepath:append(snacks_root)

package.loaded.snacks = nil
package.loaded["config.popup_terminal"] = nil
local actual_popup_terminal = require("config.popup_terminal")
local Snacks = require("snacks")
-- Avoid reporting the expected non-zero status when the test intentionally
-- wipes the interactive shell's terminal buffer.
Snacks.notify = { error = function() end }

local original_shell = vim.o.shell
vim.o.shell = "/bin/sh"
local popup = actual_popup_terminal.toggle()
local popup_buffer = popup.buf
assert(popup:valid(), "Snacks must create the popup window")
assert(vim.api.nvim_buf_is_valid(popup_buffer), "Snacks must create the popup terminal buffer")

local popup_mapping = vim.api.nvim_buf_call(popup_buffer, function()
	return vim.fn.maparg(raw_key_lhs, "t", false, true)
end)
assert(popup_mapping.buffer == 1, "raw fallback must be buffer-local on the Snacks popup terminal")
assert(type(popup_mapping.callback) == "function", "raw fallback must install a terminal-mode callback")

local isolated_terminal = vim.api.nvim_create_buf(false, true)
local isolated_mapping = vim.api.nvim_buf_call(isolated_terminal, function()
	return vim.fn.maparg(raw_key_lhs, "t", false, true)
end)
assert(vim.tbl_isempty(isolated_mapping), "raw fallback must not be installed on non-popup terminal buffers")

vim.api.nvim_set_current_win(popup.win)
vim.cmd.startinsert()
assert(
	vim.wait(1000, function()
		return vim.fn.mode(1):find("t", 1, true) ~= nil
	end),
	"popup must enter terminal mode before injecting the raw fallback"
)
popup_mapping.callback()
assert(
	vim.wait(1000, function()
		return not popup:valid()
	end),
	"raw fallback must hide the popup from terminal mode"
)
vim.cmd.stopinsert()

popup:close()
assert(
	vim.wait(1000, function()
		return not vim.api.nvim_buf_is_valid(popup_buffer)
	end),
	"wiping the popup terminal must remove its buffer-local raw fallback"
)
local isolated_after_wipe = vim.api.nvim_buf_call(isolated_terminal, function()
	return vim.fn.maparg(raw_key_lhs, "t", false, true)
end)
assert(vim.tbl_isempty(isolated_after_wipe), "raw fallback must not leak after the popup is wiped")
vim.api.nvim_buf_delete(isolated_terminal, { force = true })
vim.o.shell = original_shell

print("floating terminal regression: ok")
