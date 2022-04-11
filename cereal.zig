const pack = @import("pack.zig");
const unpack = @import("unpack.zig");
const sizes = @import("sizes.zig");

pub const serialize = pack.pack_dynamic;
pub const deserialize = unpack.unpack_dynamic;

/// Returns true if the caller can statically pack this 
///  type into the same amount of memory every time.
pub fn can_statically_pack(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .Enum, .Int, .Bool => return true,
        .Pointer => return false, // single item pointers could depend on child type.
        .Array => |arr| return can_statically_pack(arr.child),
        .Struct, .Union => |t| {
            inline for (t.fields) |f| {
                if (!can_statically_pack(f.field_type)) return false;
            }
            return true;
        },
        else => @compileLog("todo, see if we can statically pack " ++ @typeName(T)),
    }
}

/// This represents the size of the type or instance on the wire, not necessarily the size on our machine.
pub fn size_of(item: anytype) usize {
    const T = @TypeOf(item);
    return switch (T) {
        @"type" => sizes.size_of_static(item),
        else => sizes.size_of_dynamic(T, item),
    };
}

const testing = @import("std").testing;
test "'size_of' switch statement" {
    var x: []u8 = undefined;
    const dynamic = switch (@TypeOf(x)) {
        @"type" => false,
        else => true,
    };
    try testing.expect(dynamic);
    const static = switch (@TypeOf(u8)) {
        @"type" => true,
        else => false,
    };
    try testing.expect(static);
}
