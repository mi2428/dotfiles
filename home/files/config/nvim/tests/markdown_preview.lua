local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
vim.opt.runtimepath:prepend(nvim_root)
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local preview = require("config.markdown_preview")
preview.setup()

local function shell_command(argv)
	return table.concat(
		vim.tbl_map(function(arg)
			return vim.fn.shellescape(arg)
		end, argv),
		" "
	)
end

assert(vim.g.mkdp_open_to_the_world == 0, "Markdown preview must not listen on the public interface")
assert(vim.g.mkdp_open_ip == "127.0.0.1", "Markdown preview must bind to localhost")
assert(vim.g.mkdp_auto_start == 0 and vim.g.mkdp_auto_close == 0, "Markdown preview must not manage its own lifecycle")
assert(
	vim.g.mkdp_combine_preview == 1 and vim.g.mkdp_combine_preview_auto_refresh == 1,
	"Markdown preview must reuse one preview"
)
assert(vim.g.mkdp_theme == "dark", "Markdown preview must use the dark theme")
assert(vim.g.mkdp_preview_options.disable_sync_scroll == 0, "Markdown preview must enable sync scroll")
assert(vim.g.mkdp_preview_options.sync_scroll_type == "middle", "Markdown preview must sync from the middle")
assert(vim.g.mkdp_preview_options.maid.theme == "dark", "Markdown preview Mermaid theme must be dark")
assert(
	vim.g.mkdp_browserfunc == "DotfilesMarkdownPreviewBrowser",
	"Markdown browser function must use the dotfiles bridge"
)
assert(
	vim.fs.basename(vim.g.mkdp_markdown_css) == "markdown-preview.css",
	"Markdown preview CSS path must use the preview stylesheet"
)
assert(
	vim.fs.basename(vim.g.mkdp_highlight_css) == "markdown-preview-highlight.css",
	"Markdown highlight CSS path must use the preview highlight stylesheet"
)
assert(vim.fn.filereadable(vim.g.mkdp_markdown_css) == 1, "Markdown preview CSS must exist")
assert(vim.fn.filereadable(vim.g.mkdp_highlight_css) == 1, "Markdown highlight CSS must exist")

local markdown_buf = vim.api.nvim_create_buf(false, true)
vim.bo[markdown_buf].filetype = "markdown"
assert(preview.is_markdown_buffer(markdown_buf), "markdown buffers must be supported")

local big_markdown_buf = vim.api.nvim_create_buf(false, true)
vim.bo[big_markdown_buf].filetype = "bigfile"
vim.b[big_markdown_buf].dotfiles_bigfile_original_filetype = "markdown"
assert(preview.is_markdown_buffer(big_markdown_buf), "bigfile Markdown buffers must be supported")

local generic_bigfile_buf = vim.api.nvim_create_buf(false, true)
vim.bo[generic_bigfile_buf].filetype = "bigfile"
vim.b[generic_bigfile_buf].dotfiles_bigfile_original_filetype = "lua"
assert(not preview.is_markdown_buffer(generic_bigfile_buf), "generic bigfile buffers must not be supported")

local fake_dir = vim.fn.tempname()
local argv_file = vim.fs.joinpath(fake_dir, "argv")
local fake_browser = vim.fs.joinpath(fake_dir, "terminal-browser")
vim.fn.mkdir(fake_dir, "p")
vim.fn.writefile({
	"#!/bin/sh",
	"printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(argv_file),
}, fake_browser)
vim.fn.setfperm(fake_browser, "rwx------")

local original_path = vim.env.PATH
local original_term_program = vim.env.TERM_PROGRAM
local original_tmux = vim.env.TMUX
local original_herdr_env = vim.env.HERDR_ENV
local ok, err = xpcall(function()
	vim.env.PATH = fake_dir .. ":" .. original_path
	vim.env.TERM_PROGRAM = "ghostty"
	vim.env.TMUX = "/tmp/tmux-test/default,1,0"
	vim.env.HERDR_ENV = nil
	_G.DotfilesMarkdownPreviewBrowser("http://localhost:8123/page/7")
	assert(
		vim.wait(1000, function()
			return vim.fn.filereadable(argv_file) == 1
		end, 10),
		"timed out waiting for terminal-browser"
	)
	assert(
		vim.deep_equal(vim.fn.readfile(argv_file), {
			"open",
			"http://localhost:8123/page/7",
			"--split",
			"right",
			"--size",
			"0.5",
		}),
		"terminal-browser arguments must preserve the preview layout contract"
	)
end, debug.traceback)
vim.env.PATH = original_path
vim.env.TERM_PROGRAM = original_term_program
vim.env.TMUX = original_tmux
vim.env.HERDR_ENV = original_herdr_env
vim.fn.delete(fake_dir, "rf")
assert(ok, err)

