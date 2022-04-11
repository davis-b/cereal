const std = @import("std");

pub const SLICE_LEN_T = u32;

/// This represents the size of the type on the wire, not necessarily the size on our machine.
pub fn size_of_static(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .Struct => struct_size_static(T),
        // Rounds up to the nearest byte value. Will this cause an adverse side effect?
        .Int => |i| std.math.divCeil(usize, i.bits, 8) catch @panic("int bit division error"),
        .Bool => 1,
        .Enum => |e| size_of_static(e.tag_type),
        // .Union => could return the largest type this could be, if static. e.g. {a:u32, b:u16} would return 3 (bytes).
        .Pointer, .Array => @compileError("Unsupported type for static size determination"),
        else => @compileError("Unsupported type: " ++ @typeName(T)),
    };
}

/// This represents the size of the instance on the wire, not necessarily the size on our machine.
pub fn size_of_dynamic(comptime T: type, instance: T) usize {
    return switch (@typeInfo(T)) {
        .Int, .Bool, .Enum => size_of_static(T),
        .Union => union_size(T, instance),
        .Struct => struct_size_dynamic(T, instance),
        .Array => array_size(T, instance),
        .Pointer => pointer_size(T, instance),
        else => |x| @compileError("todo, find dynamic size of : " ++ @typeName(T)),
    };
}

fn pointer_size(comptime T: type, instance: T) usize {
    const TI = @typeInfo(T).Pointer;
    const CT = TI.child;
    switch (TI.size) {
        .One => {
            @compileError("todo: find size of one item pointer");
        },
        .Many => {
            @compileError("todo: find size of many item pointer");
        },
        .Slice => {
            return slice_size(T, instance);
        },
        .C => {
            @compileError("todo: find size of c pointer");
        },
    }
}

fn slice_size(comptime T: type, instance: T) usize {
    return array_size(T, instance) + size_of_static(SLICE_LEN_T);
}

fn array_size(comptime T: type, instance: T) usize {
    var total: usize = 0;
    for (instance) |i| {
        total += size_of_dynamic(std.meta.Child(T), i);
    }
    return total;
}

fn union_size(comptime T: type, instance: T) usize {
    const active_tag = std.meta.activeTag(instance);
    inline for (@typeInfo(T).Union.fields) |f| {
        if (std.mem.eql(u8, f.name, @tagName(active_tag))) {
            return size_of_static(std.meta.Tag(T)) + size_of_dynamic(f.field_type, @field(instance, f.name));
        }
    }
    unreachable;
}

fn struct_size_dynamic(comptime T: type, instance: T) usize {
    var total: usize = 0;
    inline for (std.meta.fields(T)) |f| {
        total += size_of_dynamic(f.field_type, @field(instance, f.name));
    }
    return total;
}

pub fn struct_size_static(comptime T: type) usize {
    var total: usize = 0;
    inline for (std.meta.fields(T)) |f| {
        total += size_of_static(f.field_type);
    }
    return total;
}
