-- Use Omarchy's input-language switcher instead of its terminal-prefix pass-through.
o.rebind("CTRL + SPACE", "Toggle Japanese input", "omarchy-input-method cycle")

-- Use Omarchy's down/up pattern to avoid stuck synthetic keys.
local function send_key(mods, key)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
  hl.timer(function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
  end, { timeout = 50, type = "oneshot" })
end

-- Physical US semicolon: change only the unmodified and Shift combinations.
hl.bind("code:47", function() send_key("SHIFT", "code:47") end, { repeating = true })
hl.bind("SHIFT + code:47", function() send_key("", "code:47") end, { repeating = true })

-- Preserve Omarchy's left Command actions; only right Command sends arrows.
-- Modified Command chords keep Omarchy's defaults.
local arrows = { H = "Left", J = "Down", K = "Up", L = "Right" }
local left_command = {
  H = function() send_key("SUPER", "H") end,
  J = hl.dsp.layout("togglesplit"),
  K = hl.dsp.exec_cmd("omarchy-menu-keybindings"),
  L = hl.dsp.exec_cmd("omarchy-hyprland-workspace-layout-toggle"),
}
local left_fired = {}
local keycodes = { [43] = "H", [44] = "J", [45] = "K", [46] = "L" }
hl.on("input.keyboard.key", function(code, _, state)
  if state == 0 and keycodes[code] then left_fired[keycodes[code]] = nil end
end)
for key, arrow in pairs(arrows) do
  o.rebind("SUPER + " .. key, "Right Command + " .. key .. " arrow", function()
    if hl.is_key_down("Super_R") then
      send_key("", arrow)
    elseif key == "H" or not left_fired[key] then
      -- Omarchy's actions must stay single-shot while arrows support key repeat.
      left_fired[key] = true
      hl.dispatch(left_command[key])
    end
  end, { repeating = true })
end
