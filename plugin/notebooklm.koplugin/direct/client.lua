local AuthBundle = require("direct.auth_bundle")
local Parsing = require("direct.parsing")
local Rpc = require("direct.rpc")
local Transport = require("direct.transport")

local DirectClient = {}

function DirectClient:new(settings, http)
    return setmetatable({
        settings = settings,
        transport = http or Transport,
        request_id = 100000,
    }, { __index = self })
end

function DirectClient:is_enabled()
    return self.settings and self.settings:read("backend") == "lua-direct"
end

function DirectClient:load_auth()
    if not self.settings then
        return nil, "Missing settings for Lua direct client."
    end
    return AuthBundle.load(self.settings:read("direct_auth_bundle_path"))
end

function DirectClient:build_list_notebooks(auth)
    auth = auth or {}
    return {
        url = Rpc.build_batchexecute_url(auth.base_url or "https://notebooklm.google.com", Rpc.RPC_LIST_NOTEBOOKS, {
            build_label = auth.build_label,
            session_id = auth.session_id,
        }),
        body = Rpc.build_batchexecute_body(Rpc.RPC_LIST_NOTEBOOKS, Rpc.params_list_notebooks(), auth.csrf_token),
    }
end

function DirectClient:build_get_notebook(auth, notebook_id)
    auth = auth or {}
    return {
        url = Rpc.build_batchexecute_url(auth.base_url or "https://notebooklm.google.com", Rpc.RPC_GET_NOTEBOOK, {
            source_path = "/notebook/" .. tostring(notebook_id),
            build_label = auth.build_label,
            session_id = auth.session_id,
        }),
        body = Rpc.build_batchexecute_body(Rpc.RPC_GET_NOTEBOOK, Rpc.params_get_notebook(notebook_id), auth.csrf_token),
    }
end

function DirectClient:build_create_notebook(auth, title)
    auth = auth or {}
    return {
        url = Rpc.build_batchexecute_url(auth.base_url or "https://notebooklm.google.com", Rpc.RPC_CREATE_NOTEBOOK, {
            build_label = auth.build_label,
            session_id = auth.session_id,
        }),
        body = Rpc.build_batchexecute_body(Rpc.RPC_CREATE_NOTEBOOK, Rpc.params_create_notebook(title), auth.csrf_token),
    }
end

function DirectClient:build_register_file_source(auth, notebook_id, filename)
    auth = auth or {}
    return {
        url = Rpc.build_batchexecute_url(auth.base_url or "https://notebooklm.google.com", Rpc.RPC_ADD_SOURCE_FILE, {
            source_path = "/notebook/" .. tostring(notebook_id),
            build_label = auth.build_label,
            session_id = auth.session_id,
        }),
        body = Rpc.build_batchexecute_body(Rpc.RPC_ADD_SOURCE_FILE, Rpc.params_register_file_source(notebook_id, filename), auth.csrf_token),
    }
end

function DirectClient:build_upload_start_body(notebook_id, filename, source_id)
    local json = require("direct.codec")
    return table.concat({
        '{"PROJECT_ID":',
        json.encode(tostring(notebook_id or "")),
        ',"SOURCE_NAME":',
        json.encode(tostring(filename or "")),
        ',"SOURCE_ID":',
        json.encode(tostring(source_id or "")),
        '}',
    })
end

function DirectClient:build_ask(auth, request)
    auth = auth or {}
    request = request or {}
    self.request_id = self.request_id + 100000
    return {
        url = Rpc.build_query_url(auth.base_url or "https://notebooklm.google.com", {
            build_label = auth.build_label,
            session_id = auth.session_id,
            request_id = self.request_id,
        }),
        body = Rpc.build_query_body({
            source_ids = request.source_ids or {},
            query_text = request.query_text or request.prompt or "",
            conversation_id = request.conversation_id or "",
            conversation_history = request.conversation_history,
            csrf_token = auth.csrf_token,
        }),
    }
end

