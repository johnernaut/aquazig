const std = @import("std");

pub const initiationMessage: [1]u8 = .{1};

pub const broadcastResponse = struct {
    chk: [4]u8,
    ip1: u8,
    ip2: u8,
    ip3: u8,
    ip4: u8,
    port: u16,
    gt: u8,
    gs: u8,

    pub fn parse(buf: []const u8) !broadcastResponse {
        if (buf[0] != 2) return error.InvalidResponse;
        if (buf.len < 12) return error.BufferTooSmall;

        return broadcastResponse{
            .chk = buf[0..4].*,
            .ip1 = buf[4],
            .ip2 = buf[5],
            .ip3 = buf[6],
            .ip4 = buf[7],
            .port = @as(u16, (buf[8] + buf[9])),
            .gt = buf[10],
            .gs = buf[11],
        };
    }

    pub fn host(self: broadcastResponse) []const u8 {
        return std.fmt.allocPrint(std.heap.page_allocator, "{}.{}.{}.{}", .{
            self.ip1,
            self.ip2,
            self.ip3,
            self.ip4,
        }) catch "invalid address";
    }
};
