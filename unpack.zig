const std = @import("std");
const testing = std.testing;

usingnamespace @import("sizes.zig");

pub fn unpack_dynamic(slice_allocator: ?*std.mem.Allocator, comptime T: type, bytes: []const u8) anyerror!T {
    return switch (@typeInfo(T)) {
        .Enum, .Int, .Bool => unpack_static(T, bytes),
        // .Enum => std.meta.intToEnum(T, bytes[0]),
        .Union => UnpackDynamic.unpack_union(slice_allocator, T, bytes),
        .Struct => UnpackDynamic.unpack_struct(slice_allocator, T, bytes),
        .Array => UnpackDynamic.unpack_array(slice_allocator, T, bytes),
        .Pointer => UnpackDynamic.unpack_pointer(slice_allocator, T, bytes),
        else => @compileError("Todo"),
    };
}

pub fn unpack_static(comptime T: type, bytes: []const u8) !T {
    switch (@typeInfo(T)) {
        .Enum => |e| {
            if (std.math.maxInt(e.tag_type) > std.math.maxInt(u8)) @compileError("Enums with tags > u8 are not yet supported");
            // return @intToEnum(T, bytes[0]);
            return try std.meta.intToEnum(T, bytes[0]);
        },
        .Int => {
            return std.mem.bigToNative(T, @ptrCast(*align(1) const T, bytes).*);
        },
        .Struct => {
            return unpack_struct_static(T, bytes);
        },
        .Bool => {
            return bytes[0] == 1;
        },
        else => @compileError("'unpack_static' does not support type: " ++ @typeName(T) ++ " (" ++ f.name ++ ")."),
    }
}

pub const UnpackDynamic = struct {
    fn unpack_array(slice_allocator: ?*std.mem.Allocator, comptime T: type, bytes: []const u8) anyerror!T {
        var result: T = undefined;
        const CT = std.meta.Child(T);
        var head: usize = 0;

        for (result) |*i| {
            i.* = try unpack_dynamic(slice_allocator, CT, bytes[head..]);
            head += size_of_dynamic(CT, i.*);
        }
        return result;
    }

    /// Allocates memory for this slice based off the encoded length in the initial bytes
    /// Caller owns the memory.
    fn unpack_slice(slice_allocator: ?*std.mem.Allocator, comptime T: type, bytes: []const u8) anyerror!T {
        const CT = std.meta.Child(T);
        const len = try unpack_static(SLICE_LEN_T, bytes[0..size_of_static(SLICE_LEN_T)]);
        var head: usize = size_of_static(SLICE_LEN_T);
        var result = try slice_allocator.?.alloc(CT, len);

        var index: usize = 0;
        while (index < len) : (index += 1) {
            const value = try unpack_dynamic(slice_allocator, CT, bytes[head..]);
            head += size_of_dynamic(CT, value);
            result[index] = value;
        }
        return result;
    }

    fn unpack_pointer(slice_allocator: ?*std.mem.Allocator, comptime T: type, bytes: []const u8) anyerror!T {
        const TI = @typeInfo(T).Pointer;
        switch (TI.size) {
            .One => {
                @compileError("todo: unpack one item pointer");
            },
            .Many => {
                @compileError("todo: unpack many item pointer");
            },
            .Slice => {
                if (slice_allocator) |allocator| {
                    return unpack_slice(allocator, T, bytes);
                } else {
                    return error.UnpackSliceWithoutAllocator;
                }
            },
            .C => {
                @compileError("todo: unpack c pointer");
            },
        }
    }

    pub fn unpack_union(slice_allocator: ?*std.mem.Allocator, comptime T: type, bytes: []const u8) anyerror!T {
        const Tag = std.meta.Tag(T);
        const TT = std.meta.Tag(Tag);
        // We use the static sizeOf here as enums are known static values.
        const tag_index = @ptrCast(*align(1) const TT, bytes[0..size_of_static(TT)]).*;
        // const enum_payload = @intToEnum(Tag, tag_index);

        inline for (@typeInfo(T).Union.fields) |f, n| {
            if (n == tag_index) {
                const value = try unpack_dynamic(slice_allocator, f.field_type, bytes[size_of_static(TT)..]);
                return @unionInit(T, f.name, value);
            }
        }
        unreachable;
    }

    fn unpack_struct(slice_allocator: ?*std.mem.Allocator, comptime T: type, bytes: []const u8) anyerror!T {
        var result: T = undefined;
        var head: usize = 0;
        inline for (std.meta.fields(T)) |f| {
            const slice = bytes[head..];
            const value = try unpack_dynamic(slice_allocator, f.field_type, slice);
            head += size_of_dynamic(f.field_type, value);
            @field(result, f.name) = value;
        }
        return result;
    }
};

fn unpack_struct_static(comptime T: type, bytes: []const u8) !T {
    // TODO we should probably remove this, as unpack_static(enum) can now return an error, which makes this require an unreachable statement
    var result: T = undefined;
    var head: usize = 0;

    inline for (std.meta.fields(T)) |f| {
        var value: f.field_type = undefined;

        const field_len = size_of_static(f.field_type);
        const slice = bytes[head .. head + field_len];
        defer head += field_len;

        value = unpack_static(f.field_type, slice) catch unreachable;
        @field(result, f.name) = value;
    }
    return result;
}
