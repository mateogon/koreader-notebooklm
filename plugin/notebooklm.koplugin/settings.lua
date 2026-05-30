local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Settings = {
    file = DataStorage:getSettingsDir() .. "/notebooklm.lua",
    defaults = {
        direct_auth_bundle_path = "",
        direct_notebook_id = "",
        language = "en",
        timeout = 120,
        enable_upload = true,
        upload_mode = "multipart",
        show_prompt_buttons = true,
        open_answer_automatically = true,
    },
}

function Settings:open()
    local settings = LuaSettings:open(self.file)
    return setmetatable({ settings = settings }, { __index = self })
end

function Settings:read(key)
    local default = self.defaults[key]
    return self.settings:readSetting(key, default)
end

function Settings:write(key, value)
    self.settings:saveSetting(key, value)
    self.settings:flush()
end

function Settings:asTable()
    return {
        direct_auth_bundle_path = self:read("direct_auth_bundle_path"),
        direct_notebook_id = self:read("direct_notebook_id"),
        language = self:read("language"),
        timeout = self:read("timeout"),
        enable_upload = self:read("enable_upload"),
        upload_mode = self:read("upload_mode"),
        show_prompt_buttons = self:read("show_prompt_buttons"),
        open_answer_automatically = self:read("open_answer_automatically"),
    }
end

return Settings
