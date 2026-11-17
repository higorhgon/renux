//! Draws box-drawing and block characters to fill the cell exactly. Font glyphs rarely match the
//! cell height, which would leave gaps in the borders that terminal programs draw.
//!
//! Straight lines are described here as rectangles (`lineRects`), which the terminal fills
//! itself: a screen of borders is hundreds of them, and a rectangle costs next to nothing to
//! draw where a small Cairo picture per character cost most of a frame. Only the rounded
//! corners and the diagonals, a handful on any screen, are drawn with Cairo. Block characters (halves, eighths, shades, quadrants and
//! sextants, which programs build pictures and filled shapes from) are only described here,
//! as rectangles in shares of a cell: the terminal fills them itself, with their edges on
//! whole screen pixels, so that neighbouring blocks meet with no line between them.
const std = @import("std");
const cairo = @import("cairo");

const none = 0;
const light = 1;
const heavy = 2;
const double = 3;

/// Left, right, up and down strokes of a line character.
const Segs = [4]u2;

const table = blk: {
    var t: [0x80]?Segs = @splat(null);
    const L = light;
    const H = heavy;
    const D = double;
    const entries = [_]struct { u21, Segs }{
        .{ 0x2500, .{ L, L, 0, 0 } }, .{ 0x2501, .{ H, H, 0, 0 } }, .{ 0x2502, .{ 0, 0, L, L } }, .{ 0x2503, .{ 0, 0, H, H } },
        // Dashed lines are drawn solid.
        .{ 0x2504, .{ L, L, 0, 0 } }, .{ 0x2508, .{ L, L, 0, 0 } }, .{ 0x254C, .{ L, L, 0, 0 } }, .{ 0x2505, .{ H, H, 0, 0 } },
        .{ 0x2509, .{ H, H, 0, 0 } }, .{ 0x254D, .{ H, H, 0, 0 } }, .{ 0x2506, .{ 0, 0, L, L } }, .{ 0x250A, .{ 0, 0, L, L } },
        .{ 0x254E, .{ 0, 0, L, L } }, .{ 0x2507, .{ 0, 0, H, H } }, .{ 0x250B, .{ 0, 0, H, H } }, .{ 0x254F, .{ 0, 0, H, H } },
        .{ 0x250C, .{ 0, L, 0, L } }, .{ 0x250D, .{ 0, H, 0, L } }, .{ 0x250E, .{ 0, L, 0, H } }, .{ 0x250F, .{ 0, H, 0, H } },
        .{ 0x2510, .{ L, 0, 0, L } }, .{ 0x2511, .{ H, 0, 0, L } }, .{ 0x2512, .{ L, 0, 0, H } }, .{ 0x2513, .{ H, 0, 0, H } },
        .{ 0x2514, .{ 0, L, L, 0 } }, .{ 0x2515, .{ 0, H, L, 0 } }, .{ 0x2516, .{ 0, L, H, 0 } }, .{ 0x2517, .{ 0, H, H, 0 } },
        .{ 0x2518, .{ L, 0, L, 0 } }, .{ 0x2519, .{ H, 0, L, 0 } }, .{ 0x251A, .{ L, 0, H, 0 } }, .{ 0x251B, .{ H, 0, H, 0 } },
        .{ 0x251C, .{ 0, L, L, L } }, .{ 0x251D, .{ 0, H, L, L } }, .{ 0x251E, .{ 0, L, H, L } }, .{ 0x251F, .{ 0, L, L, H } },
        .{ 0x2520, .{ 0, L, H, H } }, .{ 0x2521, .{ 0, H, H, L } }, .{ 0x2522, .{ 0, H, L, H } }, .{ 0x2523, .{ 0, H, H, H } },
        .{ 0x2524, .{ L, 0, L, L } }, .{ 0x2525, .{ H, 0, L, L } }, .{ 0x2526, .{ L, 0, H, L } }, .{ 0x2527, .{ L, 0, L, H } },
        .{ 0x2528, .{ L, 0, H, H } }, .{ 0x2529, .{ H, 0, H, L } }, .{ 0x252A, .{ H, 0, L, H } }, .{ 0x252B, .{ H, 0, H, H } },
        .{ 0x252C, .{ L, L, 0, L } }, .{ 0x252D, .{ H, L, 0, L } }, .{ 0x252E, .{ L, H, 0, L } }, .{ 0x252F, .{ H, H, 0, L } },
        .{ 0x2530, .{ L, L, 0, H } }, .{ 0x2531, .{ H, L, 0, H } }, .{ 0x2532, .{ L, H, 0, H } }, .{ 0x2533, .{ H, H, 0, H } },
        .{ 0x2534, .{ L, L, L, 0 } }, .{ 0x2535, .{ H, L, L, 0 } }, .{ 0x2536, .{ L, H, L, 0 } }, .{ 0x2537, .{ H, H, L, 0 } },
        .{ 0x2538, .{ L, L, H, 0 } }, .{ 0x2539, .{ H, L, H, 0 } }, .{ 0x253A, .{ L, H, H, 0 } }, .{ 0x253B, .{ H, H, H, 0 } },
        .{ 0x253C, .{ L, L, L, L } }, .{ 0x253D, .{ H, L, L, L } }, .{ 0x253E, .{ L, H, L, L } }, .{ 0x253F, .{ H, H, L, L } },
        .{ 0x2540, .{ L, L, H, L } }, .{ 0x2541, .{ L, L, L, H } }, .{ 0x2542, .{ L, L, H, H } }, .{ 0x2543, .{ H, L, H, L } },
        .{ 0x2544, .{ L, H, H, L } }, .{ 0x2545, .{ H, L, L, H } }, .{ 0x2546, .{ L, H, L, H } }, .{ 0x2547, .{ H, H, H, L } },
        .{ 0x2548, .{ H, H, L, H } }, .{ 0x2549, .{ H, L, H, H } }, .{ 0x254A, .{ L, H, H, H } }, .{ 0x254B, .{ H, H, H, H } },
        .{ 0x2550, .{ D, D, 0, 0 } }, .{ 0x2551, .{ 0, 0, D, D } }, .{ 0x2552, .{ 0, D, 0, L } }, .{ 0x2553, .{ 0, L, 0, D } },
        .{ 0x2554, .{ 0, D, 0, D } }, .{ 0x2555, .{ D, 0, 0, L } }, .{ 0x2556, .{ L, 0, 0, D } }, .{ 0x2557, .{ D, 0, 0, D } },
        .{ 0x2558, .{ 0, D, L, 0 } }, .{ 0x2559, .{ 0, L, D, 0 } }, .{ 0x255A, .{ 0, D, D, 0 } }, .{ 0x255B, .{ D, 0, L, 0 } },
        .{ 0x255C, .{ L, 0, D, 0 } }, .{ 0x255D, .{ D, 0, D, 0 } }, .{ 0x255E, .{ 0, D, L, L } }, .{ 0x255F, .{ 0, L, D, D } },
        .{ 0x2560, .{ 0, D, D, D } }, .{ 0x2561, .{ D, 0, L, L } }, .{ 0x2562, .{ L, 0, D, D } }, .{ 0x2563, .{ D, 0, D, D } },
        .{ 0x2564, .{ D, D, 0, L } }, .{ 0x2565, .{ L, L, 0, D } }, .{ 0x2566, .{ D, D, 0, D } }, .{ 0x2567, .{ D, D, L, 0 } },
        .{ 0x2568, .{ L, L, D, 0 } }, .{ 0x2569, .{ D, D, D, 0 } }, .{ 0x256A, .{ D, D, L, L } }, .{ 0x256B, .{ L, L, D, D } },
        .{ 0x256C, .{ D, D, D, D } }, .{ 0x2574, .{ L, 0, 0, 0 } }, .{ 0x2575, .{ 0, 0, L, 0 } }, .{ 0x2576, .{ 0, L, 0, 0 } },
        .{ 0x2577, .{ 0, 0, 0, L } }, .{ 0x2578, .{ H, 0, 0, 0 } }, .{ 0x2579, .{ 0, 0, H, 0 } }, .{ 0x257A, .{ 0, H, 0, 0 } },
        .{ 0x257B, .{ 0, 0, 0, H } }, .{ 0x257C, .{ L, H, 0, 0 } }, .{ 0x257D, .{ 0, 0, L, H } }, .{ 0x257E, .{ H, L, 0, 0 } },
        .{ 0x257F, .{ 0, 0, H, L } },
    };
    for (entries) |e| t[e[0] - 0x2500] = e[1];
    break :blk t;
};

