local parsers = {
	"bash",
	"go",
	"gomod",
	"gosum",
	"gowork",
	"javascript",
	"json",
	"lua",
	"markdown",
	"markdown_inline",
	"python",
	"query",
	"ruby",
	"rust",
	"terraform",
	"toml",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"yaml",
}

local indent_filetypes = {
	bash = true,
	go = true,
	json = true,
	lua = true,
	python = true,
	toml = true,
	vim = true,
	yaml = true,
}

local function start_treesitter(args)
	local buf = args.buf
	local filetype = vim.bo[buf].filetype
	if filetype == "" or vim.bo[buf].buftype ~= "" then
		return
	end

	local ok, lang = pcall(vim.treesitter.language.get_lang, filetype)
	if not ok or not lang then
		return
	end

	pcall(vim.treesitter.start, buf, lang)

	if indent_filetypes[filetype] then
		vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
end

local function start_treesitter_for_loaded_buffers()
	-- Startup ordering can leave the initial buffer opened before our FileType
	-- autocmd exists. Attach treesitter explicitly for any already-loaded file.
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			start_treesitter({ buf = buf })
		end
	end
end

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		opts = {
			ensure_installed = parsers,
			install_dir = vim.fn.stdpath("data") .. "/site",
		},
		config = function(plugin, opts)
			local runtime_dir = vim.fs.joinpath(plugin.dir, "runtime")
			if vim.uv.fs_stat(runtime_dir) and not vim.tbl_contains(vim.opt.rtp:get(), runtime_dir) then
				-- nvim-treesitter main keeps queries under runtime/, so add that
				-- directory explicitly or treesitter highlighting will not find
				-- language highlight queries even though parsers are installed.
				vim.opt.rtp:append(runtime_dir)
			end

			require("nvim-treesitter").setup(opts)

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("dotfiles-treesitter", { clear = true }),
				callback = start_treesitter,
			})

			start_treesitter_for_loaded_buffers()
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		event = "VeryLazy",
		opts = {
			select = {
				lookahead = true,
			},
			move = {
				set_jumps = true,
			},
		},
		config = function(_, opts)
			require("nvim-treesitter-textobjects").setup(opts)

			local move = require("nvim-treesitter-textobjects.move")
			vim.keymap.set({ "n", "x", "o" }, "]f", function()
				move.goto_next_start("@function.outer")
			end, { desc = "Next function start" })
			vim.keymap.set({ "n", "x", "o" }, "]c", function()
				move.goto_next_start("@class.outer")
			end, { desc = "Next class start" })
			vim.keymap.set({ "n", "x", "o" }, "[f", function()
				move.goto_previous_start("@function.outer")
			end, { desc = "Previous function start" })
			vim.keymap.set({ "n", "x", "o" }, "[c", function()
				move.goto_previous_start("@class.outer")
			end, { desc = "Previous class start" })
			vim.keymap.set({ "x", "o" }, "af", function()
				require("nvim-treesitter-textobjects.select").select_textobject("@function.outer", "textobjects")
			end, { desc = "Select function outer" })
			vim.keymap.set({ "x", "o" }, "if", function()
				require("nvim-treesitter-textobjects.select").select_textobject("@function.inner", "textobjects")
			end, { desc = "Select function inner" })
			vim.keymap.set({ "x", "o" }, "ac", function()
				require("nvim-treesitter-textobjects.select").select_textobject("@class.outer", "textobjects")
			end, { desc = "Select class outer" })
			vim.keymap.set({ "x", "o" }, "ic", function()
				require("nvim-treesitter-textobjects.select").select_textobject("@class.inner", "textobjects")
			end, { desc = "Select class inner" })
			vim.keymap.set({ "x", "o" }, "ap", function()
				require("nvim-treesitter-textobjects.select").select_textobject("@parameter.outer", "textobjects")
			end, { desc = "Select parameter outer" })
			vim.keymap.set({ "x", "o" }, "ip", function()
				require("nvim-treesitter-textobjects.select").select_textobject("@parameter.inner", "textobjects")
			end, { desc = "Select parameter inner" })
		end,
	},
}
