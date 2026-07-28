local catppuccin = require("config.catppuccin")
local diff_watch = require("config.diff_watch")
local diffview_panel = require("config.diffview_snacks_panel")
local review = require("config.review")
local colors = catppuccin.palette()
local diffview_windows = {}
local gitsigns_diff_windows = {}
local diffview_cursorline_provider = vim.api.nvim_create_namespace("dotfiles-diffview-cursorline-provider")
local diffview_cursorline_groups = {
	"DiffAdd",
	"DiffDelete",
	"DiffChange",
	"DiffText",
	"DiffviewDiffAdd",
	"DiffviewDiffAddAsDelete",
	"DiffviewDiffDelete",
	"DiffviewDiffDeleteDim",
	"DiffviewDiffChange",
	"DiffviewDiffText",
	"DiffviewDiffChangeAdd",
	"DiffviewDiffTextAdd",
	"DiffviewDiffChangeDelete",
	"DiffviewDiffTextDelete",
}
local diffview_cursorline_statuscolumn_groups = {
	"CursorLineNr",
	"CursorLineSign",
	"CursorLineFold",
	"DotfilesCursorLineFoldOpen",
	"DotfilesCursorLineFoldClosed",
	"DotfilesCursorLineFoldDepth",
	"DotfilesStatuscolumnMarker",
	"DotfilesCursorLineCodexNr",
}

local function winhighlight_targets(win)
	local targets = {}
	for entry in vim.wo[win].winhighlight:gmatch("[^,]+") do
		local source, target = entry:match("^([^:]+):(.+)$")
		if source then
			targets[source] = target
		end
	end
	return targets
end

-- Built-in diff highlights win over CursorLine when both define a background.
-- During redraw, switch only the active cursor row to a namespace whose diff
-- groups retain their foreground styling but use the ordinary mode-aware
-- CursorLine background. Matches and extmarks are painted too early to win
-- this conflict reliably.
local function refresh_diffview_cursorline_namespaces()
	for win, state in pairs(diffview_windows) do
		if vim.api.nvim_win_is_valid(win) then
			local targets = winhighlight_targets(win)
			local target = targets.CursorLine or "CursorLine"
			local cursorline = vim.api.nvim_get_hl(0, { name = target, link = false })
			if cursorline.bg then
				state.hl_ns = state.hl_ns or vim.api.nvim_create_namespace("dotfiles-diffview-cursorline-" .. win)
				cursorline.nocombine = true
				cursorline.underline = false
				cursorline.undercurl = false
				cursorline.underdashed = false
				cursorline.underdotted = false
				cursorline.underdouble = false
				cursorline.overline = false
				vim.api.nvim_set_hl(state.hl_ns, "CursorLine", cursorline)
				vim.api.nvim_set_hl(state.hl_ns, target, cursorline)
				for _, group in ipairs(diffview_cursorline_groups) do
					local attributes = vim.api.nvim_get_hl(0, { name = group, link = false })
					attributes.bg = cursorline.bg
					attributes.nocombine = true
					vim.api.nvim_set_hl(state.hl_ns, group, attributes)
				end
				-- nvim_set_hl_ns_fast() also changes the namespace used while the
				-- statuscolumn is drawn. Define both the source group and its
				-- window-local target in that namespace; otherwise CursorLineNr and
				-- the sign/fold cells fall back to their default-scene colors while
				-- the editor row follows Normal/Command/Insert mode.
				for _, group in ipairs(diffview_cursorline_statuscolumn_groups) do
					local statuscolumn_target = targets[group] or group
					local attributes = vim.api.nvim_get_hl(0, { name = statuscolumn_target, link = false })
					attributes.bg = cursorline.bg
					attributes.nocombine = true
					vim.api.nvim_set_hl(state.hl_ns, group, attributes)
					vim.api.nvim_set_hl(state.hl_ns, statuscolumn_target, attributes)
				end
			end
		else
			diffview_windows[win] = nil
		end
	end
end

vim.api.nvim_set_decoration_provider(diffview_cursorline_provider, {
	on_win = function(_, win)
		vim.api.nvim_set_hl_ns_fast(0)
		local state = diffview_windows[win]
		return state ~= nil
			and state.hl_ns ~= nil
			and win == vim.api.nvim_get_current_win()
			and vim.wo[win].diff
			and vim.wo[win].cursorline
	end,
	on_line = function(_, win, _, row)
		local state = diffview_windows[win]
		local cursor_row = vim.api.nvim_win_get_cursor(win)[1] - 1
		vim.api.nvim_set_hl_ns_fast(row == cursor_row and state.hl_ns or 0)
	end,
	on_end = function()
		vim.api.nvim_set_hl_ns_fast(0)
	end,
})

