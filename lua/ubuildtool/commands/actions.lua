local clangd = require("ubuildtool.clangd")
local project = require("ubuildtool.project")
local unreal = require("ubuildtool.unreal")

local M = {}

function M.build(args)
	unreal.build(args)
end

function M.build_cancel()
	unreal.cancel_build()
end

function M.editor(args)
	unreal.open_editor(args)
end

function M.clangd_database(args)
	clangd.prepare_compile_commands(project.find_project_root_from_context(), {}, function(ok, result)
		vim.schedule(function()
			if ok then
				local dir = type(result) == "table" and result.compile_commands_dir or nil
				vim.notify("UBuildTool clangd database ready" .. (dir and (": " .. dir) or ""), vim.log.levels.INFO)
				return
			end

			vim.notify("UBuildTool clangd database failed:\n" .. tostring(result), vim.log.levels.ERROR)
		end)
	end)
end

function M.help()
	print([[
UBuildTool commands:

  :UBuildTool              Show this help
  :UBuildTool build        Build current Unreal Editor target
  :UBuildTool build-stop   Stop the currently running Unreal build
  :UBuildTool editor       Build and open current project in Unreal Editor
  :UBuildTool editor !     Open Unreal Editor without building
  :UBuildTool clangd-db    Prepare compile_commands.json for clangd
  :UBuildTool help         Show this help
]])
end

return M
