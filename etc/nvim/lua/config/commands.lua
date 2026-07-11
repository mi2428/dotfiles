vim.api.nvim_create_user_command("SudoWriteCurrentBuffer", function()
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		vim.notify("No file name for current buffer", vim.log.levels.ERROR)
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local content = table.concat(lines, "\n")

	if vim.bo.endofline then
		content = content .. "\n"
	end

	local result = vim.fn.system({ "sudo", "tee", file }, content)
	if vim.v.shell_error ~= 0 then
		vim.notify(result, vim.log.levels.ERROR)
		return
	end

	vim.cmd.edit()
end, {})
