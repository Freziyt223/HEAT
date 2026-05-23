HEAT is a project of making a free modular game engine with core focus on modularity.  

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/Freziyt223/HEAT/main.yml)

# Table of contents
- [Something very important](#something-very-important)
- [Features](#features)
- [Usage](#usage)
- [Configure](#configure)

## Something very important
std.Build.StandartOptimizeOptions(.{}); Doesn't pass optimize correctly to the dependencies! Use b.option(bool, "optimize", ...) or set it manually.

## Features
I'll write this later

## Usage
To use this engine in your code you have to:
- Have `Zig 0.16.0 or higher`

Add HEAT to your **build.zig.zon**:
```zig
.{
    ...
    .dependencies = .{
        .HEAT = .{
            .url = "https://github.com/Freziyt223/HEAT"
            .hash = "(hash here)"
        }
    }
}
```
To get the hash use zig git+https://github.com/Freziyt223/HEAT in your terminal

Add those lines to your **build.zig**:
```zig
    const HEAT = b.dependency("HEAT", .{
        // You can pass options here
        .singlethreaded = false,
        .target = target
    });
    //        Has to be exact name as in build.zig.zon
    const Exe = @import("HEAT").addExecutable(b, .{
        .name = "ExecutableName",
        .user_module = MyApp // module of your code
        // You can enter other options here if you want
    });
```
Now in your code you can import and use the engine, here is an example:
**MyApp.zig**
```zig
const std = @import("std");
const Self = @This();
const Engine = @import("Engine");
const Conf = @import("Conf");

pub fn init(this: *Self, args: std.process.Args) !void {
    _ = this;
    _ = args;
    try Engine.IO.print("Hello, {s}\n", .{"world!"});
}
pub fn deinit(this: *Self) void {
    _ = this;
}

```

## Configure
Change engine's parameters like release mode, singlethreaded mode, turn on/off some optional dependencies just by editing *config.zig*  
Even from your build.zig code:
```
const HEAT = b.dependency("HEAT", .{...});

const HEAT_build = @import("HEAT); // Has to be exact same name as in b.dependency()
// Now you can edit the config directly
HEAT_build.Config.singlethreaded = true;


const Config = HEAT_build.Config;
// Or make separate function to change whole config directly
HEAT_build.Config.profile = &load_profile;
fn load_profile() {
    Config.singlethreaded = false;
    Config.optimize_mode = .ReleaseSmall;
}
```  
All those config options and options passed on build are loaded into `Engine.Conf.BuildOptions`

## Examples
All of the examples are located in **"examples"** folder, to build them all run `zig build` in that folder.  
If you want to build a singular example just run `zig build <name of example>`.
You can also use run step like this: `zig build run-<name of example>`, which will build and execute selected example.

