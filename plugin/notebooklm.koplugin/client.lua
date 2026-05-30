local DataStorage = require("datastorage")
local Json = require("direct.codec")

local Client = {}

function Client:new(settings, http, opts)
    opts = opts or {}
    return setmetatable({
        settings = settings,
        http = http,
        direct_client = nil,
        direct_jobs = {},
        plugin_path = opts.plugin_path,
    }, { __index = self })
end

local function direct_job_id()
    local timestamp = os.date("!%Y%m%dT%H%M%SZ")
    local clock = math.floor((os.clock() or 0) * 1000)
    return string.format("lua-direct-%s-%d-%06d", timestamp, clock, math.random(0, 999999))
end

function Client:_direct()
    if not self.direct_client then
        local DirectClient = require("direct.client")
        self.direct_client = DirectClient:new(self.settings)
    end
    return self.direct_client
end

local function shell_escape(value)
    return "'" .. tostring(value or ""):gsub("'", "'\\''") .. "'"
end

local function read_file(path)
    local file = io.open(path or "", "r")
    if not file then
        return nil
    end
    local body = file:read("*all")
    file:close()
    return body
end

local function write_file(path, body)
    local file = io.open(path or "", "w")
    if not file then
        return nil, "Could not write NotebookLM job file."
    end
    file:write(body)
    file:close()
    return true
end

function Client:_job_dir()
    return DataStorage:getSettingsDir() .. "/notebooklm-jobs"
end

function Client:_ensure_job_dir()
    local dir = self:_job_dir()
    os.execute("mkdir -p " .. shell_escape(dir))
    return dir
end

function Client:_koreader_root()
    local plugin_path = tostring(self.plugin_path or "")
    if plugin_path == "" then
        return nil
    end
    plugin_path = plugin_path:gsub("/+$", "")
    if plugin_path == "plugins/notebooklm.koplugin" or plugin_path == "./plugins/notebooklm.koplugin" then
        return "."
    end
    local root = plugin_path:gsub("/plugins/notebooklm%.koplugin$", "")
    if root == plugin_path then
        return nil
    end
    return root
end

function Client:_lua_direct_worker_command(job_id, request_path, result_path, log_path)
    local root = self:_koreader_root()
    if not root then
        return nil
    end
    local luajit_path = root .. "/luajit"
    local worker_path = self.plugin_path .. "/direct/worker.lua"
    if not read_file(worker_path) then
        return nil
    end
    local luajit = io.open(luajit_path, "r")
    if not luajit then
        return nil
    end
    luajit:close()
    return table.concat({
        "cd ", shell_escape(root),
        " && ./luajit ", shell_escape(worker_path),
        " ", shell_escape(request_path),
        " ", shell_escape(result_path),
        " > ", shell_escape(log_path),
        " 2>&1 &",
    })
end

function Client:_start_lua_direct_worker_job(job_id, action, request, timeout_seconds)
    local dir = self:_ensure_job_dir()
    local request_path = dir .. "/" .. job_id .. "-request.json"
    local result_path = dir .. "/" .. job_id .. "-result.json"
    local log_path = dir .. "/" .. job_id .. ".log"
    local payload = {
        auth_bundle_path = self.settings:read("direct_auth_bundle_path"),
        language = self.settings:read("language"),
        timeout = self:_timeout(),
        action = action or "ask",
        request = request,
    }
    local ok, write_err = write_file(request_path, Json.encode(payload))
    if not ok then
        return nil, write_err
    end
    local command = self:_lua_direct_worker_command(job_id, request_path, result_path, log_path)
    if not command then
        return nil, nil
    end
    os.execute(command)
    return {
        ok = true,
        job_id = job_id,
        status = "running",
        adapter = "lua-direct",
        result_path = result_path,
        log_path = log_path,
        started_at = os.time(),
        timeout_seconds = timeout_seconds or (self:_timeout() + 30),
    }
end

function Client:_refresh_lua_direct_worker_job(job)
    if not job or job.status ~= "running" or not job.result_path then
        return job
    end
    local body = read_file(job.result_path)
    if not body then
        local timeout = job.timeout_seconds or (self:_timeout() + 30)
        if job.started_at and os.time() - job.started_at > timeout then
            job.status = "failed"
            job.error = "Lua direct worker timed out."
        end
        return job
    end
    local ok, decoded = pcall(Json.decode, body)
    if not ok or type(decoded) ~= "table" then
        job.status = "failed"
        job.error = "Lua direct worker returned invalid JSON."
        return job
    end
    if decoded.ok then
        job.status = "succeeded"
        job.result = decoded.result
    else
        job.status = "failed"
        job.error = decoded.error or "Lua direct worker failed."
    end
    return job
end

function Client:_timeout()
    return tonumber(self.settings:read("timeout")) or 120
end

function Client:health()
    local _, auth_err = self:_direct():load_auth()
    if auth_err then
        return nil, auth_err
    end
    return {
        ok = true,
        service = "koreader-notebooklm-lua-direct",
        adapter = "lua-direct",
        notebook_id = self.settings:read("direct_notebook_id"),
    }
end

function Client:list_notebooks()
    return self:_direct():list_notebooks()
end

function Client:create_notebook(title)
    return self:_direct():create_notebook(title)
end

function Client:get_book(book_id)
    return nil, nil, 404
end

function Client:link_book(book)
    return { ok = true, book = book, adapter = "lua-direct" }
end

function Client:clear_book(book_id)
    return { ok = true, adapter = "lua-direct" }
end

function Client:upload_source(notebook_id, source)
    return self:_direct():upload_source(notebook_id, source or {})
end

function Client:ask(request)
    return self:_direct():ask(request)
end

function Client:start_ask_job(request)
    local job_id = direct_job_id()
    local worker_job, worker_err = self:_start_lua_direct_worker_job(job_id, "ask", request, self:_timeout() + 30)
    if worker_err then
        return nil, worker_err
    end
    if worker_job then
        self.direct_jobs[job_id] = worker_job
        return { ok = true, job_id = job_id, status = worker_job.status, adapter = "lua-direct" }
    end

    local job = {
        ok = true,
        job_id = job_id,
        status = "running",
        adapter = "lua-direct",
    }
    self.direct_jobs[job_id] = job
    self:_direct():ask_async(request, function(response, err)
        if err then
            job.status = "failed"
            job.error = err
            return
        end
        job.status = "succeeded"
        job.result = response
    end)
    return { ok = true, job_id = job_id, status = job.status, adapter = "lua-direct" }
end

function Client:get_ask_job(job_id)
    local job = self.direct_jobs[job_id]
    if not job then
        return nil, "Lua direct ask job was not found."
    end
    return self:_refresh_lua_direct_worker_job(job)
end

function Client:start_create_upload_job(request)
    local job_id = direct_job_id()
    local worker_job, worker_err = self:_start_lua_direct_worker_job(
        job_id,
        "create_upload",
        request,
        math.max(self:_timeout(), 600) + 60
    )
    if worker_err then
        return nil, worker_err
    end
    if not worker_job then
        return nil, "Background upload worker is not available in this KOReader build."
    end
    self.direct_jobs[job_id] = worker_job
    return { ok = true, job_id = job_id, status = worker_job.status, adapter = "lua-direct" }
end

function Client:get_create_upload_job(job_id)
    local job = self.direct_jobs[job_id]
    if not job then
        return nil, "Lua direct upload job was not found."
    end
    return self:_refresh_lua_direct_worker_job(job)
end

return Client
