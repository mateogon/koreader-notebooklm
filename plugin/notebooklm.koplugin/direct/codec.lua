local Codec = {}

Codec.null = {}

local function is_array(value)
    if type(value) ~= "table" then
        return false
    end
    if value.__array then
        return true
    end
    local count = 0
    for key, _ in pairs(value) do
        if type(key) ~= "number" then
            return false
        end
        if key > count then
            count = key
        end
    end
    return count > 0
end

function Codec.array(...)
    local value = { __array = true, n = select("#", ...) }
    for index = 1, value.n do
        local item = select(index, ...)
        if item == nil then
            item = Codec.null
        end
        value[index] = item
    end
    return value
end

local function escape_string(value)
    return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(char)
        local replacements = {
            ['"'] = '\\"',
            ["\\"] = "\\\\",
            ["\b"] = "\\b",
            ["\f"] = "\\f",
            ["\n"] = "\\n",
            ["\r"] = "\\r",
            ["\t"] = "\\t",
        }
        return replacements[char] or string.format("\\u%04x", char:byte())
    end) .. '"'
end

function Codec.encode(value)
    local value_type = type(value)
    if value == Codec.null or value == nil then
        return "null"
    end
    if value_type == "string" then
        return escape_string(value)
    end
    if value_type == "number" or value_type == "boolean" then
        return tostring(value)
    end
    if value_type ~= "table" then
        error("unsupported JSON value: " .. value_type)
    end

    local chunks = {}
    if is_array(value) then
        local count = value.n or #value
        for index = 1, count do
            chunks[#chunks + 1] = Codec.encode(value[index])
        end
        return "[" .. table.concat(chunks, ",") .. "]"
    end

    for key, item in pairs(value) do
        chunks[#chunks + 1] = escape_string(key) .. ":" .. Codec.encode(item)
    end
    table.sort(chunks)
    return "{" .. table.concat(chunks, ",") .. "}"
end

local Parser = {}
Parser.__index = Parser

function Parser:new(text)
    return setmetatable({ text = text or "", pos = 1 }, self)
end

function Parser:peek()
    return self.text:sub(self.pos, self.pos)
end

function Parser:skip_space()
    local _, stop = self.text:find("^[ \n\r\t]*", self.pos)
    self.pos = (stop or self.pos - 1) + 1
end

function Parser:expect(value)
    if self.text:sub(self.pos, self.pos + #value - 1) ~= value then
        error("expected " .. value .. " at " .. tostring(self.pos))
    end
    self.pos = self.pos + #value
end

function Parser:string()
    self:expect('"')
    local chunks = {}
    while self.pos <= #self.text do
        local char = self:peek()
        self.pos = self.pos + 1
        if char == '"' then
            return table.concat(chunks)
        end
        if char == "\\" then
            local escaped = self:peek()
            self.pos = self.pos + 1
            local replacements = {
                ['"'] = '"',
                ["\\"] = "\\",
                ["/"] = "/",
                b = "\b",
                f = "\f",
                n = "\n",
                r = "\r",
                t = "\t",
            }
            if escaped == "u" then
                local hex = self.text:sub(self.pos, self.pos + 3)
                self.pos = self.pos + 4
                local codepoint = tonumber(hex, 16) or 0
                if codepoint < 128 then
                    chunks[#chunks + 1] = string.char(codepoint)
                else
                    chunks[#chunks + 1] = "?"
                end
            else
                chunks[#chunks + 1] = replacements[escaped] or escaped
            end
        else
            chunks[#chunks + 1] = char
        end
    end
    error("unterminated JSON string")
end

function Parser:number()
    local start = self.pos
    local _, stop = self.text:find("^-?%d+%.?%d*[eE]?[+-]?%d*", self.pos)
    self.pos = stop + 1
    return tonumber(self.text:sub(start, stop))
end

function Parser:array()
    self:expect("[")
    local value = { __array = true, n = 0 }
    self:skip_space()
    if self:peek() == "]" then
        self.pos = self.pos + 1
        return value
    end
    while true do
        value.n = value.n + 1
        value[value.n] = self:value()
        self:skip_space()
        local char = self:peek()
        self.pos = self.pos + 1
        if char == "]" then
            return value
        end
        if char ~= "," then
            error("expected comma in array")
        end
    end
end

function Parser:object()
    self:expect("{")
    local value = {}
    self:skip_space()
    if self:peek() == "}" then
        self.pos = self.pos + 1
        return value
    end
    while true do
        self:skip_space()
        local key = self:string()
        self:skip_space()
        self:expect(":")
        value[key] = self:value()
        self:skip_space()
        local char = self:peek()
        self.pos = self.pos + 1
        if char == "}" then
            return value
        end
        if char ~= "," then
            error("expected comma in object")
        end
    end
end

function Parser:value()
    self:skip_space()
    local char = self:peek()
    if char == '"' then
        return self:string()
    end
    if char == "[" then
        return self:array()
    end
    if char == "{" then
        return self:object()
    end
    if char == "t" then
        self:expect("true")
        return true
    end
    if char == "f" then
        self:expect("false")
        return false
    end
    if char == "n" then
        self:expect("null")
        return Codec.null
    end
    return self:number()
end

function Codec.decode(text)
    local parser = Parser:new(text)
    local value = parser:value()
    parser:skip_space()
    return value
end

return Codec
