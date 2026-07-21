--- @sync entry

local function entry()
	local hovered = cx.active.current.hovered
	if not hovered then
		return
	end

	if hovered.cha.is_dir then
		ya.emit("cd", { hovered.url })
		if os.getenv("YAZI_POPUP") ~= "1" then
			ya.emit("quit", {})
		end
	else
		ya.emit("open", { hovered = true })
	end
end

return { entry = entry }