function DirectClient:parse_notebook_list(response_text)
    local result, err = Parsing.parse_batchexecute_response(response_text, Rpc.RPC_LIST_NOTEBOOKS)
    if not result then
        return nil, err
    end
    return Parsing.parse_notebooks(result)
end

function DirectClient:parse_notebook(response_text)
    local result, err = Parsing.parse_batchexecute_response(response_text, Rpc.RPC_GET_NOTEBOOK)
    if not result then
        return nil, err
    end
    return {
        raw = result,
        sources = Parsing.parse_sources_from_notebook_data(result),
    }
end

function DirectClient:parse_created_notebook(response_text, title)
    local result, err = Parsing.parse_batchexecute_response(response_text, Rpc.RPC_CREATE_NOTEBOOK)
    if not result then
        return nil, err
    end
    local notebook_id = type(result) == "table" and result[3] or nil
    if type(notebook_id) ~= "string" or notebook_id == "" then
        return nil, { kind = "parse_error", message = "Could not parse created NotebookLM notebook ID." }
    end
    return {
        id = notebook_id,
        title = title or "Untitled notebook",
        source_count = 0,
    }
end

function DirectClient:parse_registered_source(response_text)
    local result, err = Parsing.parse_batchexecute_response(response_text, Rpc.RPC_ADD_SOURCE_FILE)
    if not result then
        return nil, err
    end
    local source_id = Parsing.unwrap_first(result)
    if type(source_id) ~= "string" or source_id == "" then
        return nil, { kind = "parse_error", message = "Could not parse registered NotebookLM source ID." }
    end
    return source_id
end

function DirectClient:parse_ask(response_text)
    return Parsing.parse_query_response(response_text)
end

function DirectClient:timeout()
    return tonumber(self.settings and self.settings:read("timeout")) or 120
end

function DirectClient:list_notebooks()
    local auth, auth_err = self:load_auth()
    if not auth then
        return nil, auth_err
    end
    local request = self:build_list_notebooks(auth)
    local response_text, err = self.transport.post_form(request.url, request.body, auth, self:timeout())
    if not response_text then
        return nil, err
    end
    local notebooks, parse_err = self:parse_notebook_list(response_text)
    if not notebooks then
        return nil, parse_err and parse_err.message or "Could not parse NotebookLM notebooks."
    end
    return { ok = true, notebooks = notebooks, adapter = "lua-direct" }
end

function DirectClient:get_notebook(notebook_id)
    local auth, auth_err = self:load_auth()
    if not auth then
        return nil, auth_err
    end
    local request = self:build_get_notebook(auth, notebook_id)
    local response_text, err = self.transport.post_form(request.url, request.body, auth, self:timeout())
    if not response_text then
        return nil, err
    end
    local notebook, parse_err = self:parse_notebook(response_text)
    if not notebook then
        return nil, parse_err and parse_err.message or "Could not parse NotebookLM notebook."
    end
    notebook.ok = true
    notebook.notebook_id = notebook_id
    notebook.adapter = "lua-direct"
    return notebook
end

function DirectClient:create_notebook(title)
    title = title and title ~= "" and title or "Untitled notebook"
    local auth, auth_err = self:load_auth()
    if not auth then
        return nil, auth_err
    end
    local request = self:build_create_notebook(auth, title)
    local response_text, err = self.transport.post_form(request.url, request.body, auth, self:timeout())
    if not response_text then
        return nil, err
    end
    local notebook, parse_err = self:parse_created_notebook(response_text, title)
    if not notebook then
        return nil, parse_err and parse_err.message or "Could not parse created NotebookLM notebook."
    end
    return { ok = true, notebook = notebook, adapter = "lua-direct" }
end

local function source_file_size(file_path)
    local file, open_err = io.open(file_path or "", "rb")
    if not file then
        return nil, "Source file not found: " .. tostring(open_err or file_path)
    end
    local size = file:seek("end")
    file:close()
    if not size or size <= 0 then
        return nil, "Source file is empty."
    end
    return size