pub fn handles(cp: u32) bool {
    if (isPowerline(cp)) return true;
    if (cp >= 0x2500 and cp <= 0x257F) return table[cp - 0x2500] != null or (cp >= 0x256D and cp <= 0x2573);
    return isBlock(cp);
}

/// The Powerline separators (arrows, half circles and corner triangles). Fonts draw them at
/// the size of their glyph box, which rarely fills the cell; drawn here they meet the cell's
/// edges, so a prompt's segments join with no gap, as in other terminals.
pub fn isPowerline(cp: u32) bool {
    return cp >= 0xE0B0 and cp <= 0xE0BF;
}

/// Whether a character is made only of filled rectangles: the block elements, the quadrants
/// and the sextants.
pub fn isBlock(cp: u32) bool {
    return (cp >= 0x2580 and cp <= 0x259F) or (cp >= 0x1FB00 and cp <= 0x1FB3B);
}

/// One filled rectangle of a block character, in shares of its cell, and how solid it is.
pub const Part = struct { x0: f32, y0: f32, x1: f32, y1: f32, alpha: f32 = 1 };

/// The rectangles a block character is made of, written into `out`.
pub fn blockParts(cp: u32, out: *[6]Part) []const Part {
    var n: usize = 0;
    const one = struct {
        fn part(o: *[6]Part, count: *usize, x0: f32, y0: f32, x1: f32, y1: f32, alpha: f32) void {
            o[count.*] = .{ .x0 = x0, .y0 = y0, .x1 = x1, .y1 = y1, .alpha = alpha };
            count.* += 1;
        }
    }.part;
    switch (cp) {
        0x2580 => one(out, &n, 0, 0, 1, 0.5, 1),
        0x2581...0x2588 => one(out, &n, 0, 1 - @as(f32, @floatFromInt(cp - 0x2580)) / 8, 1, 1, 1),
        0x2589...0x258F => one(out, &n, 0, 0, @as(f32, @floatFromInt(0x2590 - cp)) / 8, 1, 1),
        0x2590 => one(out, &n, 0.5, 0, 1, 1, 1),
        0x2591...0x2593 => one(out, &n, 0, 0, 1, 1, @as(f32, @floatFromInt(cp - 0x2590)) / 4),
        0x2594 => one(out, &n, 0, 0, 1, 0.125, 1),
        0x2595 => one(out, &n, 0.875, 0, 1, 1, 1),
        0x2596...0x259F => {
            // Which quarters are filled: upper left 1, upper right 2, lower left 4, lower right 8.
            const quarters = [_]u4{ 4, 8, 1, 13, 9, 7, 11, 2, 6, 14 };
            const bits = quarters[cp - 0x2596];
            for (0..4) |i| if (bits & (@as(u4, 1) << @intCast(i)) != 0) {
                const x: f32 = @floatFromInt(i % 2);
                const y: f32 = @floatFromInt(i / 2);
                one(out, &n, x / 2, y / 2, (x + 1) / 2, (y + 1) / 2, 1);
            };
        },
        0x1FB00...0x1FB3B => {
            // Six cells, two across and three down, numbered across then down. Unicode leaves
            // out the two patterns that are the left and right halves, which it already has.
            var bits: u32 = cp - 0x1FB00 + 1;
            if (bits >= 21) bits += 1;
            if (bits >= 42) bits += 1;
            for (0..6) |i| if (bits & (@as(u32, 1) << @intCast(i)) != 0) {
                const x: f32 = @floatFromInt(i % 2);
                const y: f32 = @floatFromInt(i / 2);
                one(out, &n, x / 2, y / 3, (x + 1) / 2, (y + 1) / 3, 1);
            };
        },
        else => {},
    }
    return out[0..n];
}

