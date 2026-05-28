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

function Client:_backend()
    return tostring(self.settings:read("backend") or "bridge")
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

function Client:_start_lua_direct_worker_job(job_id, request)
    local dir = self:_ensure_job_dir()
    local request_path = dir .. "/" .. job_id .. "-request.json"
    local result_path = dir .. "/" .. job_id .. "-result.json"
    local log_path = dir .. "/" .. job_id .. ".log"
    local payload = {
        auth_bundle_path = self.settings:read("direct_auth_bundle_path"),
        timeout = self:_timeout(),
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
    }
end

function Client:_refresh_lua_direct_worker_job(job)
    if not job or job.status ~= "running" or not job.result_path then
        return job
    end
    local body = read_file(job.result_path)
    if not body then
        local timeout = self:_timeout() + 30
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

function Client:_bridge_url()
    return self.settings:read("bridge_url")
end

function Client:_timeout()
    return tonumber(self.settings:read("timeout")) or 120
end

function Client:_short_timeout()
    local timeout = self:_timeout()
    if timeout > 10 then
        return 10
    end
    return timeout
end

function Client:_ensure_bridge()
    if self:_backend() ~= "bridge" then
        return nil, "Only the bridge backend is implemented right now."
    end
    return true, nil
end

function Client:_get(path, timeout)
    local ok, err = self:_ensure_bridge()
    if not ok then
        return nil, err
    end
    return self.http.get(self:_bridge_url(), path, timeout or self:_timeout())
end

function Client:_post(path, payload, timeout)
    local ok, err = self:_ensure_bridge()
    if not ok then
        return nil, err
    end
    return self.http.post(self:_bridge_url(), path, payload, timeout or self:_timeout())
end

function Client:_delete(path)
    local ok, err = self:_ensure_bridge()
    if not ok then
        return nil, err
    end
    return self.http.delete(self:_bridge_url(), path, self:_short_timeout())
end

function Client:health()
    if self:_backend() == "lua-direct" then
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
    return self:_get("/health", self:_short_timeout())
end

function Client:list_notebooks()
    if self:_backend() == "lua-direct" then
        return self:_direct():list_notebooks()
    end
    return self:_get("/notebooks", self:_short_timeout())
end

function Client:create_notebook(title)
    if self:_backend() == "lua-direct" then
        return self:_direct():create_notebook(title)
    end
    return self:_post("/notebooks", { title = title })
end

function Client:get_book(book_id)
    if self:_backend() == "lua-direct" then
        return nil, nil, 404
    end
    local response, err, code = self:_get("/books/" .. self.http.path_escape(book_id), self:_short_timeout())
    if code == 404 then
        return nil, nil, 404
    end
    return response, err, code
end

function Client:link_book(book)
    if self:_backend() == "lua-direct" then
        return { ok = true, book = book, adapter = "lua-direct" }
    end
    return self:_post("/books/link", book)
end

function Client:clear_book(book_id)
    if self:_backend() == "lua-direct" then
        return { ok = true, adapter = "lua-direct" }
    end
    return self:_delete("/books/" .. self.http.path_escape(book_id))
end

function Client:upload_source(notebook_id, source)
    source = source or {}
    if self:_backend() == "lua-direct" then
        return self:_direct():upload_source(notebook_id, source)
    end
    local ok, err = self:_ensure_bridge()
    if not ok then
        return nil, err
    end
    if self.settings:read("upload_mode") ~= "path" then
        local filename = source.file_path and source.file_path:match("([^/]+)$") or nil
        if not filename or filename == "" then
            filename = source.title
        end
        if not filename or filename == "" then
            filename = "source"
        end
        return self.http.post_multipart_file(
            self:_bridge_url(),
            "/sources/upload-file",
            {
                notebook_id = notebook_id,
                title = source.title,
                wait = source.wait ~= false and "true" or "false",
            },
            "file",
            source.file_path,
            filename,
            self:_timeout()
        )
    end
    return self:_post("/sources/upload", {
        notebook_id = notebook_id,
        file_path = source.file_path,
        title = source.title,
        wait = source.wait ~= false,
    })
end

function Client:ask(request)
    if self:_backend() == "lua-direct" then
        return self:_direct():ask(request)
    end
    return self:_post("/ask", request)
end

function Client:start_ask_job(request)
    if self:_backend() == "lua-direct" then
        local job_id = direct_job_id()
        local worker_job, worker_err = self:_start_lua_direct_worker_job(job_id, request)
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
    return self:_post("/ask/jobs", request, self:_short_timeout())
end

function Client:get_ask_job(job_id)
    if self:_backend() == "lua-direct" then
        local job = self.direct_jobs[job_id]
        if not job then
            return nil, "Lua direct ask job was not found."
        end
        return self:_refresh_lua_direct_worker_job(job)
    end
    return self:_get("/ask/jobs/" .. self.http.path_escape(job_id), self:_short_timeout())
end

return Client
