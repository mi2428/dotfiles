local M = {}

local markdown_threshold = 64 * 1024

local function markdown_path(path)
	if type(path) ~= "string" then
		return false
	end
	local lower = path:lower()
	return lower:match("%.md$") ~= nil or lower:match("%.markdown$") ~= nil
end

local function markdown_detector(path, buf)
	if not path or not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
	if not markdown_path(path) and not markdown_path(name) then
		return
	end
	if vim.bo[buf].filetype == "bigfile" then
		return "markdown"
	end
	local size = vim.fn.getfsize(name)
	if size >= markdown_threshold then
		vim.b[buf].dotfiles_markdown_light_mode = true
		vim.b[buf].dotfiles_bigfile_original_filetype = "markdown"
		return "bigfile"
	end
	return "markdown"
end

local function configure_window(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.bo[buf].filetype ~= "bigfile" then
		return
	end
	vim.wo[win].foldmethod = "manual"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].statuscolumn = ""
	vim.wo[win].conceallevel = 0
	vim.wo[win].cursorline = false
	vim.wo[win].relativenumber = false
	vim.wo[win].list = false
	vim.wo[win].wrap = false
	vim.wo[win].spell = false
end

function M.configure(ctx)
	local buf = ctx and ctx.buf or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.b[buf].dotfiles_markdown_light_mode = vim.b[buf].dotfiles_markdown_light_mode == true or nil
	vim.b[buf].completion = false
	vim.b[buf].minianimate_disable = true
	vim.b[buf].minihipatterns_disable = true
	vim.b[buf].miniindentscope_disable = true
	vim.b[buf].dotfiles_disable_hlchunk = true
	if ctx and ctx.ft and ctx.ft ~= "" then
		vim.b[buf].dotfiles_bigfile_original_filetype = ctx.ft
	end
	vim.bo[buf].swapfile = false
	vim.bo[buf].syntax = ""
	vim.api.nvim_buf_call(buf, function()
		if vim.fn.exists(":NoMatchParen") ~= 0 then
			vim.cmd([[NoMatchParen]])
		end
	end)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		configure_window(win)
	end
end

function M.setup()
	vim.filetype.add({
		pattern = {
			[".*%.md"] = { markdown_detector, { priority = 100 } },
			[".*%.markdown"] = { markdown_detector, { priority = 100 } },
		},
	})
	vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter", "WinEnter" }, {
		group = vim.api.nvim_create_augroup("dotfiles-bigfile-windows", { clear = true }),
		pattern = "*",
		callback = function(args)
			if vim.bo[args.buf].filetype == "bigfile" then
				M.configure({ buf = args.buf })
				configure_window(vim.api.nvim_get_current_win())
			end
		end,
	})
end

M.setup()
return M
