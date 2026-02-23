const vaxis = @import("vaxis");

pub fn rect(
    x: u16,
    y: u16,
    w: u16,
    h: u16,
) vaxis.Window.ChildOptions {
    return .{
        .x_off = x,
        .y_off = y,
        .width = w,
        .height = h,
    };
}
