local Json = require("direct.codec")
local Rpc = require("direct.rpc")

local Parsing = {}

local ERROR_NAMES = {
    [3] = "INVALID_ARGUMENT",
    [5] = "NOT_FOUND",
    [7] = "PERMISSION_DENIED",
    [8] = "RESOURCE_EXHAUSTED",
    [13] = "INTERNAL",
    [14] = "UNAVAILABLE",
    [16] = "UNAUTHENTICATED",
}

local function is_null(value)
    return value == Json.null
end

local function unwrap_first(value)
    while type(value) == "table" and value[1] ~= nil do
        value = value[1]
    end
    return value
end

local function nested_get(value, path)
    for _, key in ipairs(path) do
        if type(value) ~= "table" then
            return nil
        end
        value = value[key]
    end
    return value
end

local function chunks(response_text)
    response_text = response_text or ""
    if response_text:sub(1, 4) == ")]}'" then
        response_text = response_text:sub(5)
    end
    local lines = {}
    for line in (response_text .. "\n"):gmatch("(.-)\n") do
        if line:gsub("%s+", "") ~= "" then
            lines[#lines + 1] = line
        end
    end

    local parsed = {}
    local index = 1
    while index <= #lines do
        local line = lines[index]:match("^%s*(.-)%s*$")
        if line:match("^%d+$") then
            index = index + 1
            if lines[index] then
                parsed[#parsed + 1] = Json.decode(lines[index])
            end
        else
            parsed[#parsed + 1] = Json.decode(line)
        end
        index = index + 1
    end
    return parsed
end

function Parsing.parse_batchexecute_response(response_text, rpc_id)
    for _, chunk in ipairs(chunks(response_text)) do
        for index = 1, chunk.n or #chunk do
            local item = chunk[index]
            if type(item) == "table" and item[1] == "wrb.fr" and item[2] == rpc_id then
                local error_info = item[6]
                if type(error_info) == "table" and type(error_info[1]) == "number" then
                    return nil, {
                        kind = "notebooklm_changed",
                        message = "NotebookLM RPC failed: " .. (ERROR_NAMES[error_info[1]] or "UNKNOWN"),
                        rpc_code = error_info[1],
                    }
                end
                if type(item[3]) == "string" then
                    return Json.decode(item[3])
                end
                return item[3]
            end
        end
    end
    return nil
end

local function source_status_name(code)
    return ({
        [1] = "processing",
        [2] = "ready",
        [3] = "error",
        [5] = "preparing",
    })[code] or "unknown"
end

local function source_type(source)
    local metadata = type(source) == "table" and source[3] or nil
    local source_type_code = type(metadata) == "table" and metadata[5] or nil
    if type(source_type_code) == "number" then
        return source_type_code
    end
    return nil
end

function Parsing.parse_sources_from_notebook(notebook_data)
    local sources_data = type(notebook_data) == "table" and notebook_data[2] or nil
    local sources = {}
    if type(sources_data) ~= "table" then
        return sources
    end
    for index = 1, sources_data.n or #sources_data do
        local source = sources_data[index]
        local source_id = type(source) == "table" and unwrap_first(source[1]) or nil
        if type(source_id) == "string" then
            local parsed = {
                id = source_id,
                title = type(source[2]) == "string" and source[2] or "Untitled",
            }
            local status_code = type(source[4]) == "table" and source[4][2] or nil
            if type(status_code) == "number" then
                parsed.status_code = status_code
                parsed.status = source_status_name(status_code)
            end
            local source_type_code = source_type(source)
            if source_type_code ~= nil then
                parsed.source_type = source_type_code
            end
            sources[#sources + 1] = parsed
        end
    end
    return sources
end

function Parsing.parse_sources_from_notebook_data(result)
    if type(result) == "table" and type(result[1]) == "table" then
        return Parsing.parse_sources_from_notebook(result[1])
    end
    return {}
end

function Parsing.parse_notebooks(result)
    local notebook_list = type(result) == "table" and type(result[1]) == "table" and result[1] or result
    local notebooks = {}
    if type(notebook_list) ~= "table" then
        return notebooks
    end
    for index = 1, notebook_list.n or #notebook_list do
        local item = notebook_list[index]
        if type(item) == "table" and type(item[3]) == "string" then
            local sources = Parsing.parse_sources_from_notebook(item)
            notebooks[#notebooks + 1] = {
                id = item[3],
                title = type(item[1]) == "string" and item[1] or "Untitled",
                source_count = #sources,
                sources = sources,
            }
        end
    end
    return notebooks
end

local function extract_cited_text(detail)
    local text_root = type(detail) == "table" and detail[5] or nil
    if type(text_root) ~= "table" then
        return nil
    end
    local texts = {}
    local function walk(value)
        if type(value) ~= "table" then
            return
        end
        if type(value[3]) == "string" then
            texts[#texts + 1] = value[3]
        end
        for index = 1, value.n or #value do
            walk(value[index])
        end
    end
    walk(text_root)
    return #texts > 0 and table.concat(texts, " ") or nil
end

local function extract_citations(type_info)
    local passages = type(type_info) == "table" and type_info[4] or nil
    if type(passages) ~= "table" then
        return {}
    end
    local citations = {}
    local sources_used = {}
    local source_seen = {}
    local references = {}
    for index = 1, passages.n or #passages do
        local passage = passages[index]
        local detail = type(passage) == "table" and passage[2] or nil
        local source_id = nested_get(detail, { 6, 1, 1, 1 })
        if type(source_id) == "string" then
            citations[tostring(index)] = source_id
            if not source_seen[source_id] then
                sources_used[#sources_used + 1] = source_id
                source_seen[source_id] = true
            end
            local reference = { source_id = source_id, citation_number = index }
            local cited_text = extract_cited_text(detail)
            if cited_text then
                reference.cited_text = cited_text
            end
            references[#references + 1] = reference
        end
    end
    if next(citations) == nil then
        return {}
    end
    return {
        sources_used = sources_used,
        citations = citations,
        references = references,
    }
end

function Parsing.parse_query_response(response_text)
    local longest_answer = ""
    local longest_thinking = ""
    local citation_data = {}
    local conversation_id = nil
    for _, chunk in ipairs(chunks(response_text)) do
        for index = 1, chunk.n or #chunk do
            local item = chunk[index]
            if type(item) == "table" and item[1] == "wrb.fr" and type(item[3]) == "string" then
                local inner = Json.decode(item[3])
                local first = type(inner) == "table" and inner[1] or nil
                if type(first) == "string" and #first > #longest_thinking then
                    longest_thinking = first
                elseif type(first) == "table" and type(first[1]) == "string" then
                    local type_info = first[5]
                    local is_answer = type(type_info) == "table" and type_info[type_info.n or #type_info] == 1
                    if is_answer and #first[1] > #longest_answer then
                        longest_answer = first[1]
                        citation_data = extract_citations(type_info)
                        conversation_id = type(first[3]) == "table" and first[3][1] or conversation_id
                    elseif #first[1] > #longest_thinking then
                        longest_thinking = first[1]
                    end
                end
            end
        end
    end
    local answer = longest_answer ~= "" and longest_answer or longest_thinking
    if answer == "" then
        return nil, { kind = "parse_error", message = "NotebookLM returned no answer text." }
    end
    return {
        answer = answer,
        citations = citation_data.citations or {},
        sources_used = citation_data.sources_used or {},
        references = citation_data.references or {},
        conversation_id = conversation_id,
    }
end

Parsing.Json = Json
Parsing.Rpc = Rpc
Parsing.is_null = is_null
Parsing.unwrap_first = unwrap_first

return Parsing
