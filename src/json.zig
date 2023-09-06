const std = @import("std");

const JsonError = error{ AllocationFailed, PrintStdErrorFailed };

const JsonTokenType = enum {
    end_of_stream,
    token_error,
    open_brace,
    open_bracket,
    close_brace,
    close_bracket,
    comma,
    colon,
    semi_colon,
    string_literal,
    number,
    true,
    false,
    null,
};

const JsonToken = struct {
    type: JsonTokenType,
    value: []const u8,
};

const JsonElement = struct {
    label: []const u8,
    value: []const u8,
    first_sub_element: ?*JsonElement,
    next_sibling: ?*JsonElement,
};

const JsonParser = struct {
    source: []const u8,
    at: u64 = 0,
    had_error: bool = false,
};

pub fn isInBounds(source: []const u8, at: u64) bool {
    return at < source.len;
}

pub fn isJsonDigit(source: []const u8, at: u64) bool {
    // TODO(tracy): just replace usages of this function with line below
    return std.ascii.isDigit(source[at]);
}

pub fn isJsonWhitespace(source: []const u8, at: u64) bool {
    // TODO(tracy): just replace usages of this function with line below
    return std.ascii.isWhitespace(source[at]);
}

pub fn isParsing(parser: *JsonParser) bool {
    const result = !parser.had_error and parser.at < parser.source.len;
    return result;
}

pub fn jsonError(parser: *JsonParser, token: JsonToken, message: []const u8) JsonError!void {
    parser.had_error = true;
    std.io.getStdErr().writer().print("ERROR: {s} - {s}\n", .{ token.value, message }) catch return JsonError.PrintStdErrorFailed;
}

pub fn parseKeyword(source: []const u8, at: *u64, keyword_remaining: []const u8, t: JsonTokenType, result: *JsonToken) void {
    if ((source.len - at.*) >= keyword_remaining.len) {
        const start = at.*;
        const end = at.* + keyword_remaining.len;
        const check = source[start..end];
        if (std.mem.eql(u8, check, keyword_remaining)) {
            result.type = t;
            result.value.len += keyword_remaining.len;
            at.* += keyword_remaining.len;
        }
    }
}

pub fn getJsonToken(parser: *JsonParser) JsonToken {
    var source = parser.source;
    var at = parser.at;

    while (isJsonWhitespace(source, at)) {
        at += 1;
    }

    var result: JsonToken = .{
        .type = .token_error,
        .value = source[at..(at + 1)],
    };
    var val = source[at];
    at += 1;

    switch (val) {
        '{' => result.type = .open_brace,
        '[' => result.type = .open_bracket,
        '}' => result.type = .close_brace,
        ']' => result.type = .close_bracket,
        ',' => result.type = .comma,
        ':' => result.type = .colon,
        ';' => result.type = .semi_colon,
        'f' => parseKeyword(source, &at, "alse", .false, &result),
        'n' => parseKeyword(source, &at, "ull", .null, &result),
        't' => parseKeyword(source, &at, "rue", .true, &result),
        '"' => {
            result.type = .string_literal;
            const string_start = at;
            while (source[at] != '"') : (at += 1) {
                if (source[at] == '\\' and source[at + 1] == '"') {
                    at += 1;
                }
            }

            result.value = source[string_start..at];
            at += 1;
        },
        '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
            const start = at - 1;
            result.type = .number;

            // NOTE(tracy): Move past a leading negative sign if one exists
            if (val == '-') {
                val = source[at];
                at += 1;
            }

            // NOTE(tracy): If the leading digit wasn't 0, parse any digits before the decimal point
            if (val != '0') {
                while (isJsonDigit(source, at)) {
                    at += 1;
                }
            }

            // NOTE(tracy): If there is a decimal point, parse any digit after the decimal point
            if (source[at] == '.') {
                at += 1;
                while (isJsonDigit(source, at)) {
                    at += 1;
                }
            }

            // NOTE(tracy): If it's in scientific notation, parse any digits after the "e"
            if (source[at] == 'e' or source[at] == 'E') {
                at += 1;

                if (source[at] == '+' or source[at] == '-') {
                    at += 1;
                }

                while (isJsonDigit(source, at)) : (at += 1) {}
            }

            result.value = source[start..at];
        },
        else => {},
    }

    parser.*.at = at;

    return result;
}

