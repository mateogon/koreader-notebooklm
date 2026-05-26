local Event = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local NotebookLM = InputContainer:new{
    name = "notebooklm",
    is_doc_only = false,
}

local function load_plugin_module(plugin, filename)
    return dofile(plugin.path .. "/" .. filename)
end

function NotebookLM:onDispatcherRegisterActions()
    local Dispatcher = require("dispatcher")
    Dispatcher:registerAction("notebooklm_status", {
        category = "none",
        event = "NotebookLMStatus",
        title = _("NotebookLM status"),
        general = true,
    })
    Dispatcher:registerAction("notebooklm_setup_book", {
        category = "none",
        event = "NotebookLMSetupBook",
        title = _("NotebookLM setup book"),
        general = true,
    })
end

function NotebookLM:init()
    local Client = load_plugin_module(self, "client.lua")
    local Http = load_plugin_module(self, "http.lua")
    local NotebookLMUI = load_plugin_module(self, "ui.lua")
    local Prompts = load_plugin_module(self, "prompts.lua")
    local Settings = load_plugin_module(self, "settings.lua")
    local Storage = load_plugin_module(self, "storage.lua")

    self.settings = Settings:open()
    self.storage = Storage:open()
    self.prompts = Prompts
    self.client = Client:new(self.settings, Http)
    self.notebooklm_ui = NotebookLMUI:new{
        plugin = self,
        client = self.client,
        storage = self.storage,
        settings = self.settings,
        prompts = self.prompts,
    }

    self:onDispatcherRegisterActions()

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    if self.ui and self.ui.highlight and self.ui.document then
        self.ui.highlight:addToHighlightDialog("notebooklm_ask", function(reader_highlight)
            return {
                text = _("Ask NotebookLM"),
                enabled = true,
                callback = function()
                    local selected_text = reader_highlight
                        and reader_highlight.selected_text
                        and reader_highlight.selected_text.text
                    NetworkMgr:runWhenOnline(function()
                        self.notebooklm_ui:ask_highlight(selected_text)
                    end)
                end,
                hold_callback = function()
                    self.notebooklm_ui:show_status()
                end,
            }
        end)

        if self.settings:read("show_prompt_buttons") then
            for _, prompt in ipairs(self.prompts.presets) do
                local prompt_config = prompt
                self.ui.highlight:addToHighlightDialog("notebooklm_" .. prompt_config.id, function(reader_highlight)
                    return {
                        text = prompt_config.label .. " (NotebookLM)",
                        enabled = true,
                        callback = function()
                            local selected_text = reader_highlight
                                and reader_highlight.selected_text
                                and reader_highlight.selected_text.text
                            NetworkMgr:runWhenOnline(function()
                                self.notebooklm_ui:ask_with_prompt(selected_text, prompt_config.prompt, prompt_config.label)
                            end)
                        end,
                    }
                end)
            end
        end
    end
end

function NotebookLM:addToMainMenu(menu_items)
    menu_items.notebooklm = {
        text = _("NotebookLM"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Current book setup"),
                enabled = not not (self.ui and self.ui.document),
                callback = function()
                    self.notebooklm_ui:show_setup()
                end,
            },
            {
                text = _("Status"),
                callback = function()
                    self.notebooklm_ui:show_status()
                end,
            },
            {
                text_func = function()
                    return _("Bridge URL: ") .. tostring(self.settings:read("bridge_url"))
                end,
                callback = function()
                    self:showBridgeUrlDialog()
                end,
            },
        },
    }
end

function NotebookLM:showBridgeUrlDialog()
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("NotebookLM bridge URL"),
        input_hint = _("http://127.0.0.1:8765"),
        input_type = "text",
        input = self.settings:read("bridge_url"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local url = input_dialog:getInputText()
                        if url and url ~= "" then
                            self.settings:write("bridge_url", url)
                        end
                        UIManager:close(input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
end

function NotebookLM:onNotebookLMStatus()
    self.notebooklm_ui:show_status()
end

function NotebookLM:onNotebookLMSetupBook()
    self.notebooklm_ui:show_setup()
end

function NotebookLM:onFlushSettings()
    if self.settings and self.settings.settings then
        self.settings.settings:flush()
    end
    if self.storage and self.storage.settings then
        self.storage.settings:flush()
    end
end

function NotebookLM:onCloseDocument()
    UIManager:broadcastEvent(Event:new("FlushSettings"))
end

return NotebookLM
