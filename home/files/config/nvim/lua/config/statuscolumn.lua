local M = {}

local builtin = require("statuscol.builtin")
local sign_highlight_cache = {}
local sign_highlight_index = 0

local function number_width(args)
	return math.max(vim.wo[args.win].numberwidth, #tostring(vim.api.nvim_buf_line_count(args.buf)))
end

local function marker(width, glyph, group)
	return "%#" .. group .. "#" .. string.format("%" .. width .. "s", glyph)
end

local function reset_sign_highlights()
	sign_highlight_cache = {}
	sign_highlight_index = 0
end

local function isolated_sign_highlight(group)
	group = group ~= "" and group or "NoTexthl"
	if group == "CursorLineSign" or group == "SignColumn" then
		return group
	end

	local cached = sign_highlight_cache[group]
	if cached then
		return cached
	end

	sign_highlight_index = sign_highlight_index + 1
	local derived = "DotfilesStatuscolumnSign" .. sign_highlight_index
	local attributes = vim.api.nvim_get_hl(0, { name = group, link = false })
	attributes.nocombine = true
	vim.api.nvim_set_hl(0, derived, attributes)
	sign_highlight_cache[group] = derived
	return derived
end

function M.fold(args)
	local rendered = builtin.foldfunc(args)
	if rendered == "" then
		return rendered
	end

	-- IMPORTANT: Keep 'foldcolumn' at auto:1 so nested folds still render one
	-- structural glyph. This extra highlighted cell widens only the visual rail;
	-- setting 'foldcolumn' to 2 would expose a second fold-depth marker instead.
	local group = (args.cul and args.relnum == 0) and "CursorLineFold" or "FoldColumn"
	return rendered .. "%#" .. group .. "# %*"
end

function M.fold_click(args)
	if args.button ~= "l" or args.clicks ~= 1 or args.mousepos.winid == 0 or args.mousepos.line == 0 then
		return
	end

	vim.api.nvim_win_call(args.mousepos.winid, function()
		if vim.fn.foldlevel(args.mousepos.line) == 0 then
			return
		end
		vim.api.nvim_win_set_cursor(args.mousepos.winid, { args.mousepos.line, 0 })
		vim.cmd.normal({ args = { vim.fn.foldclosed(args.mousepos.line) == -1 and "zc" or "zo" }, bang = true })
	end)
end

function M.fold_click_handler(_, clicks, button)
	-- Preserve the old callback semantics: ignored clicks must not even resolve
	-- the mouse position, because statuscol.nvim's dispatcher moves the cursor.
	if button ~= "l" or clicks ~= 1 then
		return
	end

	M.fold_click({
		button = button,
		clicks = clicks,
		mousepos = vim.fn.getmousepos(),
	})
end

_G.dotfiles_foldcolumn_click = M.fold_click_handler

local function has_ai_indicator(args, segment)
	-- IMPORTANT: Number rendering is a per-screen-row hot path. Read the sign
	-- table that statuscol.nvim builds once per redraw; querying extmarks here
	-- would multiply API work by every visible row during cursor movement.
	local signs = segment
		and segment.sign
		and segment.sign.wins[args.win]
		and segment.sign.wins[args.win].signs[args.lnum]
	return signs ~= nil and #signs > 0
end

function M.number(args, segment)
	local width = number_width(args)
	if args.virtnum ~= 0 then
		return string.rep(" ", width)
	end

	local current = vim.api.nvim_win_get_cursor(args.win)[1]
	local ai = has_ai_indicator(args, segment)
	local number_group = ai and (args.lnum == current and "DotfilesCursorLineCodexNr" or "DotfilesCodexLineNr")
	local group = number_group or (args.lnum == current and "CursorLineNr" or "LineNr")
	if args.rnu and args.lnum == current - 1 then
		return marker(width, "󰄿", number_group or "DotfilesStatuscolumnMarker")
	end
	if args.rnu and args.lnum == current + 1 then
		return marker(width, "󰄼", number_group or "DotfilesStatuscolumnMarker")
	end
	local number = args.lnum
	if args.rnu then
		number = args.relnum > 0 and args.relnum or (args.nu == false and 0 or args.lnum)
	end
	return "%#" .. group .. "#" .. string.format("%" .. width .. "d", number)
end

function M.sign_base(args)
	return (args.cul and args.relnum == 0) and "%#CursorLineSign#" or "%#SignColumn#"
end

function M.sign(args, segment)
	local rendered = builtin.signfunc(args, segment)
	return rendered:gsub("%%#([^#]+)#", function(group)
		local isolated = isolated_sign_highlight(group)
		if isolated == group then
			return "%#" .. group .. "#"
		end
		return M.sign_base(args) .. "%#" .. isolated .. "#"
	end)
end

function M.setup()
	reset_sign_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("dotfiles-statuscolumn-sign-highlights", { clear = true }),
		callback = reset_sign_highlights,
	})

	require("statuscol").setup({
		segments = {
			{ text = { M.fold }, click = "v:lua.dotfiles_foldcolumn_click" },
			{ text = { "%=" } },
			{
				-- Consume the sole Codex sign as number metadata; M.number deliberately
				-- emits no sign glyph and therefore adds no statuscolumn cell.
				text = { M.number },
				sign = {
					namespace = { "dotfiles-codex-edit-signs" },
					text = { "" },
					maxwidth = 1,
					colwidth = 1,
				},
			},
			{ text = { "%*" } },
			{
				text = { M.sign },
				sign = {
					namespace = { "gitsigns_signs_.*", "dotfiles-review-added-file" },
					text = { "▎" },
					maxwidth = 1,
					colwidth = 1,
					auto = true,
				},
			},
			{
				text = { M.sign },
				sign = {
					namespace = { "diagnostic%.signs" },
					maxwidth = 1,
					-- Keep Neovim's trailing sign padding so the diagnostic circle
					-- does not touch the first code cell. Git + diagnostic use three
					-- cells total when both segments are active.
					colwidth = 2,
					auto = true,
				},
			},
		},
		clickhandlers = {
			Lnum = false,
			[".*"] = false,
		},
	})
end

return M
