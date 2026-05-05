local actions = require("ubuildtool.commands.actions")

local M = {}

local function normalize_subcommand(args)
	local sub = (args.args or ""):match("^%s*(%S+)")
	return sub and sub:lower() or "help"
end

local function command_tail(args)
	return (args.args or ""):match("^%s*%S+%s*(.-)%s*$") or ""
end

function M.dispatch(args)
	local sub = normalize_subcommand(args)
	local tail = command_tail(args)

	local handlers = {
		help = actions.help,
		build = function()
			actions.build(tail)
		end,
		["build-stop"] = actions.build_cancel,
		["build-cancel"] = actions.build_cancel,
		buildstop = actions.build_cancel,
		buildcancel = actions.build_cancel,
		launch = function()
			actions.launch(tail)
		end,
		editor = function()
			actions.editor(tail)
		end,
		game = function()
			actions.game(tail)
		end,
		["clangd-db"] = function()
			actions.clangd_database(tail)
		end,
		clangddb = function()
			actions.clangd_database(tail)
		end,
	}

	local handler = handlers[sub]
	if not handler then
		vim.notify("Unknown UBuildTool command: " .. sub, vim.log.levels.ERROR)
		return actions.help()
	end

	handler()
end

function M.register()
	pcall(vim.api.nvim_del_user_command, "UBuildTool")

	vim.api.nvim_create_user_command("UBuildTool", M.dispatch, {
		nargs = "*",
		complete = function(arglead)
			local items = {
				"build",
				"build-stop",
				"launch",
				"editor",
				"game",
				"clangd-db",
				"help",
			}
			local needle = (arglead or ""):lower()
			return vim.tbl_filter(function(item)
				return item:find(needle, 1, true) == 1
			end, items)
		end,
	})
end

return M
