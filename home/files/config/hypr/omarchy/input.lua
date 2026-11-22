hl.config({
  input = {
    -- Match Karabiner: Caps Lock becomes Control; left Control is unchanged.
    kb_options = "ctrl:nocaps",
    sensitivity = 0.8,
    -- Hyprland caps input:scroll_factor and input:touchpad:scroll_factor at 2.0,
    -- so the real rate for the trackpad is the device factor below.
    scroll_factor = 2.0,
    touchpad = { natural_scroll = true, scroll_factor = 2.0 },
  },
})

hl.device({
  name = "apple-mtp-multi-touch",
  disable_while_typing = true,
  -- Tap-dragging bypasses libinput's typing suppression; physical dragging stays enabled.
  tap_and_drag = false,
  accel_profile = "adaptive",
  -- Per-device scroll factor: overrides both input:* factors and accepts up to
  -- 100. 3.0 is twice the rate that still felt slow at 1.5.
  scroll_factor = 3.0,
})

-- Terminals keep their own window rules because Omarchy tunes each one for its
-- internal multiplier: Ghostty scales precise (touchpad) deltas 10x before
-- converting them to lines, while Alacritty, kitty, and foot consume them as
-- pixels. 0.3 cancels Ghostty's boost at the 3.0 app rate below; mouse wheel is
-- unchanged internally, so both paths stay equal to Chromium's 3.0.
local function app_scroll(class, title, touchpad)
  o.window(class, { scroll_touchpad = touchpad, scroll_mouse = 3.0 })
  o.window({ class = "(org\\.omarchy\\..*|TUI\\.*)", initial_title = title }, { scroll_touchpad = touchpad, scroll_mouse = 3.0 })
end

app_scroll("(Alacritty|kitty)", "(Alacritty|kitty)", 3.0)
app_scroll("foot", "foot", 3.0)
app_scroll("com.mitchellh.ghostty", "Ghostty", 0.3)
