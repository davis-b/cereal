const std = @import("std");
const testing = std.testing;

usingnamespace @import("sizes.zig");

pub fn pack_dynamic(comptime T: type, buffer: []u8, value: T) void {
    const f = switch (@typeInfo(T)) {
        .Enum, .Int, .Bool => add_to_buffer,
        .Union => PackDynamic.pack_union,
        .Struct => PackDynamic.pack_struct,
        .Pointer => PackDynamic.pack_pointer,
        .Array => PackDynamic.pack_array,
        else => @compileError("todo: dynamically pack " ++ @typeName(T) ++ "."),
    };
    f(T, buffer, value);
}

pub fn pack_static(comptime T: type, instance: T) [size_of_static(T)]u8 {
    var buffer: [size_of_static(T)]u8 = undefined;
    add_to_buffer(T, buffer[0..], instance);
    return buffer;
}

pub const PackDynamic = struct {
    fn pack_pointer(comptime T: type, buffer: []u8, instance: T) void {
        const TI = @typeInfo(T).Pointer;
        const CT = TI.child;
        switch (TI.size) {
            .One => {
                @compileError("todo: one item pointer");
            },
            .Many => {
                @compileError("todo: many item pointer");
            },
            .Slice => {
                pack_slice(T, buffer, instance);
            },
            .C => {
                @compileError("todo: c pointer");
            },
        }
    }

    /// Encodes slice length as well as slice values.
    fn pack_slice(comptime T: type, buffer: []u8, instance: T) void {
        for (pack_static(SLICE_LEN_T, @intCast(SLICE_LEN_T, instance.len))) |i, n| {
            buffer[n] = i;
        }
        pack_array(T, buffer[size_of_static(SLICE_LEN_T)..], instance);
    }

    fn pack_array(comptime T: type, buffer: []u8, instance: T) void {
        const CT = std.meta.Child(T);
        var head: usize = 0;
        for (instance) |i| {
            pack_dynamic(CT, buffer[head..], i);
            head += size_of_dynamic(CT, i);
        }
    }

    fn pack_struct(comptime T: type, buffer: []u8, instance: T) void {
        var result: T = undefined;
        var head: usize = 0;

        inline for (std.meta.fields(T)) |f| {
            const value = @field(instance, f.name);
            const field_len = size_of_dynamic(f.field_type, value);
            const slice = buffer[head .. head + field_len];
            head += field_len;
            pack_dynamic(f.field_type, slice, value);
        }
    }

    pub fn pack_union(comptime T: type, buffer: []u8, instance: T) void {
        const TT = std.meta.Tag(T);
        const active_tag = std.meta.activeTag(instance);

        // Add tag enum value to buffer
        add_to_buffer(TT, buffer, active_tag);

        // Add union's unwrapped value to buffer
        inline for (@typeInfo(T).Union.fields) |f| {
            if (std.mem.eql(u8, f.name, @tagName(active_tag))) {
                const x = @field(instance, f.name);
                pack_dynamic(f.field_type, buffer[size_of_static(TT)..], x);
                return;
            }
        }
        unreachable;
    }
};

fn add_to_buffer(comptime T: type, buffer: []u8, value: T) void {
    switch (@typeInfo(T)) {
        .Enum => |e| {
            if (std.math.maxInt(e.tag_type) > std.math.maxInt(u8)) @compileError("Enums with tags > u8 are not yet supported");
            buffer[0] = @enumToInt(value); // TODO use std.meta.enumToInt and raise errors
        },
        .Int => |i| {
            // const netInt = std.mem.nativeToBig(T, value);
            // try array.appendSlice(std.mem.asBytes(&netInt));
            var int_buffer: [i.bits / 8]u8 = undefined;
            std.mem.writeIntBig(T, &int_buffer, value);
            for (int_buffer) |v, n| buffer[n] = v;
        },
        .Struct => {
            const slice = pack_struct_static(T, value);
            for (slice) |i, n| buffer[n] = i;
        },
        .Bool => {
            buffer[0] = @boolToInt(value);
        },
        .Float => @compileError("Todo"),
        else => @compileError("Serialize-Static does not support packing type: " ++ @typeName(T) ++ "."),
    }
}

fn pack_struct_static(comptime T: type, instance: T) [size_of_static(T)]u8 {
    var buffer: [size_of_static(T)]u8 = undefined;
    var head: usize = 0;
    inline for (std.meta.fields(T)) |f| {
        const value = @field(instance, f.name);
        defer head += size_of_static(f.field_type);
        add_to_buffer(f.field_type, buffer[head..], value);
    }
    return buffer;
}
