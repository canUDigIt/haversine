const std = @import("std");
const json = @import("json.zig");

const HaversinePair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
};

pub fn parseHaversinePairs(input_json: []const u8, max_pair_count: u64, pairs: *HaversinePair, allocator: std.mem.Allocator) u64 {
    var pair_count: u64 = 0;

    const root = json.parseJson(input_json, allocator);
    const pair_array = json.lookupElement(json, "pairs");
    if (pair_array) |array| {
        var element = array.first_sub_element;
        while (element and pair_count < max_pair_count) |el| {
            pair_count += 1;
            const pair = pairs + pair_count;

            pair.x0 = json.convertElementToF64(el, "x0");
            pair.y0 = json.convertElementToF64(el, "y0");
            pair.x1 = json.convertElementToF64(el, "x1");
            pair.y1 = json.convertElementToF64(el, "y1");
        }
    }

    json.freeJson(root, allocator);
    return pair_count;
}

pub fn main() !void {}
