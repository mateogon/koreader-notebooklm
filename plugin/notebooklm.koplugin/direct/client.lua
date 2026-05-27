local AuthBundle = require("direct.auth_bundle")
local Parsing = require("direct.parsing")
local Rpc = require("direct.rpc")

local DirectClient = {}

function DirectClient:new(settings, http)
    return setmetatable({
        settings = settings,
        http = http,
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

function DirectClient:ask()
    return nil, "Lua direct HTTP is not wired to the KOReader UI yet."
end

return DirectClient
