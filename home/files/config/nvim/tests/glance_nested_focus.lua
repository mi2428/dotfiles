local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")

local setup_opts
local list_buf = vim.api.nvim_create_buf(false, true)
vim.bo[list_buf].filetype = "Glance"
local preview_buf = vim.api.nvim_create_buf(false, true)
local list_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(list_win, list_buf)
vim.cmd.vsplit()
local preview_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(preview_win, preview_buf)
vim.w[preview_win].dotfiles_glance_preview = true
local aerial_buf = vim.api.nvim_create_buf(false, true)
vim.bo[aerial_buf].filetype = "aerial"
vim.api.nvim_win_set_buf(list_win, aerial_buf)
vim.w[list_win].dotfiles_glance_list_bufnr = list_buf

local glance = {
	is_open = function()
		return true
	end,
	actions = {
		enter_win = function(name)
			assert(name == "preview", "nested focus must enter Glance preview")
			return function()
				vim.api.nvim_set_current_win(preview_win)
			end
		end,
		open = function()
			vim.schedule(function()
				vim.api.nvim_set_current_win(list_win)
			end)
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
		return nil
	end,
}

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/lsp.lua"))
local glance_spec = vim.iter(specs):find(function(spec)
	return spec[1] == "dnlhc/glance.nvim"
end)
assert(glance_spec and type(glance_spec.config) == "function", "Glance plugin config must exist")
glance_spec.config()
assert(setup_opts, "Glance setup must run")

glance.actions.open("definitions", {})
assert(
	vim.wait(1000, function()
		return vim.api.nvim_get_current_win() == preview_win and vim.fn.mode() == "n"
	end, 20),
	"nested Glance open must restore preview focus in normal mode"
)

print("Glance nested focus regression: ok")
