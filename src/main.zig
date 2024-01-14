const std = @import("std");
const json = @import("json.zig");
const haversine = @import("haversine.zig");

const HaversinePair = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
};

fn parseHaversinePairs(input_json: []const u8, max_pair_count: u64, pairs: *std.ArrayList(HaversinePair), allocator: std.mem.Allocator) !u64 {
    var pair_count: u64 = 0;

    const root = try json.parseJson(input_json, allocator);
    if (root) |r| {
        const pair_array = json.lookupElement(r, "pairs");
        if (pair_array) |array| {
            var element = array.first_sub_element;
            while (element) |el| : (element = el.next_sibling) {
                const pair = HaversinePair{
                    .x0 = json.convertElementToF64(el, "x0"),
                    .y0 = json.convertElementToF64(el, "y0"),
                    .x1 = json.convertElementToF64(el, "x1"),
                    .y1 = json.convertElementToF64(el, "y1"),
                };
                try pairs.append(pair);

                pair_count += 1;

                if (pair_count >= max_pair_count) break;
            }
        }

        json.freeJson(r, allocator);
    }

    return pair_count;
}

fn sumHaversineDistances(count: u64, pairs: []HaversinePair) f64 {
    var sum: f64 = 0;

    const sum_coef: f64 = 1.0 / @as(f64, @floatFromInt(count));
    for (pairs) |pair| {
        const earth_radius = 6372.8;
        const dist = haversine.referenceHaversine(pair.x0, pair.y0, pair.x1, pair.y1, earth_radius);
        sum += sum_coef * dist;
    }
    return sum;
}

fn readEntireFile(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(name, .{});
    defer file.close();
    const file_stat = try file.stat();
    const filesize = file_stat.size;

    const file_bytes = try file.readToEndAlloc(allocator, filesize);
    return file_bytes;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const stdOut = std.io.getStdOut().writer();
    const stdErr = std.io.getStdErr().writer();

    if ((args.len != 2) and (args.len != 3)) {
        try stdErr.print("{d} args\n", .{args.len});
        try stdErr.print("Usage: {s} [haversine_input.json]\n", .{args[0]});
        try stdErr.print("       {s} [haversine_input.json] [answers.f64]\n", .{args[0]});
        return;
    }

    const json_file = try std.fs.cwd().openFile(args[1], .{});
    defer json_file.close();
    const file_stat = try json_file.stat();
    const filesize = file_stat.size;
    try stdOut.print("{s} is {d} bytes\n", .{ args[1], filesize });

    const input_json = try json_file.readToEndAlloc(allocator, filesize);
    defer allocator.free(input_json);

    const minimum_json_pair_encoding: u32 = 6 * 4;
    const max_pair_count: u64 = input_json.len / minimum_json_pair_encoding;

    if (max_pair_count > 0) {
        var parsed_values = try std.ArrayList(HaversinePair).initCapacity(allocator, max_pair_count);
        defer parsed_values.deinit();

        const pair_count = try parseHaversinePairs(input_json, max_pair_count, &parsed_values, allocator);
        const sum = sumHaversineDistances(pair_count, parsed_values.items[0..pair_count]);

        try stdOut.print("Input size: {d}\n", .{input_json.len});
        try stdOut.print("Pair count: {d}\n", .{pair_count});
        try stdOut.print("Haversine sum: {d:.16}\n", .{sum});

        if (args.len == 3) {
            const answers_f64 = try readEntireFile(args[2], allocator);
            defer allocator.free(answers_f64);

            if (answers_f64.len >= @sizeOf(f64)) {
                const answer_values = std.mem.bytesAsSlice(f64, answers_f64);
                try stdOut.print("\nValidation:\n", .{});

                const ref_answer_count = @divExact(answers_f64.len - @sizeOf(f64), @sizeOf(f64));
                if (pair_count != ref_answer_count) {
                    try stdOut.print("FAILED - pair count {d} doesn't match ref count {d}\n", .{ pair_count, ref_answer_count });
                }

                const ref_sum = answer_values[ref_answer_count];
                try stdOut.print("Reference sum: {d:.16}\n", .{ref_sum});
                try stdOut.print("Difference: {d:.16}\n", .{sum - ref_sum});
                try stdOut.print("\n", .{});
            }
        }
    } else {
        try stdErr.print("ERROR: Malformed input JSON\n", .{});
    }
}
