local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

config.color_scheme = "Gruvbox Dark (Gogh)"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = 15.0
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"
config.initial_cols = 150
config.initial_rows = 50
config.window_close_confirmation = "NeverPrompt"

-- WezTerm sends Option+Left/Right as xterm ESC[1;3D/C, which shells leave unbound
-- (typing a literal ";3D"); send Alt-b/Alt-f instead, the word jump every line
-- editor binds, matching Terminal.app. Cmd+Left/Right has no binding at all, so
-- send Ctrl-a/Ctrl-e (line start/end), like iTerm2's "Natural Text Editing".
config.keys = {
  { key = "LeftArrow", mods = "OPT", action = act.SendKey({ key = "b", mods = "ALT" }) },
  { key = "RightArrow", mods = "OPT", action = act.SendKey({ key = "f", mods = "ALT" }) },
  { key = "LeftArrow", mods = "CMD", action = act.SendKey({ key = "a", mods = "CTRL" }) },
  { key = "RightArrow", mods = "CMD", action = act.SendKey({ key = "e", mods = "CTRL" }) },
}

return config
