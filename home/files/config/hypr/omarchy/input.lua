hl.config({
  input = {
    -- Match Karabiner: Caps Lock becomes Control; left Control is unchanged.
    kb_options = "ctrl:nocaps",
    touchpad = { natural_scroll = true },
  },
})

hl.device({
  name = "apple-mtp-multi-touch",
  disable_while_typing = true,
  -- Tap-dragging bypasses libinput's typing suppression; physical dragging stays enabled.
  tap_and_drag = false,
  -- libinput's maximum speed. Tune here if macOS's acceleration feels different.
  sensitivity = 1.0,
  accel_profile = "adaptive",
})
