local next, tonumber, tostring = next, tonumber, tostring
local table_concat, string_sub, string_format = table.concat, string.sub, string.format

local g_type = _G.type
local IsColor = IsColor
local function type(val)
    return (IsColor and IsColor(val) and "Color") or g_type(val)
end

local NIL, TRUE, FALSE = "N", "T", "F"
local STRING = "S"
local TABLE, ARRAY = "H", "A"
local POS_INF, NEG_INF = "P", "p"
local NAN = "n"

local ENTITY, PLAYER = "E", "L"
local VECTOR, ANGLE = "V", "G"
local COLOR = "C"

local ESCAPES = {
    ["\0"] = "\\0", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n",
    ["\r"] = "\\r", ["\t"] = "\\t", ["\v"] = "\\v", ["\\"] = "\\\\",
}
local REVERSE_ESCAPES = {}; for k, v in pairs(ESCAPES) do REVERSE_ESCAPES[v] = k end
local ESCAPE_PATTERN = "[%z\b\f\n\r\t\v\\]" -- %z == \0
local REVERSE_ESCAPE_PATTERN = "\\[0bfnrtv\\]"

local function is_array(tbl) -- copied straight from sfs, so read the comments there
    local tbl_len = #tbl
    if tbl_len == 0 then
        return false
    end
    if tbl[0] ~= nil then
        return false
    end
    if next(tbl, tbl_len) ~= nil then
        return false
    end
    if tbl_len == 1 then
        if next(tbl) ~= 1 then
            return false
        end
    elseif tbl_len > 1 then
        if next(tbl, tbl_len - 1) ~= tbl_len then
            return false
        end
    end
    return true
end

local encoders = {}
local encode; do
    local function write_line_type_value(buf, tpy, val)
        local buf_len = buf[0] + 1
        buf[0] = buf_len
        buf[buf_len] = tpy .. val .. "\n"
    end

    local function write_line_value(buf, val)
        local buf_len = buf[0] + 1
        buf[0] = buf_len
        buf[buf_len] = val .. "\n"
    end

    local function write_type(buf, tpy)
        local buf_len = buf[0] + 1
        buf[0] = buf_len
        buf[buf_len] = tpy
    end

    local function write_value(buf, val)
        local encoder = encoders[type(val)]
        if not encoder then
            return error("Invalid type: " .. type(val))
        end
        encoder(buf, val)
    end

    function encode(val)
        local buffer = {[0] = 0 --[[length]]}
        write_value(buffer, val)
        local result = table_concat(buffer, nil, 1, buffer[0])
        return result
    end

    encoders["nil"] = function(buf, val)
        write_type(buf, NIL)
    end

    encoders.boolean = function(buf, val)
        write_type(buf, val and TRUE or FALSE)
    end

    encoders.string = function(buf, val)
        local escaped = val:gsub(ESCAPE_PATTERN, ESCAPES)
        write_line_type_value(buf, STRING, escaped)
    end

    encoders.number = function(buf, val)
        if val == 1 / 0 then
            write_type(buf, POS_INF)
        elseif val == -(1 / 0) then
            write_type(buf, NEG_INF)
        elseif val ~= val then
            write_type(buf, NAN)
        else
            write_line_value(buf, string_format("%.17g", val))
        end
    end

    encoders.table = function(buf, val)
        if is_array(val) then
            write_type(buf, ARRAY)
            for i = 1, #val do
                write_value(buf, val[i])
            end
        else
            write_type(buf, TABLE)
            for k, v in next, val do
                write_value(buf, k)
                write_value(buf, v)
            end
        end
        write_type(buf, "\n")
    end

    encoders.Entity = function(buf, val)
        write_line_type_value(buf, ENTITY, val:EntIndex())
    end

    encoders.Weapon = encoders.Entity
    encoders.Vehicle = encoders.Entity
    encoders.NextBot = encoders.Entity
    encoders.NPC = encoders.Entity

    encoders.Player = function(buf, val)
        write_line_type_value(buf, PLAYER, val:EntIndex())
    end

    local Vector_Unpack = FindMetaTable and FindMetaTable("Vector").Unpack
    encoders.Vector = function(buf, val)
        local x, y, z = Vector_Unpack(val)
        write_line_type_value(buf, VECTOR, string_format("%.17g,%.17g,%.17g", x, y, z))
    end

    local Angle_Unpack = FindMetaTable and FindMetaTable("Angle").Unpack
    encoders.Angle = function(buf, val)
        local p, y, r = Angle_Unpack(val)
        write_line_type_value(buf, ANGLE, string_format("%.17g,%.17g,%.17g", p, y, r))
    end

    encoders.Color = function(buf, val)
        write_line_type_value(buf, COLOR, string_format("%u,%u,%u,%u", val.r, val.g, val.b, val.a))
    end
