local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local filter = require("config.diagnostic_filter")
filter.setup()
filter.setup()

local namespace = vim.api.nvim_create_namespace("dotfiles-diagnostic-filter-test")
local buffers = {}
for _, filetype in ipairs({ "lua", "terraform", "yaml" }) do
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].filetype = filetype
	buffers[#buffers + 1] = bufnr

	vim.diagnostic.set(namespace, bufnr, {
		{
			lnum = 0,
			col = 0,
			message = "Line too long (121 > 120 characters)",
			code = "line-length",
			source = "yamllint",
		},
		{ lnum = 1, col = 0, message = "opaque Ruff message", code = "E501" },
		{ lnum = 2, col = 0, message = "opaque markdownlint message", code = "MD013" },
		{
			lnum = 3,
			col = 0,
			message = "opaque LSP message",
			user_data = { lsp = { code = "C0301" } },
		},
		{ lnum = 4, col = 0, message = "Line too long without a diagnostic code", source = "test" },
		{ lnum = 5, col = 0, message = "Line length must be a positive integer", source = "schema" },
		{ lnum = 6, col = 0, message = "real diagnostic", source = "test" },
	})

	local diagnostics = vim.diagnostic.get(bufnr)
	assert(#diagnostics == 3, filetype .. " must hide line-length diagnostic codes: " .. vim.inspect(diagnostics))
	assert(
		diagnostics[1].message == "Line too long without a diagnostic code",
		"message text must not control filtering"
	)
	assert(diagnostics[2].message == "Line length must be a positive integer", "unrelated line-length text was hidden")
	assert(diagnostics[3].message == "real diagnostic", "ordinary diagnostics must remain")
end

vim.diagnostic.set(namespace, buffers[1], {
	{ lnum = 0, col = 0, message = "opaque diagnostic", code = "max-line-length", source = "test" },
})
assert(#vim.diagnostic.get(buffers[1]) == 0, "an ignored-only update must clear the namespace")

print("global line-length diagnostic filter regression: ok")
