-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/ubuildtool/config.lua
-- Purpose: Store default UBuildTool settings and merge user overrides.
-- License: MIT

local M = {}

local defaults = {
	cache_dir = vim.fn.stdpath("cache") .. "/ubuildtool",
	engine_roots = {},
	startup = {
		mode = "editor",
		configuration = "Development",
		platform = "Win64",
		editor_target = nil,
		game_target = nil,
	},
	build = {
		open_quickfix_on_error = true,
		include_warnings = true,
		color_log = true,
		autosave = true,
		use_target_arguments = true,
		build_shader_compile_worker = true,
		shader_compile_worker_target = "ShaderCompileWorker",
		shader_compile_worker_platform = "Win64",
		shader_compile_worker_configuration = "Development",
		shader_compile_worker_quiet = true,
		wait_mutex = true,
		from_msbuild = true,
		extra_args = {},
	},
	editor = {
		build_before_open = true,
		autosave = true,
		prefer_configuration_executable = true,
	},
}

M.values = vim.deepcopy(defaults)

-- Merge user options into the default configuration table and cache the result.
-- 将用户选项合并到默认配置表中并缓存结果。
function M.setup(opts)
	M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	return M.values
end

return M
