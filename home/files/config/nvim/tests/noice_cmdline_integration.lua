local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
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
	vim.deep_equal(noice.dependencies, { "MunifTanjim/nui.nvim" }),
	"Noice must declare only its required UI dependency"
)

local original_cmdheight = vim.o.cmdheight
noice.init()
assert(vim.o.cmdheight == 0, "Noice must hide the native command-line area")
vim.o.cmdheight = original_cmdheight

local opts = noice.opts
assert(opts.cmdline.enabled == true, "Noice must render the command line")
assert(opts.cmdline.view == "cmdline_popup", "Noice must use the visible popup command line")
assert(opts.messages.enabled == false, "Noice must leave regular messages to Neovim")
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
assert(opts.presets.bottom_search == true, "Search commands must remain on the native bottom line")
assert(opts.presets.command_palette == true, "The command popup must use the compact palette layout")

print("Noice command-line-only integration regression: ok")
