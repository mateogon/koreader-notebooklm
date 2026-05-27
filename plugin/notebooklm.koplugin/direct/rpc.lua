local Json = require("direct.codec")

local Rpc = {
    RPC_LIST_NOTEBOOKS = "wXbhsf",
    RPC_GET_NOTEBOOK = "rLM1Ne",
    RPC_CREATE_NOTEBOOK = "CCqFvf",
    RPC_GET_CONVERSATIONS = "hPTbtc",
    RPC_ADD_SOURCE_FILE = "o4cbdc",
    RPC_RENAME_SOURCE = "b7Wfje",
    QUERY_ENDPOINT = "/_/LabsTailwindUi/data/google.internal.labs.tailwind.orchestration.v1.LabsTailwindOrchestrationService/GenerateFreeFormStreamed",
    BL_FALLBACK = "boq_labs-tailwind-frontend_20260108.06_p0",
}

local null = Json.null

local function quote(value)
    value = tostring(value or "")
    return value:gsub("([^A-Za-z0-9_%.%-%~])", function(char)
        return string.format("%%%02X", char:byte())
    end)
end

local function urlencode(parts)
    local chunks = {}
    for _, pair in ipairs(parts) do
        if pair[2] ~= nil and pair[2] ~= "" then
            chunks[#chunks + 1] = quote(pair[1]) .. "=" .. quote(pair[2])
        end
    end
    return table.concat(chunks, "&")
end

function Rpc.build_batchexecute_body(rpc_id, params, csrf_token)
    local params_json = Json.encode(params)
    local f_req = Json.array(Json.array(Json.array(rpc_id, params_json, null, "generic")))
    local parts = { "f.req=" .. quote(Json.encode(f_req)) }
    if csrf_token and csrf_token ~= "" then
        parts[#parts + 1] = "at=" .. quote(csrf_token)
    end
    return table.concat(parts, "&") .. "&"
end

function Rpc.build_batchexecute_url(base_url, rpc_id, options)
    options = options or {}
    local query = urlencode({
        { "rpcids", rpc_id },
        { "source-path", options.source_path or "/" },
        { "bl", options.build_label or Rpc.BL_FALLBACK },
        { "hl", options.language or "en" },
        { "rt", "c" },
        { "f.sid", options.session_id },
    })
    return (base_url:gsub("/+$", "")) .. "/_/LabsTailwindUi/data/batchexecute?" .. query
end

function Rpc.build_query_body(options)
    options = options or {}
    local sources = Json.array()
    for _, source_id in ipairs(options.source_ids or {}) do
        sources.n = sources.n + 1
        sources[sources.n] = Json.array(Json.array(source_id))
    end
    local params = Json.array(
        sources,
        options.query_text or "",
        options.conversation_history or null,
        Json.array(2, null, Json.array(1)),
        options.conversation_id or ""
    )
    local f_req = Json.array(null, Json.encode(params))
    local parts = { "f.req=" .. quote(Json.encode(f_req)) }
    if options.csrf_token and options.csrf_token ~= "" then
        parts[#parts + 1] = "at=" .. quote(options.csrf_token)
    end
    return table.concat(parts, "&") .. "&"
end

function Rpc.build_query_url(base_url, options)
    options = options or {}
    local query = urlencode({
        { "bl", options.build_label or Rpc.BL_FALLBACK },
        { "hl", options.language or "en" },
        { "_reqid", tostring(options.request_id or 0) },
        { "rt", "c" },
        { "f.sid", options.session_id },
    })
    return (base_url:gsub("/+$", "")) .. Rpc.QUERY_ENDPOINT .. "?" .. query
end

function Rpc.params_list_notebooks()
    return Json.array(null, 1, null, Json.array(2))
end

function Rpc.params_get_notebook(notebook_id)
    return Json.array(notebook_id, null, Json.array(2), null, 0)
end

function Rpc.params_create_notebook(title)
    return Json.array(
        title,
        null,
        null,
        Json.array(2),
        Json.array(1, null, null, null, null, null, null, null, null, null, Json.array(1))
    )
end

function Rpc.params_register_file_source(notebook_id, filename)
    return Json.array(
        Json.array(Json.array(filename)),
        notebook_id,
        Json.array(2),
        Json.array(1, null, null, null, null, null, null, null, null, null, Json.array(1))
    )
end

return Rpc
