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
