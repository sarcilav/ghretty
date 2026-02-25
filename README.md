# ghretty

A terminal user interface (TUI) for GitHub CLI (`gh`) built with Zig and Vaxis.

## Features

- Browse GitHub pull requests in your terminal
- View PR details including files changed
- Navigate between PR list and details screens
- Refresh PR list with `r` key
- Clean, responsive TUI interface

## Prerequisites

- [Zig](https://ziglang.org/) (0.15.2 or later)
- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated
- Terminal with UTF-8 support

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd ghretty
   ```

2. Build the application:
   ```bash
   zig build
   ```

3. Run the application:
   ```bash
   zig build run
   ```

## Usage

### PR List Screen
- **Navigate**: Use `j`/`k` keys to move up and down
- **Select PR**: Press `Enter` on a PR to view details
- **Refresh**: Press `r` to refresh the PR list
- **Quit**: Press `Ctrl+q` to exit the application

### PR Details Screen
- **Scroll**: Use `j`/`k` to scroll through PR details
- **Go back**: Press `q` to return to PR list

## Project Structure

```
src/
├── app.zig           # Main application logic and event loop
├── main.zig          # Entry point
├── root.zig          # Module exports
├── github/client.zig # GitHub CLI integration
├── models/pr.zig     # Data models for PRs
├── screens/          # TUI screens
│   ├── screen.zig    # Base screen interface (vtable pattern)
│   ├── pr_list.zig   # PR list screen
│   └── pr_details.zig # PR details screen
└── tui/              # UI components and themes
    ├── components.zig # Reusable UI components (List component)
    ├── layout.zig    # Layout utilities
    └── theme.zig     # Color themes and styles
```

## Development

### Building
```bash
zig build
```

### Running
```bash
zig build run
```

### Testing
```bash
zig build test
```

### Dependencies
- [Vaxis](https://github.com/Vaxis-org/vaxis): Terminal UI library for Zig (via build.zig.zon)

## Architecture Notes

- Uses a screen stack for navigation between views
- Implements a vtable pattern for polymorphic screens
- Integrates with GitHub CLI via subprocess execution
- Supports virtualized list rendering for performance

## License

[Add your license here]
