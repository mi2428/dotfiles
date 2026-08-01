local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")

-- The configured preview is 36 content rows plus its border. Neovim's
-- headless default is only 24x80, which makes the floating window clamp before
-- this test can verify the requested size.
if #vim.api.nvim_list_uis() == 0 then
	vim.o.lines = math.max(vim.o.lines, 60)
	vim.o.columns = math.max(vim.o.columns, 160)
end

local function normalize(path)
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function wait_for_lsp(bufnr)
	assert(
		vim.wait(10000, function()
			return #vim.lsp.get_clients({ bufnr = bufnr }) > 0
		end, 50),
		"lua-language-server did not attach"
	)
end

local function definition_at(line, col, label)
	vim.api.nvim_win_set_cursor(0, { line, col })
	local client = assert(vim.lsp.get_clients({ bufnr = 0 })[1], "attached LSP client is required")
	local definition
	assert(
		vim.wait(10000, function()
			local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
			local responses = vim.lsp.buf_request_sync(0, "textDocument/definition", params, 2000) or {}

			for _, response in pairs(responses) do
				local results = response.result
				if results and results.uri then
					results = { results }
				end
				if type(results) == "table" and results[1] then
					local result = results[1]
					local range = assert(result.targetSelectionRange or result.range, "definition range is required")
					definition = {
						path = normalize(
							vim.uri_to_fname(assert(result.targetUri or result.uri, "definition URI is required"))
						),
						line = range.start.line + 1,
						col = range.start.character,
					}
					return true
				end
			end
			return false
		end, 100),
		label .. ": LSP returned no definition"
	)

	return definition
end

local function mapping(lhs)
	local found = vim.iter(vim.api.nvim_buf_get_keymap(0, "n")):find(function(item)
		return item.lhs == lhs
	end)
	assert(found and type(found.callback) == "function", lhs .. " must have an LSP buffer-local callback")
	return found.callback
end

local function source_position(path, needle)
	for line_number, line in ipairs(vim.fn.readfile(path)) do
		local column = line:find(needle, 1, true)
		if column then
			return line_number, column - 1
		end
	end
	error(("%s was not found in %s"):format(needle, path))
end

local function assert_definition_preview(case)
	vim.cmd.edit(vim.fn.fnameescape(case.source))
	wait_for_lsp(0)
	local line, col = source_position(case.source, case.needle)
	local label = ("%s at %s:%d:%d"):format(case.lhs, case.source, line, col)
	local expected = definition_at(line, col, label)
	local source_win = vim.api.nvim_get_current_win()
	local expected_preview_height = math.min(vim.api.nvim_win_get_height(source_win), 36)
	mapping(case.lhs)()

	assert(
		vim.wait(10000, function()
			local win = vim.api.nvim_get_current_win()
			if win == source_win then
				return false
			end
			local cursor = vim.api.nvim_win_get_cursor(win)
			return normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))) == expected.path
				and cursor[1] == expected.line
				and cursor[2] == expected.col
		end, 50),
		("%s did not focus the LSP definition at %s:%d:%d"):format(case.lhs, expected.path, expected.line, expected.col)
	)

	local preview_win = vim.api.nvim_get_current_win()
	assert(vim.api.nvim_win_get_config(preview_win).relative ~= "", case.lhs .. " must focus the Glance preview")
	assert(
		vim.api.nvim_win_get_height(preview_win) == expected_preview_height,
		("%s Glance preview height must be %d rows"):format(case.lhs, expected_preview_height)
	)
	require("glance").actions.close()
	assert(vim.api.nvim_get_current_win() == source_win, case.lhs .. " must restore the source window on close")
end

local lsp_config = vim.fs.joinpath(nvim_root, "lua/plugins/lsp.lua")
local keymaps = vim.fs.joinpath(nvim_root, "lua/config/keymaps.lua")

for _, case in ipairs({
	{ lhs = "gd", source = lsp_config, needle = 'executable("rustup")' },
	{ lhs = "gD", source = lsp_config, needle = 'executable("rustup")' },
	{ lhs = "gd", source = keymaps, needle = "select_agent()" },
	{ lhs = "gD", source = keymaps, needle = "select_agent()" },
}) do
	assert_definition_preview(case)
end

print("Glance definition integration: ok")
