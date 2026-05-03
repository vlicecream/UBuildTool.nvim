local M = {}

local initialized = false

function M.setup(opts)
	if initialized then
		require("ubuildtool.config").setup(opts)
		return
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
