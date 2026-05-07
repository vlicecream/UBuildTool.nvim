local unreal = require("ubuildtool.unreal")

local M = {}

function M.build(args)
	unreal.build(args)
end

function M.build_cancel()
	unreal.cancel_build()
end

function M.launch(args)
	unreal.open_startup(args)
end

function M.editor(args)
	unreal.open_editor(args)
end

function M.game(args)
	unreal.open_game(args)
end

function M.help()
	print([[
UBuildTool commands:

  :UBuildTool              Show this help
  :UBuildTool build        Build the configured default target
  :UBuildTool build-stop   Stop the currently running Unreal build
  :UBuildTool launch       Open the configured startup target
  :UBuildTool editor       Build and open current project in Unreal Editor
  :UBuildTool game         Build and open current project in Unreal Game mode
  :UBuildTool launch !     Open the configured startup target without building
  :UBuildTool editor !     Open Unreal Editor without building
  :UBuildTool game !       Open Unreal Game mode without building
  :UBuildTool help         Show this help
]])
end

return M
