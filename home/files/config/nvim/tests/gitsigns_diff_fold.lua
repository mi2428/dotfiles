local worktree = assert(vim.env.NVIM_FOLD_TEST_WORKTREE, "NVIM_FOLD_TEST_WORKTREE is required")
local relative_file = vim.env.NVIM_FOLD_TEST_FILE or "docker/prometheus/internal/config/render.go"
local target = vim.fs.joinpath(worktree, relative_file)

assert(vim.uv.fs_stat(target), "fold regression target is missing: " .. target)

local function git(args)
	local result = vim.system(vim.list_extend({ "git", "-C", worktree }, args), { text = true }):wait()
	assert(result.code == 0, vim.trim(result.stderr or result.stdout or "git command failed"))
	return vim.trim(result.stdout or "")
end

local expected_base = vim.env.NVIM_FOLD_TEST_BASE
if not expected_base or expected_base == "" then
	expected_base = git({ "merge-base", assert(vim.env.NVIM_REVIEW_BASE), assert(vim.env.NVIM_REVIEW_HEAD) })
end
expected_base = git({ "rev-parse", expected_base })

vim.cmd.edit(vim.fn.fnameescape(target))
local main_buf = vim.api.nvim_get_current_buf()

assert(
	vim.wait(5000, function()
		local cache = package.loaded["gitsigns.cache"]
		local entry = cache and cache.cache[main_buf]
		return entry ~= nil and entry.git_obj.revision == expected_base
	end, 20),
	"Gitsigns did not attach the worktree buffer with the configured review base"
)

require("lazy").load({ plugins = { "nvim-ufo" } })
local ufo = require("ufo")
assert(
	vim.wait(3000, function()
		return ufo.hasAttached(main_buf)
	end, 20),
	"nvim-ufo did not attach the worktree buffer"
)

local function diff_windows()
	local revision
	local main
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.wo[win].diff then
			local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
			if vim.startswith(name, "gitsigns://") then
				revision = win
			elseif vim.api.nvim_win_get_buf(win) == main_buf then
				main = win
			end
		end
	end
	return revision, main
end

