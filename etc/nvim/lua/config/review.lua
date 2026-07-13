local M = {}

local entry_delimiter = "\t"
local commands_registered = false

local function git(args, cwd)
	local result = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
	if result.code ~= 0 then
		return nil, vim.trim(result.stderr or result.stdout or "")
	end

	return vim.trim(result.stdout or ""), nil
end

local function resolve_state()
	local env = vim.env
	if not env.NVIM_REVIEW_MODE or env.NVIM_REVIEW_MODE == "" or env.NVIM_REVIEW_MODE == "0" then
		return nil
	end

	local base = env.NVIM_REVIEW_BASE
	local head = env.NVIM_REVIEW_HEAD
	if not base or base == "" or not head or head == "" then
		vim.notify("Review mode requires NVIM_REVIEW_BASE and NVIM_REVIEW_HEAD", vim.log.levels.ERROR)
		return nil
	end

	local worktree = env.NVIM_REVIEW_WORKTREE
	if not worktree or worktree == "" then
		worktree = git({ "rev-parse", "--show-toplevel" }, vim.fn.getcwd())
	end
	if not worktree or worktree == "" then
		vim.notify("Review mode requires a Git worktree", vim.log.levels.ERROR)
		return nil
	end

	local merge_base, err = git({ "merge-base", base, head }, worktree)
	if not merge_base or merge_base == "" then
		vim.notify(("Unable to compute review merge-base: %s"):format(err or "unknown error"), vim.log.levels.ERROR)
		return nil
	end

	return {
		base = base,
		head = head,
		pr = env.NVIM_REVIEW_PR ~= "" and env.NVIM_REVIEW_PR or nil,
		range = ("%s...%s"):format(base, head),
		repo_root = env.NVIM_REVIEW_REPO_ROOT ~= "" and env.NVIM_REVIEW_REPO_ROOT or worktree,
		worktree = worktree,
		merge_base = merge_base,
	}
end

M.state = resolve_state()

function M.gitsigns_base()
	return M.state and M.state.merge_base or nil
end

local function parse_numstat(review)
	local raw, err = git({ "diff", "--numstat", "--find-renames", review.range }, review.worktree)
	if not raw then
		vim.notify(("Unable to collect review diff stats: %s"):format(err or "unknown error"), vim.log.levels.ERROR)
		return {}
	end

	local stats = {}
	for line in raw:gmatch("[^\n]+") do
		local parts = vim.split(line, "\t", { plain = true, trimempty = false })
		local added = parts[1]
		local removed = parts[2]
		local path = parts[#parts]
		if path and path ~= "" then
			stats[path] = {
				added = added == "-" and "?" or added,
				removed = removed == "-" and "?" or removed,
			}
		end
	end

	return stats
end

local function collect_items(review)
	local raw, err = git({ "diff", "--name-status", "--find-renames", review.range }, review.worktree)
	if not raw then
		vim.notify(("Unable to collect review files: %s"):format(err or "unknown error"), vim.log.levels.ERROR)
		return {}
	end

	local stats = parse_numstat(review)
	local items = {}
	for line in raw:gmatch("[^\n]+") do
		local parts = vim.split(line, "\t", { plain = true, trimempty = false })
		local status_field = parts[1]
		local status = status_field and status_field:sub(1, 1) or nil
		local old_path = nil
		local path = nil

		if status == "R" or status == "C" then
			old_path = parts[2]
			path = parts[3]
		else
			path = parts[2]
		end

		if status and path and path ~= "" then
			local stat = stats[path] or { added = "?", removed = "?" }
			local display_path = old_path and ("%s -> %s"):format(old_path, path) or path
			items[#items + 1] = {
				status = status,
				path = path,
				old_path = old_path,
				added = stat.added,
				removed = stat.removed,
				display = string.format("%-2s  +%-4s -%-4s %s", status, stat.added, stat.removed, display_path),
			}
		end
	end

	return items
end

function M.entries()
	if not M.state then
		return {}
	end

	local entries = {}
	for _, item in ipairs(collect_items(M.state)) do
		entries[#entries + 1] = table.concat({
			item.display,
			item.path,
			item.old_path or "",
		}, entry_delimiter)
	end

	return entries
end

local function parse_entry(line)
	local parts = vim.split(line or "", entry_delimiter, { plain = true, trimempty = false })
	local path = parts[2]
	if not path or path == "" then
		return nil
	end

	return {
		path = path,
		old_path = parts[3] ~= "" and parts[3] or nil,
	}
end

local function preview_command(review)
	return [=[bash -c '
line=$1
range=$2
IFS=$'\''\t'\'' read -r _ path old_path <<< "$line"
if [[ -z "$path" ]]; then
  exit 0
fi
args=("$path")
if [[ -n "$old_path" ]]; then
  args=("$old_path" "$path")
fi
if command -v delta >/dev/null 2>&1; then
  git diff --color=always "$range" -- "${args[@]}" | delta --paging=never
else
  git diff --color=always "$range" -- "${args[@]}"
fi
' bash {} ]=] .. vim.fn.shellescape(review.range)
end

local function edit_file(review, path, vertical)
	local absolute = vim.fs.joinpath(review.worktree, path)
	if not vim.uv.fs_stat(absolute) then
		vim.notify(("File is not present in HEAD: %s"):format(path), vim.log.levels.WARN)
		return
	end
	vim.cmd((vertical and "vsplit " or "edit ") .. vim.fn.fnameescape(absolute))
end

function M.open(split)
	if not M.state then
		vim.notify("Review mode is not active", vim.log.levels.WARN)
		return
	end

	local entries = M.entries()
	if #entries == 0 then
		vim.notify("No files in the current review diff", vim.log.levels.INFO)
		return
	end

	require("fzf-lua").fzf_exec(entries, {
		cwd = M.state.worktree,
		prompt = M.state.pr and ("PR " .. M.state.pr .. " review> ") or "review> ",
		fzf_opts = {
			["--delimiter"] = entry_delimiter,
			["--with-nth"] = "1",
			["--header"] = "Enter: open  Ctrl-V: vertical split",
		},
		preview = preview_command(M.state),
		actions = {
			["default"] = function(selected)
				local entry = parse_entry(selected and selected[1])
				if entry then
					edit_file(M.state, entry.path, split == true)
				end
			end,
			["ctrl-v"] = function(selected)
				local entry = parse_entry(selected and selected[1])
				if entry then
					edit_file(M.state, entry.path, true)
				end
			end,
		},
	})
end

function M.setup()
	if commands_registered then
		return
	end
	commands_registered = true

	vim.api.nvim_create_user_command("ReviewFiles", function()
		M.open(false)
	end, { desc = "Pick files in the review diff" })
	vim.api.nvim_create_user_command("ReviewFilesVsplit", function()
		M.open(true)
	end, { desc = "Pick review diff file in a vertical split" })

	if M.state then
		vim.keymap.set("n", "<leader>gr", function()
			M.open(false)
		end, { desc = "Review diff files" })
	end
end

return M
