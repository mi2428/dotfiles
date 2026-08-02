local M = {}

function M.cycle(command)
	vim.cmd.redrawtabline()
	local ok, state = pcall(require, "bufferline.state")
	local current = vim.api.nvim_get_current_buf()
	local visible_components = ok and state.components or nil
	if type(visible_components) == "table" then
		for _, component in ipairs(visible_components) do
			if type(component) == "table" and component.id == current then
				vim.cmd(command)
				return
			end
		end
	end

	local components = ok and state.__components or nil
	if type(components) == "table" then
		local buffers = {}
		for _, component in ipairs(components) do
			if type(component) == "table" and type(component.as_element) == "function" then
				local extracted, element = pcall(component.as_element, component)
				if
					extracted
					and type(element) == "table"
					and element.type == "buffer"
					and type(element.id) == "number"
					and vim.api.nvim_buf_is_valid(element.id)
				then
					buffers[#buffers + 1] = element.id
				end
			end
		end
		for index, bufnr in ipairs(buffers) do
			if bufnr == current and #buffers > 1 then
				local direction = command == "BufferLineCyclePrev" and -1 or 1
				vim.api.nvim_win_set_buf(0, buffers[((index - 1 + direction) % #buffers) + 1])
				return
			end
		end
	end
	vim.cmd(command)
end

return M
