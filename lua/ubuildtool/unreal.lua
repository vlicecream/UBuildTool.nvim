-- Author: Ame林汀
-- Website: vlicecream.github.io
-- File: lua/ubuildtool/unreal.lua
-- Purpose: Build Unreal targets, collect build diagnostics, and launch editor or game executables.
-- License: MIT

local config = require("ubuildtool.config")
local project = require("ubuildtool.project")

local M = {}

local build_job = nil
local build_buf = nil
local build_output = nil
local build_cancelled = false
local build_pid = nil

local build_diagnostics = {}
local build_error_count = 0
local build_warning_count = 0

local build_ns = vim.api.nvim_create_namespace("ubuildtool_build_log")
local highlights_setup = false
local on_build_line

-- Reuse the shared UCore output panel when it is available.
local function shared_output_panel()
	local panel = rawget(_G, "__ucore_output_panel_api")
	if type(panel) == "table" and type(panel.open_tab) == "function" then
		return panel
	end
	return nil
end

-- Define build-log highlight groups once for the current session.
local function setup_highlights()
	if highlights_setup then
		return
	end
	highlights_setup = true
	vim.api.nvim_set_hl(0, "UBuildToolBuildError", { fg = "#F44747", bold = true })
	vim.api.nvim_set_hl(0, "UBuildToolBuildWarning", { fg = "#FFCC66" })
	vim.api.nvim_set_hl(0, "UBuildToolBuildSuccess", { fg = "#89D185", bold = true })
	vim.api.nvim_set_hl(0, "UBuildToolBuildCommand", { fg = "#4FC1FF" })
end

-- Classify one build log line into a semantic output group.
local function build_line_group(text)
	text = tostring(text or "")
	local lower = text:lower()

	if text:match("^Project:") or text:match("^Engine:") or text:match("^Command:") then
		return "UCoreOutputCommand"
	end
	if text:match("error%s+C%d+:")
		or lower:find("fatal error", 1, true)
		or text:match("fatal error%s+LNK%d+")
		or text:match("%f[%a]LNK%d+%f[%A]")
		or lower:find("ubt error", 1, true)
		or lower:find("error:", 1, true)
	then
		return "UCoreOutputError"
	end
	if text:match("warning%s+C%d+:")
		or lower:find(": warning ", 1, true)
		or lower:find("warning:", 1, true)
	then
		return "UCoreOutputWarning"
	end
	if lower:find("succeeded", 1, true) or lower:find("finished with exit code 0", 1, true) then
		return "UCoreOutputSuccess"
	end

	return nil
end

-- Map shared UCore output groups back to UBuildTool-local highlight groups.
local function local_build_group(group)
	if group == "UCoreOutputCommand" then
		return "UBuildToolBuildCommand"
	end
	if group == "UCoreOutputError" then
		return "UBuildToolBuildError"
	end
	if group == "UCoreOutputWarning" then
		return "UBuildToolBuildWarning"
	end
	if group == "UCoreOutputSuccess" then
		return "UBuildToolBuildSuccess"
	end
	return group
end

-- Normalize one filesystem path to forward-slash form.
local function normalize(path)
	return path and path:gsub("\\", "/") or nil
end

-- Return whether one file path is readable.
local function readable(path)
	return path and vim.fn.filereadable(path) == 1
end

-- Return whether a path can be executed directly or at least exists as a file.
local function executable(path)
	return path and (vim.fn.executable(path) == 1 or readable(path))
end

-- Prefer PowerShell Core when available and fall back to Windows PowerShell otherwise.
local function powershell()
	return vim.fn.executable("pwsh") == 1 and "pwsh" or "powershell"
end

-- Quote one string for use inside a PowerShell command.
local function ps_quote(text)
	return "'" .. tostring(text):gsub("'", "''") .. "'"
end

-- Read one environment variable and return a printable placeholder when unset.
local function env_value(name)
	local value = vim.fn.getenv(name)
	if value == nil or value == vim.NIL or value == "" then
		return "<unset>"
	end
	return tostring(value)
end

