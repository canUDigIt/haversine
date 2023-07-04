const std = @import("std");
const haversine = @import("haversine.zig");

const Mode = enum {
    uniform,
    cluster,
};

pub fn randomInRange(rand: std.rand.Random, min: f64, max: f64) f64 {
    const f = rand.float(f64);
    const size = max - min;
    const size_half = size * 0.5;
    return (f * size) - size_half;
}

pub fn randomDegree(rand: std.rand.Random, center: f64, radius: f64, maxAllowed: f64) f64 {
    var minVal = center - radius;
    if (minVal < -maxAllowed) {
        minVal = -maxAllowed;
    }

    var maxVal = center + radius;
    if (maxVal > maxAllowed) {
        maxVal = maxAllowed;
    }
    const result = randomInRange(rand, minVal, maxVal);
    return result;
}

pub fn main() !void {
    // Setup
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    std.debug.print("Usage: generator [uniform/cluster] [random seed] [number of coordinate pairs to generate]\n", .{});

    // program name + 3 args == 4 args total
    if ((args.len - 1) != 3) {
        std.debug.print("Got {} arguments. Need 3 arguments!\n", .{args.len - 1});
        return;
    }

    const mode = if (std.mem.eql(u8, args[1], "cluster")) Mode.cluster else Mode.uniform;
    const seed = try std.fmt.parseInt(u64, args[2], 10);
    const count = try std.fmt.parseInt(u64, args[3], 10);

    var romu = std.rand.RomuTrio.init(seed);
    var r = romu.random();

    const json_filename = try std.fmt.allocPrint(allocator, "data-{d}-{s}.{s}", .{ count, "flex", "json" });
    defer allocator.free(json_filename);

    const json_file = try std.fs.cwd().createFile(
        json_filename,
        .{},
    );
    defer json_file.close();

    const ans_filename = try std.fmt.allocPrint(allocator, "data-{d}-{s}.{s}", .{ count, "haveranswer", "f64" });
    defer allocator.free(ans_filename);

    const answers_file = try std.fs.cwd().createFile(
        ans_filename,
        .{},
    );
    defer answers_file.close();

    try json_file.writer().print("{{\"pairs\":[\n", .{});

    var clusterCountLeft: u64 = if (mode == .cluster) 0 else std.math.maxInt(u64);
    const maxAllowedX: f64 = 180;
    const maxAllowedY: f64 = 90;

    var xCenter: f64 = 0;
    var yCenter: f64 = 0;
    var xRadius: f64 = maxAllowedX;
    var yRadius: f64 = maxAllowedY;

    const maxPairCount: u64 = 1 << 34;
    if (count >= maxPairCount) {
        std.debug.print("To avoid accidentally generating massive files, number of pairs must be less than {d}\n", .{maxPairCount});
        return;
    }

    const clusterCountMax: u64 = 1 + (count / 64);
    var sum: f64 = 0;
    const fCount: f64 = @floatFromInt(@as(u64, count));
    const sumCoef: f64 = 1.0 / fCount;
    for (0..count) |i| {
        if (clusterCountLeft == 0) {
            clusterCountLeft = clusterCountMax;
            xCenter = randomInRange(r, -maxAllowedX, maxAllowedX);
            yCenter = randomInRange(r, -maxAllowedY, maxAllowedY);
            xRadius = randomInRange(r, 0, maxAllowedX);
            yRadius = randomInRange(r, 0, maxAllowedY);
        }
        clusterCountLeft -= 1;

        const x0 = randomDegree(r, xCenter, xRadius, maxAllowedX);
        const y0 = randomDegree(r, yCenter, yRadius, maxAllowedY);
        const x1 = randomDegree(r, xCenter, xRadius, maxAllowedX);
        const y1 = randomDegree(r, yCenter, yRadius, maxAllowedY);

        const earthRadius = 6372.8;
        const distance = haversine.referenceHaversine(x0, y0, x1, y1, earthRadius);

        sum += sumCoef * distance;

        const jsonSep = if (i == (count - 1)) "\n" else ",\n";
        try json_file.writer().print("    {{\"x0\":{d:.16}, \"y0\":{d:.16}, \"x1\":{d:.16}, \"y1\":{d:.16}}}{s}", .{ x0, y0, x1, y1, jsonSep });

        const bytes = std.mem.toBytes(distance);
        _ = try answers_file.write(&bytes);
    }
    try json_file.writer().print("]}}\n", .{});

    const sumBytes = std.mem.toBytes(sum);
    _ = try answers_file.writer().write(&sumBytes);

    // Print stats
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Method: {s}\n", .{args[1]});
    try stdout.print("Random seed: {d}\n", .{seed});
    try stdout.print("Pair count: {d}\n", .{count});
    try stdout.print("Expected sum: {d:.16}\n", .{sum});
    try bw.flush();
}
