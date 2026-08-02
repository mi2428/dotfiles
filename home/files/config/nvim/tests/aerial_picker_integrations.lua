local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/ui.lua"))
local aerial
local snacks
for _, spec in ipairs(specs) do
	if spec[1] == "stevearc/aerial.nvim" then
		aerial = spec
	elseif spec[1] == "folke/snacks.nvim" then
		snacks = spec
	end
end
assert(aerial, "Aerial plugin spec was not found")
assert(snacks, "Snacks plugin spec was not found")

local function find_key(spec, lhs)
	for _, key in ipairs(spec.keys or {}) do
		if key[1] == lhs then
			return key
		end
	end
end

local snacks_key = assert(find_key(aerial, "<leader>ss"), "Aerial Snacks picker key is missing")
local fzf_key = assert(find_key(aerial, "<leader>sf"), "Aerial fzf-lua picker key is missing")
assert(type(snacks_key[2]) == "function", "Aerial Snacks key must use a Lua callback")
assert(type(fzf_key[2]) == "function", "Aerial fzf-lua key must use a Lua callback")
assert(find_key(snacks, "<leader>ss") == nil, "Snacks must not shadow the Aerial symbol picker key")
assert(find_key(snacks, "<leader>sS"), "workspace symbol search must remain available")

local dependencies = {}
for _, dependency in ipairs(aerial.dependencies or {}) do
	dependencies[dependency] = true
end
assert(dependencies["folke/snacks.nvim"], "Aerial must declare its Snacks integration")
assert(dependencies["ibhagwan/fzf-lua"], "Aerial must declare its fzf-lua integration")
assert(aerial.opts.layout.win_opts.cursorline == true, "Aerial must show its navigation cursor")
assert(aerial.opts.layout.win_opts.number == false, "Aerial must disable absolute line numbers")
assert(aerial.opts.layout.win_opts.relativenumber == false, "Aerial must disable relative line numbers")
assert(aerial.opts.layout.win_opts.statuscolumn == "", "Aerial must disable the custom statuscolumn gutter")
assert(type(aerial.opts.float.override) == "function", "Aerial must preserve an embedded Glance layout")

local calls = {}
local original_aerial = package.loaded.aerial
package.loaded.aerial = {
	snacks_picker = function()
		calls.snacks = (calls.snacks or 0) + 1
	end,
	fzf_lua_picker = function()
		calls.fzf = (calls.fzf or 0) + 1
	end,
}

snacks_key[2]()
fzf_key[2]()
package.loaded.aerial = original_aerial

assert(calls.snacks == 1, "<leader>ss did not call Aerial's Snacks picker")
assert(calls.fzf == 1, "<leader>sf did not call Aerial's fzf-lua picker")

print("Aerial picker integrations regression: ok")