-- Build the environment summary shown when launching Unreal through the shared output panel.
local function launch_environment_lines(root, shell_name)
	return {
		"LaunchCwd:   " .. tostring(root or ""),
		"LaunchShell: " .. tostring(shell_name or ""),
		"P4CONFIG:    " .. env_value("P4CONFIG"),
		"P4PORT:      " .. env_value("P4PORT"),
		"P4USER:      " .. env_value("P4USER"),
		"P4CLIENT:    " .. env_value("P4CLIENT"),
	}
end

-- Write one structured launch/build event into the optional UCore logger.
local function write_ucore_log(tag, fields)
	local ok, logger = pcall(require, "ucore.log")
	if ok and logger and type(logger.write) == "function" then
		logger.write(tag, fields)
	end
end

-- Resolve the active project, .uproject, and engine context for build or launch actions.
local function current_context()
	local root = project.find_project_root_from_context()
	if not root then
		return nil, "Could not find .uproject"
	end

	local uproject = project.find_project_file_in_root(root)
	if not uproject then
		return nil, "Could not find .uproject under project root: " .. root
	end

	local engine, engine_err = project.engine_metadata(root)
	if not engine then
		return nil, engine_err
	end

	return {
		root = root,
		uproject = uproject,
		project_name = project.project_name(root),
		engine_root = engine.engine_root,
		engine_association = engine.engine_association,
	}
end

-- Expose the resolved Unreal project context to other modules.
function M.current_context()
	return current_context()
end

-- Return the expected Build.bat path under one engine root.
local function build_bat(engine_root)
	return normalize(engine_root .. "/Engine/Build/BatchFiles/Build.bat")
end

-- Prefer a configuration-specific editor executable when one exists.
local function configuration_editor_exe(engine_root, platform, configuration)
	configuration = tostring(configuration or "")
	if configuration == "" or configuration == "Development" then
		return nil
	end

	local suffix = tostring(platform or "Win64") .. "-" .. configuration
	local candidates = {
		normalize(engine_root .. "/Engine/Binaries/Win64/UnrealEditor-" .. suffix .. ".exe"),
		normalize(engine_root .. "/Engine/Binaries/Win64/UE4Editor-" .. suffix .. ".exe"),
	}

	for _, path in ipairs(candidates) do
		if executable(path) then
			return path
		end
	end

	return nil
end

-- Resolve the best editor executable for the chosen engine, platform, and configuration.
local function editor_exe(engine_root, platform, configuration)
	if (config.values.editor or {}).prefer_configuration_executable ~= false then
		local configured = configuration_editor_exe(engine_root, platform, configuration)
		if configured then
			return configured
		end
	end

	local candidates = {
		normalize(engine_root .. "/Engine/Binaries/Win64/UnrealEditor.exe"),
		normalize(engine_root .. "/Engine/Binaries/Win64/UE4Editor.exe"),
	}

	for _, path in ipairs(candidates) do
		if executable(path) then
			return path
		end
	end

	return nil
end

-- Expose editor executable resolution to callers that need launch details.
function M.editor_executable(engine_root, platform, configuration)
	return editor_exe(engine_root, platform, configuration)
end

-- Normalize startup mode names to the supported editor/game set.
local function normalize_startup_mode(mode)
	mode = tostring(mode or ""):lower()
	if mode == "game" then
		return "game"
	end
	return "editor"
end

-- Merge startup config defaults with the current project context.
local function startup_defaults(ctx, mode_override)
	local startup = config.values.startup or {}
	local mode = normalize_startup_mode(mode_override or startup.mode)
	local target

	if mode == "game" then
		target = startup.game_target or project.game_target_name(ctx.root)
	else
		target = startup.editor_target or project.editor_target_name(ctx.root)
	end

	return {
		mode = mode,
		configuration = startup.configuration or "Development",
		platform = startup.platform or "Win64",
		target = target,
	}
end

-- Build the resolved startup profile used by launch commands.
function M.startup_profile(mode_override)
	local ctx, err = current_context()
	if not ctx then
		return nil, err
	end

	local defaults = startup_defaults(ctx, mode_override)
	return vim.tbl_extend("force", ctx, defaults), nil
end

