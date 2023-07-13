const std = @import("std");

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
    value: []u8,
};

const JsonElement = struct {
    label: []u8,
    value: []u8,
    first_sub_element: ?*JsonElement,
    next_sibling: ?*JsonElement,
};

const JsonParser = struct {
    source: []u8,
    at: u64 = 0,
    had_error: bool = false,
};

pub fn isInBounds(source: []const u8, at: u64) bool {
    return at < source.len;
}

pub fn isJsonDigit(source: []u8, at: u64) bool {
    var result = false;
    const val = source[at];
    result = ((val >= '0') and (val <= '9'));
    return result;
}

pub fn isJsonWhitespace(source: []u8, at: u64) bool {
    var result = false;
    const val = source[at];
    result = ((val == ' ') or (val == '\t') or (val == '\n') or (val == '\r'));
    return result;
}

pub fn isParsing(parser: *JsonParser) bool {
    const result = !parser.had_error and parser.at < parser.source.len;
    return result;
}

pub fn jsonError(parser: *JsonParser, token: JsonToken, message: []u8) void {
    parser.had_error = true;
    std.io.getStdErr().writer().print("ERROR: {s} - {s}", .{ token.value, message });
}

pub fn parseKeyword(source: []u8, at: *u64, keyword_remaining: []const u8, t: JsonTokenType, result: *JsonToken) void {
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
    var result: JsonToken = {};

    var source = parser.source;
    var at = parser.at;

    while (isJsonWhitespace(source, at)) {
        at += 1;
    }

    result.type = .token_error;
    result.value = source[at..(at + 1)];
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
            while (source[at] != '"') {
                if (source[at] == '\\' and source[at + 1] == '"') {
                    at += 1;
                }
                at += 1;
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

                while (isJsonDigit(source, at)) {
                    at += 1;
                }
            }

            result.value = source[start..at];
        },
    }

    return result;
}

pub fn parseJsonList(parser: *JsonParser, starting_token: JsonToken, end_type: JsonTokenType, has_labels: bool, allocator: std.mem.Allocator) *JsonElement {
    _ = starting_token;
    var first_element: JsonElement = {};
    var last_element: JsonElement = {};

    while (isParsing(parser)) {
        var value = getJsonToken(parser);
        var label: []const u8 = null;
        if (has_labels) {
            if (value.type == .string_literal) {
                label = value.value;
                const colon = getJsonToken(parser);
                if (colon.type == .colon) {
                    value = getJsonToken(parser);
                } else {
                    jsonError(parser, colon, "Expected colon after field name");
                }
            } else if (value.type != end_type) {
                jsonError(parser, value, "Unexpected token in JSON");
            }
        }

        const element = parseJsonElement(parser, label, value, allocator);
        if (element) {
            last_element = if (last_element) last_element.next_sibling else first_element;
        } else if (value.type == end_type) {
            break;
        } else {
            jsonError(parser, value, "Unexpected token in JSON");
        }

        const comma = getJsonToken(parser);
        if (comma.type == end_type) {
            break;
        } else if (comma.type != .comma) {
            jsonError(parser, comma, "Unexpected token in JSON");
        }
    }

    return first_element;
}

pub fn parseJsonElement(parser: *JsonParser, label: []const u8, value: JsonToken, allocator: std.mem.Allocator) *JsonElement {
    var valid = true;
    var sub_element: *JsonElement = null;
    if (value.type == .open_bracket) {
        sub_element = parseJsonList(parser, value, .close_bracket, false);
    } else if (value.type == .open_brace) {
        sub_element = parseJsonList(parser, value, .close_brace, false);
    } else if (value.type == .string_literal or
        value.type == .true or
        value.type == .false or
        value.type == .null or
        value.type == .number)
    {} else {
        valid = false;
    }

    var result: *JsonElement = null;
    if (valid) {
        result = allocator.create(JsonElement);
        result.label = label;
        result.value = value.value;
        result.first_sub_element = sub_element;
        result.next_sibling = null;
    }

    return result;
}

pub fn parseJson(input: []const u8, allocator: std.mem.Allocator) ?*JsonElement {
    const parser = JsonParser{
        .source = input,
    };
    const result = parseJsonElement(parser, [_]u8{}, getJsonToken(&parser), allocator);
    return result;
}

pub fn freeJson(element: ?*JsonElement, allocator: std.mem.Allocator) void {
    while (element) |e| {
        const free_element = e;
        element = e.next_sibling;
        freeJson(free_element.first_sub_element, allocator);
        allocator.destroy(free_element);
    }
}

pub fn lookupElement(object: ?*JsonElement, name: []const u8) ?*JsonElement {
    var result: ?*JsonElement = null;
    if (object) |o| {
        var search = o.first_sub_element;
        while (search) |s| {
            if (std.mem.eql(u8, s.label, name)) {
                result = s;
                break;
            }
            search = s.next_sibling;
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
        const char = source[at] - '0';
        if (char < 10) {
            result = 10.0 * result + @as(f64, char);
            at += 1;
        } else {
            break;
        }
    }

    at_result.* = at;

    return result;
}

pub fn convertElementToF64(object: ?*JsonElement, name: []const u8) f64 {
    var result: f64 = 0.0;

    var element = lookupElement(object, name);
    if (element) |e| {
        const source = e.value;
        var at: u64 = 0;

        const sign = convertJsonSign(source, &at);
        const number = convertJsonSign(source, &at);
        if (isInBounds(source, at) and source[at] == '.') {
            at += 1;
            var c: f64 = 1.0 / 10.0;
            while (isInBounds(source, at)) {
                const char = source[at] - '0';
                if (char < 10) {
                    number = number + c * @as(f64, char);
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
