local catppuccin = require("config.catppuccin")
local diff_watch = require("config.diff_watch")
local diffview_panel = require("config.diffview_snacks_panel")
local git_diff_peek = require("config.git_diff_peek")
local review = require("config.review")
local colors = catppuccin.palette()
local diffview_windows = {}
local gitsigns_diff_windows = {}

local function current_mode_scene()
	local mode = vim.api.nvim_get_mode().mode
	if mode:match("^c") then
		return "command"
	end
	if mode:match("^i") then
		return "insert"
	end
	if mode:match("^[Rr]") then
		return "replace"
	end
	if mode:match("^[vV\22]") then
		return "visual"
	end
	if mode:match("^[sS\19]") then
		return "select"
	end
	if mode:match("^no") then
		local operator = vim.v.operator or ""
		if operator == "y" then
			return "copy"
		end
		if operator == "d" then
			return "delete"
		end
		if operator == "c" then
			return "change"
		end
		if operator:match("[=!><g]") then
			return "format"
		end
	end
	return "default"
end

local function mode_highlight_group(base, scene)
	local suffix = (scene or "default"):gsub("^%l", string.upper)
	return "Dotfiles" .. base .. suffix
end

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

local cursorline_sources = {
	CursorLine = "CursorLine",
	CursorLineSign = "CursorLineSign",
	CursorLineFold = "CursorLineFold",
	DotfilesCursorLineFoldOpen = "CursorLineFoldOpen",
	DotfilesCursorLineFoldClosed = "CursorLineFoldClosed",
	DotfilesCursorLineFoldDepth = "CursorLineFoldDepth",
	CursorLineNr = "CursorLineNr",
	DotfilesStatuscolumnMarker = "StatuscolumnMarker",
	DotfilesCursorLineCodexNr = "CursorLineCodexNr",
}

local diff_cursorline_sources = {
	CursorLineSign = "DiffCursorLineSign",
	CursorLineFold = "DiffCursorLineFold",
	DotfilesCursorLineFoldOpen = "DiffCursorLineFoldOpen",
	DotfilesCursorLineFoldClosed = "DiffCursorLineFoldClosed",
	DotfilesCursorLineFoldDepth = "DiffCursorLineFoldDepth",
	CursorLineNr = "DiffCursorLineNr",
	DotfilesCursorLineCodexNr = "DiffCursorLineCodexNr",
}

local function cursor_line_has_diff(win)
	return vim.api.nvim_win_call(win, function()
		local line = vim.api.nvim_win_get_cursor(win)[1]
		return vim.fn.diff_hlID(line, 1) ~= 0
	end)
end

-- On ordinary lines, Diffview behaves like the rest of the editor and paints
-- the full mode-aware CursorLine. On changed lines, native diff highlighting
-- owns the body background; only the number and rail foregrounds retain the
-- mode signal. Changing window options outside redraw avoids the cell-phase
-- leakage caused by nvim_set_hl_ns_fast() in a decoration provider.
local function apply_diffview_cursorline_style(win, scene, has_diff)
	local state = diffview_windows[win]
	if not state or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local cursorlineopt = has_diff and "number" or "both"
	if
		state.cursorline_scene == scene
		and state.cursorline_has_diff == has_diff
		and vim.wo[win].cursorlineopt == cursorlineopt
		and state.cursorline_winhighlight == vim.wo[win].winhighlight
	then
		return
	end

	vim.wo[win].cursorline = true
	vim.wo[win].cursorlineopt = cursorlineopt
	for source, base in pairs(cursorline_sources) do
		local target_base = has_diff and diff_cursorline_sources[source] or nil
		replace_winhighlight(win, source, mode_highlight_group(target_base or base, scene))
	end
	state.cursorline_scene = scene
	state.cursorline_has_diff = has_diff
	state.cursorline_winhighlight = vim.wo[win].winhighlight
end

local function refresh_diffview_cursorline_styles()
	local scene = current_mode_scene()
	for win in pairs(diffview_windows) do
		if vim.api.nvim_win_is_valid(win) and vim.wo[win].diff then
			apply_diffview_cursorline_style(win, scene, cursor_line_has_diff(win))
		elseif not vim.api.nvim_win_is_valid(win) then
			diffview_windows[win] = nil
		end
	end
end

local cursorline_refresh_pending = false
local function schedule_diffview_cursorline_styles()
	if cursorline_refresh_pending then
		return
	end
	cursorline_refresh_pending = true
	vim.schedule(function()
		cursorline_refresh_pending = false
		refresh_diffview_cursorline_styles()
	end)
end

vim.api.nvim_create_autocmd({
	"BufWinEnter",
	"CmdlineEnter",
	"CmdlineLeave",
	"CursorMoved",
	"CursorMovedI",
	"DiffUpdated",
	"ModeChanged",
	"TextChanged",
	"TextChangedI",
	"WinEnter",
}, {
	group = vim.api.nvim_create_augroup("dotfiles-diffview-cursorline", { clear = true }),
	callback = function(args)
		if args.event == "CmdlineEnter" then
			-- Scheduled callbacks do not run while the command line waits for
			-- input, so update command-mode foregrounds synchronously.
			refresh_diffview_cursorline_styles()
			vim.cmd.redraw({ bang = true })
		elseif args.event == "CursorMoved" or args.event == "CursorMovedI" then
			-- CursorMoved is already outside redraw. Classify in the same event so
			-- ordinary movement does not create a second scheduled redraw cycle.
			refresh_diffview_cursorline_styles()
		else
			schedule_diffview_cursorline_styles()
		end
	end,
})

vim.api.nvim_create_autocmd("WinClosed", {
	group = "dotfiles-diffview-cursorline",
	callback = function(args)
		diffview_windows[tonumber(args.match)] = nil
	end,
})

