-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: plugin/UBuildTool.lua
-- Purpose: Reload and bootstrap the UBuildTool plugin entrypoint.
-- License: MIT

-- Unload cached UBuildTool modules so re-sourcing the plugin resets state cleanly.
-- 卸载缓存的 UBuildTool 模块，以便重新采购插件以干净地重置状态。
local function unload_ubuildtool()
	local ok, existing = pcall(require, "ubuildtool")
	if ok and type(existing) == "table" and type(existing.reset) == "function" then
		pcall(existing.reset)
	end

	for name, _ in pairs(package.loaded) do
		if name == "ubuildtool" or name:match("^ubuildtool%.") then
			package.loaded[name] = nil
		end
	end
end

if vim.g.loaded_ubuildtool == 1 then
	unload_ubuildtool()
else
	vim.g.loaded_ubuildtool = 1
end

require("ubuildtool").setup()
