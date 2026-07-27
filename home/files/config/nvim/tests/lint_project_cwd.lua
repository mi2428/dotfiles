local dotfiles_root = assert(vim.env.DOTFILES_ROOT, "DOTFILES_ROOT is required")
local nvim_root = vim.fs.joinpath(dotfiles_root, "home/files/config/nvim")
package.path = table.concat({
	vim.fs.joinpath(nvim_root, "lua/?.lua"),
	vim.fs.joinpath(nvim_root, "lua/?/init.lua"),
	package.path,
}, ";")

local calls = {}
local lint = {
	linters = {
		golangcilint = { args = { "run", "wrong-target" } },
		tflint = { args = { "--format=json", "--recursive" } },
		hadolint = { stdin = true },
	},
}

function lint.try_lint(name, opts)
	local linter = type(name) == "string" and lint.linters[name] or nil
	if linter and opts and opts.wrap_linter then
		linter = opts.wrap_linter(vim.deepcopy(linter))
	end
	calls[#calls + 1] = {
		name = name,
		opts = opts,
		linter = linter,
	}
end

package.loaded["lint"] = lint
package.loaded["lint.parser"] = {
	from_pattern = function()
		return function()
			return {}
		end
	end,
}

local specs = dofile(vim.fs.joinpath(nvim_root, "lua/plugins/lsp.lua"))
local lint_spec
for _, spec in ipairs(specs) do
	if spec[1] == "mfussenegger/nvim-lint" then
		lint_spec = spec
		break
	end
end
assert(lint_spec and lint_spec.config, "nvim-lint spec is missing")
lint_spec.config()

local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local function same_path(left, right)
	return vim.uv.fs_realpath(left) == vim.uv.fs_realpath(right)
end

local function create_file(relative, lines)
	local filename = vim.fs.joinpath(temporary, relative)
	vim.fn.mkdir(vim.fs.dirname(filename), "p")
	vim.fn.writefile(lines or {}, filename)
	return vim.fs.normalize(vim.fn.fnamemodify(filename, ":p"))
end

local function lint_buffer(filename, filetype, event)
	calls = {}
	vim.api.nvim_buf_set_name(0, filename)
	vim.bo.filetype = filetype
	vim.api.nvim_exec_autocmds(event or "BufEnter", {
		group = "dotfiles-nvim-lint",
		buffer = 0,
		modeline = false,
	})
	return calls
end