/// A filled rectangle of a line character, in the same units as the cell it was asked for.
pub const Rect = struct { x0: f64, y0: f64, x1: f64, y1: f64 };

/// Whether a character is a line that runs straight across its cell and nothing else, so a
/// run of them in a row is one line: `lineRects` over the whole run draws it in one piece.
pub fn isHorizontal(cp: u32) bool {
    if (cp < 0x2500 or cp > 0x257F) return false;
    const s = table[cp - 0x2500] orelse return false;
    return s[0] != none and s[0] == s[1] and s[2] == none and s[3] == none;
}

/// The rectangles of a line character in the cell at (x, y) of size (w, h): every character
/// made of straight strokes. Null for the others (rounded corners, diagonals), which `draw`
/// draws.
pub fn lineRects(cp: u32, x: f64, y: f64, w: f64, h: f64, out: *[8]Rect) ?[]const Rect {
    if (cp < 0x2500 or cp > 0x257F) return null;
    const s = table[cp - 0x2500] orelse return null;
    const thin = @max(1, @round(h / 16));
    var list: RectList = .{ .out = out };
    const cx = @round(x + w / 2);
    const cy = @round(y + h / 2);
    const reach = thin / 2;
    const vert = s[2] != none or s[3] != none;
    const horiz = s[0] != none or s[1] != none;
    if (!vert and s[0] == s[1]) {
        // One stroke from edge to edge, however wide the cell (or run of cells) is.
        list.horizontal(x, x + w, cy, s[0], thin);
    } else {
        list.horizontal(x, cx + if (s[0] != none and vert) reach else 0, cy, s[0], thin);
        list.horizontal(cx - if (s[1] != none and vert) reach else 0, x + w, cy, s[1], thin);
    }
    if (!horiz and s[2] == s[3]) {
        list.vertical(y, y + h, cx, s[2], thin);
    } else {
        list.vertical(y, cy + if (s[2] != none and horiz) reach else 0, cx, s[2], thin);
        list.vertical(cy - if (s[3] != none and horiz) reach else 0, y + h, cx, s[3], thin);
    }
    return out[0..list.len];
}

