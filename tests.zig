const std = @import("std");
const testing = std.testing;

usingnamespace @import("sizes.zig");
usingnamespace @import("pack.zig");
usingnamespace @import("unpack.zig");

test "basic static test" {
    const control = TestStructA{};

    const packed_bytes = pack_static(TestStructA, control);
    var unpacked = try unpack_static(TestStructA, packed_bytes[0..]);

    try testing.expect(std.meta.eql(control, unpacked));
    unpacked.other_struct.b -= 1;
    try testing.expect(!std.meta.eql(control, unpacked));
}

test "struct size" {
    const a = TestStructA{};
    const bytes = pack_static(TestStructA, a);
    try testing.expectEqual(struct_size_static(TestStructA), bytes.len);

    const b = TestStructB{};
    const bytes_b = pack_static(TestStructB, b);
    try testing.expectEqual(struct_size_static(TestStructB), bytes_b.len);
}

test "int size" {
    try testing.expectEqual(size_of_static(i8), size_of_static(u8));
    try testing.expectEqual(size_of_static(u8), size_of_static(u1));
    try testing.expectEqual(size_of_static(u8), size_of_static(u5));
    try testing.expectEqual(size_of_static(u8), 1);

    try testing.expectEqual(size_of_static(u9), size_of_static(u16));
    try testing.expectEqual(size_of_static(u16), size_of_static(i16));
    try testing.expectEqual(size_of_static(u16), size_of_static(i13));
    try testing.expectEqual(size_of_static(u16), 2);
}

test "union size" {
    var u = TestUnion{ .c = 100 };
    try testing.expectEqual(size_of_dynamic(TestUnion, u), 3);
    u = TestUnion{ .a = 99 };
    // 1 byte for the u8, 1 byte for the tag
    try testing.expectEqual(size_of_dynamic(TestUnion, u), 2);
}

pub const TestStructA = struct {
    @"bool": bool = false,
    int_a: u32 = 0xaabbcc,
    int_b: u40 = 40404040,
    @"enum": TestEnum = .a,
    other_struct: TestStructB = .{},
};

const TestStructB = struct {
    a: u8 = 55,
    b: u32 = std.math.maxInt(u32),
    c: TestEnum = .b,
};

pub const TestEnum = enum(u8) { a, b, c };

test "array" {
    var buffer = [_]u8{0} ** 50;
    const int_array = [_]u8{ 1, 2, 3 };
    const T = [int_array.len]u8;
    pack_dynamic(T, buffer[0..], int_array);
    const unpacked_sa = try unpack_dynamic(null, T, buffer[0..size_of_dynamic(T, int_array)]);
    try std.testing.expectEqual(int_array, unpacked_sa);

    const union_array = [_]TestUnion{
        .{ .a = 200 },
        .{ .b = -105 },
        .{ .c = 999 },
    };
    const T2 = [union_array.len]TestUnion;
    pack_dynamic(T2, buffer[0..], union_array);
    const unpacked_ua = try unpack_dynamic(null, T2, buffer[0..size_of_dynamic(T2, union_array)]);
    try std.testing.expectEqual(union_array, unpacked_ua);
}

test "slice (pointer)" {
    const allocator = std.testing.allocator;
    var buffer = [_]u8{0} ** 50;
    var int_slice = [_]i32{ 1, 0, -8000, 700000 };
    pack_dynamic([]i32, buffer[0..], int_slice[0..]);
    const unpacked_ints = try unpack_dynamic(allocator, []i32, buffer[0..size_of_dynamic([]i32, int_slice[0..])]);
    defer allocator.free(unpacked_ints);
    try std.testing.expect(std.mem.eql(i32, unpacked_ints, int_slice[0..]));

    var union_slice = [_]TestUnion{
        .{ .a = 200 },
        .{ .b = -105 },
        .{ .c = 999 },
    };
    pack_dynamic([]TestUnion, buffer[0..], union_slice[0..]);
    const unpacked_unions = try unpack_dynamic(allocator, []TestUnion, buffer[0..size_of_dynamic([]TestUnion, union_slice[0..])]);
    defer allocator.free(unpacked_unions);
    for (union_slice) |i, n| {
        try std.testing.expect(std.meta.eql(i, unpacked_unions[n]));
    }

    const expected: usize = 4 + 3 + size_of_static(SLICE_LEN_T); // u8, i8, u16 (1, 1, 2) + tag_type for each union (1 * 3) + slice len (4)
    try std.testing.expectEqual(expected, size_of_dynamic([]TestUnion, union_slice[0..]));

    try std.testing.expectError(error.UnpackSliceWithoutAllocator, unpack_dynamic(null, []TestUnion, buffer[0..]));
}

