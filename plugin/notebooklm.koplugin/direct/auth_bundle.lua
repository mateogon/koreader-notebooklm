local Json = require("direct.codec")

local AuthBundle = {}

local function should_send_cookie(cookie)
    local domain = tostring(cookie.domain or "")
    if domain == "" then
        return true
    end
    return domain == ".google.com" or domain == "notebooklm.google.com"
end

local function read_file(path)
    local file = io.open(path or "", "r")
    if not file then
        return nil, "Could not open NotebookLM auth bundle."
    end
    local body = file:read("*all")
    file:close()
    return body
end

function AuthBundle.load(path)
    local body, read_err = read_file(path)
    if not body then
        return nil, read_err
    end
    local ok, decoded = pcall(Json.decode, body)
    if not ok or type(decoded) ~= "table" then
        return nil, "Could not decode NotebookLM auth bundle."
    end
    if type(decoded.base_url) ~= "string" or decoded.base_url == "" then
        decoded.base_url = "https://notebooklm.google.com"
    end
    if type(decoded.cookies) ~= "table" then
        return nil, "NotebookLM auth bundle is missing cookies."
    end
    if type(decoded.csrf_token) ~= "string" or decoded.csrf_token == "" then
        return nil, "NotebookLM auth bundle is missing csrf_token."
    end
    return decoded
end

function AuthBundle.cookie_header(auth)
    local cookies = auth and auth.cookies
    if type(cookies) ~= "table" then
        return ""
    end
    local parts = {}
    if type(cookies[1]) == "table" then
        for _, cookie in ipairs(cookies) do
            if should_send_cookie(cookie) and type(cookie.name) == "string" and type(cookie.value) == "string" then
                parts[#parts + 1] = cookie.name .. "=" .. cookie.value
            end
        end
    else
        for name, value in pairs(cookies) do
            if name ~= "__array" and name ~= "n" and type(value) ~= "table" then
                parts[#parts + 1] = tostring(name) .. "=" .. tostring(value)
            end
        end
        table.sort(parts)
    end
    return table.concat(parts, "; ")
end

return AuthBundle