const RectList = struct {
    out: *[8]Rect,
    len: usize = 0,

    fn add(l: *RectList, x0: f64, y0: f64, x1: f64, y1: f64) void {
        l.out[l.len] = .{ .x0 = x0, .y0 = y0, .x1 = x1, .y1 = y1 };
        l.len += 1;
    }

    fn horizontal(l: *RectList, x0: f64, x1: f64, cy: f64, weight: u2, thin: f64) void {
        switch (weight) {
            none => {},
            double => {
                l.add(x0, cy - thin * 1.5, x1, cy - thin * 0.5);
                l.add(x0, cy + thin * 0.5, x1, cy + thin * 1.5);
            },
            else => {
                const t = if (weight == heavy) thin * 2 else thin;
                l.add(x0, cy - t / 2, x1, cy + t / 2);
            },
        }
    }

    fn vertical(l: *RectList, y0: f64, y1: f64, cx: f64, weight: u2, thin: f64) void {
        switch (weight) {
            none => {},
            double => {
                l.add(cx - thin * 1.5, y0, cx - thin * 0.5, y1);
                l.add(cx + thin * 0.5, y0, cx + thin * 1.5, y1);
            },
            else => {
                const t = if (weight == heavy) thin * 2 else thin;
                l.add(cx - t / 2, y0, cx + t / 2, y1);
            },
        }
    }
};

/// Draws a rounded corner or a diagonal in the cell at (x, y) of size (w, h), in the current
/// source color. The straight lines are `lineRects`'s.
pub fn draw(cr: *cairo.Context, cp: u32, x: f64, y: f64, w: f64, h: f64) void {
    if (isPowerline(cp)) return powerline(cr, cp, x, y, w, h);
    const thin = @max(1, @round(h / 16));
    if (cp >= 0x256D and cp <= 0x2570) return rounded(cr, cp, x, y, w, h, thin);
    if (cp >= 0x2571 and cp <= 0x2573) return diagonal(cr, cp, x, y, w, h, thin);
}

