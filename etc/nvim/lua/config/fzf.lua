local uv = vim.uv or vim.loop

local catppuccin = require("config.catppuccin")

local M = {}

local function joinpath(...)
	return vim.fs.joinpath(...)
end

local function source_file()
	local source = debug.getinfo(1, "S").source:sub(2)
	return uv.fs_realpath(source) or source
end

local function etc_dir()
	return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source_file())))
end

function M.theme_basename(flavour)
	return ("catppuccin-fzf-%s.rc"):format(flavour or catppuccin.flavour)
end

function M.theme_file(flavour)
	local basename = M.theme_basename(flavour)
	local bundled_theme = joinpath(etc_dir(), "fzf", "themes", basename)
	if uv.fs_stat(bundled_theme) then
		return bundled_theme
	end

	return joinpath(vim.fn.expand("~"), ".config", "fzf", "themes", basename)
end

function M.color_spec(opts)
	opts = opts or {}

	local parts = {}
	for _, line in ipairs(vim.fn.readfile(M.theme_file(opts.flavour))) do
		line = vim.trim(line)
		if line ~= "" and not line:match("^#") then
			line = line:gsub("^%-%-color=", "")
			for segment in line:gmatch("[^,]+") do
				local color = segment
				if opts.transparent_background and color:match("^bg:") then
					color = "bg:-1"
				end
				table.insert(parts, color)
			end
		end
	end

	return table.concat(parts, ",")
end

function M.ui_opts()
	return {
		["--info"] = "inline-right",
	}
end

return M
