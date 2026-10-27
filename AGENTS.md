# Repository Guidelines

## Project Structure

HEAT is a Zig game engine. Core modules live in `src/`: `Async/`, `IO/`, and `GUI/` contain the concurrency, I/O, and graphics code; `GUI/vulkan/` holds the Vulkan backend. `bindings/` contains C and Lua integration, and `examples/` contains sample projects (including C and web examples). `build.zig`, `build.zig.zon`, and `config.zig` define the build and engine options. Generated `.zig-cache/`, `zig-out/`, and `zig-pkg/` content is not source.

## Build and Development

Use Zig 0.16.0 or newer and Git. From the repository root, run `zig build` to build the engine. To build and run examples, change to `examples/` and use `zig build` or `zig build run-basic`; build one example with `zig build basic`. The CI workflow builds all examples on Windows and Ubuntu with Zig 0.16.0 and the Vulkan SDK installed.

## Style and Naming

Follow existing Zig conventions: format `.zig` files with `zig fmt`, use four spaces for indentation, `PascalCase` for types and modules where established, and `camelCase` for functions and local values. Keep module files named `main.zig` or `root.zig` when they serve as package entry points; use descriptive names for supporting files. Match the surrounding code when editing bindings, build files, or examples.

## Testing and Validation

There is no separate test suite configured in the repository. At minimum, run `zig build` after engine changes. For example or integration changes, run the relevant target from `examples/` (for example, `zig build basic`); graphics changes may also need a Vulkan-capable environment. CI currently validates the example build on both Windows and Ubuntu.

## Commits and Pull Requests

Recent commits use short, sentence-style summaries, often describing a fix or completed change; no strict prefix convention is established. Keep commit subjects concise and specific. Open feature branches such as `feature/<topic>` or `fix/<topic>`, and submit pull requests with a clear summary, rationale, and build/validation results. Link a related issue when one exists and include screenshots for visible GUI changes. See `CONTRIBUTING.MD` for the existing contribution workflow.

## Configuration Notes

Build features are controlled through `config.zig` and build options in `build.zig`. When changing a default or dependency option, consider the corresponding example and platform-specific build paths. Do not commit generated build caches or downloaded package directories.
