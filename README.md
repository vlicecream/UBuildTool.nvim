# UBuildTool.nvim

Standalone Unreal Engine build tooling for Neovim.

`UBuildTool.nvim` is the first split-out piece from `UCore.nvim`. It focuses on:

- building the current Unreal Editor target
- stopping running builds
- opening the current project in Unreal Editor
- preparing `compile_commands.json` for `clangd`
- build log coloring and quickfix population
- optional shared bottom output tabs when `UCore.nvim` is present

## Install

```lua
{
  "vlicecream/UBuildTool.nvim",
  main = "ubuildtool",
  lazy = false,
  opts = {},
}
```

## Commands

```vim
:UBuildTool
:UBuildTool build [configuration] [platform] [target]
:UBuildTool build-stop
:UBuildTool editor
:UBuildTool editor !
:UBuildTool clangd-db
:checkhealth ubuildtool
```

## Defaults

```lua
require("ubuildtool").setup({
  cache_dir = vim.fn.stdpath("cache") .. "/ubuildtool",
  engine_roots = {},
  build = {
    open_quickfix_on_error = true,
    include_warnings = true,
    color_log = true,
    autosave = true,
  },
  editor = {
    build_before_open = true,
    autosave = true,
  },
  clangd = {
    auto_generate_compile_commands = true,
    prewarm_on_setup = true,
    remove_source_compile_commands = true,
  },
})
```

## Notes

- Engine root resolution supports:
  - explicit `engine_roots`
  - Epic Launcher installs
  - source-build registry entries on Windows
- `clangd-db` stages `compile_commands.json` into the plugin cache under `stdpath("cache")/ubuildtool/`
- when `UCore.nvim` is loaded, build logs and Unreal Editor launch messages are sent into the shared bottom output workspace instead of opening a separate build split
