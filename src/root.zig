//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

// Export the main app module
pub const App = @import("app.zig").App;

// Export screen-related modules
pub const Screen = @import("screens/screen.zig").Screen;
pub const PRListScreen = @import("screens/pr_list.zig").PRListScreen;
pub const PRDetailsScreen = @import("screens/pr_details.zig").PRDetailsScreen;

// Export models
pub const models = @import("models/pr.zig");

// Export GitHub client
pub const github = @import("github/client.zig");

// Export TUI components
pub const tui = struct {
    pub const theme = @import("tui/theme.zig");
};
