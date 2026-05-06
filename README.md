# UBuildTool.nvim

Standalone Unreal Engine build tooling for Neovim.

`UBuildTool.nvim` is the first split-out piece from `UCore.nvim`. It focuses on:

- building the configured default Unreal target
- stopping running builds
- opening the current project in Unreal Editor or Game mode
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
:UBuildTool launch
:UBuildTool launch !
:UBuildTool editor
:UBuildTool game
:UBuildTool editor !
:UBuildTool game !
:UBuildTool clangd-db
:checkhealth ubuildtool
```

## Defaults

```lua
require("ubuildtool").setup({
  cache_dir = vim.fn.stdpath("cache") .. "/ubuildtool",
  engine_roots = {},
  startup = {
    mode = "editor", -- "editor" | "game"
    configuration = "Development", -- use "DebugGame" / "Debug" for debug-style builds
    platform = "Win64",
    editor_target = nil,
    game_target = nil,
  },
  build = {
    open_quickfix_on_error = true,
    include_warnings = true,
    color_log = true,
    autosave = true,
    use_target_arguments = true,
    build_shader_compile_worker = true,
    shader_compile_worker_target = "ShaderCompileWorker",
    shader_compile_worker_platform = "Win64",
    shader_compile_worker_configuration = "Development",
    shader_compile_worker_quiet = true,
    wait_mutex = true,
    from_msbuild = true,
    extra_args = {},
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

`startup.mode` only controls whether normal launch opens `editor` or `game`.

If you want what you call "debug mode", set `startup.configuration` to `DebugGame` or `Debug`. Do not put that into `startup.mode`.

By default, builds use Rider-style Unreal Build Tool arguments:

```text
Build.bat -Target="<Project>Editor Win64 Development -Project=\"...\Project.uproject\"" -Target="ShaderCompileWorker Win64 Development -Project=\"...\Project.uproject\" -Quiet" -WaitMutex -FromMSBuild
```

Set `build.use_target_arguments = false` if you need the older positional `Build.bat <Target> <Platform> <Configuration> -Project=...` form.

## Notes

- Engine root resolution supports:
  - explicit `engine_roots`
  - Epic Launcher installs
  - source-build registry entries on Windows
- `launch` uses this plugin's own normal startup config. It does not read `UDebugTool.nvim` config.
- `editor` always forces Unreal Editor launch.
- `game` always forces Unreal Game launch.
- `build` without explicit arguments uses `startup.configuration`, `startup.platform`, and the mode-specific target from this plugin's config.
- `clangd-db` stages `compile_commands.json` into the plugin cache under `stdpath("cache")/ubuildtool/`
- when `UCore.nvim` is loaded, build logs and Unreal Editor launch messages are sent into the shared bottom output workspace instead of opening a separate build split