/// A Powerline separator in the cell at (x, y). Filled shapes reach half a pixel past the
/// edge they share with the next cell, so no seam shows between them.
fn powerline(cr: *cairo.Context, cp: u32, x: f64, y: f64, w: f64, h: f64) void {
    const e = 0.5;
    const my = y + h / 2;
    const thin = @max(1, @round(h / 16));
    switch (cp) {
        0xE0B0, 0xE0B2 => {
            const right = cp == 0xE0B0;
            const base = if (right) x - e else x + w + e;
            const tip = if (right) x + w else x;
            cr.moveTo(base, y);
            cr.lineTo(tip, my);
            cr.lineTo(base, y + h);
            cr.closePath();
            cr.fill();
        },
        0xE0B1, 0xE0B3 => {
            const right = cp == 0xE0B1;
            cr.moveTo(if (right) x else x + w, y);
            cr.lineTo(if (right) x + w else x, my);
            cr.lineTo(if (right) x else x + w, y + h);
            cr.setLineWidth(thin);
            cr.stroke();
        },
        0xE0B4, 0xE0B5, 0xE0B6, 0xE0B7 => {
            const right = cp == 0xE0B4 or cp == 0xE0B5;
            const filled = cp == 0xE0B4 or cp == 0xE0B6;
            const edge = if (right) x - e else x + w + e;
            cr.save();
            cr.translate(if (right) x else x + w, my);
            cr.scale(w, h / 2);
            if (right) cr.arc(0, 0, 1, -std.math.pi / 2.0, std.math.pi / 2.0) else cr.arc(0, 0, 1, std.math.pi / 2.0, std.math.pi * 1.5);
            cr.restore();
            if (filled) {
                cr.lineTo(edge, y + h);
                cr.lineTo(edge, y);
                cr.closePath();
                cr.fill();
            } else {
                cr.setLineWidth(thin);
                cr.stroke();
            }
        },
        0xE0B8, 0xE0BA, 0xE0BC, 0xE0BE => {
            // Triangles filling half the cell, split along a diagonal.
            const l = x - e;
            const r = x + w + e;
            const t = y - e;
            const b = y + h + e;
            switch (cp) {
                0xE0B8 => {
                    cr.moveTo(l, t);
                    cr.lineTo(l, b);
                    cr.lineTo(r, b);
                },
                0xE0BA => {
                    cr.moveTo(r, t);
                    cr.lineTo(r, b);
                    cr.lineTo(l, b);
                },
                0xE0BC => {
                    cr.moveTo(l, t);
                    cr.lineTo(r, t);
                    cr.lineTo(l, b);
                },
                else => {
                    cr.moveTo(l, t);
                    cr.lineTo(r, t);
                    cr.lineTo(r, b);
                },
            }
            cr.closePath();
            cr.fill();
        },
        else => {
            // The lines along those diagonals.
            const up = cp == 0xE0BB or cp == 0xE0BD;
            cr.moveTo(if (up) x + w else x, y);
            cr.lineTo(if (up) x else x + w, y + h);
            cr.setLineWidth(thin);
            cr.stroke();
        },
    }
}

fn rounded(cr: *cairo.Context, cp: u32, x: f64, y: f64, w: f64, h: f64, thin: f64) void {
    const cx = @round(x + w / 2);
    const cy = @round(y + h / 2);
    const r = @min(w, h) / 2;
    switch (cp) {
        0x256D => {
            cr.moveTo(x + w, cy);
            cr.curveTo(cx, cy, cx, cy, cx, cy + r);
            cr.lineTo(cx, y + h);
        },
        0x256E => {
            cr.moveTo(x, cy);
            cr.curveTo(cx, cy, cx, cy, cx, cy + r);
            cr.lineTo(cx, y + h);
        },
        0x256F => {
            cr.moveTo(x, cy);
            cr.curveTo(cx, cy, cx, cy, cx, cy - r);
            cr.lineTo(cx, y);
        },
        else => {
            cr.moveTo(x + w, cy);
            cr.curveTo(cx, cy, cx, cy, cx, cy - r);
            cr.lineTo(cx, y);
        },
    }
    cr.setLineWidth(thin);
    cr.stroke();
}

fn diagonal(cr: *cairo.Context, cp: u32, x: f64, y: f64, w: f64, h: f64, thin: f64) void {
    cr.setLineWidth(thin);
    if (cp == 0x2571 or cp == 0x2573) {
        cr.moveTo(x + w, y);
        cr.lineTo(x, y + h);
        cr.stroke();
    }
    if (cp == 0x2572 or cp == 0x2573) {
        cr.moveTo(x, y);
        cr.lineTo(x + w, y + h);
        cr.stroke();
    }
}

test "box drawing covers lines, corners and blocks" {
    try std.testing.expect(handles(0x2500));
    try std.testing.expect(handles(0x256D));
    try std.testing.expect(handles(0x2588));
    try std.testing.expect(!handles('a'));
    try std.testing.expect(handles(0xE0B0) and handles(0xE0B6) and !handles(0xE0B0 - 1) and !handles(0xE0C0));
    try std.testing.expect(handles(0x2596) and isBlock(0x2596));
    try std.testing.expect(handles(0x1FB00) and !isBlock(0x2500));
}