local function closed_ranges(win)
	return vim.api.nvim_win_call(win, function()
		local ranges = {}
		local line = 1
		local line_count = vim.api.nvim_buf_line_count(0)
		while line <= line_count do
			local first = vim.fn.foldclosed(line)
			if first == line then
				local last = vim.fn.foldclosedend(line)
				ranges[#ranges + 1] = { first, last }
				line = last + 1
			else
				line = line + 1
			end
		end
		return ranges
	end)
end

local function filler_map(win)
	return vim.api.nvim_win_call(win, function()
		local fillers = {}
		for line = 1, vim.api.nvim_buf_line_count(0) + 1 do
			fillers[line] = vim.fn.diff_filler(line)
		end
		return fillers
	end)
end

local function display_rows(win)
	return vim.api.nvim_win_call(win, function()
		local rows = {}
		local row = 0
		local line = 1
		local line_count = vim.api.nvim_buf_line_count(0)
		while line <= line_count do
			row = row + vim.fn.diff_filler(line)
			local first = vim.fn.foldclosed(line)
			if first == line then
				local last = vim.fn.foldclosedend(line)
				row = row + 1
				for folded = line, last do
					rows[folded] = row
				end
				line = last + 1
			else
				row = row + 1
				rows[line] = row
				line = line + 1
			end
		end
		row = row + vim.fn.diff_filler(line_count + 1)
		return { height = row, rows = rows }
	end)
end

local function unique_trimmed_line(buf, text)
	local found
	for line, value in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if vim.trim(value) == text then
			assert(found == nil, "alignment anchor is not unique: " .. text)
			found = line
		end
	end
	return assert(found, "alignment anchor is missing: " .. text)
end

local function snapshot(revision, main)
	local revision_display = display_rows(revision)
	local main_display = display_rows(main)
	local anchor = vim.env.NVIM_FOLD_TEST_ANCHOR or "taskIndex, replicaCount := GlobalShardingInfo.GetShardingParams()"
	local revision_anchor = unique_trimmed_line(vim.api.nvim_win_get_buf(revision), anchor)
	local main_anchor = unique_trimmed_line(vim.api.nvim_win_get_buf(main), anchor)
	return {
		anchor_rows = { revision_display.rows[revision_anchor], main_display.rows[main_anchor] },
		display_heights = { revision_display.height, main_display.height },
		revision_folds = closed_ranges(revision),
		main_folds = closed_ranges(main),
		revision_filler = filler_map(revision),
		main_filler = filler_map(main),
	}
end

require("gitsigns").diffthis(nil, { vertical = true })
assert(
	vim.wait(3000, function()
		local revision, main = diff_windows()
		if revision == nil or main == nil or #closed_ranges(revision) == 0 or #closed_ranges(main) == 0 then
			return false
		end
		local current = snapshot(revision, main)
		return current.display_heights[1] == current.display_heights[2]
			and current.anchor_rows[1] == current.anchor_rows[2]
	end, 20),
	"Gitsigns diff did not reach its initial aligned folded state"
)

local revision, main = diff_windows()
assert(
	vim.wait(1000, function()
		return ufo.hasAttached(vim.api.nvim_win_get_buf(revision)) and ufo.hasAttached(vim.api.nvim_win_get_buf(main))
	end, 20),
	"nvim-ufo did not attach both Gitsigns diff buffers"
)
local immediate = snapshot(revision, main)
assert(#immediate.revision_folds > 0, "revision pane did not create native diff folds")
assert(#immediate.main_folds > 0, "worktree pane did not create native diff folds")
assert(immediate.display_heights[1] == immediate.display_heights[2], "initial diff display heights differ")
assert(immediate.anchor_rows[1] == immediate.anchor_rows[2], "initial unchanged anchor rows differ")
assert(vim.wo[revision].foldmethod == "diff", "revision pane must use native diff folds")
assert(vim.wo[main].foldmethod == "diff", "worktree pane must use native diff folds")
assert(vim.wo[revision].foldenable and vim.wo[main].foldenable, "both diff panes must keep folds enabled")
assert(vim.wo[revision].scrollbind and vim.wo[main].scrollbind, "both diff panes must keep scrollbind")
assert(vim.wo[revision].cursorbind and vim.wo[main].cursorbind, "both diff panes must keep cursorbind")

vim.wait(1700, function()
	return false
end, 20)

revision, main = diff_windows()
assert(revision and main, "Gitsigns diff windows disappeared during delayed lifecycle updates")
local delayed = snapshot(revision, main)
assert(
	vim.deep_equal(delayed.revision_folds, immediate.revision_folds),
	("revision native diff folds changed after delay: %s -> %s"):format(
		vim.inspect(immediate.revision_folds),
		vim.inspect(delayed.revision_folds)
	)
)
assert(vim.deep_equal(delayed.main_folds, immediate.main_folds), "worktree native diff folds changed after delay")
assert(vim.deep_equal(delayed.revision_filler, immediate.revision_filler), "revision filler map changed after delay")
assert(vim.deep_equal(delayed.main_filler, immediate.main_filler), "worktree filler map changed after delay")
assert(vim.deep_equal(delayed.display_heights, immediate.display_heights), "diff display heights changed after delay")
assert(vim.deep_equal(delayed.anchor_rows, immediate.anchor_rows), "unchanged anchor alignment changed after delay")
assert(
	vim.treesitter.highlighter.active[vim.api.nvim_win_get_buf(revision)] ~= nil,
	"revision Tree-sitter highlighter disappeared after delay"
)
assert(vim.treesitter.highlighter.active[main_buf] ~= nil, "worktree Tree-sitter highlighter disappeared after delay")
assert(
	ufo.hasAttached(vim.api.nvim_win_get_buf(revision)) and ufo.hasAttached(vim.api.nvim_win_get_buf(main)),
	"nvim-ufo detached from a Gitsigns diff buffer after delay"
)

print(
	("Gitsigns delayed diff-fold regression: ok (%d/%d stable folds)"):format(
		#delayed.revision_folds,
		#delayed.main_folds
	)
)
