local ltn12 = require("ltn12")

local has_http, http = pcall(require, "socket.http")
local has_https, https = pcall(require, "ssl.https")
local has_socketutil, socketutil = pcall(require, "socketutil")

local AuthBundle = require("direct.auth_bundle")

local Transport = {}
local async_requests = 0

local FORM_CONTENT_TYPE = "application/x-www-form-urlencoded;charset=UTF-8"
local USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
local DEFAULT_ACCEPT_LANGUAGE = "en-US,en;q=0.9"

local function request_headers(body, auth)
    local headers = {
        ["Content-Type"] = FORM_CONTENT_TYPE,
        ["Content-Length"] = tostring(#body),
        ["Accept"] = "*/*",
        ["Accept-Language"] = auth.accept_language or DEFAULT_ACCEPT_LANGUAGE,
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
    return headers
end

local function upload_headers(auth, extra)
    local headers = {
        ["Accept"] = "*/*",
        ["Accept-Language"] = auth.accept_language or DEFAULT_ACCEPT_LANGUAGE,
        ["Origin"] = auth.base_url,
        ["Referer"] = (auth.base_url:gsub("/+$", "")) .. "/",
        ["User-Agent"] = USER_AGENT,
        ["x-goog-authuser"] = "0",
    }
    local cookie_header = AuthBundle.cookie_header(auth)
    if cookie_header ~= "" then
        headers["Cookie"] = cookie_header
    end
    for key, value in pairs(extra or {}) do
        headers[key] = value
    end
    return headers
end

local function response_error(response_body, status_code)
    local preview = tostring(response_body or ""):gsub("%s+", " ")
    if #preview > 240 then
        preview = preview:sub(1, 237) .. "..."
    end
    return string.format("NotebookLM HTTP %s: %s", tostring(status_code), preview)
end

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

    local headers = request_headers(body, auth)

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
        return nil, response_error(response_body, status_code), status_code
    end
    return response_body, nil, status_code
end

function Transport.post_upload_start(base_url, body, auth, file_size, timeout)
    local url = (base_url:gsub("/+$", "")) .. "/upload/_/?authuser=0"
    local lib, lib_err = request_library(url)
    if not lib then
        return nil, lib_err
    end
    local headers = upload_headers(auth, {
        ["Content-Type"] = FORM_CONTENT_TYPE,
        ["Content-Length"] = tostring(#body),
        ["x-goog-upload-command"] = "start",
        ["x-goog-upload-header-content-length"] = tostring(file_size),
        ["x-goog-upload-protocol"] = "resumable",
    })
    local response = {}
    local _, code, response_headers, status = with_timeout(timeout, function()
        return lib.request{
            url = url,
            method = "POST",
            headers = headers,
            source = ltn12.source.string(body),
            sink = ltn12.sink.table(response),
        }
    end)
    local status_code = tonumber(code)
    local response_body = table.concat(response)
    if not status_code then
        return nil, tostring(status or code or "NotebookLM upload start failed.")
    end
    if status_code < 200 or status_code >= 300 then
        return nil, response_error(response_body, status_code), status_code
    end
    local upload_url = response_headers
        and (response_headers["x-goog-upload-url"] or response_headers["X-Goog-Upload-Url"])
    if not upload_url or upload_url == "" then
        return nil, "NotebookLM upload URL was missing."
    end
    return upload_url, nil, status_code
end

function Transport.post_file_upload(upload_url, file_path, auth, file_size, timeout)
    local lib, lib_err = request_library(upload_url)
    if not lib then
        return nil, lib_err
    end
    local file, open_err = io.open(file_path or "", "rb")
    if not file then
        return nil, "Could not open source file for upload: " .. tostring(open_err or file_path)
    end
    local headers = upload_headers(auth, {
        ["Content-Type"] = "application/x-www-form-urlencoded;charset=utf-8",
        ["Content-Length"] = tostring(file_size),
        ["x-goog-upload-command"] = "upload, finalize",
        ["x-goog-upload-offset"] = "0",
    })
    local source = function()
        return file:read(65536)
    end
    local response = {}
    local _, code, _, status = with_timeout(timeout, function()
        return lib.request{
            url = upload_url,
            method = "POST",
            headers = headers,
            source = source,
            sink = ltn12.sink.table(response),
        }
    end)
    file:close()
    local status_code = tonumber(code)
    local response_body = table.concat(response)
    if not status_code then
        return nil, tostring(status or code or "NotebookLM file upload failed.")
    end
    if status_code < 200 or status_code >= 300 then
        return nil, response_error(response_body, status_code), status_code
    end
    return response_body, nil, status_code
end

function Transport.post_form_async(url, body, auth, timeout, callback)
    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    local ok_httpclient, HTTPClient = pcall(require, "httpclient")
    if not ok_ui or not ok_httpclient or not UIManager.initLooper then
        callback(nil, "Async HTTP support is not available in this KOReader build.")
        return
    end

    local headers = request_headers(body, auth)
    UIManager:initLooper()
    if not UIManager.looper then
        callback(nil, "KOReader async HTTP is disabled. Set DUSE_TURBO_LIB=true in defaults.custom.lua and restart KOReader.")
        return
    end

    async_requests = async_requests + 1
    HTTPClient:new():request({
        url = url,
        method = "POST",
        body = body,
        request_timeout = timeout or 120,
        connect_timeout = 10,
        on_headers = function(request_headers_obj)
            for key, value in pairs(headers) do
                request_headers_obj:add(key, value)
            end
        end,
    }, function(res)
        async_requests = async_requests - 1
        if not res then
            callback(nil, "NotebookLM request returned no response.")
            return
        end
        local status_code = tonumber(res.code or res.status)
        local response_body = tostring(res.body or "")
        if not status_code then
            callback(nil, tostring(res.error or res.reason or "NotebookLM request failed."))
            return
        end
        if status_code < 200 or status_code >= 300 then
            callback(nil, response_error(response_body, status_code), status_code)
            return
        end
        callback(response_body, nil, status_code)
    end)
end

function Transport._test_headers(body, auth)
    return request_headers(body, auth)
end

function Transport._test_response_error(response_body, status_code)
    return response_error(response_body, status_code)
end

return Transport
