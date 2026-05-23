## Usage
To build all examples at once use `zig build`, just like with any other zig project,  
however you can also build them one by one using: `zig build <name>`. For example:  
```bash
zig build basic
```
Will build basic example(executable is in zig-out/bin).  

You can also use `zig build run-<name>` to build and execute example.

## Structure
```
examples/  
├── <example_name>/  
│   ├── src/
|   |   ├── main.zig
|   |   └── ...
|   └── build_example.zig
├── build.zig  
└── build.zig.zon  
```
If you follow this structure while making examples everything will work smoothly

## Contributing
If you've decided to add example to this project follow `feature` contributing guidelines 