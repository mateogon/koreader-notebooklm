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

local function enabled_label(value)
    return value and _("enabled") or _("disabled")
end

function NotebookLM:_language()
    return self.prompts.normalize_language(self.settings:read("language"))
end

function NotebookLM:_t(key)
    return self.prompts.text(self:_language(), key)
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
    self.client = Client:new(self.settings, Http, { plugin_path = self.path })
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
        self.ui.highlight:addToHighlightDialog("notebooklm", function(reader_highlight)
            return {
                text = _("NotebookLM"),
                enabled = true,
                callback = function()
                    local selected_text = reader_highlight
                        and reader_highlight.selected_text
                        and reader_highlight.selected_text.text
                    NetworkMgr:runWhenOnline(function()
                        self.notebooklm_ui:show_highlight_menu(selected_text)
                    end)
                end,
                hold_callback = function()
                    self.notebooklm_ui:show_status()
                end,
            }
        end)
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
                text = _("Answers"),
                callback = function()
                    self.notebooklm_ui:show_answers()
                end,
            },
            {
                text = _("Status"),
                callback = function()
                    self.notebooklm_ui:show_status()
                end,
            },
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text_func = function()
                            return self:_t("language") .. ": " .. self.prompts.language_label(self:_language())
                        end,
                        callback = function()
                            self:toggleLanguage()
                        end,
                    },
                    {
                        text_func = function()
                            local path = tostring(self.settings:read("direct_auth_bundle_path") or "")
                            if path == "" then
                                path = _("not set")
                            end
                            return _("Lua direct auth bundle: ") .. path
                        end,
                        callback = function()
                            self:showLuaDirectAuthBundleDialog()
                        end,
                    },
                    {
                        text_func = function()
                            local notebook_id = tostring(self.settings:read("direct_notebook_id") or "")
                            if notebook_id == "" then
                                notebook_id = _("auto")
                            end
                            return _("Lua direct notebook: ") .. notebook_id
                        end,
                        callback = function()
                            self:showLuaDirectNotebookDialog()
                        end,
                    },
                    {
                        text = _("Lua direct smoke"),
                        callback = function()
                            self:runLuaDirectSmoke()
                        end,
                    },
                    {
                        text_func = function()
                            return _("Source upload: ") .. enabled_label(self.settings:read("enable_upload"))
                        end,
                        callback = function()
                            self:toggleSourceUpload()
                        end,
                    },
                    {
                        text_func = function()
                            return _("Upload mode: ") .. tostring(self.settings:read("upload_mode"))
                        end,
                        callback = function()
                            self:toggleUploadMode()
                        end,
                    },
                    {
                        text_func = function()
                            return _("Open answers automatically: ") .. enabled_label(self.settings:read("open_answer_automatically"))
                        end,
                        callback = function()
                            self:toggleOpenAnswerAutomatically()
                        end,
                    },
                },
            },
        },
    }
end

local function show_notice(text, timeout)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        icon = "notice-info",
        text = tostring(text),
        timeout = timeout or 5,
    })
end

local function show_error(text)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        icon = "notice-warning",
        text = tostring(text),
        timeout = 8,
    })
end

function NotebookLM:showLuaDirectAuthBundleDialog()
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Lua direct auth bundle"),
        input_hint = _("/path/to/auth-bundle.json"),
        input_type = "text",
        input = self.settings:read("direct_auth_bundle_path"),
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
                        self.settings:write("direct_auth_bundle_path", input_dialog:getInputText() or "")
                        UIManager:close(input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
end

function NotebookLM:showLuaDirectNotebookDialog()
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Lua direct notebook ID"),
        input_hint = _("Notebook ID, or blank for linked/first notebook"),
        input_type = "text",
        input = self.settings:read("direct_notebook_id"),
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
                        self.settings:write("direct_notebook_id", input_dialog:getInputText() or "")
                        UIManager:close(input_dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(input_dialog)
end

function NotebookLM:toggleLanguage()
    local current = self:_language()
    local next_language = current == "en" and "es" or "en"
    self.settings:write("language", next_language)
    show_notice(self:_t("language") .. ": " .. self.prompts.language_label(next_language))
end

function NotebookLM:runLuaDirectSmoke()
    local ok_client, DirectClient = pcall(function()
        return require("direct.client")
    end)
    if not ok_client then
        show_error("Could not load Lua direct client: " .. tostring(DirectClient))
        return
    end

    show_notice("NotebookLM Lua direct smoke started.", 2)
    local direct = DirectClient:new(self.settings)
    local notebooks, list_err = direct:list_notebooks()
    if not notebooks then
        show_error("Lua direct list_notebooks failed: " .. tostring(list_err))
        return
    end

    local link = self.storage and self.storage:get_link(self.ui) or nil
    local notebook_id = self.settings:read("direct_notebook_id")
    if not notebook_id or notebook_id == "" then
        notebook_id = link and link.notebook_id or nil
    end
    if (not notebook_id or notebook_id == "") and notebooks.notebooks and notebooks.notebooks[1] then
        notebook_id = notebooks.notebooks[1].id
    end
    if not notebook_id or notebook_id == "" then
        show_error("Lua direct smoke found no NotebookLM notebook.")
        return
    end

    local notebook, notebook_err = direct:get_notebook(notebook_id)
    if not notebook then
        show_error("Lua direct get_notebook failed: " .. tostring(notebook_err))
        return
    end

    local book = self.storage:get_book_context(self.ui)
    local answer, ask_err = direct:ask{
        notebook_id = notebook_id,
        selected_text = "KOReader NotebookLM Lua direct smoke.",
        prompt = "Reply with one short sentence about this phrase.",
        book = {
            title = book.title,
            author = book.author,
            position = book.position,
        },
    }
    if not answer then
        show_error("Lua direct ask failed: " .. tostring(ask_err))
        return
    end

    local ConfirmBox = require("ui/widget/confirmbox")
    local Font = require("ui/font")
    UIManager:show(ConfirmBox:new{
        icon = "notice-info",
        face = Font:getFace("smallinfofont"),
        text = table.concat({
            "NotebookLM Lua direct smoke OK",
            "",
            "Notebooks: " .. tostring(#(notebooks.notebooks or {})),
            "Notebook ID: " .. tostring(notebook_id),
            "Sources: " .. tostring(#(notebook.sources or {})),
            "Conversation ID: " .. tostring(answer.conversation_id or ""),
            "",
            tostring(answer.answer or ""):sub(1, 900),
        }, "\n"),
        ok_text = _("Close"),
    })
end

function NotebookLM:toggleSourceUpload()
    self.settings:write("enable_upload", not self.settings:read("enable_upload"))
end

function NotebookLM:toggleUploadMode()
    local current = self.settings:read("upload_mode")
    self.settings:write("upload_mode", current == "path" and "multipart" or "path")
end

function NotebookLM:toggleOpenAnswerAutomatically()
    self.settings:write("open_answer_automatically", not self.settings:read("open_answer_automatically"))
end

function NotebookLM:togglePromptButtons()
    self.settings:write("show_prompt_buttons", not self.settings:read("show_prompt_buttons"))
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