local ghostty_dir = vim.fn.tempname()
local ghostty_argv_file = vim.fs.joinpath(ghostty_dir, "osascript-argv")
local ghostty_script_file = vim.fs.joinpath(ghostty_dir, "osascript-stdin")
local ghostty_close_argv_file = vim.fs.joinpath(ghostty_dir, "close-argv")
local ghostty_close_script_file = vim.fs.joinpath(ghostty_dir, "close-stdin")
local ghostty_tty = vim.fs.joinpath(ghostty_dir, "tty")
local ghostty_browser = vim.fs.joinpath(ghostty_dir, "terminal-browser")
local fake_ps = vim.fs.joinpath(ghostty_dir, "ps")
local fake_osascript = vim.fs.joinpath(ghostty_dir, "osascript")
local fake_mkdp_autoload = vim.fs.joinpath(ghostty_dir, "autoload/mkdp/util.vim")
vim.fn.mkdir(ghostty_dir, "p")
vim.fn.mkdir(vim.fs.dirname(fake_mkdp_autoload), "p")
vim.fn.writefile({}, ghostty_tty)
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, ghostty_browser)
vim.fn.writefile({
	"function! mkdp#util#toggle_preview() abort",
	"  let b:MarkdownPreviewToggleBool = 0",
	"endfunction",
}, fake_mkdp_autoload)
vim.fn.writefile({
	"#!/bin/sh",
	'if [ "$4" = ' .. vim.fn.shellescape(tostring(vim.fn.getpid())) .. " ]; then",
	"  printf '%s\\n' '4242 ??'",
	"else",
	"  printf '%s\\n' " .. vim.fn.shellescape("1 " .. ghostty_tty),
	"fi",
}, fake_ps)
vim.fn.writefile({
	"#!/bin/sh",
	"if [ \"$2\" = 'ghostty-test-pane' ]; then",
	"  /bin/cat > " .. vim.fn.shellescape(ghostty_close_script_file),
	"  printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(ghostty_close_argv_file),
	"else",
	"  /bin/cat > " .. vim.fn.shellescape(ghostty_script_file),
	"  printf '%s\\n' \"$@\" > " .. vim.fn.shellescape(ghostty_argv_file),
	"  printf '%s\\n' 'ghostty-test-pane'",
	"fi",
}, fake_osascript)
vim.fn.setfperm(ghostty_browser, "rwx------")
vim.fn.setfperm(fake_ps, "rwx------")
vim.fn.setfperm(fake_osascript, "rwx------")

