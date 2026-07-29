local function assert_equal(actual, expected, message)
	assert(
		vim.deep_equal(actual, expected),
		string.format("%s\nexpected: %s\nactual:   %s", message, vim.inspect(expected), vim.inspect(actual))
	)
end

local function mapping(lhs, mode)
	local result = vim.fn.maparg(lhs, mode, false, true)
	assert(not vim.tbl_isempty(result), string.format("%s is not mapped in %s mode", lhs, mode))
	return result
end

local function type_keys(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end

local function reset_buffer(lines, cursor, filetype)
	vim.cmd.enew({ bang = true })
	vim.bo.buftype = ""
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.bo.filetype = filetype or "lua"
	vim.api.nvim_win_set_cursor(0, cursor or { 1, 0 })
	-- Headless input does not stay in Insert mode long enough for Blink's
	-- InsertEnter hook, so trigger the same event explicitly in each new buffer.
	vim.api.nvim_exec_autocmds("InsertEnter", {})
end

-- Force the event-driven plugins to load so this test exercises their actual
-- Lazy configurations and their interaction with the rest of the config.
require("lazy").load({
	plugins = {
		"nvim-autopairs",
		"nvim-surround",
		"mini.ai",
		"flash.nvim",
		"blink.cmp",
		"nvim-treesitter-textobjects",
	},
})
assert(
	vim.wait(5000, function()
		return package.loaded["blink.cmp.keymap"] ~= nil
	end),
	"blink.cmp keymaps did not finish initializing"
)

-- nvim-autopairs: insertion, closing-character skip, backspace, and newline.
reset_buffer({ "" })
type_keys("i(<Esc>")
assert_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "()" }, "opening parenthesis did not create a pair")

reset_buffer({ "" })
type_keys("i()<Esc>")
assert_equal(
	vim.api.nvim_buf_get_lines(0, 0, -1, false),
	{ "()" },
	"typing the closing parenthesis did not skip its mate"
)

reset_buffer({ "" })
type_keys("i(<BS><Esc>")
assert_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" }, "backspace did not remove an empty pair")

reset_buffer({ "" })
type_keys("i{<CR><Esc>")
assert_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "", "}" }, "Enter did not expand an empty pair")
assert(mapping("<CR>", "i").desc == "blink.cmp: Accept", "autopairs replaced Blink's completion mapping")

reset_buffer({ 'local value = "text"' })
type_keys('0f"li(<Esc>')
assert_equal(
	vim.api.nvim_get_current_line(),
	'local value = "(text"',
	"Treesitter-aware pairing did not ignore a Lua string"
)

vim.cmd.vsplit()
reset_buffer({ "" }, nil, "text")
type_keys("i[<Esc>")
assert_equal(vim.api.nvim_get_current_line(), "[]", "autopairs did not attach in a split without a parser")
vim.cmd.only()

-- nvim-surround: motion, delete, change, and the remapped Visual operation.
reset_buffer({ "word" })
type_keys('ysiw"')
assert_equal(vim.api.nvim_get_current_line(), '"word"', "ys did not add a surround")
type_keys("cs\"'")
assert_equal(vim.api.nvim_get_current_line(), "'word'", "cs did not change a surround")
type_keys("ds'")
assert_equal(vim.api.nvim_get_current_line(), "word", "ds did not delete a surround")

reset_buffer({ "word" })
type_keys("viwgs]")
assert_equal(vim.api.nvim_get_current_line(), "[word]", "Visual gs did not add a surround")

assert(mapping("s", "n").desc == "Flash", "nvim-surround introduced an s-prefix delay for Flash")
assert(mapping("S", "x").desc == "Flash Treesitter", "nvim-surround replaced Flash's Visual S mapping")
assert(mapping("gs", "x").desc == "Add surround to selection", "Visual surround was not moved to gs")
assert(mapping("gS", "x").desc == "Add linewise surround to selection", "linewise Visual surround was not moved to gS")
for _, lhs in ipairs({ "sa", "sd", "sr", "sf", "sF", "sh" }) do
	assert(vim.tbl_isempty(vim.fn.maparg(lhs, "n", false, true)), lhs .. " must not delay Flash's s mapping")
end

-- mini.ai: exercise an enhanced builtin object and preserve semantic
-- Treesitter objects plus Neovim's newer builtin keyspace.
reset_buffer({ "value = (alpha + beta)" }, { 1, 12 })
type_keys("di)")
assert_equal(vim.api.nvim_get_current_line(), "value = ()", "mini.ai inside-parentheses object did not operate")

reset_buffer({ "call(first, second)" }, { 1, 13 })
type_keys("daa")
assert_equal(vim.api.nvim_get_current_line(), "call(first)", "mini.ai argument object did not operate")

reset_buffer({ "result = outer(inner)" }, { 1, 16 })
type_keys("diF")
assert_equal(vim.api.nvim_get_current_line(), "result = outer()", "mini.ai function-call object did not operate")

assert(mapping("a", "o").desc == "Around textobject", "mini.ai around mapping is missing")
assert(mapping("i", "o").desc == "Inside textobject", "mini.ai inside mapping is missing")
assert(mapping("al", "o").desc == "Around last textobject", "mini.ai last-around mapping is missing")
assert(mapping("il", "o").desc == "Inside last textobject", "mini.ai last-inside mapping is missing")
assert(mapping("af", "o").desc == "Select function outer", "mini.ai replaced Treesitter's af object")
assert(mapping("if", "o").desc == "Select function inner", "mini.ai replaced Treesitter's if object")
assert(mapping("an", "o").desc == "Select parent (outer) node", "mini.ai replaced Neovim's an object")
assert(mapping("in", "o").desc == "Select child (inner) node", "mini.ai replaced Neovim's in object")
for _, lhs in ipairs({ "g[", "g]" }) do
	assert(vim.tbl_isempty(vim.fn.maparg(lhs, "n", false, true)), "mini.ai must not map " .. lhs)
end

print("autopairs, surround, and mini.ai: ok")
