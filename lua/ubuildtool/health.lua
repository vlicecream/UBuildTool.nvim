local clangd = require("ubuildtool.clangd")
local config = require("ubuildtool.config")
local project = require("ubuildtool.project")

local M = {}

local health = vim.health or {}
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

local function executable(name)
	return vim.fn.executable(name) == 1
end

local function readable(path)
	return path and vim.fn.filereadable(path) == 1
end

local function is_dir(path)
	return path and vim.fn.isdirectory(path) == 1
end

function M.check()
	start("UBuildTool.nvim")

	local cache_dir = config.values.cache_dir
	info("cache dir: " .. tostring(cache_dir))
	if is_dir(cache_dir) then
		ok("cache dir exists")
	else
		info("cache dir does not exist yet")
	end

	local root = project.find_project_root_from_context()
	if not root then
		warn("No Unreal project detected from current context", {
			"Open a file inside an Unreal project, then run :checkhealth ubuildtool again.",
		})
		return
	end

	ok("project root: " .. root)
	local uproject = project.find_project_file_in_root(root)
	if uproject then
		ok(".uproject: " .. uproject)
	end

	local engine, engine_err = project.engine_metadata(root)
	if not engine then
		error("failed to resolve Unreal Engine root: " .. tostring(engine_err))
		return
	end

	ok("EngineAssociation resolved: " .. tostring(engine.engine_association or ""))
	ok("engine root: " .. tostring(engine.engine_root))

	local ubt, ubt_err = project.unreal_build_tool(root)
	if ubt then
		ok("UnrealBuildTool found: " .. ubt)
		if ubt:match("%.dll$") then
			if executable("dotnet") then
				ok("dotnet found on PATH")
			else
				warn("dotnet not found on PATH", {
					"Required when UnrealBuildTool is installed as a .dll.",
				})
			end
		end
	else
		warn("UnrealBuildTool not found", {
			tostring(ubt_err),
		})
	end

	local ctx = clangd.status(root)
	info("auto generate compile_commands.json: " .. tostring(ctx.auto_generate_compile_commands))
	if ctx.compile_commands_dir then
		ok("compile_commands.json found under: " .. ctx.compile_commands_dir)
	else
		info("compile_commands.json not found yet")
	end
end

return M
