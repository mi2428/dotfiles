local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")

vim.opt.runtimepath:prepend(nvim_root)
for _, plugin in ipairs({ "treesj", "mini.move", "mini.align" }) do
	vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, plugin))
end
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/editing.lua"))
local by_repo = {}
for _, spec in ipairs(specs) do
	by_repo[spec[1]] = spec
end

local treesj_spec = assert(by_repo["Wansmer/treesj"], "TreeSJ plugin spec was not found")
assert(#treesj_spec.keys == 1 and treesj_spec.keys[1][1] == "gS", "TreeSJ must use the single gS mapping")
assert(type(treesj_spec.keys[1][2]) == "function", "TreeSJ gS mapping must lazy-load its toggle function")
assert(treesj_spec.keys[1].desc == "Toggle structural split/join", "TreeSJ gS mapping needs a useful description")
assert(treesj_spec.opts.use_default_keymaps == false, "TreeSJ must not claim its leader-based default mappings")

local move_spec = assert(by_repo["nvim-mini/mini.move"], "mini.move plugin spec was not found")
local align_spec = assert(by_repo["nvim-mini/mini.align"], "mini.align plugin spec was not found")
assert(move_spec.event == "VeryLazy" and align_spec.event == "VeryLazy", "mini helpers must stay off the startup path")
assert(
	vim.deep_equal(move_spec.opts.mappings, {
		left = "<M-h>",
		right = "<M-l>",
		down = "<M-j>",
		up = "<M-k>",
		line_left = "<M-h>",
		line_right = "<M-l>",
		line_down = "<M-j>",
		line_up = "<M-k>",
	}),
	"mini.move mappings must remain explicit"
)
assert(
	vim.deep_equal(align_spec.opts.mappings, { start = "ga", start_with_preview = "gA" }),
	"mini.align mappings must remain explicit"
)

local function assert_mapping(lhs, mode, description)
	local mapping = vim.fn.maparg(lhs, mode, false, true)
	assert(not vim.tbl_isempty(mapping), lhs .. " is not mapped in " .. mode .. " mode")
	assert(mapping.desc == description, lhs .. " has an unexpected description")
end

local MiniMove = require("mini.move")
MiniMove.setup(move_spec.opts)
for _, mapping in ipairs({
	{ "<M-h>", "n", "Move line left" },
	{ "<M-j>", "n", "Move line down" },
	{ "<M-k>", "n", "Move line up" },
	{ "<M-l>", "n", "Move line right" },
	{ "<M-h>", "x", "Move left" },
	{ "<M-j>", "x", "Move down" },
	{ "<M-k>", "x", "Move up" },
	{ "<M-l>", "x", "Move right" },
}) do
	assert_mapping(unpack(mapping))
end
for _, mode in ipairs({ "n", "x" }) do
	for _, lhs in ipairs({ "<leader>mh", "<leader>mj", "<leader>mk", "<leader>ml" }) do
		assert(vim.fn.maparg(lhs, mode) == "", lhs .. " must remain unclaimed in " .. mode .. " mode")
	end
end

vim.bo.expandtab = true
vim.bo.shiftwidth = 2
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
MiniMove.move_line("up")
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "two", "one", "three" }), "line did not move up")
MiniMove.move_line("right")
assert(vim.api.nvim_get_current_line() == "  two", "horizontal line movement did not add one indentation level")
MiniMove.move_line("left")
assert(vim.api.nvim_get_current_line() == "two", "horizontal line movement did not remove one indentation level")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("normal! Vj")
MiniMove.move_selection("down")
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "one", "four", "two", "three" }),
	"Visual line selection did not move down as a block"
)
vim.cmd("normal! \27")

local MiniAlign = require("mini.align")
MiniAlign.setup(align_spec.opts)
for _, mode in ipairs({ "n", "x" }) do
	assert_mapping("ga", mode, "Align")
	assert_mapping("gA", mode, "Align with preview")
end
local align_opts = {}
local align_steps = vim.deepcopy(MiniAlign.config.steps)
MiniAlign.config.modifiers["="](align_steps, align_opts)
local aligned = MiniAlign.align_strings({ "a=1", "long = 2" }, align_opts, align_steps)
assert(vim.deep_equal(aligned, { "a    = 1", "long = 2" }), "equals modifier did not align assignment columns")

require("treesj").setup(treesj_spec.opts)
for _, lhs in ipairs({ "<Space>m", "<Space>j", "<Space>s" }) do
	assert(vim.fn.maparg(lhs, "n") == "", "TreeSJ default mapping leaked into the config: " .. lhs)
end
vim.cmd.enew({ bang = true })
vim.bo.filetype = "lua"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = { first = 1, second = 2 }" })
vim.api.nvim_win_set_cursor(0, { 1, 16 })
require("treesj").toggle()
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
		"local value = {",
		"\tfirst = 1,",
		"\tsecond = 2,",
		"}",
	}),
	"TreeSJ did not structurally split a Lua table"
)
require("treesj").toggle()
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "local value = { first = 1, second = 2 }" }),
	"TreeSJ did not join the Lua table back to its original form"
)

print("structural editing helpers: ok")
