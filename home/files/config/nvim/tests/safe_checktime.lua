local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
vim.opt.runtimepath:prepend(vim.fs.joinpath(dotfiles_root, "home/files/config/nvim"))
package.path = table.concat({
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/?.lua"),
	vim.fs.joinpath(dotfiles_root, "home/files/config/nvim/lua/?/init.lua"),
	package.path,
}, ";")

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		error(("%s\nexpected: %s\nactual:   %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local root = vim.fn.tempname()
local source = vim.fs.joinpath(root, "reload.lua")
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "local value = function(argument)", "\treturn argument", "end" }, source)

local bufnr = vim.fn.bufadd(source)
assert(bufnr > 0 and vim.fn.bufload(bufnr) == 0, "test buffer must load")
vim.bo[bufnr].autoread = true

local original_is_enabled = vim.lsp.inlay_hint.is_enabled
local original_enable = vim.lsp.inlay_hint.enable
local enabled = true
local transitions = {}

rawset(vim.lsp.inlay_hint, "is_enabled", function(filter)
	assert_equal(filter, { bufnr = bufnr }, "inlay hint state must be queried for the reloaded buffer")
	return enabled
end)
rawset(vim.lsp.inlay_hint, "enable", function(value, filter)
	assert_equal(filter, { bufnr = bufnr }, "inlay hint transition must target only the reloaded buffer")
	transitions[#transitions + 1] = {
		enabled = value,
		line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1],
	}
	enabled = value == true
end)

vim.fn.writefile({ "return true" }, source)
local ok, err = require("config.safe_checktime").checktime(bufnr)
assert(ok, err)
assert_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "return true" }, "checktime must reload the file")
assert_equal(transitions, {
	{ enabled = false, line = "local value = function(argument)" },
	{ enabled = true, line = "return true" },
}, "inlay hints must be suspended before reload and restored afterwards")

transitions = {}
enabled = false
vim.fn.writefile({ "return false" }, source)
ok, err = require("config.safe_checktime").checktime(bufnr)
assert(ok, err)
assert_equal(transitions, {}, "disabled inlay hints must remain untouched")
assert_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "return false" }, "reload must not require hints")

rawset(vim.lsp.inlay_hint, "is_enabled", original_is_enabled)
rawset(vim.lsp.inlay_hint, "enable", original_enable)

local original_get_client_by_id = vim.lsp.get_client_by_id
local original_get_clients = vim.lsp.get_clients
local lsp_util = require("vim.lsp.util")
local original_version = lsp_util.buf_versions[bufnr]
local fake_client = {
	id = 9876,
	offset_encoding = "utf-8",
	request = function()
		return true, 1
	end,
}
rawset(vim.lsp, "get_client_by_id", function(client_id)
	return client_id == fake_client.id and fake_client or original_get_client_by_id(client_id)
end)
rawset(vim.lsp, "get_clients", function(filter)
	if filter and filter.bufnr == bufnr and filter.method == "textDocument/inlayHint" then
		return { fake_client }
	end
	return original_get_clients(filter)
end)

vim.fn.writefile({ "local value = function(argument)" }, source)
vim.api.nvim_buf_call(bufnr, function()
	vim.cmd("silent checktime")
end)
lsp_util.buf_versions[bufnr] = 1
original_enable(true, { bufnr = bufnr })
vim.lsp.inlay_hint.on_inlayhint(nil, {
	{
		label = ": any",
		position = { character = 32, line = 0 },
	},
}, {
	bufnr = bufnr,
	client_id = fake_client.id,
	method = "textDocument/inlayHint",
	version = 1,
})
assert_equal(#vim.lsp.inlay_hint.get({ bufnr = bufnr }), 1, "the regression setup must cache a real inlay hint")

vim.fn.writefile({ "return nil" }, source)
ok, err = require("config.safe_checktime").checktime(bufnr)
assert(ok, err)
assert_equal(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "return nil" }, "the shorter file must reload")
assert_equal(#vim.lsp.inlay_hint.get({ bufnr = bufnr }), 0, "stale inlay hints must be discarded during reload")
assert(original_is_enabled({ bufnr = bufnr }), "inlay hints must remain enabled after the protected reload")

original_enable(false, { bufnr = bufnr })
rawset(vim.lsp, "get_client_by_id", original_get_client_by_id)
rawset(vim.lsp, "get_clients", original_get_clients)
lsp_util.buf_versions[bufnr] = original_version
vim.fn.delete(root, "rf")
print("safe checktime: ok")
