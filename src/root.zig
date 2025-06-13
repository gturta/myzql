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

        return try MyResult.init(self.DB);
    } 

};

pub const MyResult = struct {
    result: *c.MYSQL_RES,
    rows: u64,
    fields: c_uint,

    pub fn init(db: *c.MYSQL) !MyResult {
        //get result
        const opt_result: ?*c.MYSQL_RES = c.mysql_store_result(db);
        if ( opt_result ) |result| {
            const rows = c.mysql_num_rows(result);
            const fields = c.mysql_num_fields(result);
            return .{.result = result, .rows = rows, .fields = fields};
        } else {
            std.debug.print("Result store failed, msg:{s}\n", .{c.mysql_error(db)});
            return error.FetchResult; //field_count is > 0, should have had results
        }
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

pub const MyStatement = struct {
    allocator: std.mem.Allocator,
    db: *c.MYSQL,
    statement: *c.MYSQL_STMT,
    bind_params: ?[]c.MYSQL_BIND = null,

    pub fn init(allocator: std.mem.Allocator, db: *c.MYSQL, query: []const u8) !MyStatement {
        const opt_stmt: ?*c.MYSQL_STMT = c.mysql_stmt_init(db);         
        if (opt_stmt == null) return error.StatementInit;

        if (c.mysql_stmt_prepare(opt_stmt.?, query.ptr, query.len) != 0) {
            std.debug.print("Statement execute failed, msg:{s}\n", .{c.mysql_error(db)});
            return error.StatementPrepare;
        }        
        return MyStatement{.allocator = allocator, .db = db, .statement = opt_stmt.?};
    }

    pub fn deinit(self: MyStatement) void {
        _ = c.mysql_stmt_close(self.statement);
        if (self.bind_params) |binds| self.allocator.free(binds);
    }

    pub fn bind(self: *MyStatement, params: anytype) !void {

        const params_type = @TypeOf(params);
        if(@typeInfo(params_type) != std.builtin.Type.@"struct") {
            @compileError("expected struct argument, found " ++ @typeName(params_type));
        }
        //check if number of params is the same as the params from the statement
        const prep_params = c.mysql_stmt_param_count(self.statement);
        const num_params = @typeInfo(@TypeOf(params)).@"struct".fields.len;
        if (prep_params != num_params) {
            std.debug.print("Expected {} params, got {}", .{prep_params, num_params});
        }

        if (num_params > 0) {
            self.bind_params = try self.allocator.alloc(c.MYSQL_BIND, num_params);

            inline for (@typeInfo(@TypeOf(params)).@"struct".fields, 0..) |field, idx| {
                var binds = &self.bind_params.?[idx];
                binds.* = std.mem.zeroes(c.MYSQL_BIND);
                const value = @field(params, field.name);
                switch(@typeInfo(field.type)) {
                    .pointer => {
                        binds.buffer = @constCast(@ptrCast(value));
                        binds.buffer_length = value.len;
                        binds.buffer_type = c.MYSQL_TYPE_STRING;
                     },
                    .array => {
                        binds.buffer = @constCast(@ptrCast(value));
                        binds.buffer_length = value.len;
                        binds.buffer_type = c.MYSQL_TYPE_STRING;
                     },
                    .int => {
                        binds.buffer = @constCast(@ptrCast(&value));
                        binds.buffer_length = 1;
                        binds.buffer_type = c.MYSQL_TYPE_LONG;
                    },
                    else => @compileError("Bind parameter type not implemented: " ++ @typeName(field.type)),
                }
            }
            if (c.mysql_stmt_bind_param(self.statement, self.bind_params.?.ptr)) {
                std.debug.print("Statement bind failed, msg:{s}\n", .{c.mysql_error(self.db)});
                return error.StatementBind;
            }
        }
    }

    pub fn execute(self: MyStatement) !void {

        if (c.mysql_stmt_execute(self.statement) != 0) {
            std.debug.print("Statement execute failed, msg:{s}\n", .{c.mysql_error(self.db)});
            return error.StatementExecute;
        }
        //check if we need to fetch a result
        const field_count = c.mysql_field_count(self.db);
        std.debug.print("Statement execute got {} fields", .{field_count});
    }
};
