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

-- M2 Pro reports the internal trackpad as apple-mtp-multi-touch; M1 Pro as
-- apple-spi-trackpad, so the same per-device tuning covers both machines.
local function configure_trackpad(name)
  hl.device({
    name = name,
    disable_while_typing = true,
    -- Tap-dragging bypasses libinput's typing suppression; physical dragging stays enabled.
    tap_and_drag = false,
    accel_profile = "adaptive",
    -- Touchpad-only cursor speed. libinput's touchpad speed factor is
    -- pow(s + 1, 2.38) * 0.95 + 0.05, so 0.5637 is 0.8x the old 0.72.
    sensitivity = 0.5637,
    -- Per-device scroll factor: overrides both input:* factors and accepts up to
    -- 100. 1.3824 is 0.8x the previous 1.728 for non-terminal apps.
    scroll_factor = 1.3824,
  })
end

configure_trackpad("apple-mtp-multi-touch")
configure_trackpad("apple-spi-trackpad")

-- Terminals keep their own window rules because Omarchy tunes each one for its
-- internal multiplier: Ghostty scales precise (touchpad) deltas 10x before
-- converting them to lines, while Alacritty, kitty, and foot consume them as
-- pixels. 0.58212 cancels Ghostty's boost at the 5.8212 terminal rate below; the
-- mouse wheel stays at 3.0, so only touchpad scrolling is retuned.
local function app_scroll(class, title, touchpad)
  o.window(class, { scroll_touchpad = touchpad, scroll_mouse = 3.0 })
  o.window({ class = "(org\\.omarchy\\..*|TUI\\.*)", initial_title = title }, { scroll_touchpad = touchpad, scroll_mouse = 3.0 })
end

app_scroll("(Alacritty|kitty)", "(Alacritty|kitty)", 5.8212)
app_scroll("foot", "foot", 5.8212)
app_scroll("com.mitchellh.ghostty", "Ghostty", 0.58212)
