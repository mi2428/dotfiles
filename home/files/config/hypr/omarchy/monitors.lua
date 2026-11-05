-- Keep the native 120 Hz mode, with macOS's 2704 x 1756 logical size (rounded).
-- This scale needs fractional logical pixels, which Hyprland otherwise rejects.
hl.config({ debug = { disable_scale_checks = true } })
hl.monitor({ output = "eDP-1", mode = "3024x1964@120", position = "0x0", scale = 3024 / 2704 })
-- Restart existing GTK/XWayland apps to pick up this environment change.
hl.env("GDK_SCALE", "1")
