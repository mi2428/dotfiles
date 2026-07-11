local config_root = vim.fn.stdpath("config")

package.path = table.concat({
  config_root .. "/lua/?.lua",
  config_root .. "/lua/?/init.lua",
  package.path,
}, ";")

require("config")
