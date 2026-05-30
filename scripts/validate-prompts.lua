local path = arg and arg[1]
if not path or path == "" then
    io.stderr:write("usage: validate-prompts.lua <notebooklm-prompts.lua>\n")
    os.exit(2)
end

local supported_languages = {
    en = true,
    es = true,
}

local errors = {}

local function add_error(message)
    table.insert(errors, message)
end

local function is_non_empty_string(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

local function validate_common(prefix, entry)
    if type(entry.enabled) ~= "nil" and type(entry.enabled) ~= "boolean" then
        add_error(prefix .. ".enabled must be boolean or nil")
    end
    if type(entry.order) ~= "nil" and type(entry.order) ~= "number" then
        add_error(prefix .. ".order must be number or nil")
    end
    if type(entry.language) ~= "nil" then
        if type(entry.language) ~= "string" or not supported_languages[entry.language] then
            add_error(prefix .. ".language must be one of: en, es")
        end
    end
end

local chunk, load_error = loadfile(path)
if not chunk then
    io.stderr:write("invalid prompt config: " .. tostring(load_error) .. "\n")
    os.exit(1)
end

local ok, config = pcall(chunk)
if not ok then
    io.stderr:write("prompt config failed while loading: " .. tostring(config) .. "\n")
    os.exit(1)
end

if type(config) ~= "table" then
    io.stderr:write("prompt config must return a table\n")
    os.exit(1)
end

if type(config.version) ~= "nil" and type(config.version) ~= "number" then
    add_error("version must be number or nil")
end

if type(config.overrides) ~= "nil" then
    if type(config.overrides) ~= "table" then
        add_error("overrides must be a table or nil")
    else
        for id, entry in pairs(config.overrides) do
            local prefix = "overrides." .. tostring(id)
            if not is_non_empty_string(id) then
                add_error(prefix .. " key must be a non-empty string")
            end
            if type(entry) ~= "table" then
                add_error(prefix .. " must be a table")
            else
                validate_common(prefix, entry)
                if type(entry.label) ~= "nil" and not is_non_empty_string(entry.label) then
                    add_error(prefix .. ".label must be a non-empty string when set")
                end
                if type(entry.prompt) ~= "nil" and not is_non_empty_string(entry.prompt) then
                    add_error(prefix .. ".prompt must be a non-empty string when set")
                end
            end
        end
    end
end

if type(config.custom) ~= "nil" then
    if type(config.custom) ~= "table" then
        add_error("custom must be a table or nil")
    else
        local seen = {}
        for index, entry in ipairs(config.custom) do
            local prefix = "custom[" .. tostring(index) .. "]"
            if type(entry) ~= "table" then
                add_error(prefix .. " must be a table")
            else
                validate_common(prefix, entry)
                if not is_non_empty_string(entry.id) then
                    add_error(prefix .. ".id must be a non-empty string")
                elseif seen[entry.id] then
                    add_error(prefix .. ".id duplicates an earlier custom prompt: " .. entry.id)
                else
                    seen[entry.id] = true
                end
                if not is_non_empty_string(entry.label) then
                    add_error(prefix .. ".label must be a non-empty string")
                end
                if not is_non_empty_string(entry.prompt) then
                    add_error(prefix .. ".prompt must be a non-empty string")
                end
            end
        end
    end
end

if #errors > 0 then
    io.stderr:write("invalid prompt config:\n")
    for _, message in ipairs(errors) do
        io.stderr:write("- " .. message .. "\n")
    end
    os.exit(1)
end

print("Prompt config OK: " .. path)
