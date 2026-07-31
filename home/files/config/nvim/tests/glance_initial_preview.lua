local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")

local setup_opts
local entered_preview = false
local synced_initial_location = false
local glance = {
	actions = {
		enter_win = function(name)
			assert(name == "preview", "Glance must focus the preview window")
			return function()
				assert(synced_initial_location, "Glance must sync its initial location before focusing the preview")
				entered_preview = true
			end
		end,
	},
	setup = function(opts)
		setup_opts = opts
	end,
}

package.loaded.glance = glance
local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/lsp.lua"))
local glance_spec = vim.iter(specs):find(function(spec)
	return spec[1] == "dnlhc/glance.nvim"
end)
assert(glance_spec and type(glance_spec.config) == "function", "Glance plugin config must exist")
glance_spec.config()

assert(setup_opts.border.enable == true, "Glance border configuration regressed")
local before_open = assert(setup_opts.hooks.before_open, "Glance before_open hook must exist")
local list_bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(list_bufnr)
vim.api.nvim_create_autocmd("CursorMoved", {
	buffer = list_bufnr,
	callback = function()
		synced_initial_location = true
	end,
})

local results = { { uri = "file:///definition.lua" } }
before_open(results, function(opened_results)
	assert(opened_results == results, "Glance must open the original LSP results")
end)

assert(
	vim.wait(1000, function()
		return entered_preview
	end),
	"Glance preview focus was not scheduled"
)
assert(synced_initial_location, "Glance initial selection was not synchronized")

print("Glance initial preview regression: ok")
