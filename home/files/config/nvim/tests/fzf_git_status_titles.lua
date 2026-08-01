local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

package.loaded["config.fzf"] = {
	ui_opts = function()
		return {}
	end,
	color_spec = function()
		return ""
	end,
}
package.loaded["config.git_diff_peek"] = {
	child_ui_zindex = function()
		return 77
	end,
}

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/core.lua"))
local fzf
for _, spec in ipairs(specs) do
	if spec[1] == "ibhagwan/fzf-lua" then
		fzf = spec
		break
	end
end
assert(fzf, "fzf-lua plugin spec was not found")

assert(type(fzf.opts.winopts) == "function", "fzf winopts must be evaluated for each picker")
local popup_winopts = fzf.opts.winopts()
assert(popup_winopts.height == 0.9 and popup_winopts.width == 0.8 and popup_winopts.backdrop == false)
assert(popup_winopts.preview.layout == "vertical" and popup_winopts.preview.vertical == "right:60%")
assert(popup_winopts.zindex == 77, "fzf main and noautocmd preview must receive the popup z-index")
package.loaded["config.git_diff_peek"].child_ui_zindex = function()
	return nil
end
local ordinary_winopts = fzf.opts.winopts()
assert(ordinary_winopts.zindex == nil, "fzf must leave z-index to its normal default outside Git Diff Peek")

local status = assert(fzf.opts.git and fzf.opts.git.status, "git_status picker options are missing")
assert(status.winopts.border == "none", "git_status must not draw an untitled outer border")
assert(status.winopts.title == false, "git_status must not retain the outer picker title")
assert(status.fzf_opts["--input-border"] == "none", "git_status input must remain inside the list pane")
assert(status.fzf_opts["--list-border"] == "rounded", "git_status list pane border is missing")
assert(status.fzf_opts["--list-label"] == " Git Status ", "git_status list pane title is missing")
assert(status.fzf_opts["--preview-label"] == " Diff ", "git_status fallback preview title is missing")

local focus = status.keymap and status.keymap.fzf and status.keymap.fzf.focus
assert(type(focus) == "string", "git_status preview title focus binding is missing")
assert(focus:find("transform%-preview%-label"), "git_status preview title must update with the selected file")

print("fzf git status titles: ok")
