local M = {}

local states = setmetatable({}, { __mode = "k" })

-- Diffview entries can represent deleted or historical files and the same path
-- can exist in both the working and staged sets. Build a virtual Snacks tree
-- from FileEntry objects instead of consulting the live filesystem.
local group_specs = {
	{ key = "conflicting", title = "Conflicts" },
	{ key = "working", title = "Changes" },
	{ key = "staged", title = "Staged Changes" },
}

local function is_diff_view(view)
	return view
		and view.class
		and type(view.class.name) == "function"
		and view.class:name() == "DiffView"
		and view.files
		and type(view.set_file) == "function"
end

local function normalize_status(entry)
	local status = entry.status or "M"
	if status == "?" then
		return "??"
	elseif status == "U" then
		return "UU"
	elseif #status == 2 then
		return status
	elseif entry.kind == "staged" then
		return status .. " "
	end
	return " " .. status
end

local function new_node(key, name, relative_path, dir, parent)
	return {
		key = key,
		name = name,
		relative_path = relative_path,
		dir = dir,
		parent = parent,
		children = {},
		entries = {},
	}
end

local function add_entry(root, group_key, entry)
	local parts = vim.split(entry.path, "/", { plain = true, trimempty = true })
	local node = root
	local path_parts = {}

	for index, part in ipairs(parts) do
		path_parts[#path_parts + 1] = part
		local relative_path = table.concat(path_parts, "/")
		local is_file = index == #parts
		local child_key = group_key .. ":" .. (is_file and "file:" or "dir:") .. relative_path
		local child = node.children[child_key]
		if not child then
			child = new_node(child_key, part, relative_path, not is_file, node)
			node.children[child_key] = child
		end
		child.entries[#child.entries + 1] = entry
		node = child
	end

	node.entry = entry
end

local function sorted_children(node)
	local children = vim.tbl_values(node.children)
	table.sort(children, function(left, right)
		if left.dir ~= right.dir then
			return left.dir
		end
		return left.name:lower() < right.name:lower()
	end)
	return children
end

local function item_file(view, node)
	if node.group then
		return node.name
	end
	return vim.fs.joinpath(view.adapter.ctx.toplevel, node.relative_path)
end

local function compact_directory(node)
	if node.group or not node.dir then
		return node, node.name
	end

	local tail = node
	local names = { node.name }
	while true do
		local children = sorted_children(tail)
		if #children ~= 1 or not children[1].dir then
			break
		end
		tail = children[1]
		names[#names + 1] = tail.name
	end
	return tail, table.concat(names, "/")
end

local function flatten_group(view, state, node, parent_item, items, expand_all, is_last)
	local display_name
	node, display_name = compact_directory(node)
	state.directory_keys[node.key] = node.dir or nil

	local collapsed = node.dir and not expand_all and state.collapsed[node.key] == true
	local item = {
		key = node.key,
		file = item_file(view, node),
		text = (node.group_key or "") .. " " .. (node.relative_path or node.name),
		dir = node.dir,
		open = node.dir and not collapsed,
		parent = parent_item,
		last = is_last,
		group = node.group,
		entry = node.entry,
		entries = node.entries,
		display_name = display_name,
		type = node.dir and "directory" or "file",
	}

	if node.group then
		item.comment = ("(%d)"):format(#node.entries)
	elseif node.entry then
		item.status = normalize_status(node.entry)
		item.stats = node.entry.stats
		item.oldpath = node.entry.oldpath
	end

	items[#items + 1] = item
	item.sort = ("%08d"):format(#items)

	if collapsed then
		return
	end

	local children = sorted_children(node)
	for index, child in ipairs(children) do
		flatten_group(view, state, child, item, items, expand_all, index == #children)
	end
end

local function build_items(view, state, expand_all)
	local items = {}
	state.directory_keys = {}

	local roots = {}
	for _, spec in ipairs(group_specs) do
		local entries = view.files[spec.key] or {}
		if #entries > 0 then
			local root = new_node("group:" .. spec.key, spec.title, "", true)
			root.group = true
			root.group_key = spec.key
			for _, entry in ipairs(entries) do
				root.entries[#root.entries + 1] = entry
				add_entry(root, spec.key, entry)
			end
			roots[#roots + 1] = root
		end
	end
	for index, root in ipairs(roots) do
		flatten_group(view, state, root, nil, items, expand_all, index == #roots)
	end

	return items
end

M._build_items = build_items
M._normalize_status = normalize_status

local function format_item(item, picker)
	local ret = require("snacks.picker.format").file(item, picker)
	if item.dir and item.display_name then
		for _, part in ipairs(ret) do
			if part.field == "file" then
				part[1] = item.display_name
				break
			end
		end
	end
	if item.oldpath then
		ret[#ret + 1] = { "← " .. item.oldpath .. " ", "SnacksPickerComment" }
	end
	if item.stats then
		if item.stats.additions then
			ret[#ret + 1] = { "+" .. item.stats.additions .. " ", "DiffviewFilePanelInsertions" }
		end
		if item.stats.deletions then
			ret[#ret + 1] = { "-" .. item.stats.deletions .. " ", "DiffviewFilePanelDeletions" }
		end
	end
	return ret
end

local function active_picker(state)
	local picker = state and state.picker
	return picker and not picker.closed and picker or nil
end

local function reveal_entry(state, entry)
	local picker = active_picker(state)
	if not picker or not entry then
		return
	end

	for item, index in picker:iter() do
		if item.entry == entry then
			picker.list:view(index)
			return
		end
	end
end

local function refresh_picker(state, entry)
	local picker = active_picker(state)
	if not picker then
		return
	end
	picker.list:set_target()
	picker:find({
		refresh = true,
		on_done = function()
			reveal_entry(state, entry or state.view.panel.cur_file)
		end,
	})
end

local function toggle_directory(state, picker, item)
	if not item or not item.dir then
		return false
	end
	state.collapsed[item.key] = not state.collapsed[item.key]
	refresh_picker(state)
	return true
end

local function select_item(state, picker, item, focus)
	item = item or picker:current()
	if not item then
		return
	end
	if toggle_directory(state, picker, item) then
		return
	end
	if item.entry then
		state.view:set_file(item.entry, focus == true, false)
	end
end

local function file_items(picker)
	local ret = {}
	for item, index in picker:iter() do
		if item.entry then
			ret[#ret + 1] = { item = item, index = index }
		end
	end
	return ret
end

local function move_file(state, picker, offset, edge)
	local files = file_items(picker)
	if #files == 0 then
		return
	end

	local target
	if edge == "first" then
		target = files[1]
	elseif edge == "last" then
		target = files[#files]
	else
		local current = picker:current()
		local current_index = 0
		for index, value in ipairs(files) do
			if value.item == current or value.item.entry == state.view.panel.cur_file then
				current_index = index
				break
			end
		end
		target = files[(current_index + offset - 1) % #files + 1]
	end

	picker.list:view(target.index)
	select_item(state, picker, target.item, false)
end

local function collapse_parent(state, picker, item)
	if not item then
		return
	end
	local target = item.dir and item.open and item or item.parent
	if target then
		state.collapsed[target.key] = true
		refresh_picker(state)
	end
end

local function expand_all(state)
	state.collapsed = {}
	refresh_picker(state)
end

local function collapse_all(state)
	for key in pairs(state.directory_keys) do
		state.collapsed[key] = true
	end
	refresh_picker(state)
end

local function set_action_target(state, picker)
	local item = picker:current()
	if item and item.entry then
		state.view.panel:set_cur_file(item.entry)
		return item.entry
	end
end

local function emit_for_entry(state, picker, action)
	if set_action_target(state, picker) then
		require("diffview.actions")[action]()
	end
end

local function toggle_stage(state, picker)
	local item = picker:current()
	if not item then
		return
	end
	local RevType = require("diffview.vcs.rev").RevType
	if not (state.view.left.type == RevType.STAGE and state.view.right.type == RevType.LOCAL) then
		return
	end

	if item.entry then
		state.view.panel:set_cur_file(item.entry)
		require("diffview.actions").toggle_stage_entry()
		return
	end

	local entries = item.entries or {}
	local paths = {}
	local operation
	for _, entry in ipairs(entries) do
		if not operation then
			operation = entry.kind == "staged" and "reset" or "add"
		end
		if (operation == "reset") == (entry.kind == "staged") then
			paths[#paths + 1] = entry.path
		end
	end
	if #paths == 0 then
		return
	end

	local ok
	if operation == "reset" then
		ok = state.view.adapter:reset_files(paths)
	else
		ok = state.view.adapter:add_files(paths)
	end
	if ok then
		state.view:update_files()
		state.view.emitter:emit(require("diffview.events").EventName.FILES_STAGED, state.view)
	else
		vim.notify("Failed to stage/unstage Diffview directory", vim.log.levels.ERROR)
	end
end

local function picker_options(state, editor_win)
	local view = state.view
	local function action(callback)
		return function(picker, item)
			callback(picker, item or picker:current())
		end
	end

	return {
		title = "Diff files",
		cwd = view.adapter.ctx.toplevel,
		focus = false,
		auto_close = false,
		show_empty = true,
		main = { current = true },
		finder = function(_, ctx)
			return build_items(view, state, not ctx.filter:is_empty())
		end,
		format = format_item,
		sort = { fields = { "sort" } },
		matcher = { sort_empty = false, keep_parents = true },
		formatters = {
			file = { filename_only = true, git_status_hl = true },
		},
		layout = {
			preview = false,
			hidden = { "input", "preview" },
			auto_hide = { "input" },
			layout = {
				backdrop = false,
				width = 40,
				min_width = 40,
				height = 0,
				position = "left",
				border = "none",
				box = "vertical",
				{ win = "list", border = "none" },
				{ win = "preview", title = "{preview}", height = 0.4, border = "top" },
				{
					win = "input",
					height = 1,
					border = true,
					title = "{title} {live} {flags}",
					title_pos = "center",
				},
			},
		},
		actions = {
			confirm = action(function(picker, item)
				select_item(state, picker, item, false)
			end),
			diffview_focus = action(function(picker, item)
				select_item(state, picker, item, true)
			end),
			diffview_collapse = action(function(picker, item)
				collapse_parent(state, picker, item)
			end),
			diffview_expand_all = function()
				expand_all(state)
			end,
			diffview_collapse_all = function()
				collapse_all(state)
			end,
			diffview_next = function(picker)
				move_file(state, picker, 1)
			end,
			diffview_prev = function(picker)
				move_file(state, picker, -1)
			end,
			diffview_first = function(picker)
				move_file(state, picker, 0, "first")
			end,
			diffview_last = function(picker)
				move_file(state, picker, 0, "last")
			end,
			diffview_stage = function(picker)
				toggle_stage(state, picker)
			end,
			diffview_stage_all = function()
				require("diffview.actions").stage_all()
			end,
			diffview_unstage_all = function()
				require("diffview.actions").unstage_all()
			end,
			diffview_restore = function(picker)
				emit_for_entry(state, picker, "restore_entry")
			end,
			diffview_log = function()
				require("diffview.actions").open_commit_log()
			end,
			diffview_refresh = function()
				view:update_files()
			end,
			diffview_goto = function(picker)
				emit_for_entry(state, picker, "goto_file_edit")
			end,
			diffview_toggle = function()
				M.toggle_current()
			end,
		},
		win = {
			list = {
				keys = {
					["<CR>"] = "confirm",
					["<2-LeftMouse>"] = "confirm",
					["o"] = "confirm",
					["l"] = "confirm",
					["<S-CR>"] = "diffview_focus",
					["h"] = "diffview_collapse",
					["zo"] = "confirm",
					["zc"] = "diffview_collapse",
					["za"] = "confirm",
					["zR"] = "diffview_expand_all",
					["zM"] = "diffview_collapse_all",
					["<Tab>"] = "diffview_next",
					["<S-Tab>"] = "diffview_prev",
					["[F"] = "diffview_first",
					["]F"] = "diffview_last",
					["-"] = "diffview_stage",
					["s"] = "diffview_stage",
					["S"] = "diffview_stage_all",
					["U"] = "diffview_unstage_all",
					["X"] = "diffview_restore",
					["L"] = "diffview_log",
					["R"] = "diffview_refresh",
					["gf"] = "diffview_goto",
					["<leader>e"] = "diffview_focus",
					["<leader>b"] = "diffview_toggle",
				},
			},
		},
		on_show = function(picker)
			local list_buf = picker.list.win.buf
			vim.b[list_buf].dotfiles_diffview_panel = true
			vim.b[list_buf].miniindentscope_disable = true
			-- FileType may have fired before this dedicated picker was marked.
			-- Remove an already-drawn scope without touching the tree's own │ glyphs.
			local scope_namespace = vim.api.nvim_get_namespaces().MiniIndentscope
			if scope_namespace then
				vim.api.nvim_buf_clear_namespace(list_buf, scope_namespace, 0, -1)
			end
			if vim.api.nvim_win_is_valid(editor_win) then
				vim.api.nvim_set_current_win(editor_win)
			end
			-- A left Snacks split initially takes its width from only the current
			-- Diffview window. Re-run Neovim's split equalizer after Snacks has
			-- finished opening; the fixed-width sidebar stays at 40 columns while
			-- the two Diffview windows regain equal widths.
			vim.schedule(function()
				if active_picker(state) == picker and vim.api.nvim_win_is_valid(editor_win) then
					vim.api.nvim_win_call(editor_win, function()
						vim.cmd("wincmd =")
					end)
				end
			end)
		end,
		on_close = function(picker)
			if state.picker == picker then
				state.picker = nil
			end
			if not state.detaching then
				state.visible = false
			end
		end,
	}
end

local function open_panel(state, focus)
	local picker = active_picker(state)
	if picker then
		if focus then
			picker:focus("list")
		end
		return picker
	end
	if not state.view.files or state.view.files:len() == 0 then
		return
	end

	local editor_win = state.view.cur_layout:get_main_win().id
	if not vim.api.nvim_win_is_valid(editor_win) then
		return
	end
	vim.api.nvim_set_current_win(editor_win)
	state.visible = true
	state.picker = require("snacks").picker(picker_options(state, editor_win))
	if focus and state.picker then
		vim.schedule(function()
			local current = active_picker(state)
			if current then
				current:focus("list")
			end
		end)
	end
	return state.picker
end

function M.attach(view)
	if not is_diff_view(view) or states[view] then
		return
	end

	local state = {
		view = view,
		visible = true,
		collapsed = {},
		directory_keys = {},
	}
	states[view] = state

	if view.panel:is_open() then
		view.panel:close()
	end

	state.on_files_updated = function()
		vim.schedule(function()
			if states[view] ~= state or not state.visible then
				return
			end
			if active_picker(state) then
				refresh_picker(state)
			else
				open_panel(state, false)
			end
		end)
	end
	state.on_file_open = function(_, entry)
		vim.schedule(function()
			if states[view] == state then
				reveal_entry(state, entry)
			end
		end)
	end
	view.emitter:on("files_updated", state.on_files_updated)
	view.emitter:on("file_open_post", state.on_file_open)

	if view.files:len() > 0 then
		open_panel(state, false)
	end
end

function M.detach(view)
	local state = states[view]
	if not state then
		return
	end
	state.detaching = true
	view.emitter:off(state.on_files_updated, "files_updated")
	view.emitter:off(state.on_file_open, "file_open_post")
	local picker = active_picker(state)
	if picker then
		picker:close()
	end
	states[view] = nil
end

function M.focus_current()
	local view = require("diffview.lib").get_current_view()
	local state = view and states[view]
	if not state then
		require("diffview.actions").focus_files()
		return
	end
	state.visible = true
	open_panel(state, true)
end

function M.toggle_current()
	local view = require("diffview.lib").get_current_view()
	local state = view and states[view]
	if not state then
		require("diffview.actions").toggle_files()
		return
	end
	local picker = active_picker(state)
	if picker then
		state.visible = false
		picker:close()
	else
		state.visible = true
		open_panel(state, true)
	end
end

function M.setup_commands()
	vim.api.nvim_create_user_command("DiffviewFocusFiles", M.focus_current, {
		desc = "Focus the Diffview Snacks file panel",
		force = true,
	})
	vim.api.nvim_create_user_command("DiffviewToggleFiles", M.toggle_current, {
		desc = "Toggle the Diffview Snacks file panel",
		force = true,
	})
end

return M
