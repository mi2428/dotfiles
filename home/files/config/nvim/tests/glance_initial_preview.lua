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
package.loaded["glance.config"] = { options = {} }
package.loaded["config.git_diff_peek"] = {
	child_ui_zindex = function()
		return 77
	end,
}
local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/lsp.lua"))
local glance_spec = vim.iter(specs):find(function(spec)
	return spec[1] == "dnlhc/glance.nvim"
end)
assert(glance_spec and type(glance_spec.config) == "function", "Glance plugin config must exist")
local dependencies = {}
for _, dependency in ipairs(glance_spec.dependencies or {}) do
	dependencies[dependency] = true
end
assert(dependencies["Bekaboo/dropbar.nvim"], "Glance must load Dropbar for preview breadcrumbs")
assert(dependencies["stevearc/aerial.nvim"], "Glance must load Aerial for its single-result outline")
glance_spec.config()

assert(setup_opts.border.enable == true, "Glance border configuration regressed")
assert(setup_opts.height == 43, "Glance code preview height must be 1.2 times the previous 36 rows")
assert(setup_opts.winbar.enable == false, "Glance's built-in winbar must yield to Dropbar breadcrumbs")
assert(setup_opts.zindex == 45, "Glance must keep its ordinary editor z-index by default")
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
assert(package.loaded["glance.config"].options.zindex == 77, "Glance must use the active popup child z-index")

assert(
	vim.wait(1000, function()
		return entered_preview
	end),
	"Glance preview focus was not scheduled"
)
assert(synced_initial_location, "Glance initial selection was not synchronized")
assert(type(setup_opts.hooks.after_close) == "function", "Glance after_close hook must exist")
setup_opts.hooks.after_close()
assert(package.loaded["glance.config"].options.zindex == 45, "Glance close must restore its ordinary z-index")

print("Glance initial preview regression: ok")
