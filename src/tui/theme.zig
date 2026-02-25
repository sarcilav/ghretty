const vaxis = @import("vaxis");

pub const selected_row_style = vaxis.Style{
    .fg = vaxis.Color.ansi(.black),
    .bg = vaxis.Color.ansi(.white),
    .bold = true,
};

pub const normal_style = vaxis.Style{
    .fg = vaxis.Color.ansi(.white),
    .bg = vaxis.Color.ansi(.black),
};

pub const header_style = vaxis.Style{
    .fg = vaxis.Color.ansi(.cyan),
    .bold = true,
    .underline = true,
};

pub const error_style = vaxis.Style{
    .fg = vaxis.Color.ansi(.red),
    .bold = true,
};

pub const loading_style = vaxis.Style{
    .fg = vaxis.Color.ansi(.yellow),
    .bold = true,
};