local function style_diff_window(win, ctx)
	local newly_registered = diffview_windows[win] == nil
	local initialize_folds = newly_registered and vim.w[win].dotfiles_git_diff_peek_child ~= true
	diffview_windows[win] = diffview_windows[win] or {}
	-- The right/main revision is the actionable side in Diffview. Keep its
	-- minimap, but do not duplicate the same overview over the left/base pane.
	local minimap_disabled = ctx ~= nil and ctx.symbol == "a"
	git_diff_peek.apply_editor_chrome(win, {
		foldlevel = initialize_folds and 0 or nil,
		minimap_disabled = minimap_disabled,
	})
	local buf = vim.api.nvim_win_get_buf(win)
	local chunk_namespace = vim.api.nvim_get_namespaces().chunk
	if chunk_namespace then
		vim.api.nvim_buf_clear_namespace(buf, chunk_namespace, 0, -1)
	end
	local side
	if ctx and (ctx.layout_name == "diff2_horizontal" or ctx.layout_name == "diff2_vertical") then
		side = ctx.symbol == "a" and "Delete" or ctx.symbol == "b" and "Add" or nil
	end
	if side then
		replace_winhighlight(win, "DiffAdd", side == "Delete" and "DiffviewDiffAddAsDelete" or "DiffviewDiffAdd")
		-- Core diff uses DiffDelete for alignment filler. Keep it uncolored on
		-- both Diffview and Gitsigns routes so the rendered panes stay identical.
		replace_winhighlight(win, "DiffDelete", "DiffviewDiffDeleteDim")
	end
	replace_winhighlight(win, "DiffChange", side and ("DiffviewDiffChange" .. side) or "DiffviewDiffChange")
	replace_winhighlight(win, "DiffText", side and ("DiffviewDiffText" .. side) or "DiffviewDiffText")
	schedule_diffview_cursorline_styles()
end

local function is_gitsigns_revision(win)
	local buf = vim.api.nvim_win_get_buf(win)
	return vim.startswith(vim.api.nvim_buf_get_name(buf), "gitsigns://")
end

local function save_gitsigns_diff_window(win)
	if gitsigns_diff_windows[win] then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	gitsigns_diff_windows[win] = {
		buf = buf,
		foldcolumn = vim.wo[win].foldcolumn,
		foldlevel = vim.wo[win].foldlevel,
		foldenable = vim.wo[win].foldenable,
		signcolumn = vim.wo[win].signcolumn,
		statuscolumn = vim.wo[win].statuscolumn,
		number = vim.wo[win].number,
		relativenumber = vim.wo[win].relativenumber,
		numberwidth = vim.wo[win].numberwidth,
		winbar = vim.wo[win].winbar,
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
	if vim.api.nvim_win_is_valid(win) then
		vim.wo[win].foldcolumn = state.foldcolumn
		vim.wo[win].foldlevel = state.foldlevel
		vim.wo[win].foldenable = state.foldenable
		vim.wo[win].signcolumn = state.signcolumn
		vim.wo[win].statuscolumn = state.statuscolumn
		vim.wo[win].number = state.number
		vim.wo[win].relativenumber = state.relativenumber
		vim.wo[win].numberwidth = state.numberwidth
		vim.wo[win].winbar = state.winbar
		vim.wo[win].cursorline = state.cursorline
		vim.wo[win].cursorlineopt = state.cursorlineopt
		vim.wo[win].fillchars = state.fillchars
		vim.wo[win].winhighlight = state.winhighlight
		vim.w[win].dotfiles_disable_minimap = state.disable_minimap
	end
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
			local worktree_win = vim.iter(wins):find(function(win)
				return vim.wo[win].diff
					and not is_gitsigns_revision(win)
					and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
			end)
			local worktree_buf = worktree_win and vim.api.nvim_win_get_buf(worktree_win) or nil
			for _, win in ipairs(wins) do
				if vim.wo[win].diff then
					local revision = is_gitsigns_revision(win)
					active[win] = true
					save_gitsigns_diff_window(win)
					if revision then
						git_diff_peek.prepare_revision_buffer(vim.api.nvim_win_get_buf(win), worktree_buf)
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
		opts = function()
			local configured_base = review.gitsigns_base() or diff_watch.gitsigns_base()
			-- Gitsigns' plugin script starts the initial attach before lazy.nvim
			-- applies this user config. Correct only that first normal buffer after
			-- on_attach returns and the cache entry has been registered.
			local initial_base_scheduled = false
			local function is_normal_file_buffer(bufnr)
				if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
					return false
				end
				local name = vim.api.nvim_buf_get_name(bufnr)
				return vim.bo[bufnr].buftype == ""
					and name ~= ""
					and not vim.startswith(name, "gitsigns://")
					and vim.uv.fs_stat(name) ~= nil
			end
			return {
				base = configured_base,
				on_attach = function(bufnr)
					vim.keymap.set("n", "]h", function()
						require("gitsigns").nav_hunk("next")
					end, { buffer = bufnr, desc = "Next Git hunk" })
					vim.keymap.set("n", "[h", function()
						require("gitsigns").nav_hunk("prev")
					end, { buffer = bufnr, desc = "Previous Git hunk" })

					if initial_base_scheduled or not configured_base or not is_normal_file_buffer(bufnr) then
						return
					end
					initial_base_scheduled = true
					vim.schedule(function()
						if not is_normal_file_buffer(bufnr) then
							initial_base_scheduled = false
							return
						end
						vim.api.nvim_buf_call(bufnr, function()
							require("gitsigns").change_base(configured_base, false)
						end)
					end)
				end,
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
			}
		end,
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
