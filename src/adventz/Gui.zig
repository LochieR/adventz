const std = @import("std");
const vaxis = @import("vaxis");

const Y2026 = @import("2026/2026.zig");

const Gui = @This();

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    focus_in,
};

allocator: *std.mem.Allocator,
buffer: [1024]u8 = undefined,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
loop: vaxis.Loop(Event),

color_flag: bool, // to alternate between red and green buttons

buttons: [][]const u8 = &.{},

const button_width = 100;

pub fn init(self: *Gui, init_info: std.process.Init, allocator: *std.mem.Allocator) !void {
    self.allocator = allocator;

    self.tty = try vaxis.Tty.init(init_info.io, &self.buffer);
    self.vx = try vaxis.init(init_info.io, allocator.*, init_info.environ_map, .{});
    self.loop = .init(init_info.io, &self.tty, &self.vx);

    self.buttons = try allocator.alloc([]const u8, Y2026.days.len + 1);
    for (0..self.buttons.len - 1) |i| {
        self.buttons[i] = Y2026.days[i].getName();
    }
    self.buttons[self.buttons.len - 1] = "Quit";
}

pub fn deinit(self: *Gui) void {
    self.allocator.free(self.buttons);
    self.vx.deinit(self.allocator.*, self.tty.writer());
    self.tty.deinit();
}

pub fn run(self: *Gui) !void {
    try self.loop.start();
    defer self.loop.stop();

    try self.vx.enterAltScreen(self.tty.writer());
    try self.vx.queryTerminal(self.tty.writer(), .fromSeconds(1));
    try self.vx.setMouseMode(self.tty.writer(), false); // must come after queryTerminal

    var selected: usize = 0;

    var showing_result = false;
    var result: ?[]const u8 = null;

    while (true) {
        var pressed: ?usize = null;

        switch (try self.loop.nextEvent()) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
                    selected = (selected + self.buttons.len - 1) % self.buttons.len;
                } else if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
                    selected = (selected + 1) % self.buttons.len;
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    if (!showing_result) {
                        pressed = selected;
                    } else {
                        showing_result = false;
                        result = null;
                    }
                }
            },
            .mouse => |mouse| {
                if (self.buttonAt(self.listWindow(self.vx.window()), mouse)) |i| {
                    selected = i; // hover follows the mouse
                    if (mouse.type == .press and mouse.button == .left) pressed = i;
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator.*, self.tty.writer(), ws),
            else => {},
        }

        if (pressed) |i| {
            if (std.mem.eql(u8, self.buttons[i], "Quit"))
                break;

            result = try Y2026.days[i].run();
            showing_result = true;
        }

        const win = self.vx.window();
        win.clear();

        const list = self.listWindow(win);
        if (!showing_result) {
            for (self.buttons, 0..) |label, i| {
                self.drawButton(buttonWindow(list, i), label, selected == i);
            }
        } else {
            const text_width = list.gwidth(result.?);

            _ = list.printSegment(
                .{
                    .text = result.?,
                    .style = .{}
                },
                .{
                    .col_offset = (list.width -| text_width) / 2, // -| clamps to min or max when there is an integer overflow
                }
            );
        }

        try self.vx.render(self.tty.writer());
    }
}

fn listWindow(self: *Gui, win: vaxis.Window) vaxis.Window {
    const height: u16 = @intCast(self.buttons.len); // 1 row each, no gap
    return win.child(.{
        .x_off = (win.width -| button_width) / 2,
        .y_off = (win.height -| height) / 2,
        .width = button_width,
        .height = height,
    });
}

fn buttonWindow(list: vaxis.Window, index: usize) vaxis.Window {
    return list.child(.{
        .y_off = @intCast(index),
        .width = button_width,
        .height = 1,
    });
}

fn buttonAt(self: *Gui, list: vaxis.Window, mouse: vaxis.Mouse) ?usize {
    for (self.buttons, 0..) |_, i| {
        if (buttonWindow(list, i).hasMouse(mouse) != null) return i;
    }
    return null;
}

fn drawButton(self: *Gui, btn: vaxis.Window, label: []const u8, selected: bool) void {
    const bg = self.getButtonBackgroundColor();
    const style: vaxis.Style = .{ .fg = .{ .index = 0 }, .bg = bg, .bold = selected };

    const prefix: []const u8 = if (selected) "-> " else "";
    const total_width = btn.gwidth(prefix) + btn.gwidth(label);

    const segments = [_]vaxis.Segment{
        .{ .text = prefix, .style = style },
        .{ .text = label, .style = style },
    };

    btn.fill(.{ .style = style });
    _ = btn.print(&segments, .{
        .col_offset = (btn.width -| total_width) / 2,
    });
}

fn getButtonBackgroundColor(self: *Gui) vaxis.Color {
    if (self.color_flag) {
        self.color_flag = !self.color_flag;
        return .{ .rgb = .{ 176, 0, 0 } };
    } else {
        self.color_flag = !self.color_flag;
        return .{ .rgb = .{ 35, 94, 27 } };
    }
}