test "straight lines are rectangles, and a run of a horizontal line is one of them" {
    var buf: [8]Rect = undefined;
    // A light horizontal line in a 10 by 20 cell: one stroke, 1 thick, across the middle.
    const flat = lineRects(0x2500, 0, 0, 10, 20, &buf).?;
    try std.testing.expectEqual(@as(usize, 1), flat.len);
    try std.testing.expectEqual(Rect{ .x0 = 0, .y0 = 9.5, .x1 = 10, .y1 = 10.5 }, flat[0]);
    try std.testing.expect(isHorizontal(0x2500) and isHorizontal(0x2550) and !isHorizontal(0x2502) and !isHorizontal(0x252C));
    // Five cells of it are still one stroke.
    try std.testing.expectEqual(Rect{ .x0 = 0, .y0 = 9.5, .x1 = 50, .y1 = 10.5 }, lineRects(0x2500, 0, 0, 50, 20, &buf).?[0]);
    // A light vertical line is one stroke too; a double one is two.
    try std.testing.expectEqual(Rect{ .x0 = 4.5, .y0 = 0, .x1 = 5.5, .y1 = 20 }, lineRects(0x2502, 0, 0, 10, 20, &buf).?[0]);
    try std.testing.expectEqual(@as(usize, 2), lineRects(0x2551, 0, 0, 10, 20, &buf).?.len);
    // A corner is a stroke to the right and one down, meeting in the middle.
    const corner = lineRects(0x250C, 0, 0, 10, 20, &buf).?;
    try std.testing.expectEqual(@as(usize, 2), corner.len);
    try std.testing.expectEqual(Rect{ .x0 = 4.5, .y0 = 9.5, .x1 = 10, .y1 = 10.5 }, corner[0]);
    try std.testing.expectEqual(Rect{ .x0 = 4.5, .y0 = 9.5, .x1 = 5.5, .y1 = 20 }, corner[1]);
    // A double cross is the most strokes there are; rounded corners and letters have none.
    try std.testing.expectEqual(@as(usize, 8), lineRects(0x256C, 0, 0, 10, 20, &buf).?.len);
    try std.testing.expect(lineRects(0x256D, 0, 0, 10, 20, &buf) == null and lineRects('a', 0, 0, 10, 20, &buf) == null);
}

test "block characters are rectangles in shares of a cell" {
    var buf: [6]Part = undefined;
    // The upper half, and the lower three eighths.
    try std.testing.expectEqual(Part{ .x0 = 0, .y0 = 0, .x1 = 1, .y1 = 0.5 }, blockParts(0x2580, &buf)[0]);
    try std.testing.expectEqual(Part{ .x0 = 0, .y0 = 0.625, .x1 = 1, .y1 = 1 }, blockParts(0x2583, &buf)[0]);
    // A full block and a medium shade both cover the cell; the shade is half solid.
    try std.testing.expectEqual(@as(usize, 1), blockParts(0x2588, &buf).len);
    try std.testing.expectEqual(@as(f32, 0.5), blockParts(0x2592, &buf)[0].alpha);
    // The quadrant with the upper left and lower right quarters.
    const two = blockParts(0x259A, &buf);
    try std.testing.expectEqual(@as(usize, 2), two.len);
    try std.testing.expectEqual(Part{ .x0 = 0, .y0 = 0, .x1 = 0.5, .y1 = 0.5 }, two[0]);
    try std.testing.expectEqual(Part{ .x0 = 0.5, .y0 = 0.5, .x1 = 1, .y1 = 1 }, two[1]);
    // The first sextant is the top left cell alone; the last is every cell but that one.
    try std.testing.expectEqual(@as(usize, 1), blockParts(0x1FB00, &buf).len);
    try std.testing.expectEqual(@as(usize, 5), blockParts(0x1FB3B, &buf).len);
    // The pattern for the plain left half is skipped, so the 21st sextant is pattern 22.
    try std.testing.expectEqual(@as(usize, 3), blockParts(0x1FB14, &buf).len);
    try std.testing.expectEqual(@as(usize, 0), blockParts('a', &buf).len);
}
