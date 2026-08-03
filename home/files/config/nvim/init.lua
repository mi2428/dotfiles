local config_source = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fn.fnamemodify(config_source, ":p:h")
if vim.fs.normalize(config_root) ~= vim.fs.normalize(vim.fn.stdpath("config")) then
	vim.opt.runtimepath:prepend(config_root)
end

package.path = table.concat({
	config_root .. "/lua/?.lua",
	config_root .. "/lua/?/init.lua",
	package.path,
}, ";")

require("config")
require("config.bigfile")
