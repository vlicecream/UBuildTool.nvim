-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/ubuildtool/commands/actions.lua
-- Purpose: Implement the concrete actions behind each :UBuildTool subcommand.
-- License: MIT

local unreal = require("ubuildtool.unreal")

local M = {}

-- Start one Unreal build using the supplied raw argument tail.
-- 使用提供的原始参数 tail 启动一个 Unreal 构建。
function M.build(args)
	unreal.build(args)
end

-- Stop the currently running Unreal build, if any.
-- 停止当前正在运行的虚幻构建（如果有）。
function M.build_cancel()
	unreal.cancel_build()
end

-- Build and launch using the configured startup mode.
-- 使用配置的启动模式构建并启动。
function M.launch(args)
	unreal.open_startup(args)
end

-- Build and launch Unreal Editor for the current project.
-- 为当前项目构建并启动虚幻编辑器。
function M.editor(args)
	unreal.open_editor(args)
end

-- Build and launch Unreal Game mode for the current project.
-- 为当前项目构建并启动虚幻游戏模式。
function M.game(args)
	unreal.open_game(args)
end

-- Print the supported :UBuildTool commands and usage examples.
-- 打印支持的 :UBuildTool 命令以及对应的使用示例。
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
