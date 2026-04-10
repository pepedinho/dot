# Dot

> A blazing-fast, modal terminal text editor written in **Zig**, deeply scriptable with embedded **Lua 5.5!**.

![ed](https://github.com/user-attachments/assets/8acd0451-f61f-46e3-b72c-6b361effdc91)

**Dot** is a high-performance terminal text editor built from the ground up in Zig. It aims to combine the speed and memory safety of Zig with the limitless extensibility of Lua. Rather than forcing plugins to draw UI elements manually, Dot embraces a "Lua drives the logic, Zig handles the rendering" philosophy.

## Key Features

* **Zero-Dependency Lua Embedding:** Lua 5.5 C sources are compiled directly into the editor via `zig build`. No external dynamic libraries required.
* **Modal Editing:** Native Vim-like keybindings (Normal, Insert, Command, Search modes).
* **Gap Buffer:** Efficient text manipulation using a Gap Buffer data structure.
* **Smart Rendering Engine:** A 4-speed rendering pipeline (Full, Targeted/Dirty, Micro/Line, Animations) ensuring maximum FPS and minimal terminal flickering.
* **Rich UI Components:** Built-in floating windows, Toast notifications, and Popup Menus (PUM) accessible via the Lua API.
* **Split Panes:** Support for vertical and horizontal window splitting (`:vsplit`, `:split`).
* **Bulletproof History:** Transaction-based Undo/Redo tree.

---

## Getting Started

### Prerequisites
* **Zig** (v0.15.2 or newer)

### Building from Source

Clone the repository and build the project using Zig's build system:

    git clone https://github.com/yourusername/pepedinho-dot.git
    cd pepedinho-dot
    zig build run

To open a specific file:

    zig build run -- src/main.zig

---

## Default Keybindings

Dot uses familiar modal keybindings.

| Key | Action (Normal Mode) |
| :--- | :--- |
| `i` | Enter Insert Mode |
| `a` | Append after cursor |
| `o` | Append on a new line |
| `x` | Delete character under cursor |
| `w` | Jump to next word |
| `u` | Undo |
| `y` / `p` | Yank line / Paste |
| `:` / `/` | Open Command Prompt / Search |
| `n` / `N` | Next / Previous search result |

### Built-in Commands (`:`)
* `:w` / `:wq` / `:q` - Write, Write & Quit, Quit
* `:open <path>` - Open a file in the current view
* `:vsplit` / `:split` - Split the current view
* `:bnext` / `:bprev` - Cycle through active buffers
* `:source <file.lua>` - Execute a Lua plugin script
* `:debug` - Open the internal performance/memory debug panel

---

## The Lua Plugin System

![Lua Autocompletion Demo](path/to/your/autocomplete_demo.gif)

Dot is designed to be fully customizable. The editor exposes a global `dot` API to Lua, allowing you to intercept internal events, modify buffers, and spawn UI components without touching the Zig source code.

### Event Hooks ("Prevent Default")
You can intercept editor actions before they happen. If your Lua callback returns `true`, Dot's default behavior is cancelled!
```lua
    -- File: examples/hook.lua
    dot.print("Auto-Cleaner Loaded!")
    
    -- Intercept the save event
    dot.hook_on("BufWritePre", function()
        local cursor = dot.get_cursor()
        
        dot.insert("\n// File Saved via Lua Hook!")
        dot.print("Hook BufWritePre triggered")
        
        return true -- Zig continues the save operation
    end)
```
### Building Custom UI (Popup Menus)
Lua can command Zig's rendering engine to display complex interactive components like popup menus (PUM) for autocompletion.
```lua
    -- Example: Displaying a popup menu at the cursor
    local matches = { "main.zig", "core.zig", "utils.zig" }
    local cursor = dot.get_cursor()
    
    dot.show_pum(cursor[2], cursor[1] - 1, matches, 0)
```
*(Check out `examples/cmd_completion.lua` for a complete implementation of path autocompletion using `CmdTab` and `read_dir`!)*

### LSP & Autocompletion Support
Writing plugins is easy thanks to the included **EmmyLua definitions**. Simply point your Lua Language Server to the `src/api/dot.lua` file to get full type hinting and documentation for the `dot` API right in your editor.

---

## Architecture Overview

For developers interested in the internals, Dot is built around a few core pillars:

1. **The Action Queue:** User inputs are translated into `Action` enums and pushed into a ring buffer. The `Editor` consumes this queue sequentially, ensuring thread-safe, predictable state mutations.
2. **Event-Driven C-API:** When an action occurs, Zig queries the `LUA_REGISTRYINDEX` to check for registered callbacks, executing them synchronously.
3. **The Scheduler:** A fixed-size, allocation-free job scheduler handles recurring tasks (like UI ticks, animation phases, and expiring Toasts).
4. **Retained-Mode UI with Span Styling:** The Renderer uses an `ArenaAllocator` to build lines consisting of styled `Spans` (colors, bold, and even dynamic Shimmer effects), diffs them, and writes standard ANSI escape sequences to `stdout`.

## Directory Structure

    dot/
    ├── build.zig          # Zig build script (compiles Zig + Lua C sources)
    ├── examples/          # Example Lua plugins (Autocompletion, Formatting)
    ├── vendor/lua/        # Lua 5.5 C Source code
    └── src/
        ├── main.zig       # Entry point
        ├── api/           # Zig-Lua C-API bindings & EmmyLua definitions
        ├── core/          # Editor state, GapBuffer, History, ActionQueue
        ├── view/          # Rendering engine, ANSI, Popups, PUM, Toasts
        └── fs/            # File system mmap loaders

---
