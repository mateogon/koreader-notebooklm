local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Storage = {
    settings_file = DataStorage:getSettingsDir() .. "/notebooklm-books.lua",
}

local function djb2(value)
    local hash = 5381
    for i = 1, #value do
        hash = (hash * 33 + string.byte(value, i)) % 4294967296
    end
    return string.format("%08x", hash)
end

local function string_value(value)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        return value
    end
    if type(value) == "number" or type(value) == "boolean" then
        return tostring(value)
    end
    if type(value) == "table" then
        local parts = {}
        for _, item in ipairs(value) do
            local text = string_value(item)
            if text and text ~= "" then
                table.insert(parts, text)
            end
        end
        if #parts > 0 then
            return table.concat(parts, ", ")
        end
    end
    return nil
end

local function now_iso()
    local ok, value = pcall(os.date, "!%Y-%m-%dT%H:%M:%SZ")
    if ok then
        return string_value(value)
    end
    return nil
end

local function read_doc_setting(ui, key)
    if ui and ui.doc_settings and ui.doc_settings.readSetting then
        local ok, value = pcall(function()
            return ui.doc_settings:readSetting(key)
        end)
        if ok then
            return value
        end
    end
    return nil
end

local function save_doc_setting(ui, key, value)
    if value == nil and ui and ui.doc_settings and ui.doc_settings.delSetting then
        local ok = pcall(function()
            ui.doc_settings:delSetting(key)
        end)
        return ok
    end
    if ui and ui.doc_settings and ui.doc_settings.saveSetting then
        local ok = pcall(function()
            ui.doc_settings:saveSetting(key, value)
        end)
        return ok
    end
    return false
end

local function normalize_link(book, link)
    if type(link) ~= "table" then
        return nil
    end
    return {
        book_id = string_value(link.book_id) or book.book_id,
        notebook_id = string_value(link.notebook_id),
        notebook_title = string_value(link.notebook_title),
        title = string_value(link.title) or book.title,
        author = string_value(link.author) or book.author,
        path = string_value(link.path) or book.path,
        source_id = string_value(link.source_id),
        linked_at = string_value(link.linked_at) or now_iso(),
    }
end

function Storage:open()
    local settings = LuaSettings:open(self.settings_file)
    return setmetatable({ settings = settings }, { __index = self })
end

function Storage:get_book_context(ui)
    local document = ui and ui.document
    local props = {}
    if document and document.getProps then
        local ok, result = pcall(function()
            return document:getProps()
        end)
        if ok and type(result) == "table" then
            props = result
        end
    end

    local path = string_value(document and document.file)
    local title = string_value(props.title) or (path and path:match("([^/]+)$")) or "Unknown title"
    local author = string_value(props.authors) or string_value(props.author)
    local position = nil

    if ui and ui.doc_settings then
        local percent = read_doc_setting(ui, "percent_finished")
        if type(percent) == "number" then
            position = string.format("%.1f%%", percent * 100)
        end
    end

    local stable_basis = table.concat({
        path or "",
        title or "",
        author or "",
    }, "|")

    return {
        book_id = "book-" .. djb2(stable_basis),
        title = title,
        author = author,
        path = path,
        position = position,
    }
end

function Storage:get_link(ui)
    local book = self:get_book_context(ui)
    local doc_value = read_doc_setting(ui, "notebooklm_link")
    if type(doc_value) == "table" then
        return normalize_link(book, doc_value)
    end

    local fallback = self.settings:readSetting("book_" .. book.book_id)
    if type(fallback) == "table" then
        return normalize_link(book, fallback)
    end

    return nil
end

function Storage:save_link(ui, link)
    local book = self:get_book_context(ui)
    local saved = normalize_link(book, link or {}) or {
        book_id = book.book_id,
        title = book.title,
        author = book.author,
        path = book.path,
        linked_at = now_iso(),
    }

    save_doc_setting(ui, "notebooklm_link", saved)
    self.settings:saveSetting("book_" .. book.book_id, saved)
    self.settings:flush()
    return saved
end

function Storage:clear_link(ui)
    local book = self:get_book_context(ui)
    save_doc_setting(ui, "notebooklm_link", nil)
    self.settings:delSetting("book_" .. book.book_id)
    self.settings:flush()
end

return Storage