end

function DirectClient:register_file_source(auth, notebook_id, filename)
    local request = self:build_register_file_source(auth, notebook_id, filename)
    local response_text, err = self.transport.post_form(request.url, request.body, auth, self:timeout())
    if not response_text then
        return nil, err
    end
    local source_id, parse_err = self:parse_registered_source(response_text)
    if not source_id then
        return nil, parse_err and parse_err.message or "Could not parse registered NotebookLM source."
    end
    return source_id
end

function DirectClient:wait_for_source_ready(notebook_id, source_id)
    local ok_socket, socket = pcall(require, "socket")
    local deadline = os.time() + self:timeout()
    repeat
        local notebook, err = self:get_notebook(notebook_id)
        if not notebook then
            return nil, err
        end
        for _, source in ipairs(notebook.sources or {}) do
            if source.id == source_id then
                if not source.status or source.status == "ready" then
                    return source
                end
                if source.status == "error" then
                    return nil, "NotebookLM source processing failed."
                end
            end
        end
        if ok_socket and socket.sleep then
            socket.sleep(3)
        else
            break
        end
    until os.time() >= deadline
    return nil, "NotebookLM source processing timed out."
end

function DirectClient:upload_source(notebook_id, source)
    source = source or {}
    if not notebook_id or notebook_id == "" then
        return nil, "NotebookLM notebook ID is required for Lua direct upload."
    end
    if not source.file_path or source.file_path == "" then
        return nil, "Source file path is required for Lua direct upload."
    end
    local auth, auth_err = self:load_auth()
    if not auth then
        return nil, auth_err
    end
    local size, size_err = source_file_size(source.file_path)
    if not size then
        return nil, size_err
    end
    local filename = source.title
        or tostring(source.file_path):match("([^/]+)$")
        or "source"
    local source_id, register_err = self:register_file_source(auth, notebook_id, filename)
    if not source_id then
        return nil, register_err
    end
    local upload_body = self:build_upload_start_body(notebook_id, filename, source_id)
    local upload_url, start_err = self.transport.post_upload_start(
        auth.base_url or "https://notebooklm.google.com",
        upload_body,
        auth,
        size,
        math.min(self:timeout(), 60)
    )
    if not upload_url then
        return nil, start_err
    end
    local _, upload_err = self.transport.post_file_upload(
        upload_url,
        source.file_path,
        auth,
        size,
        math.max(self:timeout(), 300)
    )
    if upload_err then
        return nil, upload_err
    end
    local result = {
        ok = true,
        source_id = source_id,
        title = filename,
        notebook_id = notebook_id,
        adapter = "lua-direct",
    }
    if source.wait ~= false then
        local ready, wait_err = self:wait_for_source_ready(notebook_id, source_id)
        if not ready then
            return nil, wait_err
        end
        if ready.title then
            result.title = ready.title
        end
        if ready.status then
            result.status = ready.status
        end
    end
    return result
end

function DirectClient:get_notebook_async(notebook_id, auth, callback)
    if not self.transport.post_form_async then
        callback(nil, "Async HTTP support is not available for Lua direct.")
        return
    end
    local request = self:build_get_notebook(auth, notebook_id)
    self.transport.post_form_async(request.url, request.body, auth, self:timeout(), function(response_text, err)
        if not response_text then
            callback(nil, err)
            return
        end
        local notebook, parse_err = self:parse_notebook(response_text)
        if not notebook then
            callback(nil, parse_err and parse_err.message or "Could not parse NotebookLM notebook.")
            return
        end
        notebook.ok = true
        notebook.notebook_id = notebook_id
        notebook.adapter = "lua-direct"
        callback(notebook, nil)
    end)
end

