# HEAT

![GitHub stars](https://img.shields.io/github/stars/Freziyt223/HEAT?style=for-the-badge&logo=github) ![GitHub forks](https://img.shields.io/github/forks/Freziyt223/HEAT?style=for-the-badge&logo=github) ![GitHub issues](https://img.shields.io/github/issues/Freziyt223/HEAT?style=for-the-badge&logo=github) ![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)

## 📑 Table of Contents

- [Description](#-description)
- [Something very important](#something-very-important)
- [Quick Start](#-quick-start)
- [Configure](#️-configure)
- [Example](#-example)
- [Project Structure](#-project-structure)
- [Contributing](#-contributing)
- [License](#-license)

## 📝 Description
Heat is a free game engine designed with a core focus on modularity. It's designed as generic so almost everything assembles in runtime as Engine module and User module, which can interact with each other by interfaces   

## Something very important
std.Build.StandartOptimizeOptions(.{}); Doesn't pass optimize correctly to the dependencies! Use b.option(bool, "optimize", ...) or set it manually.

## ⚡ Quick Start

**build.zig.zon**
```zig
.{
    .dependencies = .{
        .HEAT = .{
            .url = "https://github.com/Freziyt223/HEAT.git",
            .hash = "(hash here)"
        }
    }
}
```
To get hash use:  
`zig fetch git+https://github.com/Freziyt223/HEAT.git`

**build.zig**
```zig
const HEAT = b.dependency("HEAT", .{
    // you can enter options here
    .singlethreaded = false,
    .target = target,
    .optimize = optimize
})
// Use exactly the same name as in build.zig.zon
const Exe = @import("HEAT").addExecutable(b, .{
    .name = "MyApp",
    .user_module = MyApp,
    // You can enter target and optimize here instead of b.dependency
});
```
Now you can do anything with this Executable(Exe)

## ⚙️ Configure
Change engine's parameters like release mode, singlethreaded mode, turn on/off some optional dependencies just by editing *config.zig*

## 📖 Example

` Make sure you have zig 0.16.0 or higher`  
**Open your terminal**
```bash

# Clone the repository
git clone https://github.com/Freziyt223/HEAT.git

# Go into clonned directory
cd HEAT

# Build the engine!
zig build

# (See Development Setup below)
```

## 📁 Project Structure

```
.
├── config.zig | Edit compilation and runtime parameter
|
├── lldb_pretty_printers.py | Helps with lldb debugging
|
└── src
    ├── IO | File and console manipulations
    |
    ├── TrackingAllocator.zig | Memory tracking
    |
    ├── main.zig | Entrypoint of a program
    |
    ├── root.zig | Main header of an engine
    └── ...
```

## 💾 Requirements
(Not benchmarked for now)

## 👥 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork** the repository
2. **Clone** your fork: `git clone (link here)`
3. **Create** a new branch: `git checkout -b feature/your-feature`
4. **Commit** your changes: `git commit -am 'Add some feature'`
5. **Push** to your branch: `git push origin feature/your-feature`
6. **Open** a pull request

Please ensure your code follows the project's style guidelines and includes tests where applicable.
(For now isn't propertly defined)

## 📜 License

This project is licensed under the MIT License.

---
*This README was generated with ❤️ by [ReadmeBuddy](https://readmebuddy.com)*
