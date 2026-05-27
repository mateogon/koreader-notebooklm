local http = require("socket.http")
local ltn12 = require("ltn12")

local has_https, https = pcall(require, "ssl.https")
local has_socketutil, socketutil = pcall(require, "socketutil")

local json = nil
local ok_json, json_mod = pcall(require, "json")
if ok_json then
    json = json_mod
else
    local ok_rapidjson, rapidjson_mod = pcall(require, "rapidjson")
    if ok_rapidjson then
        json = rapidjson_mod
    end
end

local Http = {}

local function join_url(base_url, path)
    return (base_url:gsub("/+$", "")) .. path
end

local function request_library(url)
    if url:match("^https://") then
        if has_https then
            https.cert_verify = false
            return https
        end
        return nil, "HTTPS support is not available in this KOReader build."
    end
    return http
end

local function with_timeout(timeout, fn)
    if has_socketutil and timeout then
        socketutil:set_timeout(timeout, timeout)
    end
    local ok, a, b, c, d = pcall(fn)
    if has_socketutil and timeout then
        socketutil:reset_timeout()
    end
    if not ok then
        return nil, nil, nil, tostring(a)
    end
    return a, b, c, d
end

local function decode_json(body)
    if not json then
        return nil, "No JSON module found. Expected `json` or `rapidjson`."
    end
    local ok, decoded = pcall(json.decode, body or "")
    if not ok then
        return nil, "Could not decode bridge JSON response: " .. tostring(decoded)
    end
    return decoded, nil
end

local function normalize_status(code, status, fallback)
    local status_code = tonumber(code)
    if not status_code then
        return nil, tostring(status or code or fallback or "Bridge request failed.")
    end
    return status_code, nil
end

function Http.encode(value)
    if not json then
        return nil, "No JSON module found. Expected `json` or `rapidjson`."
    end
    local ok, encoded = pcall(json.encode, value)
    if not ok then
        return nil, "Could not encode JSON request: " .. tostring(encoded)
    end
    return encoded, nil
end

function Http.path_escape(value)
    value = tostring(value or "")
    return value:gsub("([^%w%-%_%.%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

function Http.get(base_url, path, timeout)
    local url = join_url(base_url, path)
    local lib, lib_err = request_library(url)
    if not lib then
        return nil, lib_err
    end

    local response = {}
    local _, code, _, status = with_timeout(timeout, function()
        return lib.request{
            url = url,
            method = "GET",
            sink = ltn12.sink.table(response),
        }
    end)
    local body = table.concat(response)

    local status_code, status_err = normalize_status(code, status, "Bridge request failed.")
    if not status_code then
        return nil, status_err
    end
    if status_code < 200 or status_code >= 300 then
        return nil, string.format("Bridge GET %s failed: %s %s", path, tostring(status_code), body), status_code
    end
    return decode_json(body)
end

function Http.delete(base_url, path, timeout)
    local url = join_url(base_url, path)
    local lib, lib_err = request_library(url)
    if not lib then
        return nil, lib_err
    end

    local response = {}
    local _, code, _, status = with_timeout(timeout, function()
        return lib.request{
            url = url,
            method = "DELETE",
            sink = ltn12.sink.table(response),
        }
    end)
    local body = table.concat(response)

    local status_code, status_err = normalize_status(code, status, "Bridge request failed.")
    if not status_code then
        return nil, status_err
    end
    if status_code < 200 or status_code >= 300 then
        return nil, string.format("Bridge DELETE %s failed: %s %s", path, tostring(status_code), body), status_code
    end
    return decode_json(body)
end

function Http.post(base_url, path, payload, timeout)
    local url = join_url(base_url, path)
    local lib, lib_err = request_library(url)
    if not lib then
        return nil, lib_err
    end

    local body, encode_err = Http.encode(payload or {})
    if not body then
        return nil, encode_err
    end

    local response = {}
    local _, code, _, status = with_timeout(timeout, function()
        return lib.request{
            url = url,
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#body),
            },
            source = ltn12.source.string(body),
            sink = ltn12.sink.table(response),
        }
    end)
    local response_body = table.concat(response)

    local status_code, status_err = normalize_status(code, status, "Bridge request failed.")
    if not status_code then
        return nil, status_err
    end
    if status_code < 200 or status_code >= 300 then
        return nil, string.format("Bridge POST %s failed: %s %s", path, tostring(status_code), response_body), status_code
    end
    return decode_json(response_body)
end

function Http.post_multipart_file(base_url, path, fields, file_field, file_path, filename, timeout)
    local url = join_url(base_url, path)
    local lib, lib_err = request_library(url)
    if not lib then
        return nil, lib_err
    end
    if not file_path or file_path == "" then
        return nil, "No source file path was provided for upload."
    end

    local file = io.open(file_path, "rb")
    if not file then
        return nil, "Could not open source file for upload: " .. tostring(file_path)
    end
    local file_content = file:read("*all")
    file:close()

    local boundary = "----koreader-notebooklm-" .. tostring(os.time()) .. tostring(math.random(100000, 999999))
    local chunks = {}
    for key, value in pairs(fields or {}) do
        if value ~= nil then
            table.insert(chunks, "--" .. boundary .. "\r\n")
            table.insert(chunks, 'Content-Disposition: form-data; name="' .. tostring(key) .. '"\r\n\r\n')
            table.insert(chunks, tostring(value))
            table.insert(chunks, "\r\n")
        end
    end
    table.insert(chunks, "--" .. boundary .. "\r\n")
    table.insert(chunks, 'Content-Disposition: form-data; name="' .. tostring(file_field or "file") .. '"; filename="' .. tostring(filename or "source") .. '"\r\n')
    table.insert(chunks, "Content-Type: application/octet-stream\r\n\r\n")
    table.insert(chunks, file_content)
    table.insert(chunks, "\r\n--" .. boundary .. "--\r\n")

    local body = table.concat(chunks)
    local response = {}
    local _, code, _, status = with_timeout(timeout, function()
        return lib.request{
            url = url,
            method = "POST",
            headers = {
                ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
                ["Content-Length"] = tostring(#body),
            },
            source = ltn12.source.string(body),
            sink = ltn12.sink.table(response),
        }
    end)
    local response_body = table.concat(response)

    local status_code, status_err = normalize_status(code, status, "Bridge upload request failed.")
    if not status_code then
        return nil, status_err
    end
    if status_code < 200 or status_code >= 300 then
        return nil, string.format("Bridge upload %s failed: %s %s", path, tostring(status_code), response_body), status_code
    end
    return decode_json(response_body)
end

return Http
