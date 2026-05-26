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

    local path = document and document.file or nil
    local title = props.title or (path and path:match("([^/]+)$")) or "Unknown title"
    local author = props.authors or props.author
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
        doc_value.book_id = doc_value.book_id or book.book_id
        return doc_value
    end

    local fallback = self.settings:readSetting("book_" .. book.book_id)
    if type(fallback) == "table" then
        fallback.book_id = fallback.book_id or book.book_id
        return fallback
    end

    return nil
end

function Storage:save_link(ui, link)
    local book = self:get_book_context(ui)
    link = link or {}
    link.book_id = link.book_id or book.book_id
    link.title = link.title or book.title
    link.author = link.author or book.author
    link.path = link.path or book.path
    link.linked_at = link.linked_at or os.date("!%Y-%m-%dT%H:%M:%SZ")

    save_doc_setting(ui, "notebooklm_link", link)
    self.settings:saveSetting("book_" .. book.book_id, link)
    self.settings:flush()
    return link
end

function Storage:clear_link(ui)
    local book = self:get_book_context(ui)
    save_doc_setting(ui, "notebooklm_link", nil)
    self.settings:delSetting("book_" .. book.book_id)
    self.settings:flush()
end

return Storage
