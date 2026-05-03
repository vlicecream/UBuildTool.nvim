local M = {}

local initialized = false

function M.reset()
	pcall(function()
		local unreal = require("ubuildtool.unreal")
		if unreal.is_build_running and unreal.is_build_running() then
			unreal.cancel_build()
		end
	end)
	pcall(vim.api.nvim_del_user_command, "UBuildTool")
	initialized = false
end

function M.setup(opts)
	if initialized then
		M.reset()
	end

	initialized = true
	require("ubuildtool.config").setup(opts)
	require("ubuildtool.commands").register()

	vim.schedule(function()
		pcall(function()
			require("ubuildtool.clangd").prewarm_current_project()
		end)
	end)
end

return M
