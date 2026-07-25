local M = {}

local function suspend_inlay_hints(bufnr)
	local inlay_hint = vim.lsp and vim.lsp.inlay_hint
	if not inlay_hint or type(inlay_hint.is_enabled) ~= "function" or type(inlay_hint.enable) ~= "function" then
		return nil
	end

	local filter = { bufnr = bufnr }
	local checked, enabled = pcall(inlay_hint.is_enabled, filter)
	if not checked or not enabled then
		return nil
	end

	local suspended = pcall(inlay_hint.enable, false, filter)
	return suspended and inlay_hint or nil
end

function M.checktime(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return false, "buffer is not loaded"
	end

	-- Neovim 0.12 may render cached hints against a shorter externally
	-- reloaded line. Clear them before :checktime can redraw the buffer.
	local inlay_hint = suspend_inlay_hints(bufnr)
	local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
		vim.cmd("silent checktime")
	end)

	if inlay_hint and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
		pcall(inlay_hint.enable, true, { bufnr = bufnr })
	end

	return ok, err
end

return M
