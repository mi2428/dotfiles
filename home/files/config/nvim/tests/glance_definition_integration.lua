local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")

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

local function references_at(line, col, label)
	vim.api.nvim_win_set_cursor(0, { line, col })
	local client = assert(vim.lsp.get_clients({ bufnr = 0 })[1], "attached LSP client is required")
	local references
	assert(
		vim.wait(10000, function()
			local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
			params.context = { includeDeclaration = true }
			local responses = vim.lsp.buf_request_sync(0, "textDocument/references", params, 2000) or {}
			local found = {}

			for _, response in pairs(responses) do
				for _, result in ipairs(response.result or {}) do
					local range = assert(result.range, "reference range is required")
					found[#found + 1] = {
						path = normalize(vim.uri_to_fname(assert(result.uri, "reference URI is required"))),
						line = range.start.line + 1,
						col = range.start.character,
					}
				end
			end

			if #found < 2 then
				return false
			end
			table.sort(found, function(left, right)
				if left.path ~= right.path then
					return left.path < right.path
				end
				if left.line ~= right.line then
					return left.line < right.line
				end
				return left.col < right.col
			end)
			references = found
			return true
		end, 100),
		label .. ": LSP returned fewer than two references"
	)

	return references
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
	require("glance").actions.close()
	assert(vim.api.nvim_get_current_win() == source_win, case.lhs .. " must restore the source window on close")
end

local function assert_references_preview(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	wait_for_lsp(0)
	local line, col = source_position(path, "executable(name)")
	local references = references_at(line, col, "gr reference navigation")
	local source_win = vim.api.nvim_get_current_win()
	mapping("gr")()

	local function at_location(location)
		local win = vim.api.nvim_get_current_win()
		local cursor = vim.api.nvim_win_get_cursor(win)
		return normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))) == location.path
			and cursor[1] == location.line
			and cursor[2] == location.col
	end

	assert(
		vim.wait(10000, function()
			return vim.api.nvim_get_current_win() ~= source_win and at_location(references[1])
		end, 50),
		"gr did not focus the first LSP reference"
	)
	mapping("<Tab>")()
	assert(
		vim.wait(1000, function()
			return at_location(references[2])
		end, 20),
		"gr <Tab> did not move to the next caller/reference"
	)

	require("glance").actions.close()
	assert(vim.api.nvim_get_current_win() == source_win, "gr must restore the source window on close")
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

assert_references_preview(lsp_config)

print("Glance definition integration: ok")
