local config = require("ubuildtool.config")
local project = require("ubuildtool.project")

local M = {}
local uv = vim.uv or vim.loop

local function normalize(path)
	return path and path:gsub("\\", "/") or nil
end

local function path_join(...)
	return normalize(table.concat({ ... }, "/"):gsub("//+", "/"))
end

local function dirname(path)
	path = normalize(path or ""):gsub("/+$", "")
	return path:match("^(.*)/[^/]*$") or ""
end

local function fs_stat(path)
	return path and uv.fs_stat(path) or nil
end

local function readable(path)
	local stat = fs_stat(path)
	return stat and stat.type == "file"
end

local function executable(path)
	return readable(path)
end

local function path_exists(path)
	return fs_stat(path) ~= nil
end

local function is_dir(path)
	local stat = fs_stat(path)
	return stat and stat.type == "directory"
end

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

local function normalize_compile_db_dir(value)
	value = normalize(value)
	if not value or value == "" then
		return nil
	end
	if value:match("compile_commands%.json$") then
		return dirname(normalize(vim.fs.abspath(value)))
	end
	return value
end

local function has_compile_commands(dir)
	dir = normalize_compile_db_dir(dir)
	return dir and path_exists(path_join(dir, "compile_commands.json")) and dir or nil
end

local function project_cache_compile_commands_dir(root)
	root = normalize(root)
	if not root or root == "" then
		return nil
	end
	local paths = project.build_paths(root)
	mkdirp(paths.clangd_dir)
	return normalize(paths.clangd_dir)
end

local function copy_file(source_path, target_path)
	if uv.fs_copyfile then
		local ok_copy = pcall(uv.fs_copyfile, source_path, target_path)
		if ok_copy or readable(target_path) then
			return true
		end
	end

	local source = io.open(source_path, "rb")
	if not source then
		return false
	end
	local content = source:read("*a")
	source:close()

	mkdirp(dirname(target_path))
	local target = io.open(target_path, "wb")
	if not target then
		return false
	end
	target:write(content or "")
	target:close()
	return true
end

local function delete_file(path)
	if not path or path == "" then
		return false
	end
	if uv.fs_unlink then
		local ok = pcall(uv.fs_unlink, path)
		return ok
	end
	return false
end

function M.find_compilation_database(root)
	root = normalize(root)
	if not root or root == "" then
		return nil
	end

	local cache_dir = project_cache_compile_commands_dir(root)
	local cached = has_compile_commands(cache_dir)
	if cached then
		return cached
	end

	local configured = normalize_compile_db_dir((config.values.clangd or {}).compile_commands_dir)
	if has_compile_commands(configured) then
		return configured
	end

	local candidates = {
		root,
		path_join(root, ".vscode"),
		path_join(root, "build"),
		path_join(root, "Build"),
		path_join(root, "Intermediate"),
		path_join(root, "Intermediate/Build"),
		path_join(root, ".cache"),
	}

	local engine = project.engine_metadata(root)
	if engine and engine.engine_root then
		table.insert(candidates, normalize(engine.engine_root))
		table.insert(candidates, path_join(engine.engine_root, "Engine"))
	end

	for _, dir in ipairs(candidates) do
		local found = has_compile_commands(dir)
		if found then
			return found
		end
	end

	return nil
end

function M.ensure_project_compile_database(root, opts)
	opts = opts or {}
	root = normalize(root)
	if not root or root == "" then
		return nil
	end

	local cache_dir = project_cache_compile_commands_dir(root)
	if not cache_dir then
		return nil
	end

	local cached = has_compile_commands(cache_dir)
	if cached and not opts.refresh then
		return cached
	end

	local source_dir = M.find_compilation_database(root)
	if not source_dir then
		return nil
	end

	local source_path = path_join(source_dir, "compile_commands.json")
	local target_path = path_join(cache_dir, "compile_commands.json")
	if not readable(source_path) then
		return nil
	end

	if normalize(source_path) ~= normalize(target_path) and not copy_file(source_path, target_path) then
		return nil
	end

	if opts.remove_source and normalize(source_path) ~= normalize(target_path) then
		delete_file(source_path)
	end

	return cache_dir
