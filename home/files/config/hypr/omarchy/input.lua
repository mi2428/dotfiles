hl.config({
  input = {
    -- Match Karabiner: Caps Lock becomes Control; left Control is unchanged.
    kb_options = "ctrl:nocaps",
    touchpad = { natural_scroll = true },
  },
})

hl.device({
  name = "apple-mtp-multi-touch",
  -- libinput's maximum speed. Tune here if macOS's acceleration feels different.
  sensitivity = 1.0,
  accel_profile = "adaptive",
})
