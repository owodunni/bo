const std = @import("std");
pub const c = @import("c.zig").c;
const testing = std.testing;

const errors = @import("errors.zig");
pub const errorFromResultCode = errors.errorFromResultCode;
pub const Error = errors.Error;
pub const DetailedError = errors.DetailedError;
const getLastDetailedErrorFromDb = errors.getLastDetailedErrorFromDb;
const getDetailedErrorFromResultCode = errors.getDetailedErrorFromResultCode;

const getTestDb = @import("test.zig").getTestDb;

/// Db is a wrapper around a SQLite database, providing high-level functions for executing queries.
/// A Db can be opened with a file database or a in-memory database:
///
///     // File database
///     var db = try sqlite.Db.init(.{ .mode = .{ .File = "/tmp/data.db" } });
///
///     // In memory database
///     var db = try sqlite.Db.init(.{ .mode = .{ .Memory = {} } });
///
pub const Db = struct {
    const Self = @This();

    db: *c.sqlite3,

    /// Mode determines how the database will be opened.
    ///
    /// * File means opening the database at this path with sqlite3_open_v2.
    /// * Memory means opening the database in memory.
    ///   This works by opening the :memory: path with sqlite3_open_v2 with the flag SQLITE_OPEN_MEMORY.
    pub const Mode = union(enum) {
        File: [:0]const u8,
        Memory,
    };

    /// OpenFlags contains various flags used when opening a SQLite databse.
    ///
    /// These flags partially map to the flags defined in https://sqlite.org/c3ref/open.html
    ///  * write=false and create=false means SQLITE_OPEN_READONLY
    ///  * write=true and create=false means SQLITE_OPEN_READWRITE
    ///  * write=true and create=true means SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE
    pub const OpenFlags = struct {
        write: bool = false,
        create: bool = false,
    };

    pub const InitError = error{
        SQLiteBuildNotThreadSafe,
    } || Error;
    /// init creates a database with the provided options.
    pub fn init(options: InitOptions) InitError!Self {
        var dummy_diags = Diagnostics{};
        var diags = options.diags orelse &dummy_diags;

        // Validate the threading mode
        if (options.threading_mode != .SingleThread and !isThreadSafe()) {
            return error.SQLiteBuildNotThreadSafe;
        }

        // Compute the flags
        var flags: c_int = c.SQLITE_OPEN_URI;
        flags |= @as(c_int, if (options.open_flags.write) c.SQLITE_OPEN_READWRITE else c.SQLITE_OPEN_READONLY);
        if (options.open_flags.create) {
            flags |= c.SQLITE_OPEN_CREATE;
        }
        if (options.shared_cache) {
            flags |= c.SQLITE_OPEN_SHAREDCACHE;
        }
        switch (options.threading_mode) {
            .MultiThread => flags |= c.SQLITE_OPEN_NOMUTEX,
            .Serialized => flags |= c.SQLITE_OPEN_FULLMUTEX,
            else => {},
        }

        switch (options.mode) {
            .File => |path| {
                var db: ?*c.sqlite3 = undefined;
                const result = c.sqlite3_open_v2(path.ptr, &db, flags, null);
                if (result != c.SQLITE_OK or db == null) {
                    if (db) |v| {
                        diags.err = getLastDetailedErrorFromDb(v);
                    } else {
                        diags.err = getDetailedErrorFromResultCode(result);
                    }
                    return errors.errorFromResultCode(result);
                }

                return Self{ .db = db.? };
            },
            .Memory => {
                flags |= c.SQLITE_OPEN_MEMORY;

                var db: ?*c.sqlite3 = undefined;
                const result = c.sqlite3_open_v2(":memory:", &db, flags, null);
                if (result != c.SQLITE_OK or db == null) {
                    if (db) |v| {
                        diags.err = getLastDetailedErrorFromDb(v);
                    } else {
                        diags.err = getDetailedErrorFromResultCode(result);
                    }
                    return errors.errorFromResultCode(result);
                }

                return Self{ .db = db.? };
            },
        }
    }

    /// deinit closes the database.
    pub fn deinit(self: *Self) void {
        _ = c.sqlite3_close(self.db);
    }
};