end

local decoders = {}
local decode; do
    local function peak_char(ctx)
        if ctx[1] > ctx[3] then
            return error("Unexpected end of string")
        end
        return (string_sub(ctx[2], ctx[1], ctx[1]))
    end

    local function get_decoder(ctx)
        local tpy = peak_char(ctx)
        local decoder = decoders[tpy]
        if not decoder then
            return error("Invalid type: " .. tpy)
        end
        return decoder
    end

    local function read_value(ctx)
        local decoder = get_decoder(ctx)
        local val = decoder(ctx)
        return val
    end

    local function read_line(ctx)
        local str_end = ctx[2]:find("\n", ctx[1], true)
        if not str_end then
            return error("line not terminated")
        end
        local str = string_sub(ctx[2], ctx[1], str_end - 1)
        ctx[1] = str_end + 1
        return str
    end

    decoders[NIL] = function(ctx)
        ctx[1] = ctx[1] + 1
        return nil
    end

    decoders[FALSE] = function(ctx)
        ctx[1] = ctx[1] + 1
        return false
    end

    decoders[TRUE] = function(ctx)
        ctx[1] = ctx[1] + 1
        return true
    end

    decoders[STRING] = function(ctx)
        ctx[1] = ctx[1] + 1
        local str = read_line(ctx)
        return (str:gsub(REVERSE_ESCAPE_PATTERN, REVERSE_ESCAPES))
    end

    decoders[POS_INF] = function(ctx)
        ctx[1] = ctx[1] + 1
        return math.huge
    end

    decoders[NEG_INF] = function(ctx)
        ctx[1] = ctx[1] + 1
        return -math.huge
    end

    decoders[NAN] = function(ctx)
        ctx[1] = ctx[1] + 1
        return 0 / 0
    end

    for k, v in ipairs({"-", 0, 1, 2, 3, 4, 5, 6, 7, 8, 9}) do
        decoders[tostring(v)] = function(ctx)
            local str = read_line(ctx)
            local num = tonumber(str)
            if not num then
                return error("Invalid number")
            end
            return num
        end
    end

    decoders[ARRAY] = function(ctx)
        ctx[1] = ctx[1] + 1
        local arr = {}
        local len = 0
        while peak_char(ctx) ~= "\n" do
            local val = read_value(ctx)
            len = len + 1
            arr[len] = val
        end
        ctx[1] = ctx[1] + 1
        return arr
    end

    decoders[TABLE] = function(ctx)
        ctx[1] = ctx[1] + 1
        local tbl = {}
        while peak_char(ctx) ~= "\n" do
            local key = read_value(ctx)
            local val = read_value(ctx)
            tbl[key] = val
        end
        ctx[1] = ctx[1] + 1
        return tbl
    end

    decoders[ENTITY] = function(ctx)
        ctx[1] = ctx[1] + 1
        local str = read_line(ctx)
        return Entity(tonumber(str))
    end

    decoders[PLAYER] = function(ctx)
        ctx[1] = ctx[1] + 1
        local str = read_line(ctx)
        local idx = tonumber(str)
        if not idx then
            return error("Invalid player index")
        end
        return Entity(tonumber(str))
    end

    decoders[VECTOR] = function(ctx)
        ctx[1] = ctx[1] + 1
        local str = read_line(ctx)
        local x, y, z = str:match("([^,]+),([^,]+),([^,]+)")
        x, y, z = tonumber(x), tonumber(y), tonumber(z)
        if not x or not y or not z then
            return error("Invalid vector")
        end
        return Vector(x, y, z)
    end

    decoders[ANGLE] = function(ctx)
        ctx[1] = ctx[1] + 1
        local str = read_line(ctx)
        local p, y, r = str:match("([^,]+),([^,]+),([^,]+)")
        return Angle(tonumber(p), tonumber(y), tonumber(r))
    end

    decoders[COLOR] = function(ctx)
        ctx[1] = ctx[1] + 1
        local str = read_line(ctx)
        local r, g, b, a = str:match("([^,]+),([^,]+),([^,]+),([^,]+)")
        return Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
    end

    function decode(str)
        if #str == 0 then
            return error("Empty string")
        end
        local context = {1--[[index]], str --[[value]], #str --[[length]]}
        local val = read_value(context)
        return val
    end
end

return {
    encode = encode,
    decode = decode
}