local original_cmux_bundle_id = vim.env.CMUX_BUNDLE_ID
local original_buf = vim.api.nvim_get_current_buf()
local ghostty_ok, ghostty_err = xpcall(function()
	vim.env.PATH = ghostty_dir .. ":" .. original_path
	vim.opt.runtimepath:prepend(ghostty_dir)
	vim.env.TERM_PROGRAM = "ghostty"
	vim.env.TMUX = nil
	vim.env.HERDR_ENV = nil
	vim.env.CMUX_BUNDLE_ID = nil
	_G.DotfilesMarkdownPreviewBrowser("http://localhost:8123/page/8")
	assert(
		vim.wait(2000, function()
			return vim.fn.filereadable(ghostty_argv_file) == 1
		end, 10),
		"timed out waiting for the Ghostty split"
	)

	local argv = vim.fn.readfile(ghostty_argv_file)
	assert(argv[1] == "-", "osascript must read the Ghostty split script from stdin")
	assert(argv[2]:match("^markdown%-preview%-%d+%-%d+$"), "Ghostty pane marker is invalid")
	assert(argv[3] == shell_command({
		ghostty_browser,
		"open",
		"http://localhost:8123/page/8",
		"--split-dir=right",
		"--parent-tty=" .. ghostty_tty,
	}), "Ghostty must launch terminal-browser as the split command")
	assert(argv[4] == vim.fn.getcwd(), "Ghostty split must preserve Neovim's working directory")

	local script = table.concat(vim.fn.readfile(ghostty_script_file), "\n")
	assert(script:find("configuration {command:cmdText", 1, true), "Ghostty split must use the command API")
	assert(not script:find("initial input", 1, true), "Ghostty split must not race the login shell with initial input")
	local tty_contents = table.concat(vim.fn.readfile(ghostty_tty, "b"), "\n")
	assert(tty_contents:find(argv[2], 1, true), "Ghostty pane marker must be written to the parent TTY")

	vim.wait(100)
	vim.api.nvim_set_current_buf(markdown_buf)
	vim.b[markdown_buf].MarkdownPreviewToggleBool = 1
	preview.toggle()
	assert(
		vim.wait(2000, function()
			return vim.fn.filereadable(ghostty_close_argv_file) == 1
		end, 10),
		"timed out waiting for the Ghostty preview pane to close"
	)
	assert(
		vim.deep_equal(vim.fn.readfile(ghostty_close_argv_file), { "-", "ghostty-test-pane" }),
		"Markdown preview toggle must close its Ghostty pane"
	)
	assert(
		table.concat(vim.fn.readfile(ghostty_close_script_file), "\n"):find("close term", 1, true),
		"Ghostty close script must close the matched terminal"
	)
end, debug.traceback)
vim.env.PATH = original_path
vim.env.TERM_PROGRAM = original_term_program
vim.env.TMUX = original_tmux
vim.env.HERDR_ENV = original_herdr_env
vim.env.CMUX_BUNDLE_ID = original_cmux_bundle_id
vim.api.nvim_set_current_buf(original_buf)
vim.opt.runtimepath:remove(ghostty_dir)
pcall(vim.cmd, "delfunction mkdp#util#toggle_preview")
vim.fn.delete(ghostty_dir, "rf")
assert(ghostty_ok, ghostty_err)

local lazy = package.loaded["lazy"]
if not lazy then
	local lazy_ok, loaded_lazy = pcall(require, "lazy")
	if lazy_ok then
		lazy = loaded_lazy
	end
end
if lazy then
	local original_buf = vim.api.nvim_get_current_buf()
	local original_browser = _G.DotfilesMarkdownPreviewBrowser
	local captured_url
	local integration_ok, integration_err = xpcall(function()
		lazy.load({ plugins = { "markdown-preview.nvim" } })
		vim.api.nvim_set_current_buf(markdown_buf)
		_G.DotfilesMarkdownPreviewBrowser = function(url)
			captured_url = url
		end
		vim.fn["mkdp#util#open_preview_page"]()
		vim.wait(1000)
		vim.fn["mkdp#util#open_preview_page"]()
		assert(
			vim.wait(8000, function()
				return captured_url ~= nil
			end, 20),
			"timed out waiting for Markdown preview URL"
		)
		assert(captured_url:match("^http://127%.0%.0%.1:%d+/page/"), "preview URL must use localhost page path")
		local curl_result
		vim.system({ "curl", "-fsS", "--max-time", "5", captured_url }, { text = true }, function(result)
			curl_result = result
		end)
		assert(
			vim.wait(10000, function()
				return curl_result ~= nil
			end, 20),
			"timed out retrieving the Markdown preview page"
		)
		assert(curl_result.code == 0, "curl must retrieve the Markdown preview page")
		assert(curl_result.stdout:find('id="__next"', 1, true), "preview HTML marker is missing")
	end, debug.traceback)
	local cleanup_ok, cleanup_err = pcall(function()
		vim.fn["mkdp#util#stop_preview"]()
	end)
	_G.DotfilesMarkdownPreviewBrowser = original_browser
	if vim.api.nvim_buf_is_valid(original_buf) then
		vim.api.nvim_set_current_buf(original_buf)
	end
	assert(integration_ok, integration_err)
	assert(cleanup_ok, cleanup_err)
end

vim.api.nvim_buf_delete(markdown_buf, { force = true })
vim.api.nvim_buf_delete(big_markdown_buf, { force = true })
vim.api.nvim_buf_delete(generic_bigfile_buf, { force = true })
print("markdown preview: ok")
