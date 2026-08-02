local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local aerial_max_width = require("config.sidebar").width

-- The configured preview is 43 content rows plus its border. Neovim's
-- headless default is only 24x80, which makes the floating window clamp before
-- this test can verify the requested size.
if #vim.api.nvim_list_uis() == 0 then
	vim.o.lines = math.max(vim.o.lines, 70)
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

local function filetype_window(filetype)
	return vim.iter(vim.api.nvim_tabpage_list_wins(0)):find(function(win)
		return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == filetype
	end)
end

local function assert_definition_preview(case)
	vim.cmd.edit(vim.fn.fnameescape(case.source))
	wait_for_lsp(0)
	local line, col = source_position(case.source, case.needle)
	local label = ("%s at %s:%d:%d"):format(case.lhs, case.source, line, col)
	local expected = definition_at(line, col, label)
	local source_win = vim.api.nvim_get_current_win()
	local sibling_win
	if case.source_width then
		vim.cmd("rightbelow vnew")
		sibling_win = vim.api.nvim_get_current_win()
		vim.api.nvim_set_current_win(source_win)
		vim.api.nvim_win_set_width(source_win, case.source_width)
	end
	local source_width = vim.api.nvim_win_get_width(source_win)
	local expected_preview_height = math.min(vim.api.nvim_win_get_height(source_win), 43)
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
	assert(vim.w[preview_win].dotfiles_glance_preview == true, case.lhs .. " must mark its preview for Dropbar")
	assert(
		vim.wo[preview_win].winbar == "%{%v:lua.dropbar()%}",
		case.lhs .. " must use Dropbar breadcrumbs in its preview"
	)
	local rendered_breadcrumb = ""
	assert(
		vim.wait(10000, function()
			rendered_breadcrumb = vim.api.nvim_eval_statusline(vim.wo[preview_win].winbar, { winid = preview_win }).str
			return rendered_breadcrumb:find(vim.fs.basename(expected.path), 1, true) ~= nil
		end, 50),
		("%s breadcrumb must identify %s (rendered=%q)"):format(
			case.lhs,
			vim.fs.basename(expected.path),
			rendered_breadcrumb
		)
	)
	assert(
		vim.api.nvim_win_get_height(preview_win) == expected_preview_height,
		("%s Glance preview height must be %d rows"):format(case.lhs, expected_preview_height)
	)
	if case.omit_aerial then
		assert(filetype_window("aerial") == nil, case.lhs .. " narrow preview must omit Aerial")
		local hidden_list = assert(filetype_window("Glance"), case.lhs .. " must retain its hidden result state")
		assert(vim.api.nvim_win_get_config(hidden_list).hide == true, case.lhs .. " narrow result list must be hidden")
		assert(
			vim.api.nvim_win_get_config(preview_win).width == source_width,
			case.lhs .. " narrow code preview must reclaim the hidden list width"
		)
		if case.nested then
			mapping("gd")()
			assert(
				vim.wait(10000, function()
					return vim.bo.filetype == "Glance" and vim.api.nvim_win_get_config(0).hide == false
				end, 50),
				case.lhs .. " nested definition must restore the hidden result list"
			)
		end
		require("glance").actions.close()
		assert(vim.api.nvim_get_current_win() == source_win, case.lhs .. " must restore the narrow source window")
		if sibling_win and vim.api.nvim_win_is_valid(sibling_win) then
			vim.api.nvim_win_close(sibling_win, true)
		end
		return
	end
	local aerial_win = assert(filetype_window("aerial"), case.lhs .. " single definition must use an Aerial outline")
	local embedded_layout = assert(
		vim.w[aerial_win].dotfiles_glance_aerial_layout,
		case.lhs .. " Aerial outline must retain its allocated Glance layout"
	)
	local sidebar_sync_settled = false
	vim.defer_fn(function()
		sidebar_sync_settled = true
	end, 100)
	assert(
		vim.wait(1000, function()
			return sidebar_sync_settled
		end),
		case.lhs .. " sidebar layout did not settle"
	)
	local settled_layout = vim.api.nvim_win_get_config(aerial_win)
	assert(
		settled_layout.width == embedded_layout.width,
		("%s Aerial outline width changed after sidebar sync (expected=%d, actual=%d)"):format(
			case.lhs,
			embedded_layout.width,
			settled_layout.width
		)
	)
	assert(
		settled_layout.width == aerial_max_width,
		("%s Aerial outline must be capped at %d columns (actual=%d)"):format(
			case.lhs,
			aerial_max_width,
			settled_layout.width
		)
	)
	assert(
		vim.api.nvim_win_get_config(preview_win).width + settled_layout.width == source_width,
		case.lhs .. " must return capped Aerial width to the code preview"
	)
	if case.resize_width then
		vim.api.nvim_win_set_width(source_win, case.resize_width)
		local upvalue_name, session = debug.getupvalue(require("glance").actions.next, 1)
		assert(upvalue_name == "glance" and type(session) == "table", "active Glance session must be inspectable")
		session:on_resize()
		local resized_aerial_layout = vim.api.nvim_win_get_config(aerial_win)
		local resized_preview_layout = vim.api.nvim_win_get_config(preview_win)
		assert(
			resized_aerial_layout.width == aerial_max_width,
			case.lhs .. " resize must preserve the Aerial width cap"
		)
		assert(
			resized_preview_layout.width + resized_aerial_layout.width == vim.api.nvim_win_get_width(source_win),
			case.lhs .. " resize must continue to use the full source width"
		)
	end
	local preview_position = vim.fn.win_screenpos(preview_win)
	local aerial_position = vim.fn.win_screenpos(aerial_win)
	local preview_layout = vim.api.nvim_win_get_config(preview_win)
	local current_aerial_layout = vim.api.nvim_win_get_config(aerial_win)
	assert(
		preview_position[2] < aerial_position[2]
			and preview_layout.col + preview_layout.width == current_aerial_layout.col,
		("%s Aerial outline must remain to the right of the preview (preview=%s, aerial=%s)"):format(
			case.lhs,
			vim.inspect(preview_position),
			vim.inspect(aerial_position)
		)
	)
	if case.nested then
		mapping("gd")()
		assert(
			vim.wait(10000, function()
				return vim.bo.filetype == "Glance"
			end, 50),
			case.lhs .. " nested definition must restore the Glance result list"
		)
		assert(filetype_window("aerial") == nil, case.lhs .. " nested definition must retire the stale Aerial outline")
	end
	require("glance").actions.close()
	assert(vim.api.nvim_get_current_win() == source_win, case.lhs .. " must restore the source window on close")
	assert(filetype_window("aerial") == nil, case.lhs .. " must close its Aerial outline with the preview")
	if sibling_win and vim.api.nvim_win_is_valid(sibling_win) then
		vim.api.nvim_win_close(sibling_win, true)
	end
end

local lsp_config = vim.fs.joinpath(nvim_root, "lua/plugins/lsp.lua")
local keymaps = vim.fs.joinpath(nvim_root, "lua/config/keymaps.lua")

for _, case in ipairs({
	{ lhs = "gd", source = lsp_config, needle = 'executable("rustup")', nested = true },
	{ lhs = "gD", source = lsp_config, needle = 'executable("rustup")' },
	{ lhs = "gd", source = lsp_config, needle = "child_ui_zindex()" },
	{ lhs = "gd", source = keymaps, needle = "select_agent()" },
	{ lhs = "gD", source = keymaps, needle = "select_agent()" },
	{
		lhs = "gd",
		source = keymaps,
		needle = "select_agent()",
		source_width = 140,
		resize_width = 150,
	},
	{
		lhs = "gd",
		source = lsp_config,
		needle = 'executable("rustup")',
		source_width = 100,
		omit_aerial = true,
		nested = true,
	},
}) do
	assert_definition_preview(case)
end

print("Glance definition integration: ok")
