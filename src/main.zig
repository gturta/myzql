const std = @import("std");
const my = @import("mysqueal");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
}

fn getEnvVars(allocator: std.mem.Allocator) !struct {[:0]const u8, [:0]const u8, [:0]const u8} {
    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();

    var host: [:0]u8 = undefined;
    if (env.get("SQUEAL_HOST")) |env_host| {
        host = try allocator.allocSentinel(u8, env_host.len, 0);
        @memcpy(host, env_host);
    } else return error.EnvNotDefined;

    var user: [:0]u8 = undefined;
    if (env.get("SQUEAL_USER")) |env_user| {
        user = try allocator.allocSentinel(u8, env_user.len, 0);
        @memcpy(user, env_user);
    } else return error.EnvNotDefined;

    var passwd: [:0]u8 = undefined;
    if (env.get("SQUEAL_PASSWD")) |env_passwd| {
        passwd = try allocator.allocSentinel(u8, env_passwd.len, 0);
        @memcpy(passwd, env_passwd);
    } else return error.EnvNotDefined;

    return .{host, user, passwd};
}

test "simple select" {
    const allocator = std.testing.allocator;
    const query = "select 'george' as value";

    const host, const user, const passwd = try getEnvVars(allocator);
    defer {
        allocator.free(host);
        allocator.free(user);
        allocator.free(passwd);
    }

    const db = try my.MyDB.init(.{
        .host = host,
        .user = user,
        .passwd = passwd,
        .port = 3306,
        .db = ""
    });
    defer db.deinit();
    
    if(try db.execute_query(query)) |result| {
        defer result.deinit();
        try std.testing.expectEqual(result.rows, 1);
        try std.testing.expectEqual(result.fields, 1);

        const row = result.next();
        try std.testing.expect(row != null);
        const value = try row.?.get(0);
        try std.testing.expectEqualSlices(u8, "george", value);
    }

}
