local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local panel = require("config.diffview_snacks_panel")

local function entry(kind, path, status, opts)
	opts = opts or {}
	return {
		kind = kind,
		path = path,
		status = status,
		oldpath = opts.oldpath,
		stats = opts.stats,
	}
end

local working = entry("working", "lua/config/init.lua", "M", {
	stats = { additions = 4, deletions = 2 },
})
local deleted = entry("working", "lua/removed.lua", "D")
local untracked = entry("working", "README.new", "?")
local deep = entry("working", "packages/frontend/src/components/Button/index.lua", "M")
local staged = entry("staged", "lua/config/init.lua", "M")
local renamed = entry("staged", "lua/new_name.lua", "R", { oldpath = "lua/old_name.lua" })
local conflict = entry("conflicting", "lua/conflicted.lua", "U")

local view = {
	adapter = { ctx = { toplevel = "/virtual/repository" } },
	files = {
		conflicting = { conflict },
		working = { working, deleted, untracked, deep },
		staged = { staged, renamed },
	},
	panel = { cur_file = working },
}
local state = { collapsed = {}, directory_keys = {} }
local items = panel._build_items(view, state, false)

local by_entry = {}
local roots = {}
local group_count = 0
for _, item in ipairs(items) do
	if item.entry then
		by_entry[item.entry] = item
	elseif not item.parent then
		group_count = group_count + 1
		roots[#roots + 1] = item
	end
	if item.dir then
		assert(item.open, "the dedicated Diffview tree must start fully expanded")
	end
end

assert(group_count == 3, "conflicts, working changes, and staged changes must have separate roots")
assert(not roots[1].last and not roots[2].last and roots[3].last, "top-level tree branches must terminate correctly")
assert(by_entry[working], "working file is missing")
assert(by_entry[deleted], "deleted files must remain visible without a filesystem node")
assert(by_entry[untracked], "untracked file is missing")
assert(by_entry[deep], "deeply nested file is missing")
assert(by_entry[staged], "staged file is missing")
assert(by_entry[renamed].oldpath == "lua/old_name.lua", "rename source path must be retained")
assert(by_entry[conflict], "conflicted file is missing")
assert(by_entry[working] ~= by_entry[staged], "the same path in working and staged sets must remain distinct")
assert(by_entry[working].label == nil, "active-file markers must not shift virtual tree branches")
assert(by_entry[working].status == " M", "working status must use the right git-status column")
assert(by_entry[staged].status == "M ", "staged status must use the left git-status column")
assert(by_entry[untracked].status == "??", "untracked status must use git porcelain form")
assert(by_entry[conflict].status == "UU", "conflict status must use git porcelain form")
assert(by_entry[working].parent and by_entry[working].parent.dir, "files must retain virtual directory parents")
assert(
	by_entry[deep].parent.display_name == "packages/frontend/src/components/Button",
	"single-child directory chains must render as one compact folder"
)
assert(
	by_entry[deep].parent.parent and by_entry[deep].parent.parent.group,
	"compact folders must remove redundant indentation levels without losing their group parent"
)
local compact_key = by_entry[deep].parent.key
local ancestor = by_entry[working].parent
while ancestor.parent do
	ancestor = ancestor.parent
end
assert(ancestor.last == roots[2].last, "descendants must retain their top-level branch metadata")

state.collapsed["working:dir:lua"] = true
items = panel._build_items(view, state, false)
local visible_working = false
local visible_staged = false
for _, item in ipairs(items) do
	visible_working = visible_working or item.entry == working
	visible_staged = visible_staged or item.entry == staged
end
assert(not visible_working, "collapsing a working directory must hide its descendants")
assert(visible_staged, "collapsing working changes must not hide the staged copy of the same path")

state.collapsed[compact_key] = true
items = panel._build_items(view, state, false)
for _, item in ipairs(items) do
	assert(item.entry ~= deep, "collapsing a compact folder must hide its file descendants")
end

items = panel._build_items(view, state, true)
for _, item in ipairs(items) do
	visible_working = visible_working or item.entry == working
end
assert(visible_working, "search mode must expand collapsed paths")

local picker_opts = panel._picker_options({ view = view, collapsed = {}, directory_keys = {} }, 0)
assert(picker_opts.source == "diffview_files", "the dedicated picker must expose its sidebar source")
assert(picker_opts.layout.layout.position == "right", "the Diffview tree must open on the right")

local root_win = vim.api.nvim_get_current_win()
vim.w[root_win].snacks_win = { id = 17, position = "right", relative = "editor" }
assert(
	panel._isolate_picker_equalize_group({ layout = { root = { win = root_win } } }),
	"the Diffview picker root must be isolated from generic right-sidebar equalization"
)
local isolated = vim.w[root_win].snacks_win
assert(isolated.id == 17 and isolated.relative == "editor", "equalize isolation must preserve Snacks root metadata")
assert(isolated.position == "diffview_files", "the Diffview picker needs a distinct equalize identity")
vim.w[root_win].snacks_win = nil

local deferred = {}
local aerial_attempts = 0
local original_defer_fn = vim.defer_fn
local original_sidebar = package.loaded["config.sidebar"]
vim.defer_fn = function(callback, delay)
	deferred[#deferred + 1] = { callback = callback, delay = delay }
end
package.loaded["config.sidebar"] = {
	open_aerial = function(opts)
		aerial_attempts = aerial_attempts + 1
		assert(opts.source_win == vim.api.nvim_get_current_win(), "Aerial must attach to the Diffview main window")
		return aerial_attempts >= 2
	end,
}
local fake_picker = { closed = false }
local aerial_state = { picker = fake_picker }
panel._schedule_aerial(aerial_state, fake_picker, vim.api.nvim_get_current_win())
table.sort(deferred, function(left, right)
	return left.delay < right.delay
end)
for _, pending in ipairs(deferred) do
	pending.callback()
end
vim.defer_fn = original_defer_fn
package.loaded["config.sidebar"] = original_sidebar
assert(#deferred == 4, "Aerial startup must retry while Diffview still shows its null buffer")
assert(aerial_attempts == 2 and aerial_state.aerial_opened, "Aerial startup must stop retrying after success")

print("Diffview Snacks virtual panel regression: ok")