function DirectClient:ask(request)
    request = request or {}
    local notebook_id = request.notebook_id
    if not notebook_id or notebook_id == "" then
        return nil, "NotebookLM notebook ID is required for Lua direct ask."
    end
    local auth, auth_err = self:load_auth()
    if not auth then
        return nil, auth_err
    end

    local source_ids = request.source_ids
    if not source_ids then
        local notebook, notebook_err = self:get_notebook(notebook_id)
        if not notebook then
            return nil, notebook_err
        end
        source_ids = {}
        for _, source in ipairs(notebook.sources or {}) do
            if source.id then
                source_ids[#source_ids + 1] = source.id
            end
        end
    end

    local query = self:build_ask(auth, {
        source_ids = source_ids,
        query_text = self:build_question(request),
        conversation_id = request.conversation_id or self:conversation_id(),
        conversation_history = request.conversation_history,
    })
    local response_text, err = self.transport.post_form(query.url, query.body, auth, self:timeout())
    if not response_text then
        return nil, err
    end
    local parsed, parse_err = self:parse_ask(response_text)
    if not parsed then
        return nil, parse_err and parse_err.message or "Could not parse NotebookLM answer."
    end
    parsed.ok = true
    parsed.notebook_id = notebook_id
    parsed.adapter = "lua-direct"
    return parsed
end

function DirectClient:ask_async(request, callback)
    request = request or {}
    local notebook_id = request.notebook_id
    if not notebook_id or notebook_id == "" then
        callback(nil, "NotebookLM notebook ID is required for Lua direct ask.")
        return
    end
    if not self.transport.post_form_async then
        callback(nil, "Async HTTP support is not available for Lua direct.")
        return
    end
    local auth, auth_err = self:load_auth()
    if not auth then
        callback(nil, auth_err)
        return
    end

    local function send_ask(source_ids)
        local query = self:build_ask(auth, {
            source_ids = source_ids,
            query_text = self:build_question(request),
            conversation_id = request.conversation_id or self:conversation_id(),
            conversation_history = request.conversation_history,
        })
        self.transport.post_form_async(query.url, query.body, auth, self:timeout(), function(response_text, err)
            if not response_text then
                callback(nil, err)
                return
            end
            local parsed, parse_err = self:parse_ask(response_text)
            if not parsed then
                callback(nil, parse_err and parse_err.message or "Could not parse NotebookLM answer.")
                return
            end
            parsed.ok = true
            parsed.notebook_id = notebook_id
            parsed.adapter = "lua-direct"
            callback(parsed, nil)
        end)
    end

    if request.source_ids then
        send_ask(request.source_ids)
        return
    end

    self:get_notebook_async(notebook_id, auth, function(notebook, notebook_err)
        if not notebook then
            callback(nil, notebook_err)
            return
        end
        local source_ids = {}
        for _, source in ipairs(notebook.sources or {}) do
            if source.id then
                source_ids[#source_ids + 1] = source.id
            end
        end
        send_ask(source_ids)
    end)
end

function DirectClient:build_question(request)
    local parts = { tostring(request.prompt or ""):gsub("^%s+", ""):gsub("%s+$", "") }
    local book = request.book
    if type(book) == "table" then
        local book_lines = {}
        if book.title and book.title ~= "" then
            book_lines[#book_lines + 1] = "Title: " .. tostring(book.title)
        end
        if book.author and book.author ~= "" then
            book_lines[#book_lines + 1] = "Author: " .. tostring(book.author)
        end
        if book.position and book.position ~= "" then
            book_lines[#book_lines + 1] = "Position: " .. tostring(book.position)
        end
        if #book_lines > 0 then
            parts[#parts + 1] = "Book context:\n" .. table.concat(book_lines, "\n")
        end
    end
    parts[#parts + 1] = 'Selected passage:\n"""\n' .. tostring(request.selected_text or ""):gsub("^%s+", ""):gsub("%s+$", "") .. '\n"""'
    return table.concat(parts, "\n\n")
end

function DirectClient:conversation_id()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (template:gsub("[xy]", function(char)
        local value = char == "x" and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", value)
    end))
end

return DirectClient
