const std = @import("std");
const Day = @import("adventb").Day;

pub const Day01 = @import("Day01.zig");

var day01: Day01 = undefined;

pub const days: []const Day = &.{ Day.asDay(&day01) };
