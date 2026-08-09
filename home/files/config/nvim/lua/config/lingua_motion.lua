local M = {}

function M.setup()
	if vim.uv.os_uname().sysname ~= "Darwin" then
		return
	end

	vim.cmd.packadd("lingua-motion.nvim")
	local lingua_motion = require("lingua_motion")
	lingua_motion.setup({ timeout_ms = 500 })
	vim.keymap.set("n", "cw", "ce", { remap = true, desc = "Change word" })
	vim.api.nvim_create_user_command("Wakachigaki", function(args)
		local view = vim.fn.winsaveview()
		local lines = vim.api.nvim_buf_get_lines(0, args.line1 - 1, args.line2, false)
		local changed = false

		for index, line in ipairs(lines) do
			local row = args.line1 + index - 1
			local boundaries = {}
			local previous_column = -1
			vim.api.nvim_win_set_cursor(0, { row, 0 })
			for _ = 1, #line do
				lingua_motion.motion("w")
				local cursor = vim.api.nvim_win_get_cursor(0)
				if cursor[1] ~= row or cursor[2] <= previous_column then
					break
				end
				previous_column = cursor[2]
				boundaries[#boundaries + 1] = cursor[2]
			end

			for boundary_index = #boundaries, 1, -1 do
				local column = boundaries[boundary_index]
				local prefix = line:sub(1, column)
				local previous_character = vim.fn.strcharpart(prefix, vim.fn.strchars(prefix) - 1, 1)
				if column > 0 and column < #line and vim.fn.charclass(previous_character) ~= 0 then
					line = prefix .. " " .. line:sub(column + 1)
					changed = true
				end
			end
			lines[index] = line
		end

		vim.fn.winrestview(view)
		if changed then
			vim.api.nvim_buf_set_lines(0, args.line1 - 1, args.line2, false, lines)
		end
	end, { range = true, desc = "Separate text at Lingua word boundaries" })
end

return M
