local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.env.NVIM_TEST_NVIM_ROOT or vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")

local function run_child(root)
	vim.opt.runtimepath:prepend(root)
	package.path = table.concat({
		vim.fs.joinpath(root, "lua/?.lua"),
		vim.fs.joinpath(root, "lua/?/init.lua"),
		package.path,
	}, ";")
	vim.o.equalalways = true
	vim.o.eadirection = "both"
	assert(vim.o.columns == 447 and vim.o.lines == 147, "child UI must be 447x147")

	local function set_buffer(win, name, filetype)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, name)
		vim.bo[buf].filetype = filetype
		vim.api.nvim_win_set_buf(win, buf)
		return buf
	end

	vim.cmd("enew")
	local editor = vim.api.nvim_get_current_win()
	set_buffer(editor, "FLOWCHARTS.md", "markdown")
	vim.cmd("rightbelow vsplit")
	local explorer = vim.api.nvim_get_current_win()
	set_buffer(explorer, "Explorer", "snacks_layout_box")
	vim.cmd("belowright split")
	local aerial = vim.api.nvim_get_current_win()
	set_buffer(aerial, "Aerial", "aerial")
	vim.api.nvim_set_current_win(editor)
	vim.cmd("belowright new")
	vim.api.nvim_win_close(0, true)
	vim.cmd("belowright 10new")
	local trouble = vim.api.nvim_get_current_win()
	set_buffer(trouble, "Trouble", "trouble")
	vim.wo[trouble].winfixheight = true
	vim.api.nvim_win_set_height(trouble, 10)
	vim.api.nvim_set_current_win(editor)

	local fake_picker = {
		closed = false,
		layout = {
			root = { win = explorer },
			update = function() end,
		},
	}

	local function fake_terminal(opts)
		local terminal = { buf = vim.api.nvim_create_buf(false, true), opts = opts.win }
		vim.bo[terminal.buf].filetype = "snacks_terminal"

		function terminal:valid()
			return self.win and vim.api.nvim_win_is_valid(self.win) and vim.api.nvim_win_get_buf(self.win) == self.buf
		end

		function terminal:show()
			local parent = self.opts.win and vim.api.nvim_win_is_valid(self.opts.win) and self.opts.win or 0
			if self.opts.position == "right" then
				vim.api.nvim_win_call(parent, function()
					local width = math.floor(vim.api.nvim_win_get_width(0) * (self.opts.width or 0.5))
					vim.cmd(
						("silent noswapfile vertical rightbelow sbuffer %d | vertical resize %d"):format(
							self.buf,
							width
						)
					)
					self.win = vim.api.nvim_get_current_win()
				end)
			elseif self.opts.position == "top" then
				vim.api.nvim_win_call(parent, function()
					vim.cmd(("silent noswapfile aboveleft sbuffer %d | resize %d"):format(self.buf, self.opts.height))
					self.win = vim.api.nvim_get_current_win()
				end)
			else
				vim.cmd(("silent noswapfile botright sbuffer %d | resize %d"):format(self.buf, self.opts.height))
				self.win = vim.api.nvim_get_current_win()
			end
			vim.api.nvim_win_set_height(self.win, self.opts.height)
			vim.wo[self.win].winfixheight = self.opts.wo.winfixheight
		end

		function terminal:hide()
			if self:valid() then
				vim.api.nvim_win_close(self.win, true)
			end
			self.win = nil
		end

		function terminal:close()
			self:hide()
		end

		function terminal:focus()
			vim.api.nvim_set_current_win(self.win)
		end

		terminal:show()
		return terminal
	end

	package.loaded.snacks = {
		terminal = {
			open = function(_, opts)
				return fake_terminal(opts)
			end,
		},
		picker = {
			get = function(opts)
				return opts.source == "explorer" and { fake_picker } or {}
			end,
		},
	}

	local sidebar = require("config.sidebar")
	sidebar.setup()
	sidebar.sync()
	local sync_calls = 0
	local real_sync = sidebar.sync
	sidebar.sync = function(...)
		sync_calls = sync_calls + 1
		return real_sync(...)
	end

	local function flush()
		vim.wait(100)
		local settled = sync_calls
		vim.wait(100)
		assert(sync_calls == settled, "sidebar sync must settle without a resize loop")
	end

	local function sidebar_heights()
		return vim.api.nvim_win_get_height(explorer), vim.api.nvim_win_get_height(aerial)
	end

	local function assert_sidebar_ratio(expected)
		local explorer_height, aerial_height = sidebar_heights()
		assert(
			math.abs(explorer_height - aerial_height) <= 1,
			("sidebar ratio changed: Explorer=%d Aerial=%d expected=%d/%d"):format(
				explorer_height,
				aerial_height,
				expected[1],
				expected[2]
			)
		)
	end

	local function assert_no_managed_terminal()
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			assert(not vim.w[win].dotfiles_terminal_group, "test must not create a managed terminal")
		end
	end

	local function assert_open(group, expected_sidebar)
		assert(vim.api.nvim_win_get_height(group.commits.win) == 15, "Commits must remain 15 rows")
		assert(vim.api.nvim_win_get_height(group.files.win) == 15, "Files must remain 15 rows")
		local explorer_height, aerial_height = sidebar_heights()
		assert(
			vim.api.nvim_win_get_height(trouble) == 10 and math.abs(explorer_height - aerial_height) <= 1,
			("open geometry regressed: editor=%d Trouble=%d Explorer=%d Aerial=%d expected Trouble=10 sidebar=%d/%d"):format(
				vim.api.nvim_win_get_height(editor),
				vim.api.nvim_win_get_height(trouble),
				explorer_height,
				aerial_height,
				expected_sidebar[1],
				expected_sidebar[2]
			)
		)
		assert_no_managed_terminal()
	end

	local function geometry()
		return {
			layout = vim.fn.winlayout(),
			editor = vim.api.nvim_win_get_height(editor),
			trouble = vim.api.nvim_win_get_height(trouble),
			explorer = vim.api.nvim_win_get_height(explorer),
			aerial = vim.api.nvim_win_get_height(aerial),
		}
	end

	local function assert_hidden(expected)
		assert(vim.deep_equal(vim.fn.winlayout(), expected.layout), "hidden split tree must be restored")
		assert(math.abs(vim.api.nvim_win_get_height(editor) - expected.editor) <= 1, "editor height must be restored")
		assert(vim.api.nvim_win_get_height(trouble) == expected.trouble, "Trouble height must be restored")
		assert(
			math.abs(vim.api.nvim_win_get_height(explorer) - expected.explorer) <= 1,
			"Explorer height must be restored"
		)
		assert(math.abs(vim.api.nvim_win_get_height(aerial) - expected.aerial) <= 1, "Aerial height must be restored")
		assert_no_managed_terminal()
	end

	flush()
	local hidden = geometry()
	local hidden_sidebar = { sidebar_heights() }
	assert_sidebar_ratio(hidden_sidebar)
	local lazygit = require("config.lazygit")
	for _ = 1, 3 do
		vim.api.nvim_set_current_win(editor)
		local group = lazygit.toggle()
		flush()
		assert_open(group, hidden_sidebar)
		lazygit.toggle()
		flush()
		assert_hidden(hidden)
	end

	vim.api.nvim_set_current_win(editor)
	lazygit.toggle()
	lazygit.toggle()
	flush()
	assert_hidden(hidden)

	vim.api.nvim_set_current_win(editor)
	lazygit.toggle()
	lazygit.close_all()
	flush()
	assert_hidden(hidden)

	vim.api.nvim_set_current_win(editor)
	local group = lazygit.toggle()
	vim.cmd("tabnew")
	local other_tab = vim.api.nvim_get_current_tabpage()
	flush()
	assert(vim.api.nvim_get_current_tabpage() == other_tab, "stale callback must not change the active tab")
	vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(editor))
	flush()
	assert_open(group, hidden_sidebar)
	lazygit.toggle()
	flush()
	assert_hidden(hidden)

	vim.api.nvim_set_current_win(editor)
	vim.cmd("botright 48new")
	local managed_terminal = vim.api.nvim_get_current_win()
	set_buffer(managed_terminal, "managed-shell", "snacks_terminal")
	vim.w[managed_terminal].dotfiles_terminal_group = 1
	vim.wo[managed_terminal].winfixheight = true
	vim.api.nvim_win_set_height(managed_terminal, 48)
	vim.api.nvim_win_set_height(trouble, 10)
	vim.api.nvim_set_current_win(editor)
	flush()

	local function upvalue(fn, name)
		for index = 1, 64 do
			local key, value = debug.getupvalue(fn, index)
			if not key then
				break
			end
			if key == name then
				return value
			end
		end
	end

	local hide_group = assert(upvalue(lazygit.toggle, "hide_group"), "hide_group upvalue is unavailable")
	local restore_fixed_heights =
		assert(upvalue(hide_group, "restore_fixed_heights"), "restore_fixed_heights upvalue is unavailable")
	local adversarial_heights = { [trouble] = 10, [managed_terminal] = 48 }
	assert(next(adversarial_heights) == trouble, "test setup must exercise the harmful top-to-bottom map order")
	local set_height = vim.api.nvim_win_set_height
	local restore_order = {}
	vim.api.nvim_win_set_height = function(win, fixed_height)
		restore_order[#restore_order + 1] = win
		return set_height(win, fixed_height)
	end
	local restored, restore_error = pcall(restore_fixed_heights, {
		tabpage = vim.api.nvim_get_current_tabpage(),
		fixed_heights = adversarial_heights,
	})
	vim.api.nvim_win_set_height = set_height
	assert(restored, restore_error)
	assert(
		vim.deep_equal(restore_order, { managed_terminal, trouble }),
		"nested fixed heights must be restored bottom-to-top"
	)

	for _ = 1, 3 do
		local managed_group = lazygit.toggle()
		flush()
		assert(vim.api.nvim_win_get_height(managed_group.commits.win) == 15, "managed Commits must remain 15 rows")
		assert(vim.api.nvim_win_get_height(managed_group.files.win) == 15, "managed Files must remain 15 rows")
		assert(vim.api.nvim_win_get_height(trouble) == 10, "opening above a managed terminal must preserve Trouble")
		assert(vim.api.nvim_win_get_height(managed_terminal) == 48, "opening LazyGit must preserve managed terminal")
		assert_sidebar_ratio({ sidebar_heights() })

		vim.api.nvim_set_current_win(editor)
		lazygit.toggle()
		flush()
		assert(vim.api.nvim_win_get_height(trouble) == 10, "hiding above a managed terminal must preserve Trouble")
		assert(vim.api.nvim_win_get_height(managed_terminal) == 48, "hiding LazyGit must preserve managed terminal")
		assert_sidebar_ratio({ sidebar_heights() })
	end
	assert(sync_calls <= 80, "sidebar sync must remain finite across the regression matrix")
	return true
end

if vim.g.dotfiles_lazygit_sidebar_layout_child then
	return run_child(vim.g.dotfiles_lazygit_sidebar_layout_nvim_root)
end

local test_file = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
assert(child > 0, "failed to start LazyGit sidebar child")

local function request(method, ...)
	return vim.rpcrequest(child, method, ...)
end

local function finish()
	pcall(request, "nvim_command", "qa!")
	local status = vim.fn.jobwait({ child }, 2000)[1]
	if status == -1 then
		vim.fn.jobstop(child)
		vim.fn.jobwait({ child }, 2000)
	end
end

local ok, result = xpcall(function()
	request("nvim_ui_attach", 447, 147, { rgb = true, ext_multigrid = false })
	return request(
		"nvim_exec_lua",
		[[
vim.g.dotfiles_lazygit_sidebar_layout_child = true
vim.g.dotfiles_lazygit_sidebar_layout_nvim_root = select(2, ...)
return assert(loadfile(select(1, ...)))()
]],
		{ test_file, nvim_root }
	)
end, debug.traceback)
finish()
assert(ok, result)
assert(result, "LazyGit sidebar child did not complete")
print("lazygit sidebar layout regression: ok")