/// ThreadingMode controls the threading mode used by SQLite.
///
/// See https://sqlite.org/threadsafe.html
pub const ThreadingMode = enum {
    /// SingleThread makes SQLite unsafe to use with more than a single thread at once.
    SingleThread,
    /// MultiThread makes SQLite safe to use with multiple threads at once provided that
    /// a single database connection is not by more than a single thread at once.
    MultiThread,
    /// Serialized makes SQLite safe to use with multiple threads at once with no restriction.
    Serialized,
};

/// Diagnostics can be used by the library to give more information in case of failures.
pub const Diagnostics = struct {
    message: []const u8 = "",
    err: ?DetailedError = null,

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.err) |err| {
            if (self.message.len > 0) {
                _ = try writer.print("{{message: {s}, detailed error: {s}}}", .{ self.message, err });
                return;
            }

            _ = try err.format(fmt, options, writer);
            return;
        }

        if (self.message.len > 0) {
            _ = try writer.write(self.message);
            return;
        }

        _ = try writer.write("none");
    }
};

pub const InitOptions = struct {
    /// mode controls how the database is opened.
    ///
    /// Defaults to a in-memory database.
    mode: Db.Mode = .Memory,

    /// open_flags controls the flags used when opening a database.
    ///
    /// Defaults to a read only database.
    open_flags: Db.OpenFlags = .{},

    /// threading_mode controls the threading mode used by SQLite.
    ///
    /// Defaults to Serialized.
    threading_mode: ThreadingMode = .Serialized,

    /// shared_cache controls whether or not concurrent SQLite
    /// connections share the same cache.
    ///
    /// Defaults to false.
    shared_cache: bool = false,

    /// if provided, diags will be populated in case of failures.
    diags: ?*Diagnostics = null,
};

fn isThreadSafe() bool {
    return c.sqlite3_threadsafe() > 0;
}

const TestUser = struct {
    name: []const u8,
    id: usize,
    age: usize,
    weight: f32,
    favorite_color: Color,

    pub const Color = enum {
        red,
        majenta,
        violet,
        indigo,
        blue,
        cyan,
        green,
        lime,
        yellow,
        //
        orange,
        //

        pub const BaseType = []const u8;
        pub const default = .red;
    };
};

const test_users = &[_]TestUser{
    .{ .name = "Vincent", .id = 20, .age = 33, .weight = 85.4, .favorite_color = .violet },
    .{ .name = "Julien", .id = 40, .age = 35, .weight = 100.3, .favorite_color = .green },
    .{ .name = "José", .id = 60, .age = 40, .weight = 240.2, .favorite_color = .indigo },
};

fn createTestTables(db: *Db) !void {
    const AllDDL = &[_][]const u8{
        "DROP TABLE IF EXISTS user",
        "DROP TABLE IF EXISTS article",
        "DROP TABLE IF EXISTS test_blob",
        \\CREATE TABLE user(
        \\ name text,
        \\ id integer PRIMARY KEY,
        \\ age integer,
        \\ weight real,
        \\ favorite_color text
        \\)
        ,
        \\CREATE TABLE article(
        \\  id integer PRIMARY KEY,
        \\  author_id integer,
        \\  data text,
        \\  is_published integer,
        \\  FOREIGN KEY(author_id) REFERENCES user(id)
        \\)
    };

    // Create the tables
    inline for (AllDDL) |ddl| {
        try db.exec(ddl, .{}, .{});
    }
}

fn addTestData(db: *Db) !void {
    try createTestTables(db);

    for (test_users) |user| {
        try db.exec("INSERT INTO user(name, id, age, weight, favorite_color) VALUES(?{[]const u8}, ?{usize}, ?{usize}, ?{f32}, ?{[]const u8})", .{}, user);

        const rows_inserted = db.rowsAffected();
        try testing.expectEqual(@as(usize, 1), rows_inserted);
    }
}

test "simple test2" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "sqlite: db init" {
    var db = try getTestDb();
    defer db.deinit();
    try std.testing.expect(true);
}
