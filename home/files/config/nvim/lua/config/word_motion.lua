local M = {}

local function same_position(left, right)
	return left[1] == right[1] and left[2] == right[2]
end

function M.motion(key)
	local before = vim.api.nvim_win_get_cursor(0)
	require("spider").motion(key)

	-- Spider currently cannot identify CJK-only words, even with its optional
	-- UTF-8 dependency. Preserve Neovim's native motion whenever Spider cannot
	-- find a destination instead of leaving `w`/`e`/`b`/`ge` stuck in place.
	if same_position(before, vim.api.nvim_win_get_cursor(0)) then
		local count = vim.v.count > 0 and tostring(vim.v.count) or ""
		vim.cmd.normal({ count .. key, bang = true })
	end
end

return M
