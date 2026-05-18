const std = @import("std");
const mem = std.mem;

const w = 1400;
const h = 700;

// time in ms
var prev_time: f64 = undefined;
var acc_time: f64 = 0;
const step_time: f64 = 7.5;

const alive_color: u32 = 0xFF000000;
const dead_color: u32 = 0xFFFFFFFF;

var image_data_old: bool = true;
var image_data: [w * h]u32 = @splat(0);

// each u64 stores 64 horizontal cells
// halo words are zeroed and never written to
const words = (w + 63) / 64;
const stride = words + 2;
const grid_words = (h + 2) * stride;

var grid_buf_a: [grid_words]u64 = @splat(0);
var grid_buf_b: [grid_words]u64 = @splat(0);
var cur_grid: *[grid_words]u64 = &grid_buf_a;
var new_grid: *[grid_words]u64 = &grid_buf_b;

fn get_cell(grid: []const u64, x: usize, y: usize) bool {
    const i = (y + 1) * stride + 1 + (x / 64);
    const mask = @as(u64, 1) << @intCast(x % 64);

    return (grid[i] & mask) != 0;
}

fn set_cell(grid: []u64, x: usize, y: usize, alive: bool) void {
    const i = (y + 1) * stride + 1 + (x / 64);
    const mask = @as(u64, 1) << @intCast(x % 64);

    if (alive) {
        grid[i] |= mask;
    } else {
        grid[i] &= ~mask;
    }
}

fn load_pattern() void {
    const pattern = @embedFile("pattern.rle");
    const offset = 0;

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
        const x = std.fmt.parseUnsigned(usize, line[i..][0..comma_x], 10) catch @panic("pattern");
        i += comma_x + 1;

        if (!mem.startsWith(u8, line[i..], " y = ")) @panic("pattern");
        i += 5;
        const y = std.fmt.parseUnsigned(usize, line[i..], 10) catch @panic("pattern");

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

                var j: usize = 0;
                while (j < n) : (j += 1) {
                    set_cell(cur_grid, x_cnt + offset + j, y_cnt + offset, true);
                }

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
            set_cell(cur_grid, x_cnt + offset, y_cnt + offset, true);
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

    load_pattern();
}

const Csa = struct {
    lo: u64,
    hi: u64,
};

// carry-save add 3 bitboards
inline fn csa(a: u64, b: u64, c: u64) Csa {
    const u = a ^ b;
    return .{
        .lo = u ^ c,
        .hi = (a & b) | (u & c),
    };
}

fn step() void {
    var y: usize = 1;
    while (y <= h) : (y += 1) {
        const top_base = (y - 1) * stride;
        const mid_base = y * stride;
        const bot_base = (y + 1) * stride;

        // preloaded prev/cur words
        var top_prev = cur_grid[top_base + 0];
        var top_cur = cur_grid[top_base + 1];

        var mid_prev = cur_grid[mid_base + 0];
        var mid_cur = cur_grid[mid_base + 1];

        var bot_prev = cur_grid[bot_base + 0];
        var bot_cur = cur_grid[bot_base + 1];

        var i: usize = 1;
        while (true) {
            // preload next words for this iteration
            const top_next = cur_grid[top_base + i + 1];
            const mid_next = cur_grid[mid_base + i + 1];
            const bot_next = cur_grid[bot_base + i + 1];

            const top_left = (top_cur << 1) | (top_prev >> 63);
            const top_mid = top_cur;
            const top_right = (top_cur >> 1) | (top_next << 63);

            const mid_left = (mid_cur << 1) | (mid_prev >> 63);
            const mid_right = (mid_cur >> 1) | (mid_next << 63);

            const bot_left = (bot_cur << 1) | (bot_prev >> 63);
            const bot_mid = bot_cur;
            const bot_right = (bot_cur >> 1) | (bot_next << 63);

            const a = csa(top_left, top_mid, top_right);
            const b = csa(mid_left, mid_right, bot_left);
            const c = csa(bot_mid, bot_right, 0);
            const d = csa(a.lo, b.lo, c.lo);

            const p = a.hi ^ b.hi;
            const q = c.hi ^ d.hi;

            const at_least_two_twos = (a.hi & b.hi) | (c.hi & d.hi) | (p & q);
            const exactly_one_two = (p ^ q) & ~at_least_two_twos;
            const next = exactly_one_two & (d.lo | mid_cur);

            if (i == words) {
                const last_word_mask: u64 = if (w % 64 == 0)
                    ~@as(u64, 0)
                else
                    ~@as(u64, 0) >> @intCast(64 - w % 64);

                new_grid[mid_base + i] = next & last_word_mask;
                break;
            }

            new_grid[mid_base + i] = next;

            // advance prev/cur words to the next column
            top_prev = top_cur;
            top_cur = top_next;

            mid_prev = mid_cur;
            mid_cur = mid_next;

            bot_prev = bot_cur;
            bot_cur = bot_next;

            i += 1;
        }
    }

    // swap
    const tmp = cur_grid;
    cur_grid = new_grid;
    new_grid = tmp;
}

fn time_update(time: f64) void {
    acc_time += time - prev_time;
    prev_time = time;

    // give up
    if (acc_time >= 100) {
        acc_time = step_time;
    }

    while (acc_time >= step_time) : (acc_time -= step_time) {
        step();
        image_data_old = true;
    }
}

extern fn output_image_data([*]const u32, usize) void;

fn render_image() void {
    const grid_bytes = mem.sliceAsBytes(cur_grid);

    var y: usize = 0;
    while (y < h) : (y += 1) {
        const grid_row_byte = ((y + 1) * stride + 1) * 8;
        const image_row = y * w;

        const full_bytes = w / 8;
        const tail_bits = w % 8;

        var byte_i: usize = 0;
        while (byte_i < full_bytes) : (byte_i += 1) {
            const byte = grid_bytes[grid_row_byte + byte_i];

            const PixelVec = @Vector(8, u32);
            const byte_vec: PixelVec = @splat(byte);

            const masks: PixelVec = .{ 1, 2, 4, 8, 16, 32, 64, 128 };
            const zero_vec: PixelVec = @splat(0);
            const dead_vec: PixelVec = @splat(dead_color);
            const alive_vec: PixelVec = @splat(alive_color);

            const pixels = @select(
                u32,
                (byte_vec & masks) == zero_vec,
                dead_vec,
                alive_vec,
            );

            const dst_i = image_row + byte_i * 8;

            const ptr: *align(@alignOf(u32)) PixelVec = @ptrCast(image_data[dst_i..][0..8].ptr);

            ptr.* = pixels;
        }

        if (tail_bits != 0) {
            const byte = grid_bytes[grid_row_byte + full_bytes];
            const dst_i = image_row + full_bytes * 8;

            var bit_i: usize = 0;
            while (bit_i < tail_bits) : (bit_i += 1) {
                image_data[dst_i + bit_i] = if (((byte >> @intCast(bit_i)) & 1) != 0)
                    alive_color
                else
                    dead_color;
            }
        }
    }
}

export fn frame(time: f64) void {
    time_update(time);

    if (image_data_old) {
        render_image();

        output_image_data(&image_data, image_data.len);
        image_data_old = false;
    }
}
