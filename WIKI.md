# dot — Project Wiki

> **dot** is a lightweight, modal terminal text editor written in [Zig](https://ziglang.org/), heavily inspired by Vim.
> It runs entirely in the terminal, has zero external dependencies, and is built around a gap-buffer text data structure.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Repository Layout](#2-repository-layout)
3. [Architecture](#3-architecture)
4. [Module Reference](#4-module-reference)
   - 4.1 [Entry Point — `src/main.zig`](#41-entry-point--srcmainzig)
   - 4.2 [Gap Buffer — `src/buffer/gap.zig`](#42-gap-buffer--srcbuffergapzig)
   - 4.3 [Editor Core — `src/buffer/core.zig`](#43-editor-core--srcbuffercorezig)
   - 4.4 [Filesystem — `src/fs/filesystem.zig`](#44-filesystem--srcfsfilesystemzig)
   - 4.5 [Terminal — `src/view/terminal.zig`](#45-terminal--srcviewterminalzig)
   - 4.6 [Keyboard — `src/view/keyboard.zig`](#46-keyboard--srcviewkeyboardzig)
   - 4.7 [UI / Rendering — `src/view/ui.zig`](#47-ui--rendering--srcviewuizig)
   - 4.8 [Popup System — `src/view/pop.zig`](#48-popup-system--srcviewpopzig)
   - 4.9 [Utilities — `src/utils.zig`](#49-utilities--srcutilszig)
5. [Editor Modes](#5-editor-modes)
6. [Keybindings](#6-keybindings)
7. [Commands](#7-commands)
8. [Data Structures In Depth](#8-data-structures-in-depth)
9. [Memory Management](#9-memory-management)
10. [Build System](#10-build-system)
11. [CLI Usage](#11-cli-usage)
12. [Development History](#12-development-history)
13. [Known Limitations & Future Work](#13-known-limitations--future-work)

---

## 1. Overview

| Property | Value |
|----------|-------|
| Language | Zig |
| Minimum Zig version | 0.15.2 |
| Package version | 0.0.0 (pre-release) |
| External dependencies | **None** |
| Platforms | Linux, macOS |
| Editor paradigm | Modal (Normal / Insert / Command) |

dot opens a file passed on the command line, displays it inside the terminal's **alternate screen buffer** (so it doesn't clobber your shell history), and lets you edit and save it using a Vim-like key model.

---

## 2. Repository Layout

```
dot/
├── build.zig          # Zig build script
├── build.zig.zon      # Package manifest (name, version, fingerprint, paths)
├── WIKI.md            # This document
└── src/
    ├── main.zig           # Program entry point & main event loop
    ├── utils.zig          # Shared utility types
    ├── buffer/
    │   ├── gap.zig        # GapBuffer — core text storage data structure
    │   └── core.zig       # Editor struct, Action enum, Mode enum, Window struct
    ├── fs/
    │   └── filesystem.zig # File open / mmap-based fast loading
    └── view/
        ├── terminal.zig   # Raw mode, alternate screen management
        ├── keyboard.zig   # Key reading and escape-sequence parsing
        ├── ui.zig         # Full-screen and partial rendering, status bar
        └── pop.zig        # Popup window data structure and renderer
```

---

## 3. Architecture

```
┌──────────────────────────────────────────────────────┐
│                     main.zig                         │
│                                                      │
│  1. Parse CLI args → load file into GapBuffer        │
│  2. Enter raw mode + alternate screen                │
│  3. Main loop:                                       │
│       • Render (full or partial)                     │
│       • Render popups                                │
│       • Read key → translate to Action               │
│       • editor.execute(action)                       │
│       • Update terminal window size                  │
│  4. Close alternate screen + restore terminal        │
└──────────┬───────────────────────────────────────────┘
           │ owns
           ▼
┌──────────────────────┐     ┌──────────────────────┐
│  Editor (core.zig)   │────▶│  GapBuffer (gap.zig) │
│  mode / cmd_buf /    │     │  gap_start / gap_end  │
│  pop_store / win     │     │  buffer []u8          │
└──────────────────────┘     └──────────────────────┘
           │
           ├── view/ui.zig        (renders Editor state to stdout)
           ├── view/pop.zig       (renders each Pop from pop_store)
           ├── view/terminal.zig  (raw mode, alt screen)
           ├── view/keyboard.zig  (reads Key from stdin)
           └── fs/filesystem.zig  (loads file on startup, saves on :w)
```

The overall design follows a **unidirectional data flow**:

```
Input (keyboard) → Action → Editor.execute() → State mutation → Render
```

---

## 4. Module Reference

### 4.1 Entry Point — `src/main.zig`

The `main` function:

1. Creates a `GeneralPurposeAllocator` with leak detection (exits with code 42 on leaks).
2. Enables raw terminal mode and opens the alternate screen.
3. Initialises the `Editor` struct.
4. If a filename is passed as a CLI argument:
   - Records the filename on the editor (`dot.loadFile`).
   - Reads the file content via `Fs.loadFast` (memory-mapped).
   - Initialises the `GapBuffer` from the file content (`GapBuffer.initFromFile`).
5. Runs the **main event loop**:
   - Conditionally calls `ui.refreshScreen` (full redraw) or `ui.updateCurrentLine` (fast partial update).
   - Renders all active popups.
   - Flushes the stdout buffer.
   - Reads the next key with `keyboard.readKey`.
   - Maps the key to an `Action` based on the current editor mode.
   - Dispatches the action via `editor.execute`.
   - Calls `win.updateSize()` to track terminal resize.
6. Closes the alternate screen on exit.

The stdout is wrapped in a **buffered writer** (`[4096]u8` stack buffer) to batch escape sequences and text into fewer `write` syscalls.

---

### 4.2 Gap Buffer — `src/buffer/gap.zig`

The `GapBuffer` is the core text storage data structure. It stores all text as a single flat byte slice with a moveable "gap" at the cursor position.

```
[ text before cursor ] [ ---- gap ---- ] [ text after cursor ]
 0                  gap_start         gap_end             .len
```

- **Insertions** at the cursor are `O(1)` — just write into the gap and advance `gap_start`.
- **Deletions** (backspace) are `O(1)` — decrement `gap_start`.
- **Cursor movement** copies one byte across the gap boundary.
- **Gap exhaustion** triggers `expand()`, which doubles capacity.

#### Constants

| Name | Value | Purpose |
|------|-------|---------|
| `INITIAL_CAPACITY` | `1024` | Initial byte capacity for a new buffer |
| `TAB_SIZE` | `8` | Visual width of a tab character for cursor positioning |

#### Public API

| Function | Description |
|----------|-------------|
| `init(allocator)` | Create an empty buffer of `INITIAL_CAPACITY` bytes |
| `initFromFile(allocator, text)` | Create a buffer pre-loaded with file content; capacity = `text.len + INITIAL_CAPACITY` |
| `deinit()` | Free the backing allocation |
| `moveCursorLeft()` | Move gap one byte to the left |
| `moveCursorRight()` | Move gap one byte to the right |
| `moveCursorUp()` | Move cursor to the same column on the previous line |
| `moveCursorDown()` | Move cursor to the same column on the next line |
| `insertChar(char)` | Insert one byte at cursor; auto-expands if gap is empty |
| `backspace()` | Delete the character before the cursor (`gap_start--`) |
| `getFirst()` | Return slice `buffer[0..gap_start]` (text before cursor) |
| `getSecond()` | Return slice `buffer[gap_end..len]` (text after cursor) |
| `getCursorPos()` | Scan `getFirst()` and return `{x, y}` (1-based, tab-aware) |
| `printDebug()` | Print buffer state to stderr for debugging |

---

### 4.3 Editor Core — `src/buffer/core.zig`

Defines the main editor state machine and all supporting types.

#### `Mode` enum

```zig
pub const Mode = enum { Normal, Insert, Command };
```

#### `Action` union

All mutations to editor state happen through a single `Action` value dispatched to `Editor.execute`.

| Action | Payload | Effect |
|--------|---------|--------|
| `InsertChar` | `u8` | Insert byte at cursor |
| `InsertNewLine` | — | Insert `\n` at cursor |
| `DeleteChar` | — | Backspace |
| `MoveLeft/Right/Up/Down` | — | Move cursor |
| `SetMode` | `Mode` | Switch editor mode |
| `Append` | — | Move right then enter Insert |
| `AppendNewLine` | — | Move down then enter Insert |
| `CreatePop` | `PopBuilder` | Create a new popup window |
| `CommandChar` | `u8` | Append byte to command buffer |
| `CommandBackspace` | — | Remove last byte from command buffer |
| `ExecuteCommand` | — | Parse and run current command buffer |
| `ClearCommandBuf` | — | Clear command buffer without executing |
| `Quit` | — | Set `is_running = false` |
| `Tick` | — | Housekeeping (expire timed popups) |

#### `PopBuilder` struct

A configuration struct used to create a popup via `CreatePop`:

```zig
pub const PopBuilder = struct {
    size: Pos,        // width (x) and height (y) in terminal cells
    pos:  Pos,        // top-left corner position
    text: []const u8, // content to write into the popup
    duration_ms: ?i64, // null = persistent; some value = auto-expire
};
```

#### `Window` struct

Queries the terminal size using the `TIOCGWINSZ` ioctl on `STDOUT_FILENO`. Handles both macOS (`0x40087468`) and Linux (`0x5413`) constants automatically.

```zig
pub const Window = struct {
    rows: u16,
    cols: u16,
    pub fn init() !Window
    pub fn updateSize(self: *Window) !void
};
```

#### `Editor` struct

| Field | Type | Description |
|-------|------|-------------|
| `allocator` | `std.mem.Allocator` | Allocator for all heap allocations |
| `buf` | `GapBuffer` | The text buffer |
| `mode` | `Mode` | Current editor mode |
| `last_mode` | `Mode` | Previous mode (restored after command execution) |
| `is_running` | `bool` | Main loop gate |
| `needs_redraw` | `bool` | Full-screen redraw flag |
| `win` | `Window` | Terminal dimensions |
| `cmd_buf` | `ArrayListUnmanaged(u8)` | Command character accumulator |
| `filename` | `?[]const u8` | Path of the open file |
| `pop_store` | `AutoHashMap(u32, Pop)` | Active popup windows keyed by ID |
| `next_popup_id` | `u32` | Auto-incrementing popup ID counter |

Key methods:

| Method | Description |
|--------|-------------|
| `init(allocator)` | Allocate and initialise the editor |
| `deinit()` | Free all resources |
| `loadFile(filename)` | Record the filename (does not read from disk) |
| `execute(action)` | Dispatch an action and mutate state |
| `saveFile()` | Write buffer content to disk (errors if no filename is set) |
| `createPop(pos, size, duration_ms)` | Allocate a new `Pop` and store it; returns its ID |
| `destroyPop(id)` | Remove and free a popup by ID |
| `renderAllPopup(stdout)` | Render every popup in `pop_store` |
| `quit()` | Set `is_running = false` |

**Command execution (`executeCmd`):**

| Input | Effect |
|-------|--------|
| `q` | Quit |
| `w` | Save file (`saveFile`) |
| `wq` | Save file then quit |
| *(anything else)* | No-op (mode resets silently) |

After any command, the mode reverts to `last_mode` and `cmd_buf` is cleared.

---

### 4.4 Filesystem — `src/fs/filesystem.zig`

The `Fs` struct provides two functions:

#### `Fs.open(path) !std.fs.File`

Opens a file for reading, handling both absolute and relative paths transparently.

#### `Fs.loadFast(allocator, path) ![]u8`

Loads a file into an owned heap slice using **`mmap`** for fast reading:

1. Open the file.
2. Get the file size (`getEndPos`).
3. `mmap` the file as read-only private.
4. `allocator.dupe` the mapped region into heap memory.
5. `munmap` the mapping immediately after copying.

This approach avoids repeated `read` syscalls for large files and hands the caller a standard allocator-owned slice they can `free` normally.

---

### 4.5 Terminal — `src/view/terminal.zig`

Manages the raw terminal state and the alternate screen buffer.

#### `enableRawMode() !void`

Saves the current `termios` settings and reconfigures the terminal:

| Flag | Group | Disabled effect |
|------|-------|-----------------|
| `ECHO` | `lflag` | Characters are not echoed automatically |
| `ICANON` | `lflag` | Input is delivered byte-by-byte (no line buffering) |
| `ISIG` | `lflag` | `Ctrl-C`/`Ctrl-Z` signals are not raised |
| `IEXTEN` | `lflag` | Extended processing (e.g., `Ctrl-V`) is disabled |
| `IXON` | `iflag` | Software flow control (`Ctrl-S`/`Ctrl-Q`) disabled |
| `ICRNL` | `iflag` | `\r` is not converted to `\n` on input |
| `BRKINT` | `iflag` | Break no longer sends `SIGINT` |
| `INPCK` | `iflag` | Parity checking disabled |
| `ISTRIP` | `iflag` | 8th bit stripping disabled |
| `OPOST` | `oflag` | Output post-processing disabled (no auto `\r\n`) |

`cc[MIN] = 0` and `cc[TIME] = 1` make `read` return after a 100 ms timeout even when no bytes are available (enables the `.none` key / `Tick` action).

#### `disableRawMode() void`

Restores the saved `termios` settings. Called via `defer` in `main`.

#### `openAlternateScreen(stdout) !void` / `closeAlternateScreen(stdout) !void`

Send `\x1b[?1049h` (enter) and `\x1b[?1049l` (exit) to switch between the normal and alternate terminal screen buffers.

---

### 4.6 Keyboard — `src/view/keyboard.zig`

#### `Key` union

```zig
pub const Key = union(enum) {
    ascii: u8,   // printable or control characters
    up, down, right, left,
    backspace,
    enter,
    escape,
    none,        // no byte was available (read timed out)
};
```

#### `readKey() !Key`

Reads one byte from `stdin`:

- `0` bytes read → `.none`
- `\x1b` → reads two more bytes:
  - `[A/B/C/D` → `.up/.down/.right/.left`
  - anything else → `.escape`
- `127` → `.backspace`
- `\r` → `.enter`
- anything else → `.{ .ascii = c }`

---

### 4.7 UI / Rendering — `src/view/ui.zig`

All rendering functions write ANSI escape codes to the buffered stdout writer.

#### Mode colours

| Mode | ANSI Background | Appearance |
|------|----------------|------------|
| Normal | `\x1b[0;106m` | Cyan |
| Insert | `\x1b[0;102m` | Green |
| Command | `\x1b[0;101m` | Red |

#### `refreshScreen(stdout, editor) !void`

Full redraw, executed when `editor.needs_redraw == true`:

1. Hide cursor (`\x1b[?25l`).
2. Clear screen and move to home (`\x1b[2J\x1b[H`).
3. Write `getFirst()` then `getSecond()` through `writeWithCTRLF` (converts bare `\n` → `\r\n` for raw mode).
4. Move cursor to `getCursorPos()`.
5. Draw the mode status bar (`displayMode`).
6. If in Command mode, draw the command prompt (`commandPrompt`).
7. Show cursor (`\x1b[?25h`).

#### `updateCurrentLine(stdout, buf) !void`

**Optimised partial update** for Insert mode typing (avoids flickering from a full redraw):

1. Determine the current row from `getCursorPos`.
2. Erase that row (`\x1b[{row};1H\x1b[2K`).
3. Re-write only the characters on that line from both buffer halves.
4. Restore cursor position.

#### `displayMode(stdout, editor) !void`

Renders the mode indicator on the last terminal row. Colour is chosen from `MODE_COLOR` by casting the `Mode` enum to an integer index.

#### `commandPrompt(stdout, editor) !void`

Renders a full-width dark bar (`\x1b[48;5;237m`) on the last terminal row displaying `:` followed by the command buffer content. Pads the rest of the row with spaces to fill the width.

#### `writeWithCTRLF(stdout, text) !void`

Splits the text on `\n` and emits each chunk followed by `\r\n`, since raw mode disables the output `\r` translation.

#### `insertLine(stdout, text, row) !void`

Utility: moves to a specific row, clears it, and writes text. Currently not called in the main loop (available for future use).

---

### 4.8 Popup System — `src/view/pop.zig`

Provides a floating box-drawing popup overlay system.

#### `Pop` struct

| Field | Type | Description |
|-------|------|-------------|
| `id` | `u32` | Unique identifier |
| `allocator` | `Allocator` | For the text buffer |
| `pos` | `Pos` | Top-left corner (x, y) |
| `size` | `Pos` | Width (x) and height (y) |
| `buffer` | `ArrayList(u8)` | Text content |
| `border_color` | `[]const u8` | ANSI escape string (default: white `\x1b[37m`) |
| `expire_at` | `?i64` | Millisecond timestamp to auto-remove; `null` = persistent |

Methods: `init`, `deinit`, `write(content)`, `clear()`.

#### `render(stdout, pop) !void`

Draws the popup using Unicode box-drawing characters:

```
┌──────────────┐
│ content here │
└──────────────┘
```

- Top and bottom borders: `┌─…─┐` / `└─…─┘`
- Side borders: `│ … │`
- Content lines are word-split by `\n` and drawn inside the border.
- Lines are clipped to the popup width (`w - 2`).
- Content overflow beyond `h - 2` lines is silently truncated.

**Lifecycle:** Popups are stored in `Editor.pop_store` (an `AutoHashMap(u32, Pop)`). Each `Tick` action (fired on read timeout) checks all popups against the current millisecond timestamp and removes any that have expired.

---

### 4.9 Utilities — `src/utils.zig`

```zig
pub const Pos = struct { x: usize, y: usize };
```

A simple 2D position type used by the popup system and potentially for future layout calculations.

---

## 5. Editor Modes

dot is a **modal editor**. Every keypress is interpreted differently depending on the current mode.

```
        ┌──────┐
  'i'   │      │  'a' / 'o'
 ──────▶│INSERT│◀───────────
        │      │
        └──┬───┘
    Esc    │
           ▼
        ┌──────┐     ':'     ┌─────────┐
        │NORMAL│────────────▶│ COMMAND │
        │      │◀────────────│         │
        └──────┘  Esc/Enter  └─────────┘
```

| Mode | Description |
|------|-------------|
| **Normal** | Default mode; navigation, mode switching, quick deletions |
| **Insert** | Free text entry; characters are inserted at the cursor |
| **Command** | Ex-style command entry at the bottom of the screen |

---

## 6. Keybindings

### Normal Mode

| Key | Action |
|-----|--------|
| `i` | Enter Insert mode |
| `a` | Append — move one character right, enter Insert mode |
| `o` | Append new line — move down, enter Insert mode |
| `h` or `←` | Move cursor left |
| `j` or `↓` | Move cursor down |
| `k` or `↑` | Move cursor up |
| `l` or `→` | Move cursor right |
| `x` | Delete character under cursor (backspace) |
| `q` | Quit immediately (without saving) |
| `:` | Enter Command mode |

### Insert Mode

| Key | Action |
|-----|--------|
| `Esc` | Return to Normal mode |
| Any printable character | Insert that character at the cursor |
| `Enter` | Insert a newline (`\n`) |
| `Backspace` | Delete the character before the cursor |
| `←` / `→` / `↑` / `↓` | Move cursor |

### Command Mode

| Key | Action |
|-----|--------|
| `Esc` | Cancel command, return to previous mode |
| Any character | Append to the command buffer |
| `Backspace` | Delete the last character from the command buffer |
| `Enter` | Execute the current command |

---

## 7. Commands

Commands are entered in Command mode (press `:` from Normal mode). The prompt appears at the bottom of the screen.

| Command | Effect |
|---------|--------|
| `:q` | Quit the editor without saving |
| `:w` | Save the file to disk |
| `:wq` | Save the file to disk and quit |

> **Note:** `:w` requires a filename to have been provided on the command line. If no filename was given, saving returns a `NoFileName` error (currently unhandled in the UI — a visible error message is planned).

---

## 8. Data Structures In Depth

### GapBuffer Memory Layout

```
Initial (empty, capacity = 1024):
[0000000000000000000000000000000...]
 ^                                ^
 gap_start = 0                    gap_end = 1024

After typing "hello":
[h e l l o 0000000000000000000...]
           ^                    ^
           gap_start = 5        gap_end = 1024

After moving left twice:
[h e l 0000000000000000000 l o]
       ^                   ^
       gap_start = 3       gap_end = 1022
```

**Buffer expansion** (when `gap_start == gap_end`):
- New capacity = old capacity × 2
- Left part copied verbatim.
- Right part moved to the end of the new allocation.
- The gap grows by `old_capacity` bytes.

### Popup Store

```
pop_store: AutoHashMap(u32, Pop)
next_popup_id: u32 (starts at 1, increments on each creation)
```

Popups are keyed by their auto-incremented ID. The `Tick` action iterates all entries, collects expired IDs (to avoid mutating the map during iteration), then removes them.

---

## 9. Memory Management

| Resource | Strategy |
|----------|----------|
| Heap allocator | `GeneralPurposeAllocator` with leak detection at exit |
| GapBuffer backing array | Freed in `GapBuffer.deinit()` |
| File content slice | Caller-owned; freed in `main` with `defer allocator.free` |
| Command buffer | `ArrayListUnmanaged(u8)` freed in `Editor.deinit` |
| Popup text buffers | Each `Pop` frees its own `ArrayList(u8)` in `Pop.deinit` |
| Popup hash map | Freed in `Editor.deinit`; all values are deinitialized first |

On exit, if any allocations were leaked, the program prints `[!] MEMORY LEAKS DETECTED` and exits with code 42.

---

## 10. Build System

The project uses the standard Zig build system. There are no external dependencies.

### `build.zig.zon` manifest

| Field | Value |
|-------|-------|
| `name` | `.dot` |
| `version` | `"0.0.0"` |
| `minimum_zig_version` | `"0.15.2"` |
| `fingerprint` | `0x59278a3a28514ce` |
| `dependencies` | *(none)* |

### Build steps

| Command | Action |
|---------|--------|
| `zig build` | Compile the `dot` executable into `zig-out/bin/dot` |
| `zig build run` | Compile and run (no file argument) |
| `zig build run -- <file>` | Compile and run with a file argument |
| `zig build test` | Run the test suite (shares the same root module as the executable) |

### Ignored paths (`.gitignore`)

```
.zig-cache/
zig-out/
```

---

## 11. CLI Usage

```
dot [filename]
```

| Invocation | Behaviour |
|------------|-----------|
| `dot` | Opens an empty, unnamed buffer |
| `dot path/to/file.txt` | Loads the file into the gap buffer; saves back to the same path on `:w` |
| `dot /absolute/path/file` | Same, for absolute paths |

---

## 12. Development History

The project was built incrementally through a series of pull requests:

| PR | Title | Changes |
|----|-------|---------|
| #1 | Core state machine | Introduced the modal `Editor` struct, `Mode` enum, `Action` union, `Window` size detection, and wired everything into the main event loop. Added tab-aware cursor positioning in `GapBuffer`. |
| #2 | Colorized mode display | Added `MODE_COLOR` array in `ui.zig`; each mode now shows a distinct background colour in the status bar (cyan / green / red). |
| #3 | Fix winsize ioctl | Fixed the `TIOCGWINSZ` constant to use the correct value on Linux vs macOS. |
| #4 | Popup window system | Introduced the `Pop` struct and renderer in `pop.zig`, `PopBuilder` and `CreatePop`/`Tick` actions in `core.zig`, and integrated popup rendering and expiry into the main loop. Added the `Pos` utility type. |
| #5 | Command mode & prompt | Added Command mode to the editor state machine; implemented `cmd_buf`, command character actions, and the `commandPrompt` UI function. Added `openAlternateScreen` / `closeAlternateScreen` to `terminal.zig`. Implemented the `:q` command. |
| #6 | File loading/saving | Added `Fs` struct with mmap-based `loadFast`. Added `GapBuffer.initFromFile`. Implemented `saveFile` on `Editor` with `:w` and `:wq` command support. Added `last_mode` to restore mode after command execution. Added `CoreError.NoFileName`. |

---

## 13. Known Limitations & Future Work

### Current limitations

| Area | Issue |
|------|-------|
| **Saving** | No visible feedback when `:w` succeeds or fails — a popup notification is stubbed out but commented out in the code |
| **No filename** | Attempting `:w` without a filename raises a Zig error that is not surfaced to the user |
| **`o` (AppendNewLine)** | Moves the cursor down rather than inserting a blank line above the next line |
| **Undo/Redo** | Not implemented |
| **Syntax highlighting** | Not implemented |
| **Search & replace** | Not implemented |
| **Line numbers** | Not implemented |
| **Mouse support** | Not implemented |
| **Config file** | Not implemented |
| **Tests** | A `zig build test` step exists but no test cases are written yet |
| **`insertLine`** | The `ui.insertLine` function exists but is not called anywhere in the current code |
| **Popup trigger** | The `p` command in Command mode (which would open a test popup) is commented out |

### Planned / natural next steps

- Show a success/error popup after `:w` (the popup system is already in place)
- Implement `:w <newfile>` to save to a different path
- Add a `:e <file>` command to open a new file
- Implement `dd` (delete line), `yy`/`p` (yank/put), and other Vim motions
- Add line number display in the left gutter
- Add a search mode (e.g., `/pattern`)
- Write unit tests for `GapBuffer` (especially cursor movement edge cases)
- Handle terminal resize signals (`SIGWINCH`) instead of polling `updateSize` every frame
