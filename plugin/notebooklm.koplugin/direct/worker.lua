local worker_path = arg and arg[0] or ""
local plugin_path = worker_path:gsub("/direct/worker%.lua$", "")
local koreader_root = plugin_path:gsub("/plugins/notebooklm%.koplugin$", "")
if plugin_path == "plugins/notebooklm.koplugin" then
    koreader_root = "."
end
if plugin_path ~= worker_path then
    package.path = table.concat({
        plugin_path .. "/?.lua",
        plugin_path .. "/?/init.lua",
        plugin_path .. "/direct/?.lua",
        koreader_root .. "/frontend/?.lua",
        koreader_root .. "/frontend/?/init.lua",
        koreader_root .. "/common/?.lua",
        koreader_root .. "/common/?/init.lua",
        koreader_root .. "/common/?/?.lua",
        package.path,
    }, ";")
    package.cpath = table.concat({
        koreader_root .. "/libs/?.so",
        koreader_root .. "/libs/?.so.?",
        koreader_root .. "/common/?.so",
        koreader_root .. "/common/?/?.so",
        package.cpath,
    }, ";")
end

local Json = require("direct.codec")
local DirectClient = require("direct.client")

local request_path = arg and arg[1]
local result_path = arg and arg[2]

local function read_file(path)
    local file = io.open(path or "", "r")
    if not file then
        return nil, "Could not open worker request."
    end
    local body = file:read("*all")
    file:close()
    return body
end

local function write_file(path, body)
    local temp_path = path .. ".tmp"
    local file = io.open(temp_path, "w")
    if not file then
        return nil
    end
    file:write(body)
    file:close()
    os.rename(temp_path, path)
    return true
end

local function finish(payload)
    if result_path and result_path ~= "" then
        write_file(result_path, Json.encode(payload))
    end
end

local body, read_err = read_file(request_path)
if not body then
    finish({ ok = false, error = read_err })
    os.exit(1)
end

local ok, payload = pcall(Json.decode, body)
if not ok or type(payload) ~= "table" then
    finish({ ok = false, error = "Could not decode worker request." })
    os.exit(1)
end

local settings = {
    read = function(_, key)
        if key == "backend" then
            return "lua-direct"
        end
        if key == "direct_auth_bundle_path" then
            return payload.auth_bundle_path
        end
        if key == "timeout" then
            return payload.timeout or 120
        end
        if key == "language" then
            return payload.language or "en"
        end
        return nil
    end,
}

local client = DirectClient:new(settings)
local action = payload.action or "ask"
local request = payload.request or {}
local result, err
local err_meta

if action == "ask" then
    result, err = client:ask(request)
elseif action == "create_upload" then
    local title = request.title or "Untitled notebook"
    local created
    created, err = client:create_notebook(title)
    if created and not err then
        local notebook = created.notebook
        if not notebook or not notebook.id then
            err = "NotebookLM did not return a created notebook ID."
        else
            local upload = nil
            if request.upload_after then
                upload, err, err_meta = client:upload_source(notebook.id, {
                    file_path = request.file_path,
                    title = request.source_title,
                    wait = request.wait ~= false,
                    wait_timeout = request.wait_timeout,
                    fail_on_any_error = request.fallback_file_path ~= nil,
                })
                if err and err_meta and err_meta.terminal_source_error and request.fallback_file_path then
                    local primary_error = err
                    upload, err, err_meta = client:upload_source(notebook.id, {
                        file_path = request.fallback_file_path,
                        title = request.fallback_source_title,
                        wait = request.wait ~= false,
                        wait_timeout = request.wait_timeout,
                    })
                    if upload and not err then
                        upload.primary_failed = true
                        upload.primary_error = primary_error
                        upload.fallback_used = true
                        upload.fallback_method = request.fallback_source_export_method
                    end
                end
            end
            if not err then
                result = {
                    notebook = notebook,
                    upload = upload,
                    adapter = "lua-direct",
                }
            end
        end
    end
else
    err = "Unknown NotebookLM worker action: " .. tostring(action)
end

if not result then
    finish({ ok = false, error = tostring(err or "NotebookLM worker failed.") })
    os.exit(1)
end

finish({ ok = true, result = result })