vim.api.nvim_create_autocmd(
	{ "BufWinEnter", "CmdlineEnter", "CmdlineLeave", "CursorMoved", "CursorMovedI", "ModeChanged", "WinEnter" },
	{
		group = vim.api.nvim_create_augroup("dotfiles-diffview-cursorline", { clear = true }),
		callback = function(args)
			if args.event == "CmdlineEnter" then
				-- Scheduled callbacks do not run while the command line is waiting
				-- for input. options.lua has already selected the command-mode group.
				refresh_diffview_cursorline_namespaces()
				vim.cmd.redraw({ bang = true })
			else
				vim.schedule(refresh_diffview_cursorline_namespaces)
			end
		end,
	}
)

vim.api.nvim_create_autocmd("WinClosed", {
	group = "dotfiles-diffview-cursorline",
	callback = function(args)
		diffview_windows[tonumber(args.match)] = nil
	end,
})

local function blend(foreground, background, alpha)
	local function channel(color, offset)
		return tonumber(color:sub(offset, offset + 1), 16)
	end
	local function mix(offset)
		return math.floor(channel(foreground, offset) * alpha + channel(background, offset) * (1 - alpha) + 0.5)
	end
	return ("#%02x%02x%02x"):format(mix(2), mix(4), mix(6))
end

local function set_gitsigns_highlights()
	vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = colors.green, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsChange", { fg = colors.peach, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = colors.red, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsTopdelete", { fg = colors.red, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsChangedelete", { fg = colors.yellow, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsUntracked", { fg = colors.teal, bg = "NONE" })
	vim.api.nvim_set_hl(0, "GitSignsCurrentLineBlame", { fg = colors.overlay1, bg = "NONE", italic = true })
end

local function set_diffview_highlights()
	local delete_change = blend(colors.red, colors.base, 0.18)
	local delete_text = blend(colors.red, colors.base, 0.42)
	local add_change = blend(colors.green, colors.base, 0.18)
	local add_text = blend(colors.green, colors.base, 0.42)
	vim.api.nvim_set_hl(0, "DiffviewFilePanelTitle", { fg = colors.blue, bold = true })
	vim.api.nvim_set_hl(0, "DiffviewFilePanelCounter", { fg = colors.peach, bold = true })
	vim.api.nvim_set_hl(0, "DiffviewFilePanelRootPath", { fg = colors.overlay1, italic = true })
	vim.api.nvim_set_hl(0, "DiffviewPrimary", { fg = colors.blue, bold = true })
	vim.api.nvim_set_hl(0, "DiffviewSecondary", { fg = colors.mauve })
	vim.api.nvim_set_hl(0, "DiffviewDim1", { fg = colors.surface2 })
	vim.api.nvim_set_hl(0, "DiffviewNormal", { fg = colors.text, bg = "NONE" })
	vim.api.nvim_set_hl(0, "DiffviewDiffAddAsDelete", { bg = delete_change })
	vim.api.nvim_set_hl(0, "DiffviewDiffChangeDelete", { bg = delete_change })
	vim.api.nvim_set_hl(0, "DiffviewDiffTextDelete", { bg = delete_text })
	vim.api.nvim_set_hl(0, "DiffviewDiffAdd", { bg = add_change })
	vim.api.nvim_set_hl(0, "DiffviewDiffChangeAdd", { bg = add_change })
	vim.api.nvim_set_hl(0, "DiffviewDiffTextAdd", { bg = add_text })
	-- Diffview maps actual deletions and alignment filler to separate groups.
	-- Keep real deletions red, but make the empty side of pure additions blank.
	vim.api.nvim_set_hl(0, "DiffviewDiffDeleteDim", { fg = "NONE", bg = "NONE" })
end

