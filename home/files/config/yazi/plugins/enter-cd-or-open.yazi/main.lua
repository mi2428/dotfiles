local get_hovered = ya.sync(function()
	local hovered = cx.active.current.hovered
	if not hovered then
		return nil
	end

	return { url = hovered.url, is_dir = hovered.cha.is_dir }
end)

local function entry()
	local hovered = get_hovered()
	if not hovered then
		return
	end

	if hovered.is_dir then
		ya.emit("cd", { hovered.url })
		if os.getenv("YAZI_POPUP") ~= "1" then
			ya.emit("quit", {})
		end
	elseif os.getenv("YAZI_POPUP") == "1" then
		local helper = os.getenv("YAZI_TMUX_OPEN")
		local source_pane = os.getenv("TMUX_YAZI_SOURCE_PANE")
		if not helper or not source_pane then
			ya.emit("open", { hovered = true })
			return
		end

		local status, err = Command(helper):arg({ source_pane, tostring(hovered.url) }):status()
		if not status then
			ya.notify({ title = "Yazi", content = tostring(err), level = "error", timeout = 5 })
			return
		end
		if not status.success then
			ya.notify({ title = "Yazi", content = "Failed to open file", level = "error", timeout = 5 })
			return
		end

		ya.emit("quit", {})
	else
		ya.emit("open", { hovered = true })
	end
end

return { entry = entry }
