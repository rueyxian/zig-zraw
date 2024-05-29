const std = @import("std");
const debug = std.debug;
const fmt = std.fmt;

pub fn partialByInclusion(value: anytype, field_names_tuple: anytype) PartialByInclusion(@TypeOf(value), field_names_tuple) {
    var partial: PartialByInclusion(@TypeOf(value), field_names_tuple) = undefined;
    inline for (@typeInfo(@TypeOf(partial)).Struct.fields) |field| {
        @field(partial, field.name) = @field(value, field.name);
    }
    return partial;
}

pub fn partialByExclusion(value: anytype, field_names_tuple: anytype) PartialByExclusion(@TypeOf(value), field_names_tuple) {
    var partial: PartialByExclusion(@TypeOf(value), field_names_tuple) = undefined;
    inline for (@typeInfo(@TypeOf(partial)).Struct.fields) |field| {
        @field(partial, field.name) = @field(value, field.name);
    }
    return partial;
}

pub fn PartialByInclusion(comptime T: type, field_names_tuple: anytype) type {
    return PartialStruct(T, true, field_names_tuple);
}

pub fn PartialByExclusion(comptime T: type, field_names: anytype) type {
    return PartialStruct(T, false, field_names);
}

fn PartialStruct(comptime T: type, comptime inclusion: bool, field_names_tuple: anytype) type {
    const base_info = @typeInfo(T);
    debug.assert(base_info == .Struct);
    debug.assert(base_info.Struct.layout == .auto);
    debug.assert(base_info.Struct.backing_integer == null);
    debug.assert(base_info.Struct.is_tuple == false);
    const base_fields = @typeInfo(T).Struct.fields;

    const tup_info = @typeInfo(@TypeOf(field_names_tuple));
    debug.assert(tup_info == .Struct);
    debug.assert(tup_info.Struct.is_tuple);
    const fields_len = field_names_tuple.len + (@intFromBool(!inclusion) * (base_fields.len - (field_names_tuple.len * 2)));

    debug.assert(fields_len > 0);

    const Map: type = blk: {
        inline for (field_names_tuple) |field_name| {
            debug.assert(@hasField(T, field_name));
        }
        break :blk StaticStringMap(field_names_tuple);
    };
    var fields: [fields_len]std.builtin.Type.StructField = undefined;
    var i: usize = 0;
    inline for (base_fields) |base_field| {
        if (Map.has(base_field.name) == inclusion) {
            fields[i] = base_field;
            i += 1;
        }
    }

    const info = std.builtin.Type.Struct{
        .layout = .auto,
        .backing_integer = null,
        .fields = &fields,
        // .decls = &.{},
        .decls = base_info.Struct.decls,
        .is_tuple = false,
    };
    return @Type(std.builtin.Type{ .Struct = info });
}

fn StaticStringMap(comptime strings_tuple: anytype) type {
    const kvs_list = comptime blk: {
        const KV = struct { []const u8, void };
        var fields: [strings_tuple.len]std.builtin.Type.StructField = undefined;
        for (0..strings_tuple.len) |i| {
            const value = KV{ strings_tuple[i], {} };
            fields[i] = std.builtin.Type.StructField{
                .name = fmt.comptimePrint("{}", .{i}),
                .type = KV,
                .default_value = @ptrCast(@alignCast(&value)),
                .is_comptime = true,
                .alignment = @alignOf(KV),
            };
        }
        const info = std.builtin.Type.Struct{
            .layout = .auto,
            .backing_integer = null,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        };
        break :blk @Type(std.builtin.Type{ .Struct = info }){};
    };
    return std.ComptimeStringMap(void, kvs_list);
}

pub fn getPartialByInclusionFn(comptime Context: type, field_names_tuple: anytype) fn (*const Context) PartialByInclusion(Context, field_names_tuple) {
    return struct {
        const Partial = PartialByInclusion(Context, field_names_tuple);
        fn func(context: *const Context) Partial {
            return partialByInclusion(context.*, field_names_tuple);
            // var partial: Partial = undefined;
            // inline for (@typeInfo(Partial).Struct.fields) |field| {
            //     @field(partial, field.name) = @field(context, field.name);
            // }
            // return partial;
        }
    }.func;
}

pub fn getPartialByExclusionFn(comptime Context: type, field_names_tuple: anytype) fn (*const Context) PartialByExclusion(Context, field_names_tuple) {
    return struct {
        const Partial = PartialByExclusion(Context, field_names_tuple);
        fn func(context: *const Context) Partial {
            return partialByExclusion(context.*, field_names_tuple);
            // var partial: Partial = undefined;
            // inline for (@typeInfo(Partial).Struct.fields) |field| {
            //     @field(partial, field.name) = @field(context, field.name);
            // }
            // return partial;
        }
    }.func;
}
