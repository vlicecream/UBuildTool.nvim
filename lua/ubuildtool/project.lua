-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/ubuildtool/project.lua
-- Purpose: Resolve Unreal project roots, engine metadata, cache paths, and build tool locations.
-- License: MIT

local config = require("ubuildtool.config")

local M = {}

local uv = vim.uv or vim.loop

-- Normalize one filesystem path to forward-slash form.
-- 将一个文件系统路径规范为正斜杠形式。
local function normalize(path)
	return path and path:gsub("\\", "/") or nil
end

-- Return whether the current host platform is Windows.
-- 返回当前主机平台是否为Windows。
local function is_windows()
	return package.config:sub(1, 1) == "\\"
end

-- Remove trailing separators while preserving filesystem roots.
-- 删除尾随分隔符，同时保留文件系统根。
local function trim_trailing_slashes(path)
	path = normalize(path or "")
	if path == "" then
		return nil
	end
	if path == "/" or path:match("^%a:/$") then
		return path
	end
	path = path:gsub("/+$", "")
	return path ~= "" and path or nil
end

-- Expand, absolutize, and realpath one path so different spellings compare consistently.
-- 扩展、绝对化和真实路径一条路径，以便不同的拼写能够一致地进行比较。
local function canonicalize_path(path)
	path = tostring(path or "")
	path = vim.trim(path)
	if path == "" then
		return nil
	end
	path = vim.fn.expand(path)

	local absolute
	if vim.fs and vim.fs.abspath then
		absolute = vim.fs.abspath(path)
	else
		absolute = vim.fn.fnamemodify(path, ":p")
	end

	absolute = normalize(absolute)
	local native = is_windows() and absolute:gsub("/", "\\") or absolute
	local real = (vim.uv or vim.loop).fs_realpath(native) or (vim.uv or vim.loop).fs_realpath(absolute)
	return trim_trailing_slashes(real or absolute)
end

-- Build a comparable normalized path for equality checks.
-- 为平等检查建立可比较的标准化路径。
local function comparable_path(path)
	return canonicalize_path(path) or trim_trailing_slashes(path) or normalize(path)
end

-- Compare two paths after normalization and realpath resolution.
-- 比较归一化和实际路径解析后的两条路径。
local function same_path(a, b)
	local left = comparable_path(a)
	local right = comparable_path(b)
	return left ~= nil and right ~= nil and left == right
end

-- Build one stable cache key from a filesystem path.
-- 从文件系统路径构建一个稳定的缓存密钥。
local function path_key(path)
	return canonicalize_path(path) or trim_trailing_slashes(path) or normalize(path)
end

-- Return the last path segment from one normalized path.
-- 返回一个标准化路径的最后一个路径段。
local function basename(path)
	path = normalize(path or "")
	path = path:gsub("/+$", "")
	return path:match("([^/]+)$") or ""
end

-- Hash one string into a short stable cache suffix.
-- 将一个字符串哈希为一个短的稳定缓存后缀。
local function stable_hash12(text)
	text = tostring(text or "")
	local bitlib = bit or bit32
	local h1 = 2166136261
	local h2 = 16777619
	for i = 1, #text do
		local b = text:byte(i)
		h1 = bitlib.bxor(h1, b)
		h1 = (h1 * 16777619) % 4294967296
		h2 = bitlib.bxor(h2, b + i)
		h2 = (h2 * 2166136261) % 4294967296
	end
	return string.format("%08x%08x", h1, h2):sub(1, 12)
end

-- Return the parent directory for one normalized path.
-- 返回一个标准化路径的父目录。
local function dirname(path)
	path = normalize(path or ""):gsub("/+$", "")
	return path:match("^(.*)/[^/]*$") or ""
end

-- Read filesystem metadata for one path.
-- 读取一个路径的文件系统元数据。
local function fs_stat(path)
	return path and uv.fs_stat(path) or nil
end

-- Return whether one path is a readable file.
-- 返回一个路径是否是可读文件。
local function readable(path)
	local stat = fs_stat(path)
	return stat and stat.type == "file"
end

-- Return whether one path exists at all.
-- 返回一条路径是否存在。
local function path_exists(path)
	return fs_stat(path) ~= nil
end

-- Return whether one path is a directory.
-- 返回一个路径是否是目录。
local function is_dir(path)
	local stat = fs_stat(path)
	return stat and stat.type == "directory"
end

