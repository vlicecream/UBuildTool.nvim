if vim.g.loaded_ubuildtool == 1 then
	return
end

vim.g.loaded_ubuildtool = 1

require("ubuildtool").setup()
