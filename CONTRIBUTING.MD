## Contributing to this project
Thank you for your interest in contributing to HEAT. Here is a guide for you to get started.

## Requirements
- `Zig 0.16.0 or higher`
- git

## Setup
1. Fork the repository on github by using the button above the **About** title
2. Clone this fork by using `git clone (url of a forked repository)`
   and open a terminal in it's directory
3. Use `zig build` to verify engine actually builds without any error

### Project structure
HEAT/  
├── src/  
|   ├── main.zig  # Entrypoint of a combined program  
|   ├── root.zig  # Main header of the engine  
|   ├── IO        # IO wrapper  
|   └── Async     # Multithreading  
├── config.zig    # Build configurations  
├── build.zig  
└── build.zig.zon  

## How to contribute
You can do following by making an Issue on github:
- **Report bugs** ,
- **Suggest a feature**

To add your code suggestions do following:
1. Create a branch from *main* like this:
`git checkout issue_type/your-issue`
Example:
`git checkout feature/glfw_windowing`
or
`git checkout fix/io_writer`

2. Make your changes and run `zig build` to make sure your code builds correctly
3. Commit changes by running:
```bash
git add . # To stage all of your changes
git commit -m "Test commit description"
```
4. Push your changes to your fork by running
`git push origin (your branch here)`
Then on the github repository page open the *Pull request* tab and make a new pull request with your fork

5. Then your contribution will be staged for futher examination by maintainers of the project and if it's valid your code will be merged with the main branch
