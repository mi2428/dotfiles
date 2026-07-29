local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")
vim.opt.runtimepath:prepend(nvim_root)
vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, "nui.nvim"))
vim.opt.runtimepath:prepend(vim.fs.joinpath(lazy_root, "noice.nvim"))
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/cmdline.lua"))
local noice

for _, spec in ipairs(specs) do
	if spec[1] == "folke/noice.nvim" then
		noice = spec
		break
	end
end

assert(noice, "Noice plugin spec was not found")
assert(noice.event == "VeryLazy", "Noice must load after the startup UI has settled")
assert(
	vim.deep_equal(noice.dependencies, {
		"MunifTanjim/nui.nvim",
		"rachartier/tiny-inline-diagnostic.nvim",
	}),
	"Noice must load its popup and inline-diagnostic UI dependencies"
)

local original_cmdheight = vim.o.cmdheight
noice.init()
assert(vim.o.cmdheight == 0, "Noice must hide the native command-line area")
assert(
	package.preload["noice.view.backend.dotfiles_search_count"] ~= nil,
	"Noice must register the custom search-count backend before setup"
)
vim.o.cmdheight = original_cmdheight

local opts = noice.opts
assert(opts.cmdline.enabled == true, "Noice must render the command line")
assert(opts.cmdline.view == "cmdline_popup", "Noice must use the visible popup command line")
assert(opts.messages.enabled == true, "Noice must render regular messages and confirmation prompts")
assert(
	opts.messages.view == "mini" and opts.messages.view_error == "notify" and opts.messages.view_warn == "notify",
	"Noice must keep routine messages compact while promoting warnings and errors to notifications"
)
assert(opts.messages.view_search == "search_count", "Search counts must use their dedicated inline view")
assert(
	require("noice.config.views").defaults.notify.backend[1] == "snacks",
	"Noice notifications must prefer the existing Snacks notification backend"
)
assert(
	opts.views.search_count.backend == "dotfiles_search_count",
	"Search counts must use the complete tiny-inline-diagnostic annotation renderer"
)

local chunks = require("config.noice_ui").search_count_virtual_text(" /builder            [1/35] ")
assert(#chunks == 6, "Search count annotations must keep their six visual chunks")
assert(
	chunks[1][1] == "    " and chunks[1][2] == "TinyInlineDiagnosticVirtualTextArrowNoBg",
	"Search counts need a diagnostic arrow without a CursorLine background"
)
assert(
	chunks[2][1] == "" and chunks[2][2] == "TinyInlineInvDiagnosticVirtualTextInfoNoBg",
	"Search counts need one rounded left edge without a CursorLine background"
)
assert(
	chunks[3][1] == " " and chunks[3][2] == "TinyInlineDiagnosticVirtualTextInfo",
	"Search count body padding must remain inside the pill"
)
assert(
	chunks[4][1] == " " and chunks[4][2] == "TinyInlineDiagnosticVirtualTextInfo",
	"Forward search counts need the Noice search-down icon"
)
assert(
	chunks[5][1] == " Match 1 of 35 " and chunks[5][2] == "TinyInlineDiagnosticVirtualTextInfo",
	"Search count text must explain the current match in English"
)
assert(
	chunks[6][1] == "" and chunks[6][2] == "TinyInlineInvDiagnosticVirtualTextInfoNoBg",
	"Search counts need one rounded right edge without a CursorLine background"
)
local reverse_chunks = require("config.noice_ui").search_count_virtual_text(" ?builder            [2/35] ")
assert(reverse_chunks[4][1] == " ", "Reverse search counts need the Noice search-up icon")
assert(reverse_chunks[5][1] == " Match 2 of 35 ", "Reverse search counts need the normalized match label")
assert(
	require("config.noice_ui").search_count_message("/", { current = 1, total = 999, incomplete = 2 }) == "/ [1/>999]",
	"maxcount-limited searches must make their truncated total explicit"
)

assert(opts.notify.enabled == false, "Snacks must remain the notification provider")
assert(opts.popupmenu.enabled == false, "blink.cmp must remain the command-line completion renderer")
assert(opts.lsp.progress.enabled == false, "Noice must not replace LSP progress")
assert(opts.lsp.hover.enabled == false, "Noice must not replace LSP hover")
assert(opts.lsp.signature.enabled == false, "Noice must not replace blink.cmp signature help")
assert(opts.lsp.message.enabled == false, "Noice must not reroute LSP messages")
assert(
	opts.lsp.override["vim.lsp.util.convert_input_to_markdown_lines"] == false
		and opts.lsp.override["vim.lsp.util.stylize_markdown"] == false
		and opts.lsp.override["cmp.entry.get_documentation"] == false,
	"Noice must not override the existing LSP markdown renderers"
)
assert(opts.presets.bottom_search == false, "Search commands must use the Noice popup")
assert(opts.presets.command_palette == true, "The command popup must use the compact palette layout")
assert(
	opts.views.cmdline_popup.position.row == -2 and opts.views.cmdline_popup.position.col == 0,
	"Noice command input must stay above the bottom-left statusline"
)
assert(noice.config == nil, "Noice must use its standard setup path")
assert(opts.routes == nil, "Noice must not install custom rich-confirmation routes")
assert(opts.views.confirm == nil, "Noice must not customize the rich-confirmation view")

require("noice.config").setup(opts)
local Cmdline = require("noice.ui.cmdline")
local input_prompt = "Quit all Neovim windows? (Y/n): "
Cmdline.on_show("cmdline_show", { { 0, "" } }, 0, "", input_prompt, 0, 1)
assert(Cmdline.active:get_format().view == "cmdline_input", "input() prompts must use Noice's standard input dialog")
assert(
	Cmdline.message.title == " Quit all Neovim windows? (Y/n) ",
	"quit-all input must use its prompt as the dialog title"
)
Cmdline.on_hide("cmdline_hide", 1)

print("Noice command-line and message integration regression: ok")
