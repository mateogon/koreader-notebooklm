local Client = {}

function Client:new(settings, http)
    return setmetatable({ settings = settings, http = http }, { __index = self })
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
    local backend = self.settings:read("backend")
    if backend ~= "bridge" then
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
    return self:_get("/health", self:_short_timeout())
end

function Client:list_notebooks()
    return self:_get("/notebooks", self:_short_timeout())
end

function Client:create_notebook(title)
    return self:_post("/notebooks", { title = title })
end

function Client:get_book(book_id)
    local response, err, code = self:_get("/books/" .. self.http.path_escape(book_id), self:_short_timeout())
    if code == 404 then
        return nil, nil, 404
    end
    return response, err, code
end

function Client:link_book(book)
    return self:_post("/books/link", book)
end

function Client:clear_book(book_id)
    return self:_delete("/books/" .. self.http.path_escape(book_id))
end

function Client:upload_source(notebook_id, source)
    source = source or {}
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
    return self:_post("/ask", request)
end

function Client:start_ask_job(request)
    return self:_post("/ask/jobs", request, self:_short_timeout())
end

function Client:get_ask_job(job_id)
    return self:_get("/ask/jobs/" .. self.http.path_escape(job_id), self:_short_timeout())
end

return Client
