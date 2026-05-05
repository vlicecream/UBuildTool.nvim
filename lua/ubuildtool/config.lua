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
	},
	editor = {
		build_before_open = true,
		autosave = true,
	},
	clangd = {
		auto_generate_compile_commands = true,
		prewarm_on_setup = true,
		remove_source_compile_commands = true,
	},
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
	M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	return M.values
end

return M