create_file("go-module/go.mod", { "module example.test/project", "", "go 1.26" })
local go_file = create_file("go-module/pkg/check.go", { "package pkg" })
local go_calls = lint_buffer(go_file, "go")
assert(#go_calls == 1 and go_calls[1].name == "golangcilint", "Go must run only golangci-lint")
assert(
	same_path(go_calls[1].opts.cwd, vim.fs.dirname(go_file)),
	"golangci-lint must run in the buffer package directory: "
		.. vim.inspect({ actual = go_calls[1].opts.cwd, expected = vim.fs.dirname(go_file), file = go_file })
)
assert(go_calls[1].linter.args[#go_calls[1].linter.args] == ".", "Go modules must be linted as a package")
assert(go_calls[1].linter.args[1] == "run", "golangci-lint's upstream arguments must be preserved")

local go_insert_calls = lint_buffer(go_file, "go", "InsertLeave")
assert(#go_insert_calls == 0, "non-stdin Go lint must not run for unsaved InsertLeave changes")
local go_write_calls = lint_buffer(go_file, "go", "BufWritePost")
assert(#go_write_calls == 1, "Go lint must still run after saving")

create_file("go-work/go.work", { "go 1.26" })
local go_work_file = create_file("go-work/pkg/check.go", { "package pkg" })
local go_work_calls = lint_buffer(go_work_file, "go")
assert(go_work_calls[1].linter.args[#go_work_calls[1].linter.args] == ".", "go.work files must lint as a package")

local standalone_go = create_file("standalone/single.go", { "package standalone" })
local standalone_calls = lint_buffer(standalone_go, "go")
assert(
	same_path(standalone_calls[1].opts.cwd, vim.fs.dirname(standalone_go)),
	"standalone Go must use its file directory"
)
assert(
	standalone_calls[1].linter.args[#standalone_calls[1].linter.args] == "single.go",
	"standalone Go must retain single-file linting"
)

local unnamed_calls = lint_buffer("", "go")
assert(#unnamed_calls == 0, "unnamed Go buffers must not start golangci-lint")

local terraform_root = vim.fs.normalize(vim.fn.fnamemodify(vim.fs.joinpath(temporary, "terraform"), ":p"))
create_file("terraform/.tflint.hcl", {})
local terraform_file = create_file("terraform/nested/main.tf", { "terraform {}" })
local terraform_calls = lint_buffer(terraform_file, "terraform")
assert(#terraform_calls == 1 and terraform_calls[1].name == "tflint", "Terraform must run only tflint")
assert(same_path(terraform_calls[1].opts.cwd, vim.fs.dirname(terraform_file)), "tflint must run in the current module")
assert(vim.tbl_contains(terraform_calls[1].linter.args, "--format=json"), "tflint's output format must be preserved")
assert(not vim.tbl_contains(terraform_calls[1].linter.args, "--recursive"), "tflint must not scan sibling modules")
local tflint_config_arg = vim.iter(terraform_calls[1].linter.args):find(function(arg)
	return vim.startswith(arg, "--config=")
end)
assert(
	tflint_config_arg
		and same_path(tflint_config_arg:sub(#"--config=" + 1), vim.fs.joinpath(terraform_root, ".tflint.hcl")),
	"tflint must load the nearest configuration explicitly"
)

local terraform_insert_calls = lint_buffer(terraform_file, "terraform", "InsertLeave")
assert(#terraform_insert_calls == 0, "non-stdin Terraform lint must not run for unsaved InsertLeave changes")
local terraform_write_calls = lint_buffer(terraform_file, "terraform", "BufWritePost")
assert(#terraform_write_calls == 1, "Terraform lint must still run after saving")

local diagnostics = lint.linters.tflint.parser(
	vim.json.encode({
		issues = {
			{
				message = "example issue",
				rule = { name = "terraform_example", severity = "warning", link = "https://example.test/rule" },
				range = {
					filename = "main.tf",
					start = { line = 2, column = 3 },
					["end"] = { line = 2, column = 7 },
				},
			},
		},
	}),
	0,
	terraform_calls[1].opts.cwd
)
assert(#diagnostics == 1, "tflint must retain diagnostics relative to its project cwd")
assert(diagnostics[1].lnum == 1 and diagnostics[1].col == 2, "tflint positions must be converted to zero-based")
assert(diagnostics[1].end_lnum == 1 and diagnostics[1].end_col == 6, "tflint end positions must be zero-based")
assert(diagnostics[1].code == "terraform_example", "tflint rule names must be preserved")
assert(diagnostics[1].message:find("https://example.test/rule", 1, true), "tflint rule references must be preserved")
assert(#lint.linters.tflint.parser("not json", 0, terraform_calls[1].opts.cwd) == 0, "malformed JSON must be ignored")
assert(
	#lint.linters.tflint.parser('{"issues":null}', 0, terraform_calls[1].opts.cwd) == 0,
	"null issue lists must be ignored"
)
assert(
	#lint.linters.tflint.parser('{"issues":[{"range":{"filename":[]}}]}', 0, terraform_calls[1].opts.cwd) == 0,
	"invalid issue filenames must be ignored"
)

local hadolint_root = create_file("docker/.hadolint.yaml", { "ignored: []" })
local dockerfile = create_file("docker/nested/Dockerfile", { "FROM scratch" })
local hadolint_calls = lint_buffer(dockerfile, "dockerfile", "InsertLeave")
assert(#hadolint_calls == 1 and hadolint_calls[1].name == "hadolint", "Dockerfiles must use hadolint")
assert(
	same_path(hadolint_calls[1].opts.cwd, vim.fs.dirname(hadolint_root)),
	"hadolint must discover the nearest project configuration"
)
assert(hadolint_calls[1].opts.filter == "stdin", "InsertLeave must admit stdin linters only")

local helm_values = create_file("chart/values.yaml", { "example: true" })
create_file("chart/Chart.yaml", { "apiVersion: v2", "name: example", "version: 0.1.0" })
local helm_insert_calls = lint_buffer(helm_values, "helm", "InsertLeave")
assert(not vim.iter(helm_insert_calls):any(function(call)
	return call.name == "helm_lint"
end), "non-stdin Helm lint must not run on InsertLeave")

local kustomization = create_file("kube/kustomization.yaml", { "resources: []" })
local kube_insert_calls = lint_buffer(kustomization, "yaml", "InsertLeave")
assert(not vim.iter(kube_insert_calls):any(function(call)
	return call.name == "kubeconform"
end), "non-stdin kubeconform must not run on InsertLeave")

vim.fn.mkdir(vim.fs.joinpath(temporary, "workflow-repo", ".git"), "p")
local workflow = create_file("workflow-repo/.github/workflows/ci.yml", { "name: CI" })
local workflow_calls = lint_buffer(workflow, "yaml")
assert(#workflow_calls == 2, "workflow YAML must run its normal linter and actionlint")
assert(workflow_calls[2].name == "actionlint", "the workflow-specific linter must be actionlint")
assert(
	same_path(workflow_calls[2].opts.cwd, vim.fs.joinpath(temporary, "workflow-repo")),
	"actionlint must run from the repository root"
)

local extracted_workflow = create_file("extracted/.github/workflows/ci.yml", { "name: CI" })
local extracted_workflow_calls = lint_buffer(extracted_workflow, "yaml")
assert(
	same_path(extracted_workflow_calls[2].opts.cwd, vim.fs.joinpath(temporary, "extracted")),
	"actionlint must find .github configuration outside a Git checkout"
)

print("lint project cwd regression: ok")
