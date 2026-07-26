local M = {}

local sign_highlight_cache = {}
local sign_highlight_index = 0

local fold_symbols = {
	close = "",
	open = "",
	sep = " ",
}

local function number_width(args)
	return math.max(vim.wo[args.win].numberwidth, #tostring(vim.api.nvim_buf_line_count(args.buf)))
end

local function marker(width, glyph)
	return "%#DotfilesStatuscolumnMarker#" .. string.format("%" .. width .. "s", glyph)
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
	if args.virtnum ~= 0 then
		return " "
	end

	local level = vim.fn.foldlevel(args.lnum)
	if level == 0 then
		return " "
	end

	local symbol = fold_symbols.sep
	if vim.fn.foldclosed(args.lnum) == args.lnum then
		symbol = fold_symbols.close
	elseif args.lnum == 1 or level > vim.fn.foldlevel(args.lnum - 1) then
		symbol = fold_symbols.open
	end

	return (args.relnum == 0 and "%#CursorLineFold#" or "%#FoldColumn#") .. symbol
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

function M.number(args)
	local width = number_width(args)
	if args.virtnum ~= 0 then
		return string.rep(" ", width)
	end

	local current = vim.api.nvim_win_get_cursor(args.win)[1]
	if not args.rnu then
		return (args.lnum == current and "%#CursorLineNr#" or "%#LineNr#")
			.. string.format("%" .. width .. "d", args.lnum)
	end
	if args.lnum == current - 1 then
		return marker(width, "󰄿")
	end
	if args.lnum == current then
		return "%#CursorLineNr#" .. string.format("%" .. width .. "d", args.lnum)
	end
	if args.lnum == current + 1 then
		return marker(width, "󰄼")
	end
	return "%#LineNr#" .. string.format("%" .. width .. "d", args.relnum)
end

function M.sign_base(args)
	return (args.cul and args.relnum == 0) and "%#CursorLineSign#" or "%#SignColumn#"
end

function M.sign(args, segment)
	local rendered = require("statuscol.builtin").signfunc(args, segment)
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
			{ text = { M.number } },
			{ text = { "%*" } },
			{
				text = { M.sign },
				sign = {
					namespace = { "gitsigns_signs_.*", "dotfiles-review-added-file" },
					maxwidth = 2,
					colwidth = 1,
					auto = true,
				},
			},
			{
				text = { M.sign },
				sign = {
					name = { ".*" },
					text = { ".*" },
					namespace = { ".*" },
					maxwidth = 2,
					colwidth = 1,
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