-- Build the runtime executable candidates for a packaged or local game target.
local function game_exe_candidates(root, target, platform, configuration, project_name)
	local base = normalize(root .. "/Binaries/" .. tostring(platform))
	local items = {
		normalize(base .. "/" .. tostring(target) .. ".exe"),
		normalize(base .. "/" .. tostring(target) .. "-" .. tostring(platform) .. "-" .. tostring(configuration) .. ".exe"),
	}

	if project_name and project_name ~= "" and project_name ~= target then
		table.insert(items, normalize(base .. "/" .. tostring(project_name) .. ".exe"))
		table.insert(items, normalize(base .. "/" .. tostring(project_name) .. "-" .. tostring(platform) .. "-" .. tostring(configuration) .. ".exe"))
	end

	return items
end

-- Resolve the first existing game executable from the known candidate paths.
function M.game_executable(root, opts)
	opts = opts or {}
	local target = opts.target or project.game_target_name(root)
	local platform = opts.platform or "Win64"
	local configuration = opts.configuration or "Development"
	local project_name = opts.project_name or project.project_name(root)

	for _, path in ipairs(game_exe_candidates(root, target, platform, configuration, project_name)) do
		if executable(path) then
			return path
		end
	end

	return nil
end

-- Save modified project buffers before starting a build or launching the editor.
local function save_modified_project_buffers(root)
	root = normalize(root)
	if not root or root == "" then
		return
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified and vim.bo[bufnr].buftype == "" then
			local path = normalize(vim.api.nvim_buf_get_name(bufnr))
			if path and path:sub(1, #root) == root then
				pcall(vim.api.nvim_buf_call, bufnr, function()
					vim.cmd("silent write")
				end)
			end
		end
	end
end

-- Build the exact PowerShell command line used to invoke Unreal's Build.bat.
local function build_command(ctx, opts)
	local bat = build_bat(ctx.engine_root)
	if not readable(bat) then
		return nil, "Build.bat not found: " .. tostring(bat)
	end

	local build = config.values.build or {}
	local target = opts.target or project.editor_target_name(ctx.root)
	local platform = opts.platform or "Win64"
	local configuration = opts.configuration or "Development"
	local args = {}

	if build.use_target_arguments ~= false then
		-- Package one -Target argument in the format expected by Build.bat.
		local function target_arg(name, target_platform, target_config, extra)
			local spec = table.concat({
				tostring(name),
				tostring(target_platform),
				tostring(target_config),
				'-Project="' .. tostring(ctx.uproject) .. '"',
				extra or "",
			}, " ")
			spec = vim.trim(spec)
			return '-Target="' .. spec .. '"'
		end

		table.insert(args, target_arg(target, platform, configuration))

		if build.build_shader_compile_worker ~= false then
			local shader_extra = build.shader_compile_worker_quiet ~= false and "-Quiet" or nil
			table.insert(args, target_arg(
				build.shader_compile_worker_target or "ShaderCompileWorker",
				build.shader_compile_worker_platform or platform,
				build.shader_compile_worker_configuration or "Development",
				shader_extra
			))
		end
	else
		table.insert(args, target)
		table.insert(args, platform)
		table.insert(args, configuration)
		table.insert(args, "-Project=" .. ctx.uproject)
	end

	if build.wait_mutex ~= false then
		table.insert(args, "-WaitMutex")
	end
	if build.from_msbuild ~= false then
		table.insert(args, "-FromMSBuild")
	end
	for _, arg in ipairs(build.extra_args or {}) do
		table.insert(args, tostring(arg))
	end

	local script_parts = { "&", ps_quote(bat) }
	for _, arg in ipairs(args) do
		table.insert(script_parts, ps_quote(arg))
	end
	local script = table.concat(script_parts, " ")

	return { powershell(), "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script }, nil
end

-- Parse optional build arguments and merge them with startup defaults.
local function parse_build_args(args, ctx, mode_override)
	args = vim.trim(args or "")
	local tokens = {}
	for token in args:gmatch("%S+") do
		table.insert(tokens, token)
	end
	local defaults = startup_defaults(ctx, mode_override)
	return {
		mode = defaults.mode,
		configuration = tokens[1] or defaults.configuration,
		platform = tokens[2] or defaults.platform,
		target = tokens[3] or defaults.target,
	}
end

-- Create a scratch buffer that displays build output when the shared panel is unavailable.
local function create_log_buffer(title)
	local previous_win = vim.api.nvim_get_current_win()
	vim.cmd("botright 15new")
	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false
	vim.bo[buf].filetype = "ubuildtool-build"
	local name = title:gsub("^UBuildTool build:%s*", "UBuildTool build - ") .. " #" .. tostring(buf)
	pcall(vim.api.nvim_buf_set_name, buf, name)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		title,
		string.rep("=", vim.fn.strdisplaywidth(title)),
		"",
	})
	vim.bo[buf].modified = false

	if vim.api.nvim_win_is_valid(previous_win) then
		vim.api.nvim_set_current_win(previous_win)
	end

	return buf
