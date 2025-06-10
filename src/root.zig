//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const c = @cImport({
    @cInclude("mysql/mysql.h");
});

pub const MyDB = struct {
    DB: *c.MYSQL,

    const DbInfo = struct {
        host: [:0]const u8,
        user: [:0]const u8,
        passwd: [:0]const u8,
        db: [:0]const u8,
        port: c_uint,
    };

    pub fn init(conn: DbInfo) !MyDB{
        if(c.mysql_library_init(0, null, null) != 0) {
            return error.Initialize;
        }
        const init_db: ?*c.MYSQL = c.mysql_init(null);
        errdefer c.mysql_close(init_db);
        if (init_db == null) return error.Initialize;

        const connected: ?*c.MYSQL = c.mysql_real_connect(init_db, conn.host.ptr, conn.user.ptr, conn.passwd.ptr, conn.db.ptr, conn.port, null, 0);
        if (connected != init_db) return error.Connect;

        return MyDB {
            .DB = connected.?,
        };
    }

    pub fn deinit(self: MyDB) void {
        c.mysql_library_end();
        c.mysql_close(self.DB);
    }

    pub fn execute_query(self: MyDB, query: []const u8) !?MyResult {
        if (c.mysql_real_query(self.DB, query.ptr, query.len) != 0){
            return error.ExecuteQuery;
        }
        //check if we need to fetch a result
        const field_count = c.mysql_field_count(self.DB);
        if (field_count == 0) return null;

        const result: ?*c.MYSQL_RES = c.mysql_store_result(self.DB);
        if ( result == null ) {
            return error.FetchResult; //field_count is > 0, should have had results
        }
        return MyResult.init(result.?);
    } 

};

pub const MyResult = struct {
    result: *c.MYSQL_RES,
    rows: u64,
    fields: c_uint,

    pub fn init(result: *c.MYSQL_RES) MyResult {
        const rows = c.mysql_num_rows(result);
        const fields = c.mysql_num_fields(result);
        return .{.result = result, .rows = rows, .fields = fields};
    }

    pub fn deinit(self: MyResult) void{
        c.mysql_free_result(self.result);
    }

    pub fn num_rows(self: MyResult) u64 {
        return self.rows;
    }
    pub fn num_fields(self: MyResult) u64 {
        return self.fields;
    }
    pub fn next(self: MyResult) ?MyRow {
        const row: ?c.MYSQL_ROW = c.mysql_fetch_row(self.result);
        if(row != null) {
            const lengths = c.mysql_fetch_lengths(self.result);
            return .{.row = row.?, .fields = self.fields, .lengths = lengths};
        } else return null;
    }
};

pub const MyRow = struct {
    row: c.MYSQL_ROW,
    fields: c_uint,
    lengths: [*]c_ulong,

    pub fn get(self: MyRow, index: usize) ![]u8 {
        if (index >= self.fields) return error.RowIndexError;
        var data: []u8 = undefined;
        data.ptr = self.row[index];
        data.len = self.lengths[index];
        return data;
    }
};
