local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local ui = require("config.noice_ui")
vim.o.hlsearch = true
vim.fn.setreg("/", "needle")

local function percentile(values, fraction)
	table.sort(values)
	return values[math.max(1, math.ceil(#values * fraction))]
end

local function benchmark(line_count, iterations, match_interval)
	match_interval = match_interval or 200
	local buf = vim.api.nvim_create_buf(false, true)
	local lines = {}
	for index = 1, line_count do
		lines[index] = index % match_interval == 0 and "prefix needle suffix" or "ordinary fixture text"
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_win_set_cursor(0, { 200, 7 })
	vim.fn.searchcount({ recompute = true, maxcount = vim.o.maxsearchcount, timeout = ui.search_count_timeout_ms })

	local raw = {}
	local wrapped = {}
	for _ = 1, iterations do
		local started = vim.uv.hrtime()
		vim.fn.searchcount({ recompute = true, maxcount = vim.o.maxsearchcount, timeout = ui.search_count_timeout_ms })
		raw[#raw + 1] = (vim.uv.hrtime() - started) / 1e6

		started = vim.uv.hrtime()
		ui.evaluate_search_count()
		wrapped[#wrapped + 1] = (vim.uv.hrtime() - started) / 1e6
	end

	local raw_p95 = percentile(raw, 0.95)
	local wrapped_p95 = percentile(wrapped, 0.95)
	assert(
		wrapped_p95 <= raw_p95 * 1.25 + 2,
		("wrapper overhead too high at %d lines: raw %.2fms, wrapped %.2fms"):format(line_count, raw_p95, wrapped_p95)
	)
	assert(
		wrapped_p95 < 75,
		("a single debounced refresh is too expensive at %d lines: %.2fms"):format(line_count, wrapped_p95)
	)

	local no_hit_ms
	if line_count == 1000000 then
		vim.fn.setreg("/", "definitely-absent-search-pattern")
		local started = vim.uv.hrtime()
		local count = ui.evaluate_search_count()
		no_hit_ms = (vim.uv.hrtime() - started) / 1e6
		assert(count == nil, "a no-hit scan must not produce a search chip")
		assert(no_hit_ms < 75, ("the one-million-line no-hit scan was unexpectedly slow: %.2fms"):format(no_hit_ms))
		vim.fn.setreg("/", "needle")
	end

	vim.api.nvim_buf_delete(buf, { force = true })
	return raw_p95, wrapped_p95, no_hit_ms
end

local raw_10k, wrapped_10k = benchmark(10000, 30)
local raw_100k, wrapped_100k = benchmark(100000, 15)
local raw_1m, wrapped_1m, no_hit_1m = benchmark(1000000, 5, 2000)
print(
	("Noice search performance: ok (p95 raw/wrapped: 10k %.2f/%.2fms, 100k %.2f/%.2fms, 1m %.2f/%.2fms; 1m no-hit %.2fms)"):format(
		raw_10k,
		wrapped_10k,
		raw_100k,
		wrapped_100k,
		raw_1m,
		wrapped_1m,
		no_hit_1m
	)
)
