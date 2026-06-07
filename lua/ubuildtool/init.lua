-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/ubuildtool/init.lua
-- Purpose: Initialize, register, and reset the UBuildTool plugin runtime.
-- License: MIT

local M = {}

local initialized = false

-- Tear down registered commands and stop any running build job before reinitializing.
-- 在重新初始化之前，拆除已注册的命令并停止任何正在运行的构建作业。
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

-- Apply configuration and register the user-facing UBuildTool commands.
-- 应用配置并注册面向用户的 UBuildTool 命令。
function M.setup(opts)
	if initialized then
		M.reset()
	end

	initialized = true
	require("ubuildtool.config").setup(opts)
	require("ubuildtool.commands").register()
end

return M
