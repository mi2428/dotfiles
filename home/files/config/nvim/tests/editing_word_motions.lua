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

local function press(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end

local function reset(line, col)
	vim.cmd.enew({ bang = true })
	vim.bo.buftype = ""
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
	vim.api.nvim_win_set_cursor(0, { 1, col or 0 })
end

local function assert_col(expected, message)
	assert_equal(vim.api.nvim_win_get_cursor(0), { 1, expected }, message)
end

if vim.uv.os_uname().sysname == "Darwin" then
	assert(vim.fn.executable("lingua-motion-helper") == 1, "lingua-motion-helper is missing from Neovim PATH")
	for _, lhs in ipairs({ "w", "e", "b", "ge", "iw", "aw", "is", "as", "(", ")" }) do
		for _, mode in ipairs({ "n", "o", "x" }) do
			assert(mapping(lhs, mode).desc == "Lingua motion " .. lhs, lhs .. " is not owned by lingua-motion")
		end
	end
	assert(mapping("cw", "n").desc == "Change word", "cw compatibility mapping is missing")
	assert(package.loaded.spider == nil, "nvim-spider must stay unloaded on macOS")
	for _, lhs in ipairs({ "W", "E", "B", "gE" }) do
		assert(vim.fn.maparg(lhs, "n") == "", lhs .. " must remain a native WORD motion")
	end

	reset("日本語。次")
	press("w")
	assert_col(6, "w did not reach the next NaturalLanguage token")
	press("w")
	assert_col(9, "w did not reach Japanese punctuation")
	press("b")
	assert_col(6, "b did not return to the previous Japanese token")

	reset("日本語。次")
	press("diw")
	assert_equal(vim.api.nvim_get_current_line(), "語。次", "diw did not use the NaturalLanguage word range")

	reset("日本語。次")
	press("cwX<Esc>")
	assert_equal(vim.api.nvim_get_current_line(), "X語。次", "cw no longer behaves like ce")

	reset("One. Two.")
	press(")")
	assert_col(5, "sentence motion did not reach the next sentence")

	print("NaturalLanguage word and sentence motions: ok")
	return
end

-- Force the key-driven plugin to load so the test exercises the final mappings
-- produced by the real Lazy specification.
require("lazy").load({ plugins = { "nvim-spider" } })

-- The configured mappings must cover navigation, selection, and operators.
local descriptions = {
	w = "Next word (skip punctuation)",
	e = "End of word (skip punctuation)",
	b = "Previous word (skip punctuation)",
	ge = "Previous word end (skip punctuation)",
}
for lhs, description in pairs(descriptions) do
	for _, mode in ipairs({ "n", "o", "x" }) do
		assert(mapping(lhs, mode).desc == description, lhs .. " has an unexpected description in " .. mode .. " mode")
	end
end
assert(mapping("cw", "n").desc == "Change word", "cw compatibility mapping is missing")
for _, lhs in ipairs({ "W", "E", "B", "gE" }) do
	assert(vim.fn.maparg(lhs, "n") == "", lhs .. " must remain a native WORD motion")
end

-- Spider has an upstream CJK limitation. The local wrapper must retain native
-- movement rather than allowing lowercase word motions to become no-ops.
reset("日本語。テスト 次")
press("w")
assert_col(9, "w did not fall back to native movement on a CJK-only word")
press("w")
assert_col(12, "the native CJK fallback did not advance past punctuation")
press("b")
assert_col(9, "b did not fall back to native movement on CJK text")

-- `w` should skip attached syntax punctuation while retaining useful,
-- whitespace-delimited operators as stops.
reset("foo.bar baz")
press("w")
assert_col(4, "w stopped on the period instead of the next identifier")
press("w")
assert_col(8, "the second w did not reach the following word")

reset("foo == bar")
press("w")
assert_col(4, "w skipped a whitespace-delimited operator")
press("w")
assert_col(7, "w did not move from the operator to the next word")

-- Keep the established whole-identifier behavior; this configuration should
-- not introduce camelCase or snake_case subword stops.
reset("myVariable FOO_BAR next")
press("w")
assert_col(11, "w split a camelCase identifier")
press("w")
assert_col(19, "w split a snake_case identifier")

reset("foo.bar baz")
press("2w")
assert_col(8, "a count did not use punctuation-skipping word boundaries")

-- Exercise the other three directions so forward and backward boundaries stay
-- symmetrical around punctuation.
reset("foo.bar baz")
press("e")
assert_col(2, "e did not stop at the end of the current word")
press("e")
assert_col(6, "e stopped at the period instead of the next word end")
vim.api.nvim_win_set_cursor(0, { 1, 8 })
press("b")
assert_col(4, "b did not reach the previous identifier")
press("b")
assert_col(0, "b stopped at the period instead of the first identifier")
vim.api.nvim_win_set_cursor(0, { 1, 8 })
press("ge")
assert_col(6, "ge stopped at the period instead of the previous word end")

-- Operator-pending mappings must use the same boundaries. Preserve Vim's
-- familiar `cw` behavior and verify that Ex-command mappings remain dot-repeatable.
reset("foo.bar baz")
press("dw")
assert_equal(vim.api.nvim_get_current_line(), "bar baz", "dw did not consume insignificant punctuation")

reset("日本語。テスト")
press("dw")
assert_equal(
	vim.api.nvim_get_current_line(),
	"。テスト",
	"operator-pending CJK fallback changed native dw behavior"
)

reset("foo.bar baz")
press("cwX<Esc>")
assert_equal(vim.api.nvim_get_current_line(), "X.bar baz", "cw no longer behaves like ce")

reset("foo.bar foo.bar")
press("dw")
press("w")
press(".")
assert_equal(vim.api.nvim_get_current_line(), "bar bar", "dot-repeat did not replay a Spider operator motion")

-- Visual movement should extend to the same semantic boundary.
reset("foo.bar baz")
press("vw")
assert_col(4, "Visual w stopped on the period")
press("<Esc>")

print("punctuation-skipping word motions: ok")