end

function M.generate_compile_commands(root, opts, callback)
	opts = opts or {}
	callback = callback or function() end
	root = normalize(root or project.find_project_root_from_context())
	if not root or root == "" then
		return callback(false, "Could not find .uproject")
	end

	local uproject = project.find_project_file_in_root(root)
	if not uproject then
		return callback(false, "Could not find .uproject under: " .. root)
	end

	local ubt, ubt_err = project.unreal_build_tool(root)
	if not ubt then
		return callback(false, ubt_err or "UnrealBuildTool not found")
	end

	local target = opts.target or project.editor_target_name(root)
	local platform = opts.platform or "Win64"
	local configuration = opts.configuration or "Development"

	local cmd
	if ubt:match("%.dll$") then
		cmd = {
			"dotnet",
			ubt,
			"-Mode=GenerateClangDatabase",
			target,
			platform,
			configuration,
			"-Project=" .. uproject,
		}
	else
		cmd = {
			ubt,
			"-Mode=GenerateClangDatabase",
			target,
			platform,
			configuration,
			"-Project=" .. uproject,
		}
	end

	vim.system(cmd, {
		cwd = root,
		text = true,
	}, function(result)
		local ok = result.code == 0
		if ok then
			M.ensure_project_compile_database(root, { refresh = true, remove_source = opts.remove_source ~= false })
		end

		local compile_commands_dir = M.find_compilation_database(root)
		local payload = {
			code = result.code,
			cmd = cmd,
			stdout = result.stdout,
			stderr = result.stderr,
			compile_commands_dir = compile_commands_dir,
			target = target,
			platform = platform,
			configuration = configuration,
		}

		if ok and compile_commands_dir then
			return callback(true, payload)
		end
		if ok then
			return callback(false, "GenerateClangDatabase succeeded but compile_commands.json was not found")
		end

		local output = vim.trim(table.concat({
			result.stdout or "",
			result.stderr or "",
		}, "\n"))
		callback(false, output ~= "" and output or ("GenerateClangDatabase failed with exit code " .. tostring(result.code)))
	end)
end

function M.prepare_compile_commands(root, opts, callback)
	opts = opts or {}
	callback = callback or function() end
	root = normalize(root or project.find_project_root_from_context())
	if not root or root == "" then
		return callback(false, "Could not find .uproject")
	end

	local ready_dir = M.ensure_project_compile_database(root, {
		remove_source = opts.remove_source ~= false,
	})
	if ready_dir then
		return callback(true, {
			compile_commands_dir = ready_dir,
			generated = false,
			staged = true,
		})
	end

	if opts.auto_generate == false or config.values.clangd.auto_generate_compile_commands == false then
		return callback(false, "compile_commands.json not found")
	end

	M.generate_compile_commands(root, opts, callback)
end

function M.prewarm_current_project()
	if config.values.clangd.prewarm_on_setup == false then
		return
	end

	local root = project.find_project_root_from_context()
	if not root then
		return
	end

	M.prepare_compile_commands(root, {
		remove_source = config.values.clangd.remove_source_compile_commands ~= false,
	}, function(ok, result)
		if ok then
			return
		end

		if result and tostring(result) ~= "compile_commands.json not found" then
			vim.schedule(function()
				vim.notify("UBuildTool clangd database failed:\n" .. tostring(result), vim.log.levels.WARN)
			end)
		end
	end)
end

function M.status(root)
	root = normalize(root or project.find_project_root_from_context())
	local ubt, ubt_err, engine = nil, nil, nil
	if root then
		ubt, ubt_err, engine = project.unreal_build_tool(root)
	end

	return {
		project_root = root,
		auto_generate_compile_commands = config.values.clangd.auto_generate_compile_commands ~= false,
		compile_commands_dir = root and M.find_compilation_database(root) or nil,
		target = root and project.editor_target_name(root) or nil,
		unreal_build_tool = ubt,
		unreal_build_tool_error = ubt_err,
		engine_root = engine and engine.engine_root or nil,
	}
end

return M
