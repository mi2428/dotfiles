local M = {}

function M.setup()
	if vim.uv.os_uname().sysname ~= "Darwin" then
		return
	end

	vim.cmd.packadd("lingua-motion.nvim")
	require("lingua_motion").setup({ timeout_ms = 500 })
	vim.keymap.set("n", "cw", "ce", { remap = true, desc = "Change word" })
end

return M