-- Create a directory tree without failing when intermediate directories already exist.
-- 当中间目录已存在时，创建目录树不会失败。
local function mkdirp(path)
	path = normalize(path or "")
	if path == "" or is_dir(path) then
		return
	end

	local prefix = ""
	local rest = path
	local drive = rest:match("^%a:")
	if drive then
		prefix = drive
		rest = rest:sub(#drive + 1):gsub("^/+", "")
	elseif rest:sub(1, 1) == "/" then
		prefix = "/"
		rest = rest:gsub("^/+", "")
	end

	local current = prefix
	for part in rest:gmatch("[^/]+") do
		current = current == "" and part or (current:gsub("/$", "") .. "/" .. part)
		if not is_dir(current) then
			pcall(uv.fs_mkdir, current, 493)
		end
	end
end

-- Return Neovim's data directory in normalized form.
-- 以标准化形式返回 Neovim 的数据目录。
local function nvim_data_dir()
	return normalize(vim.fn.stdpath("data"))
end

-- Join path segments with normalized separators.
-- 使用标准化分隔符连接路径段。
local function path_join(...)
	return normalize(table.concat({ ... }, "/"):gsub("//+", "/"))
end

-- List target definition files directly under the project's Source directory.
-- 直接在项目的源目录下列出目标定义文件。
local function list_target_files(root)
	local source_dir = path_join(root, "Source")
	local handle = uv.fs_scandir(source_dir)
	local result = {}

	if not handle then
		return result
	end

	while true do
		local name, typ = uv.fs_scandir_next(handle)
		if not name then
			break
		end
		if typ == "file" and name:match("%.Target%.cs$") then
			table.insert(result, path_join(source_dir, name))
		end
	end

	return result
end

-- Build one stable cache directory name for a project root.
-- 为项目根目录构建一个稳定的缓存目录名称。
local function project_cache_name(project_root)
	local normalized = path_key(project_root) or normalize(project_root)
	local name = basename(normalized)
	local hash = stable_hash12(normalized)
	if name == "" then
		return hash
	end
	return name .. "-" .. hash
end

-- Decode one JSON file into a Lua table.
-- 将一个 JSON 文件解码为一张 Lua 表。
local function read_json_file(path)
	local file = path and io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	local ok_decode, data = pcall(vim.json.decode, content or "")
	if not ok_decode then
		return nil
	end
	return data
end

-- Return the shared UCore registry path that stores discovered project metadata.
-- 返回存储发现的项目元数据的共享 UCore 注册表路径。
local function ucore_registry_path()
	local cache_dir = normalize(nvim_data_dir() .. "/ucore")
	mkdirp(cache_dir)
	return cache_dir .. "/registry.json"
end

-- Read the UCore registry and normalize missing tables to empty maps.
-- 读取 UCore 注册表并将缺失的表标准化为空映射。
local function read_ucore_registry()
	local registry = read_json_file(ucore_registry_path())
	if type(registry) ~= "table" then
		return {
			projects = {},
			engines = {},
		}
	end
	registry.projects = type(registry.projects) == "table" and registry.projects or {}
	registry.engines = type(registry.engines) == "table" and registry.engines or {}
	return registry
end

-- Build the possible engine association keys used by config, launcher, and registry lookups.
-- 构建配置、启动器和注册表查找可能使用的引擎关联键。
local function engine_association_candidates(association)
	if not association or association == "" then
		return {}
	end
	local items = { association }
	if not association:match("^UE_") then
		table.insert(items, "UE_" .. association)
	end
	if association:match("^UE_") then
		table.insert(items, association:gsub("^UE_", ""))
	end
	return items
end

-- Search upward from one path until a .uproject file is found.
-- 从一个路径向上搜索，直到找到 .uproject 文件。
function M.find_project_file(start_path)
	start_path = start_path or vim.api.nvim_buf_get_name(0)
	if start_path == "" then
		start_path = vim.loop.cwd()
	end
	if start_path == "" then
		return nil
	end

	local dir
	if is_dir(start_path) then
		dir = start_path
	else
		dir = dirname(normalize(vim.fs.abspath(start_path)))
	end

	local found = vim.fs.find(function(name)
		return name:match("%.uproject$")
	end, {
		path = dir,
		upward = true,
		type = "file",
		limit = 1,
	})[1]

	return found and (path_key(found) or normalize(found)) or nil
end

-- Return the project root directory for one path inside an Unreal project.
-- 返回虚幻项目内一个路径的项目根目录。
function M.find_project_root(start_path)
	local project_file = M.find_project_file(start_path)
	if not project_file then
		return nil
	end
	local absolute = vim.fs.abspath(project_file)
	return dirname(path_key(absolute) or normalize(absolute))
end

-- Resolve the active project root from the current editor context.
-- 从当前编辑器上下文解析活动项目根。
function M.find_project_root_from_context()
	local buf_path = vim.api.nvim_buf_get_name(0)
	if buf_path and buf_path ~= "" then
		local root = M.find_project_root(buf_path)
		if root then
			return root
		end
	end

	local cwd = vim.loop.cwd()
	if cwd then
		local root = M.find_project_root(cwd)
		if root then
			return root
		end
	end

	local alt = tonumber(vim.v.alternate)
	if alt and alt > 0 then
		local alt_path = vim.api.nvim_buf_get_name(alt)
		if alt_path and alt_path ~= "" then
			local root = M.find_project_root(alt_path)
			if root then
				return root
			end
		end
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local bo = vim.bo[bufnr]
		if bo.buflisted and bo.buftype == "" and bo.modifiable then
			local path = vim.api.nvim_buf_get_name(bufnr)
			if path and path ~= "" then
				local root = M.find_project_root(path)
				if root then
					return root
				end
			end
		end
	end

	return nil
end

-- Find the .uproject file directly under one known project root.
-- 直接在一个已知项目根目录下查找 .uproject 文件。
function M.find_project_file_in_root(project_root)
	project_root = path_key(project_root) or normalize(project_root)
	local scan = uv.fs_scandir(project_root)
	if not scan then
		return nil
	end
	while true do
		local name, t = uv.fs_scandir_next(scan)
		if not name then
			break
		end
		if t == "file" and name:match("%.uproject$") then
			return path_key(path_join(project_root, name)) or normalize(path_join(project_root, name))
		end
	end
	return nil
end

-- Read EngineAssociation from one .uproject JSON file.
-- 从一个 .uproject JSON 文件读取 EngineAssociation。
function M.read_engine_association(uproject_path)
	local file = uproject_path and io.open(uproject_path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	local ok_decode, data = pcall(vim.json.decode, content or "")
	if not ok_decode or type(data) ~= "table" then
		return nil
	end
	return data.EngineAssociation
end

-- Return whether one path looks like a valid Unreal Engine installation root.
-- 返回一个路径是否看起来像有效的虚幻引擎安装根目录。
function M.is_engine_root(path)
	if not path or path == "" then
		return false
	end
	path = path_key(path) or normalize(path)
	return is_dir(path .. "/Engine/Source") or readable(path .. "/Engine/Build/Build.version")
end

-- Resolve an engine root from user configuration overrides.
-- 从用户配置覆盖解析引擎根。
function M.find_engine_root_from_config(association)
	for _, key in ipairs(engine_association_candidates(association)) do
		local root = config.values.engine_roots and config.values.engine_roots[key]
		if M.is_engine_root(root) then
			return path_key(root) or normalize(root)
		end
	end
	return nil
end

-- Resolve an engine root from Epic Launcher installation metadata.
-- 从 Epic Launcher 安装元数据解析引擎根。
function M.find_engine_root_from_launcher(association)
	local data = read_json_file("C:/ProgramData/Epic/UnrealEngineLauncher/LauncherInstalled.dat")
	if type(data) ~= "table" or type(data.InstallationList) ~= "table" then
		return nil
	end

	local candidates = {}
	for _, key in ipairs(engine_association_candidates(association)) do
		candidates[key] = true
	end

	for _, item in ipairs(data.InstallationList) do
		if candidates[item.AppName] and M.is_engine_root(item.InstallLocation) then
			return path_key(item.InstallLocation) or normalize(item.InstallLocation)
		end
	end
	return nil
end

-- Resolve an engine root from the Windows Unreal Engine registry keys.
-- 从 Windows Unreal Engine 注册表项解析引擎根。
function M.find_engine_root_from_registry(association)
	if not is_windows() then
		return nil
	end

	local result = vim.system({
		"reg",
		"query",
		"HKCU\\Software\\Epic Games\\Unreal Engine\\Builds",
	}, { text = true }):wait()
	if result.code ~= 0 then
		return nil
	end

	local candidates = {}
	for _, key in ipairs(engine_association_candidates(association)) do
		candidates[key] = true
	end

	for line in (result.stdout or ""):gmatch("[^\r\n]+") do
		line = vim.trim(line)
		local name, path = line:match("^(%S+)%s+REG_SZ%s+(.+)$")
		path = path and vim.trim(path)
		if name and path and candidates[name] and M.is_engine_root(path) then
			return path_key(path) or normalize(path)
		end
	end

	return nil
end

-- Resolve the engine root for one project using association text and known discovery sources.
-- 使用关联文本和已知的发现源解析一个项目的引擎根。
function M.resolve_engine_root(project_root)
	project_root = path_key(project_root) or normalize(project_root)
	local uproject_path = M.find_project_file_in_root(project_root)
	local association = M.read_engine_association(uproject_path)
	if not association or association == "" then
		return nil, "No EngineAssociation in .uproject"
	end
	if M.is_engine_root(association) then
		return path_key(association) or normalize(association), association
	end

	local root = M.find_engine_root_from_config(association)
		or M.find_engine_root_from_launcher(association)
		or M.find_engine_root_from_registry(association)
	if root then
		return root, association
	end
	return nil, "Could not resolve Unreal Engine root for EngineAssociation: " .. tostring(association)
end

-- Read cached engine metadata for one project from the shared UCore registry.
-- 从共享 UCore 注册表中读取一个项目的缓存引擎元数据。
function M.cached_engine_metadata(project_root)
	project_root = path_key(project_root) or normalize(project_root)
	if not project_root or project_root == "" then
		return nil
	end

	local registry = read_ucore_registry()
	local item = registry.projects and registry.projects[project_root]
	if type(item) ~= "table" then
		for root, value in pairs(registry.projects or {}) do
			if same_path(path_key(root) or normalize(root), project_root) then
				item = value
				break
			end
		end
	end
	if type(item) ~= "table" or not item.engine_root then
		return nil
	end

	return {
		engine_association = item.engine_association,
		engine_root = path_key(item.engine_root) or normalize(item.engine_root),
		engine_id = item.engine_id,
	}
end

-- Return engine metadata for one project and surface cache-miss guidance.
-- 返回一个项目的引擎元数据和表面缓存未命中指南。
function M.engine_metadata(project_root)
	local cached = M.cached_engine_metadata(project_root)
	if cached then
		return cached
	end

	return nil, "UCore engine cache missing for project. Run :UCore boot first."
end

-- Return the human-readable project name derived from the .uproject filename.
-- 返回从 .uproject 文件名派生的人类可读的项目名称。
function M.project_name(root)
	local project_file = M.find_project_file_in_root(root)
	if not project_file then
		return basename(root)
	end
	return (basename(project_file):gsub("%.uproject$", ""))
end

-- Prefer an Editor target name that matches the current project layout.
-- 首选与当前项目布局匹配的编辑器目标名称。
function M.editor_target_name(root)
	local base_name = M.project_name(root)
	local preferred = base_name .. "Editor"
	local candidates = list_target_files(root)
	local fallback = nil

	for _, path in ipairs(candidates) do
		local name = tostring(path):match("([^/\\]+)%.Target%.cs$")
		if name then
			if name == preferred then
				return preferred
			end
			if name:match("Editor$") and not fallback then
				fallback = name
			end
		end
	end

	return fallback or preferred
end

-- Prefer a non-editor runtime target name that matches the current project layout.
-- 首选与当前项目布局匹配的非编辑器运行时目标名称。
function M.game_target_name(root)
	local base_name = M.project_name(root)
	local candidates = list_target_files(root)
	local fallback = nil

	for _, path in ipairs(candidates) do
		local name = tostring(path):match("([^/\\]+)%.Target%.cs$")
		if name then
			if name == base_name then
				return base_name
			end
			if not name:match("Editor$") and not name:match("Server$") and not name:match("Client$") and not fallback then
				fallback = name
			end
		end
	end

	return fallback or base_name
end

-- Locate UnrealBuildTool under the resolved engine installation.
-- 在已解析的引擎安装下找到 UnrealBuildTool。
function M.unreal_build_tool(root)
	local engine, err = M.engine_metadata(root)
	if not engine or not engine.engine_root then
		return nil, err or "failed to resolve Unreal Engine root", engine
	end

	local candidates = {
		path_join(engine.engine_root, "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.exe"),
		path_join(engine.engine_root, "Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll"),
	}

	for _, path in ipairs(candidates) do
		if path_exists(path) then
			return path, nil, engine
		end
	end

	return nil, "UnrealBuildTool not found under: " .. tostring(engine.engine_root), engine
end

-- Build the cache paths used for one project's UBuildTool state.
-- 构建用于一个项目的 UBuildTool 状态的缓存路径。
function M.build_paths(project_root)
	project_root = path_key(project_root) or normalize(project_root)
	local cache_dir = normalize(config.values.cache_dir)
	local project_cache_dir = path_join(cache_dir, "projects", project_cache_name(project_root))
	mkdirp(project_cache_dir)
	return {
		project_root = project_root,
		cache_dir = project_cache_dir,
	}
end

return M