local function replace_winhighlight(win, group, target)
	local entries = vim.split(vim.wo[win].winhighlight, ",", { plain = true, trimempty = true })
	local replacement = group .. ":" .. target
	local replaced = false
	for index, entry in ipairs(entries) do
		if vim.startswith(entry, group .. ":") then
			entries[index] = replacement
			replaced = true
			break
		end
	end
	if not replaced then
		entries[#entries + 1] = replacement
	end
	vim.wo[win].winhighlight = table.concat(entries, ",")
end

local function style_diff_window(win, ctx)
	diffview_windows[win] = diffview_windows[win] or {}
	-- The right/main revision is the actionable side in Diffview. Keep its
	-- minimap, but do not duplicate the same overview over the left/base pane.
	vim.w[win].dotfiles_disable_minimap = ctx ~= nil and ctx.symbol == "a"
	local buf = vim.api.nvim_win_get_buf(win)
	vim.b[buf].dotfiles_disable_hlchunk = true
	local chunk_namespace = vim.api.nvim_get_namespaces().chunk
	if chunk_namespace then
		vim.api.nvim_buf_clear_namespace(buf, chunk_namespace, 0, -1)
	end
	vim.api.nvim_win_call(win, function()
		vim.opt_local.fillchars:append({ diff = " " })
		vim.wo.cursorline = true
		-- The redraw namespace below owns the editor-row background. Let core
		-- CursorLine style only the number column, otherwise diff rendering leaves
		-- a second horizontal line across the row.
		vim.wo.cursorlineopt = "number"
	end)
	-- Diffview can install its own static cursor-line group while creating a
	-- layout. Start from the ordinary CursorLine group; the existing
	-- ModeChanged UI then replaces it with the same mode-specific group used by
	-- normal editing windows.
	replace_winhighlight(win, "CursorLine", "CursorLine")

	local side
	if ctx and (ctx.layout_name == "diff2_horizontal" or ctx.layout_name == "diff2_vertical") then
		side = ctx.symbol == "a" and "Delete" or ctx.symbol == "b" and "Add" or nil
	end
	if side then
		replace_winhighlight(win, "DiffAdd", side == "Delete" and "DiffviewDiffAddAsDelete" or "DiffviewDiffAdd")
		-- Core diff renders the empty side of an addition with DiffDelete. In a
		-- Gitsigns revision pane that empty side represents a deletion, while
		-- Diffview deliberately keeps its alignment filler uncolored.
		replace_winhighlight(
			win,
			"DiffDelete",
			ctx and ctx.gitsigns and side == "Delete" and "DiffviewDiffAddAsDelete" or "DiffviewDiffDeleteDim"
		)
	end
	replace_winhighlight(win, "DiffChange", side and ("DiffviewDiffChange" .. side) or "DiffviewDiffChange")
	replace_winhighlight(win, "DiffText", side and ("DiffviewDiffText" .. side) or "DiffviewDiffText")
	vim.schedule(refresh_diffview_cursorline_namespaces)
end

local function is_gitsigns_revision(win)
	local buf = vim.api.nvim_win_get_buf(win)
	return vim.startswith(vim.api.nvim_buf_get_name(buf), "gitsigns://")
end

local function start_gitsigns_revision_treesitter(win)
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.bo[buf].filetype ~= "" then
		pcall(vim.treesitter.start, buf)
	end
end

local function save_gitsigns_diff_window(win)
	if gitsigns_diff_windows[win] then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	gitsigns_diff_windows[win] = {
		buf = buf,
		cursorline = vim.wo[win].cursorline,
		cursorlineopt = vim.wo[win].cursorlineopt,
		fillchars = vim.wo[win].fillchars,
		winhighlight = vim.wo[win].winhighlight,
		disable_hlchunk = vim.b[buf].dotfiles_disable_hlchunk,
		disable_minimap = vim.w[win].dotfiles_disable_minimap,
	}
end

local function restore_gitsigns_diff_window(win, state)
	diffview_windows[win] = nil
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	vim.wo[win].cursorline = state.cursorline
	vim.wo[win].cursorlineopt = state.cursorlineopt
	vim.wo[win].fillchars = state.fillchars
	vim.wo[win].winhighlight = state.winhighlight
	vim.w[win].dotfiles_disable_minimap = state.disable_minimap
	if vim.api.nvim_buf_is_valid(state.buf) then
		vim.b[state.buf].dotfiles_disable_hlchunk = state.disable_hlchunk
	end
end

-- Gitsigns diffthis() builds a regular Neovim diff instead of a Diffview
-- layout, so Diffview's window hook never runs. Detect that pair by its
-- gitsigns:// revision buffer and apply the same styling to both sides. Keep a
-- snapshot because the worktree window survives after the revision closes.
local function refresh_gitsigns_diff_styles()
	local active = {}
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local wins = vim.api.nvim_tabpage_list_wins(tab)
		local has_revision = vim.iter(wins):any(function(win)
			return vim.wo[win].diff and is_gitsigns_revision(win)
		end)
		if has_revision then
			for _, win in ipairs(wins) do
				if vim.wo[win].diff then
					local revision = is_gitsigns_revision(win)
					active[win] = true
					save_gitsigns_diff_window(win)
					if revision then
						start_gitsigns_revision_treesitter(win)
					end
					style_diff_window(win, {
						layout_name = "diff2_vertical",
						symbol = revision and "a" or "b",
						gitsigns = revision,
					})
				end
			end
		end
	end

	for win, state in pairs(gitsigns_diff_windows) do
		if not active[win] then
			restore_gitsigns_diff_window(win, state)
			gitsigns_diff_windows[win] = nil
		end
	end
end

vim.api.nvim_create_autocmd(
	{ "BufEnter", "BufWinEnter", "BufWinLeave", "FileType", "ModeChanged", "WinEnter", "WinClosed" },
	{
		group = vim.api.nvim_create_augroup("dotfiles-gitsigns-diff-style", { clear = true }),
		callback = function(args)
			if args.event == "FileType" and vim.startswith(vim.api.nvim_buf_get_name(args.buf), "gitsigns://") then
				pcall(vim.treesitter.start, args.buf)
			end
			vim.schedule(refresh_gitsigns_diff_styles)
		end,
	}
)

return {
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			base = review.gitsigns_base() or diff_watch.gitsigns_base(),
			attach_to_untracked = diff_watch.is_active(),
			sign_priority = 100,
			signs = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "▎" },
				topdelete = { text = "▎" },
				changedelete = { text = "▎" },
				untracked = { text = "▎" },
			},
			signcolumn = true,
			numhl = false,
			linehl = false,
			current_line_blame = false,
			preview_config = {
				border = "rounded",
			},
		},
		init = function()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-gitsigns-catppuccin", { clear = true }),
				pattern = "*",
				callback = set_gitsigns_highlights,
			})
			set_gitsigns_highlights()
		end,
		config = function(_, opts)
			require("gitsigns").setup(opts)

			-- Gitsigns may attach on BufReadPre before its configured base is
			-- applied. Reapply it so review and HEAD-watch buffers do not fall
			-- back to the Git index.
			local base = review.gitsigns_base() or diff_watch.gitsigns_base()
			if base then
				local function apply_configured_base()
					require("gitsigns").change_base(base, true)
				end
				local function apply_configured_base_after_attach()
					-- Gitsigns attaches asynchronously. Retry during startup so a
					-- slow initial attach cannot leave configured buffers on index base.
					for _, delay in ipairs({ 100, 500, 1000 }) do
						vim.defer_fn(apply_configured_base, delay)
					end
				end

				vim.api.nvim_create_autocmd({ "BufEnter", "VimEnter" }, {
					group = vim.api.nvim_create_augroup("dotfiles-gitsigns-configured-base", { clear = true }),
					callback = function()
						apply_configured_base_after_attach()
					end,
				})
				apply_configured_base_after_attach()
			end
		end,
	},
	{
		"sindrets/diffview.nvim",
		cmd = {
			"DiffviewOpen",
			"DiffviewClose",
			"DiffviewFileHistory",
			"DiffviewFocusFiles",
			"DiffviewToggleFiles",
			"DiffviewRefresh",
		},
		opts = {
			enhanced_diff_hl = true,
			hooks = {
				diff_buf_win_enter = function(_, win, ctx)
					style_diff_window(win, ctx)
				end,
				view_opened = diffview_panel.attach,
				view_closed = diffview_panel.detach,
			},
			keymaps = {
				view = {
					["<leader>e"] = diffview_panel.focus_current,
					["<leader>b"] = diffview_panel.toggle_current,
				},
			},
			view = {
				default = {
					layout = "diff2_horizontal",
					disable_diagnostics = false,
				},
			},
			default_args = {
				DiffviewOpen = { "--imply-local" },
			},
		},
		init = function()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("dotfiles-diffview-catppuccin", { clear = true }),
				pattern = "*",
				callback = set_diffview_highlights,
			})
			set_diffview_highlights()
		end,
		config = function(_, opts)
			require("diffview").setup(opts)
			diffview_panel.setup_commands()
			-- diffview.setup() recreates DiffviewDiffDeleteDim as a Comment link.
			-- Apply our blank filler style after the plugin finishes its highlights.
			set_diffview_highlights()
		end,
	},
}
