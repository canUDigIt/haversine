const std = @import("std");

pub fn radiansFromDegrees(degrees: f64) f64 {
    const result = 0.01745329251994329577 * degrees;
    return result;
}

pub fn square(a: f64) f64 {
    const result = a * a;
    return result;
}

pub fn referenceHaversine(x0: f64, y0: f64, x1: f64, y1: f64, earthRadius: f64) f64 {
    var lat1 = y0;
    var lat2 = y1;
    var lon1 = x0;
    var lon2 = x1;

    const dLat = radiansFromDegrees(lat2 - lat1);
    const dLon = radiansFromDegrees(lon2 - lon1);
    lat1 = radiansFromDegrees(lat1);
    lat2 = radiansFromDegrees(lat2);

    const a = square(std.math.sin(dLat / 2.0)) + std.math.cos(lat1) * std.math.cos(lat2) * square(std.math.sin(dLon / 2.0));
    const c = 2.0 * std.math.asin(std.math.sqrt(a));

    const result = earthRadius * c;
    return result;
}
