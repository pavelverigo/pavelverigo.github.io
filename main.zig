const std = @import("std");

// time in ms
var prev_time: f64 = undefined;
var acc_time: f64 = 0;
const step_time: f64 = 15;

const w = 1400;
const h = 700;
const allocator = std.heap.wasm_allocator;

var image_data_old: bool = true;
var image_data: []u32 = undefined;
const alive_color: u32 = 0xFF000000;
const dead_color: u32 = 0xFFFFFFFF;

// padded by 1 cell on all sides
var cur_grid: []u8 = undefined;
var new_grid: []u8 = undefined;

inline fn index(x: usize, y: usize) usize {
    return (y + 1) * (w + 2) + (x + 1);
}

fn load_pattern() void {
    const pattern = @embedFile("pattern.rle");
    const offset = 0;
    const mem = std.mem;

    var line_it = mem.tokenizeScalar(u8, pattern, '\n');

    // header line
    const x, const y = blk: {
        var line = line_it.next() orelse @panic("pattern");
        while (mem.startsWith(u8, line, "#")) {
            line = line_it.next() orelse @panic("pattern");
        }

        var i: usize = 0;

        if (!mem.startsWith(u8, line[i..], "x = ")) @panic("pattern");
        i += 4;
        const comma_x = mem.indexOfScalar(u8, line[i..], ',') orelse @panic("pattern");
        const x = std.fmt.parseInt(usize, line[i..][0..comma_x], 10) catch @panic("pattern");
        i += comma_x + 1;

        if (!mem.startsWith(u8, line[i..], " y = ")) @panic("pattern");
        i += 5;
        const y = std.fmt.parseInt(usize, line[i..], 10) catch @panic("pattern");

        break :blk .{ x, y };
    };

    if (x + offset > w or y + offset > h) @panic("pattern");

    const data = line_it.rest();
    var x_cnt: usize = 0;
    var y_cnt: usize = 0;
    var i: usize = 0;
    var c = data[i];
    while (c != '!') : ({
        i += 1;
        if (i == data.len) @panic("pattern");
        c = data[i];
    }) {
        if ('0' <= c and c <= '9') {
            var n: usize = 0;
            while ('0' <= c and c <= '9') {
                n = 10 * n + (c - '0');
                if (n > x) @panic("pattern");
                i += 1;
                if (i == data.len) @panic("pattern");
                c = data[i];
            }
            if (c == 'b') {
                if (x_cnt + n - 1 >= x) @panic("pattern");
                x_cnt += n;
                continue;
            }
            if (c == 'o') {
                if (x_cnt + n - 1 >= x) @panic("pattern");
                @memset(cur_grid[index(x_cnt + offset, y_cnt + offset)..][0..n], 1);
                x_cnt += n;
                continue;
            }
            if (c == '$') {
                if (y_cnt + n - 1 >= y) @panic("pattern");
                x_cnt = 0;
                y_cnt += n;
                continue;
            }
            @panic("pattern");
        }
        if (c == 'b') {
            if (x_cnt >= x) @panic("pattern");
            x_cnt += 1;
            continue;
        }
        if (c == 'o') {
            if (x_cnt >= x) @panic("pattern");
            cur_grid[index(x_cnt + offset, y_cnt + offset)] = 1;
            x_cnt += 1;
            continue;
        }
        if (c == '$') {
            if (y_cnt >= y) @panic("pattern");
            x_cnt = 0;
            y_cnt += 1;
            continue;
        }
        if (c == '\n' or c == ' ') continue;
        @panic("pattern");
    }

    if (y_cnt != y - 1) @panic("pattern");
}

export fn init(time: f64) void {
    prev_time = time;

    cur_grid = allocator.alloc(u8, (w + 2) * (h + 2)) catch @panic("OOM");
    @memset(cur_grid, 0);
    new_grid = allocator.alloc(u8, (w + 2) * (h + 2)) catch @panic("OOM");
    @memset(new_grid, 0);

    image_data = allocator.alloc(u32, w * h) catch @panic("OOM");
    @memset(image_data, dead_color);

    load_pattern();
}

fn step() void {
    const stride = w + 2;
    var i: usize = stride + 1;
    for (0..h) |y| {
        for (0..w) |x| {
            var n: u8 = 0;
            n += cur_grid[i - stride - 1];
            n += cur_grid[i - stride];
            n += cur_grid[i - stride + 1];
            n += cur_grid[i - 1];
            n += cur_grid[i + 1];
            n += cur_grid[i + stride - 1];
            n += cur_grid[i + stride];
            n += cur_grid[i + stride + 1];
            if (cur_grid[index(x, y)] == 1) {
                new_grid[index(x, y)] = @intFromBool(n == 2 or n == 3);
            } else {
                new_grid[index(x, y)] = @intFromBool(n == 3);
            }
            i += 1;
        }
        i += 2;
    }

    const tmp = cur_grid;
    cur_grid = new_grid;
    new_grid = tmp;
}

export fn time_update(time: f64) void {
    acc_time += time - prev_time;
    prev_time = time;

    // give up
    if (acc_time >= step_time * 500) {
        acc_time = 0.0;
    }

    if (acc_time >= step_time) {
        image_data_old = true;
    }
    while (acc_time >= step_time) : (acc_time -= step_time) {
        step();
    }
}

extern fn output_image_data([*]const u32, usize) void;

export fn frame(time: f64) void {
    time_update(time);

    if (image_data_old) {
        for (0..h) |y| {
            for (0..w) |x| {
                image_data[y * w + x] = if (cur_grid[index(x, y)] == 1) alive_color else dead_color;
            }
        }

        output_image_data(image_data.ptr, image_data.len);
        image_data_old = false;
    }
}
