local Json = require("direct.codec")

local AuthBundle = {}

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

return AuthBundle