pub fn parseJsonList(parser: *JsonParser, starting_token: JsonToken, end_type: JsonTokenType, has_labels: bool, allocator: std.mem.Allocator) JsonError!?*JsonElement {
    _ = starting_token;

    var last_element: ?*JsonElement = null;
    var first_element: ?*JsonElement = null;

    while (isParsing(parser)) {
        var value = getJsonToken(parser);
        var label: []const u8 = undefined;
        if (has_labels) {
            if (value.type == .string_literal) {
                label = value.value;
                const colon = getJsonToken(parser);
                if (colon.type == .colon) {
                    value = getJsonToken(parser);
                } else {
                    try jsonError(parser, colon, "Expected colon after field name");
                }
            } else if (value.type != end_type) {
                try jsonError(parser, value, "Unexpected token in JSON");
            }
        }

        const element = try parseJsonElement(parser, label, value, allocator);
        if (element) |e| {
            if (last_element) |l| {
                l.next_sibling = e;
            } else {
                first_element = e;
            }
            last_element = e;
        } else if (value.type == end_type) {
            break;
        } else {
            try jsonError(parser, value, "Unexpected token in JSON");
        }

        const comma = getJsonToken(parser);
        if (comma.type == end_type) {
            break;
        } else if (comma.type != .comma) {
            try jsonError(parser, comma, "Unexpected token in JSON");
        }
    }

    return first_element;
}

pub fn parseJsonElement(parser: *JsonParser, label: []const u8, value: JsonToken, allocator: std.mem.Allocator) JsonError!?*JsonElement {
    var valid = true;
    var sub_element: ?*JsonElement = null;
    switch (value.type) {
        .open_bracket => {
            sub_element = try parseJsonList(parser, value, .close_bracket, false, allocator);
        },
        .open_brace => {
            sub_element = try parseJsonList(parser, value, .close_brace, true, allocator);
        },
        .string_literal, .true, .false, .null, .number => {},
        else => valid = true,
    }

    var result: ?*JsonElement = null;
    if (valid) {
        result = allocator.create(JsonElement) catch {
            return JsonError.AllocationFailed;
        };
        if (result) |r| {
            r.label = label;
            r.value = value.value;
            r.first_sub_element = sub_element;
            r.next_sibling = null;
        }
    }

    return result;
}

pub fn parseJson(input: []const u8, allocator: std.mem.Allocator) !?*JsonElement {
    var parser = JsonParser{
        .source = input,
    };
    var token = getJsonToken(&parser);
    var result = try parseJsonElement(&parser, &[_]u8{}, token, allocator);
    return result;
}

pub fn freeJson(element: *JsonElement, allocator: std.mem.Allocator) void {
    var el = element;
    var done = false;
    while (!done) {
        var free_element = el;
        if (el.next_sibling) |sibling| {
            el = sibling;
        } else {
            done = true;
        }

        if (free_element.first_sub_element) |first_sub_element| {
            freeJson(first_sub_element, allocator);
        }
        allocator.destroy(free_element);
    }
}

pub fn lookupElement(object: *JsonElement, name: []const u8) ?*JsonElement {
    var result: ?*JsonElement = null;
    var search = object.first_sub_element;
    while (search) |s| : (search = s.next_sibling) {
        if (std.mem.eql(u8, s.label, name)) {
            result = s;
            break;
        }
    }
    return result;
}

pub fn convertJsonSign(source: []const u8, at_result: *u64) f64 {
    var at = at_result.*;
    var result: f64 = 1.0;
    if (source[at] == '-') {
        result = -1.0;
        at += 1;
    }

    at_result.* = at;
    return result;
}

pub fn convertJsonNumber(source: []const u8, at_result: *u64) f64 {
    var at = at_result.*;
    var result: f64 = 0.0;
    while (isInBounds(source, at)) {
        const char = source[at];
        if (std.ascii.isDigit(char)) {
            const digit = std.fmt.charToDigit(char, 10) catch continue;
            result = 10.0 * result + @as(f64, @floatFromInt(digit));
            at += 1;
        } else {
            break;
        }
    }

    at_result.* = at;

    return result;
}

pub fn convertElementToF64(object: *JsonElement, name: []const u8) f64 {
    var result: f64 = 0.0;

    var element = lookupElement(object, name);
    if (element) |e| {
        const source = e.value;
        var at: u64 = 0;

        const sign = convertJsonSign(source, &at);
        var number = convertJsonNumber(source, &at);
        if (isInBounds(source, at) and source[at] == '.') {
            at += 1;
            var c: f64 = 1.0 / 10.0;
            while (isInBounds(source, at)) {
                const char = source[at] - '0';
                if (char < 10) {
                    number = number + c * @as(f64, @floatFromInt(char));
                    c *= 1.0 / 10.0;
                    at += 1;
                } else {
                    break;
                }
            }
        }

        if (isInBounds(source, at) and (source[at] == 'e' or source[at] == 'E')) {
            at += 1;
            if (isInBounds(source, at) and source[at] == '+') {
                at += 1;
            }

            const exponent_sign = convertJsonSign(source, &at);
            const exponent = exponent_sign * convertJsonNumber(source, &at);
            number *= std.math.pow(f64, 10.0, exponent);
        }

        result = sign * number;
    }

    return result;
}
