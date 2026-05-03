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
