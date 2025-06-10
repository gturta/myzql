const std = @import("std");
const my = @import("mysqueal");

pub fn main() !void {
    // Prints to stderr, ignoring potential errors.
}


test "simple select" {
    const query = "select 'george' as value";

    const db = try my.MyDB.init(.{
        .host = "srv-webisdb-q",
        .user = "webuser",
        .passwd = "hu2eih2der4quei1Oonah1xoh1eimae5ed!",
        .port = 3306,
        .db = "testisend_engie_ro"
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