test "struct dynamic" {
    var buffer = [_]u8{0} ** 50;
    var t = TestStructWithUnion{ .u = .{ .c = 500 } };

    pack_dynamic(TestStructWithUnion, buffer[0..], t);

    const unpacked_struct = try unpack_dynamic(null, TestStructWithUnion, buffer[0..size_of_dynamic(TestStructWithUnion, t)]);
    try std.testing.expect(std.meta.eql(t, unpacked_struct));
    t.a = 0;
    try std.testing.expect(!std.meta.eql(t, unpacked_struct));

    t.u = .{ .a = 9 };
    try std.testing.expect(!std.meta.eql(t, try unpack_dynamic(null, TestStructWithUnion, buffer[0..size_of_dynamic(TestStructWithUnion, t)])));
    pack_dynamic(TestStructWithUnion, buffer[0..], t);
    try std.testing.expect(std.meta.eql(t, try unpack_dynamic(null, TestStructWithUnion, buffer[0..size_of_dynamic(TestStructWithUnion, t)])));
}

test "struct with slice" {
    var buffer = [_]u8{0} ** 50;
    var slice = [_]u8{ 0, 1, 2, 3, 4 };
    var t = TestStructWithSlice{ .s = slice[0..] };

    pack_dynamic(TestStructWithSlice, buffer[0..], t);

    const unpacked_struct = try unpack_dynamic(std.testing.allocator, TestStructWithSlice, buffer[0..size_of_dynamic(TestStructWithSlice, t)]);
    defer std.testing.allocator.free(unpacked_struct.s);
    for (unpacked_struct.s) |i, n| {
        try std.testing.expectEqual(i, t.s[n]);
    }
}

test "union" {
    var buffer = [_]u8{0} ** 50;
    var u = TestUnion{ .b = -120 };
    PackDynamic.pack_union(TestUnion, buffer[0..], u);
    const unpacked = try UnpackDynamic.unpack_union(null, TestUnion, buffer[0..size_of_dynamic(TestUnion, u)]);
    buffer[0] = 0;
    const unpacked2 = try UnpackDynamic.unpack_union(null, TestUnion, buffer[0..size_of_dynamic(TestUnion, u)]);

    // Despite the buffer changing, unpacked remains the same. Its memory is not relient on the buffer.
    try std.testing.expect(std.meta.eql(u, unpacked));
    try std.testing.expect(!std.meta.eql(u, unpacked2));

    // Using pack/unpack_dynamic instead of the lower level add/unpack_union functions
    pack_dynamic(TestUnion, buffer[0..], u);
    var unpacked_union = try unpack_dynamic(null, TestUnion, buffer[0..size_of_dynamic(TestUnion, u)]);
    try std.testing.expect(std.meta.eql(u, unpacked_union));

    u = .{ .c = 7777 };
    try std.testing.expect(!std.meta.eql(u, unpacked_union));
    pack_dynamic(TestUnion, buffer[0..], u);
    unpacked_union = try unpack_dynamic(null, TestUnion, buffer[0..size_of_dynamic(TestUnion, u)]);
    try std.testing.expect(std.meta.eql(u, unpacked_union));
}

const TestStructWithUnion = struct {
    a: u8 = 8,
    u: TestUnion,
};
const TestStructWithSlice = struct {
    s: []u8,
};
const TestUnion = union(enum) {
    a: u8,
    b: i8,
    c: u16,
};
