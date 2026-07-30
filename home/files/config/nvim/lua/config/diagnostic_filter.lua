local M = {}

local ignored_codes = {
	c0301 = true,
	e501 = true,
	lll = true,
	md013 = true,
	["line-length"] = true,
	line_length = true,
	["max-line-length"] = true,
}

local function diagnostic_code(diagnostic)
	local code = diagnostic.code
	local lsp = type(diagnostic.user_data) == "table" and diagnostic.user_data.lsp or nil
	if code == nil and type(lsp) == "table" then
		code = lsp.code
	end
	if type(code) == "table" then
		code = code.value or code.code
	end
	return code ~= nil and tostring(code):lower() or nil
end

function M.is_ignored(diagnostic)
	local code = diagnostic_code(diagnostic)
	return code ~= nil and ignored_codes[code] == true
end

function M.filter(diagnostics)
	if type(diagnostics) ~= "table" then
		return diagnostics
	end
	return vim.tbl_filter(function(diagnostic)
		return not M.is_ignored(diagnostic)
	end, diagnostics)
end

function M.setup()
	if M.original_set then
		return
	end

	M.original_set = vim.diagnostic.set
	vim.diagnostic.set = function(namespace, bufnr, diagnostics, opts)
		return M.original_set(namespace, bufnr, M.filter(diagnostics), opts)
	end
end

return M