end

-- Keep all visible build windows scrolled to the newest output line.
local function scroll_to_bottom(buf)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		local line_count = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_win_set_cursor(win, { line_count, 0 })
	end
end

-- Append output text to one log buffer and invoke per-line processing hooks.
local function append_lines(buf, data, on_line)
	if not data or data == "" then
		return
	end

	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
		local lines = vim.split(data, "\n", { plain = true })
		if lines[#lines] == "" then
			table.remove(lines, #lines)
		end
		if vim.tbl_isempty(lines) then
			return
		end

		local start_line = vim.api.nvim_buf_line_count(buf)
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
		vim.bo[buf].modified = false
		scroll_to_bottom(buf)

		if on_line then
			for i, line_text in ipairs(lines) do
				on_line(buf, start_line + i - 1, line_text)
			end
		end
	end)
end

-- Parse one compiler or linker output line into a quickfix-style diagnostic item.
local function parse_diagnostic_line(line, project_root)
	local path, lnum, col, kind, msg = line:match(
		"^(.-)%((%d+)(?:,(%d+))?%)%s*:%s*(error|warning)%s+(.+)$"
	)
	if path then
		lnum = tonumber(lnum)
		col = tonumber(col or 0)
		kind = (kind == "error") and "E" or "W"
		if not readable(path) and project_root then
			local abs = normalize(project_root .. "/" .. path)
			if readable(abs) then
				path = abs
			end
		end
		return { filename = path, lnum = lnum, col = col, type = kind, text = msg }
	end

	local path2, lnum2, col2, kind2, msg2 = line:match(
		"^([A-Za-z]:[^:]+):(%d+):(%d+):%s*(error|warning):%s*(.+)$"
	)
	if path2 then
		return {
			filename = path2,
			lnum = tonumber(lnum2),
			col = tonumber(col2),
			type = (kind2 == "error") and "E" or "W",
			text = msg2,
		}
	end

	if line:find("fatal error LNK", 1, true) then
		local msg3 = line:match("fatal error LNK%d+%s*:.*$") or line
		return { type = "E", text = msg3 }
	end

	if line:find("Error:", 1, true) and (line:match("^LogCompile") or line:match("^LogLinker")) then
		return { type = "E", text = line }
	end

	return nil
end

-- Apply semantic highlighting to one build log line when color output is enabled.
local function color_build_line(buf, line_num, text)
	if not config.values.build.color_log then
		return
	end

	local group = local_build_group(build_line_group(text))

	if group then
		local end_col = math.max(0, vim.fn.strchars(text))
		vim.api.nvim_buf_set_extmark(buf, build_ns, line_num, 0, {
			hl_group = group,
			end_row = line_num,
			end_col = end_col,
		})
	end
end

-- Split one stdout or stderr chunk into normalized display lines.
local function split_lines(data)
	if not data or data == "" then
		return {}
	end

	data = tostring(data):gsub("\r\n", "\n"):gsub("\r", "\n")
	local lines = vim.split(data, "\n", { plain = true })
	if lines[#lines] == "" then
		table.remove(lines, #lines)
	end
	return lines
end

-- Create the active build output sink, preferring the shared output panel.
local function build_output_sink(title)
	local panel = shared_output_panel()
	if panel then
		return {
			kind = "panel",
			panel = panel,
			key = panel.open_tab({
				key = "workspace:build",
				title = "Build",
				kind = "build",
				focus = true,
			}),
		}
	end

	return {
		kind = "buffer",
		buf = create_log_buffer(title),
	}
end

-- Append a build output chunk and optionally parse diagnostics from each line.
local function append_build_chunk(sink, project_root, data, no_parse)
	if not data or data == "" then
		return
	end

	if sink.kind == "panel" then
		local lines = split_lines(data)
		if vim.tbl_isempty(lines) then
			return
		end

		local groups = {}
		for i, line_text in ipairs(lines) do
			if not no_parse then
				local item = parse_diagnostic_line(line_text, project_root)
				if item then
					table.insert(build_diagnostics, item)
					if item.type == "E" then
						build_error_count = build_error_count + 1
					elseif item.type == "W" then
						build_warning_count = build_warning_count + 1
					end
				end
			end
			groups[i] = build_line_group(line_text)
		end

		sink.panel.append(sink.key, lines, {
			focus = false,
			line_groups = groups,
		})
		return
	end

	append_lines(sink.buf, data, function(b, ln, t)
		on_build_line(project_root, b, ln, t, no_parse)
	end)
end

-- Publish parsed build diagnostics into quickfix and UCore diagnostic views.
local function fill_quickfix()
	local items = {}
	for _, item in ipairs(build_diagnostics) do
		if config.values.build.include_warnings ~= false or item.type == "E" then
			table.insert(items, item)
		end
	end

	pcall(function()
		require("ucore.diagnostics").from_quickfix(items)
	end)

	if vim.tbl_isempty(items) then
		return
	end

	vim.fn.setqflist(items, "r")

	if config.values.build.open_quickfix_on_error and build_error_count > 0 then
		vim.cmd("botright copen")
		vim.cmd("wincmd p")
	end
end

-- Summarize build completion status, error count, warning count, and exit code.
local function build_summary(ok, exit_code)
	local parts = {}
	table.insert(parts, ok and "Build succeeded" or "Build failed")
	if build_error_count > 0 then
		table.insert(parts, build_error_count .. " error" .. (build_error_count > 1 and "s" or ""))
	end
	if build_warning_count > 0 then
		table.insert(parts, build_warning_count .. " warning" .. (build_warning_count > 1 and "s" or ""))
	end
	if exit_code ~= nil then
		table.insert(parts, "exit " .. exit_code)
	end
	return table.concat(parts, ", ")
end

-- Process one build output line into diagnostics and syntax highlighting state.
on_build_line = function(project_root, buf, line_num, text, no_parse)
	if not no_parse then
		local item = parse_diagnostic_line(text, project_root)
		if item then
			table.insert(build_diagnostics, item)
			if item.type == "E" then
				build_error_count = build_error_count + 1
			elseif item.type == "W" then
				build_warning_count = build_warning_count + 1
			end
		end
	end
	color_build_line(buf, line_num, text)
end

-- Reset build-scoped diagnostics and cancellation flags before a new job starts.
local function reset_diagnostics()
	build_diagnostics = {}
	build_error_count = 0
	build_warning_count = 0
	build_cancelled = false
end

-- Start one asynchronous Unreal build and stream output into the active sink.
local function start_build(args, callback, mode_override)
	callback = callback or function() end

	if build_job then
		vim.notify("UBuildTool build is already running", vim.log.levels.WARN)
		return callback(false, "build already running")
	end

	local ctx, err = current_context()
	if not ctx then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return callback(false, err)
	end

	if config.values.build.autosave ~= false then
		save_modified_project_buffers(ctx.root)
	end

	local opts = parse_build_args(args, ctx, mode_override)
	local cmd, cmd_err = build_command(ctx, opts)
	if not cmd then
		vim.notify(tostring(cmd_err), vim.log.levels.ERROR)
		return callback(false, cmd_err)
	end

	reset_diagnostics()
	setup_highlights()

	local title = string.format("UBuildTool build: %s %s %s", opts.target, opts.platform, opts.configuration)
	local sink = build_output_sink(title)
	build_output = sink
	if sink.kind == "buffer" then
		build_buf = sink.buf
	end

	if sink.kind == "panel" then
		sink.panel.replace(sink.key, {
			"Project: " .. ctx.uproject,
			"Engine:  " .. ctx.engine_root,
			"Command: " .. table.concat(cmd, " "),
			"",
		}, {
			title = "Build",
			kind = "build",
			focus = true,
			line_groups = {
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
			},
		})
	else
		append_build_chunk(sink, ctx.root, "Project: " .. ctx.uproject .. "\nEngine:  " .. ctx.engine_root .. "\nCommand: " .. table.concat(cmd, " ") .. "\n", true)
	end

	local project_root = ctx.root
	build_job = vim.system(cmd, {
		cwd = ctx.root,
		text = true,
		stdout = function(_, data)
			append_build_chunk(sink, project_root, data, false)
		end,
		stderr = function(_, data)
			append_build_chunk(sink, project_root, data, true)
		end,
	}, function(result)
		build_job = nil
		build_pid = nil
		-- Keep sink-local state so the completion callback can finish even after globals are reset.
		local this_buf = build_buf
		local this_output = build_output
		build_buf = nil
		build_output = nil
		local was_cancelled = build_cancelled

		vim.schedule(function()
			if not was_cancelled then
				local ok = result.code == 0
				local summary = build_summary(ok, result.code)
				local level = ok and vim.log.levels.INFO or vim.log.levels.ERROR

				if this_output and this_output.kind == "panel" then
					this_output.panel.append(this_output.key, {"", summary}, {
						focus = false,
						line_groups = { nil, ok and "UCoreOutputSuccess" or "UCoreOutputError" },
					})
					if ok then
						this_output.panel.finish(this_output.key, nil, { open = true })
					else
						this_output.panel.fail(this_output.key, nil, { open = true, focus = false })
					end
				elseif this_buf and vim.api.nvim_buf_is_valid(this_buf) then
					append_lines(this_buf, "")
					append_lines(this_buf, summary)
				end

				vim.notify(summary, level)
				fill_quickfix()
				callback(ok, result, ctx)
			else
				vim.notify("UBuildTool build stopped", vim.log.levels.WARN)
				callback(false, "cancelled")
			end
		end)
	end)
	build_pid = build_job and build_job.pid or nil
end

-- Return whether the current host platform is Windows.
local function is_windows()
	return package.config:sub(1, 1) == "\\"
end

-- Terminate the active build process tree on the current platform.
local function kill_process_tree(pid)
	if not pid then
		return false
	end
	if is_windows() then
		vim.system({ "taskkill", "/PID", tostring(pid), "/T", "/F" }, { text = true }, function() end)
		return true
	end
	if build_job then
		return pcall(function()
			build_job:kill(15)
		end)
	end
	return false
end

-- Launch one resolved Unreal profile and mirror the launch context into the shared output panel.
local function launch_profile(profile)
	local program = profile.program
	if not program then
		return vim.notify("Launch program was not found", vim.log.levels.ERROR)
	end

	local panel = shared_output_panel()
	local shell_name = powershell()
	local env_lines = launch_environment_lines(profile.root, shell_name)
	if panel then
		local key = panel.open_tab({
			key = "workspace:unreal",
			title = "Unreal",
			kind = "unreal",
			focus = true,
		})
		panel.replace(key, {
			"Project: " .. tostring(profile.project_name or ""),
			"Engine:  " .. tostring(profile.engine_root or ""),
			"Mode:    " .. tostring(profile.mode or ""),
			"Target:  " .. tostring(profile.target or ""),
			"Program: " .. tostring(program),
			env_lines[1],
			env_lines[2],
			env_lines[3],
			env_lines[4],
			env_lines[5],
			env_lines[6],
			"",
			"Opening " .. tostring(profile.display_name or "Unreal") .. "...",
		}, {
			title = "Unreal",
			line_groups = {
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				"UCoreOutputCommand",
				nil,
				"UCoreOutputInfo",
			},
			focus = true,
		})
		panel.finish(key, nil, { open = true })
	end

	write_ucore_log("ubuildtool.unreal_launch", {
		project = profile.project_name,
		program = program,
		root = profile.root,
		shell = shell_name,
		p4config = env_value("P4CONFIG"),
		p4port = env_value("P4PORT"),
		p4user = env_value("P4USER"),
		p4client = env_value("P4CLIENT"),
	})

	vim.system({
		shell_name,
		"-NoProfile",
		"-ExecutionPolicy",
		"Bypass",
		"-Command",
		"Start-Process -FilePath "
			.. ps_quote(program)
			.. " -ArgumentList @("
			.. table.concat(vim.tbl_map(ps_quote, profile.program_args or {}), ", ")
			.. ") -WorkingDirectory "
			.. ps_quote(profile.root),
	}, { cwd = profile.root }, function() end)

	vim.notify("Opening " .. tostring(profile.display_name or "Unreal") .. ": " .. tostring(profile.project_name or ""), vim.log.levels.INFO)
end

-- Start a build using the default startup/build profile.
function M.build(args)
	start_build(args)
end

-- Start a build and forward completion status to the supplied callback.
function M.build_async(args, callback)
	start_build(args, callback)
end

-- Return whether a build job is currently active.
function M.is_build_running()
	return build_job ~= nil
end

-- Stop the active build job and close out any remaining UI state.
function M.cancel_build()
	if not build_job then
		return vim.notify("No UBuildTool build is running", vim.log.levels.INFO)
	end

	build_cancelled = true
	local buf = build_buf
	local sink = build_output
	local pid = build_pid or (build_job and build_job.pid) or nil
	kill_process_tree(pid)
	build_job = nil
	build_pid = nil
	build_buf = nil
	build_output = nil

	if sink and sink.kind == "panel" then
		sink.panel.append(sink.key, {"", "UBuildTool build stopped"}, {
			focus = false,
			line_groups = { nil, "UCoreOutputWarning" },
		})
		sink.panel.finish(sink.key, nil, {
			open = true,
			status = "success",
		})
	elseif buf and vim.api.nvim_buf_is_valid(buf) then
		append_lines(buf, "")
		append_lines(buf, "UBuildTool build stopped")
	end
end

-- Resolve the executable and arguments needed to launch editor or game mode.
local function resolve_launch_profile(mode_override)
	local profile, err = M.startup_profile(mode_override)
	if not profile then
		return nil, err
	end

	if profile.mode == "game" then
		local game_exe = M.game_executable(profile.root, profile)
		if game_exe then
			profile.program = game_exe
			profile.program_args = {}
			profile.display_name = "Unreal Game"
			return profile, nil
		end

		local editor = editor_exe(profile.engine_root, profile.platform, profile.configuration)
		if not editor then
			return nil, "Unreal game executable was not found and UnrealEditor.exe fallback is unavailable"
		end

		profile.program = editor
		profile.program_args = { profile.uproject, "-game" }
		profile.display_name = "Unreal Game"
		profile.uses_editor_fallback = true
		return profile, nil
	end

	local editor = editor_exe(profile.engine_root, profile.platform, profile.configuration)
	if not editor then
		return nil, "UnrealEditor.exe not found under: " .. tostring(profile.engine_root)
	end

	profile.program = editor
	profile.program_args = { profile.uproject }
	profile.display_name = "Unreal Editor"
	return profile, nil
end

-- Build first when configured, then launch the resolved editor or game profile.
function M.open_mode(mode_override, args)
	local profile, err = resolve_launch_profile(mode_override)
	if not profile then
		return vim.notify(tostring(err), vim.log.levels.ERROR)
	end

	if config.values.editor.autosave ~= false then
		save_modified_project_buffers(profile.root)
	end

	if config.values.editor.build_before_open == false or args == "!" then
		return launch_profile(profile)
	end

	start_build(args, function(ok, _, build_ctx)
		if not ok then
			return vim.notify("UBuildTool launch: build failed, not opening " .. tostring(profile.display_name or "Unreal"), vim.log.levels.ERROR)
		end

		local refreshed = build_ctx and resolve_launch_profile(mode_override) or nil
		launch_profile(refreshed or profile)
	end, mode_override)
end

-- Build and open Unreal Editor mode.
function M.open_editor(args)
	return M.open_mode("editor", args)
end

-- Build and open Unreal Game mode.
function M.open_game(args)
	return M.open_mode("game", args)
end

-- Build and open whichever startup mode is configured by default.
function M.open_startup(args)
	return M.open_mode(nil, args)
end

return M
