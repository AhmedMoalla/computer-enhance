const std = @import("std");
const math = std.math;
const cos = math.cos;
const sin = math.sin;
const asin = math.asin;
const sqrt = math.sqrt;

const degreesToRadians = math.degreesToRadians;

pub const earthRadius: f64 = 6372.8;

pub fn reference(x0: f64, y0: f64, x1: f64, y1: f64) f64 {
    var lat1: f64 = y0;
    var lat2: f64 = y1;
    const lon1: f64 = x0;
    const lon2: f64 = x1;

    const dLat = degreesToRadians(lat2 - lat1);
    const dLon = degreesToRadians(lon2 - lon1);
    lat1 = degreesToRadians(lat1);
    lat2 = degreesToRadians(lat2);

    const a = squared(sin(dLat / 2.0)) + cos(lat1) * cos(lat2) * squared(sin(dLon / 2));
    const c = 2.0 * asin(sqrt(a));

    return earthRadius * c;
}

fn squared(a: f64) f64 {
    return a * a;
}
