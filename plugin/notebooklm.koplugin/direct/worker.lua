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
        return nil
    end,
}

local client = DirectClient:new(settings)
local result, err = client:ask(payload.request or {})
if not result then
    finish({ ok = false, error = tostring(err or "NotebookLM ask failed.") })
    os.exit(1)
end

finish({ ok = true, result = result })
