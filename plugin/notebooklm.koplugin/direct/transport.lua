local ltn12 = require("ltn12")

local has_http, http = pcall(require, "socket.http")
local has_https, https = pcall(require, "ssl.https")
local has_socketutil, socketutil = pcall(require, "socketutil")

local AuthBundle = require("direct.auth_bundle")

local Transport = {}

local FORM_CONTENT_TYPE = "application/x-www-form-urlencoded;charset=UTF-8"
local USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

local function request_library(url)
    if url:match("^https://") then
        if has_https then
            https.cert_verify = false
            return https
        end
        return nil, "HTTPS support is not available in this KOReader build."
    end
    if has_http then
        return http
    end
    return nil, "HTTP support is not available in this KOReader build."
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

function Transport.post_form(url, body, auth, timeout)
    local lib, lib_err = request_library(url)
    if not lib then
        return nil, lib_err
    end

    local headers = {
        ["Content-Type"] = FORM_CONTENT_TYPE,
        ["Content-Length"] = tostring(#body),
        ["Accept"] = "*/*",
        ["Accept-Language"] = "en-US,en;q=0.9",
        ["Origin"] = auth.base_url,
        ["Referer"] = (auth.base_url:gsub("/+$", "")) .. "/",
        ["User-Agent"] = USER_AGENT,
        ["X-Same-Domain"] = "1",
    }
    local cookie_header = AuthBundle.cookie_header(auth)
    if cookie_header ~= "" then
        headers["Cookie"] = cookie_header
    end
    if auth.csrf_token and auth.csrf_token ~= "" then
        headers["X-Goog-Csrf-Token"] = auth.csrf_token
    end

    local response = {}
    local _, code, _, status = with_timeout(timeout, function()
        return lib.request{
            url = url,
            method = "POST",
            headers = headers,
            source = ltn12.source.string(body),
            sink = ltn12.sink.table(response),
        }
    end)
    local response_body = table.concat(response)
    local status_code = tonumber(code)
    if not status_code then
        return nil, tostring(status or code or "NotebookLM request failed.")
    end
    if status_code < 200 or status_code >= 300 then
        local preview = tostring(response_body or ""):gsub("%s+", " ")
        if #preview > 240 then
            preview = preview:sub(1, 237) .. "..."
        end
        return nil, string.format("NotebookLM HTTP %s: %s", tostring(status_code), preview), status_code
    end
    return response_body, nil, status_code
end

return Transport
