#!/usr/bin/env python3
"""Exercise the KOReader plugin with lightweight Lua stubs.

This does not replace device/emulator testing. It catches broken `require`
paths, syntax errors, basic plugin initialization failures, and the main
link/upload/ask control flow without needing a runnable KOReader desktop build.
"""

from __future__ import annotations

from pathlib import Path

from lupa import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
PLUGIN_DIR = ROOT / "plugin" / "notebooklm.koplugin"


STUBS = r'''
local preload = package.preload

local function class()
    local cls = {}
    function cls:new(o)
        o = o or {}
        setmetatable(o, { __index = self })
        if o.init then o:init() end
        return o
    end
    function cls:extend(defaults)
        defaults = defaults or {}
        setmetatable(defaults, { __index = self })
        return defaults
    end
    return cls
end

preload["gettext"] = function()
    return function(text) return text end
end

preload["dispatcher"] = function()
    return {
        actions = {},
        registerAction = function(self, name, action)
            self.actions[name] = action
        end,
    }
end

preload["ui/event"] = function()
    return {
        new = function(_, name, data)
            return { name = name, data = data }
        end,
    }
end

preload["ui/widget/container/inputcontainer"] = function()
    local InputContainer = class()
    function InputContainer:new(o)
        o = o or {}
        setmetatable(o, { __index = self })
        return o
    end
    return InputContainer
end

preload["ui/network/manager"] = function()
    return {
        runWhenOnline = function(_, fn) return fn() end,
    }
end

preload["ui/uimanager"] = function()
    return {
        shown = {},
        show = function(self, widget)
            table.insert(self.shown, widget)
        end,
        close = function() end,
        scheduleIn = function(_, _, fn) return fn() end,
        broadcastEvent = function() end,
    }
end

preload["ui/widget/inputdialog"] = function()
    local InputDialog = class()
    function InputDialog:getInputText()
        return self.input or ""
    end
    return InputDialog
end

preload["ui/widget/confirmbox"] = function() return class() end
preload["ui/widget/infomessage"] = function() return class() end
preload["ui/widget/textviewer"] = function()
    return {
        last_opened = nil,
        openFile = function(path)
            package.loaded["ui/widget/textviewer"].last_opened = path
        end,
    }
end
preload["ui/font"] = function()
    return {
        getFace = function(_, name) return name end,
    }
end

preload["datastorage"] = function()
    return {
        getSettingsDir = function() return "/tmp" end,
        getDataDir = function() return "/tmp" end,
    }
end

preload["luasettings"] = function()
    local stores = {}
    return {
        open = function(path)
            stores[path] = stores[path] or {}
            local store = stores[path]
            return {
                readSetting = function(_, key, default)
                    local value = store[key]
                    if value == nil then return default end
                    return value
                end,
                saveSetting = function(_, key, value)
                    store[key] = value
                end,
                delSetting = function(_, key)
                    store[key] = nil
                end,
                flush = function() end,
            }
        end,
    }
end

preload["socket.http"] = function()
    _G.__http_requests = {}
    _G.__linked_book = nil
    _G.__force_network_error = false
    return {
        request = function(req)
            local url = req.url or ""
            local method = req.method or "GET"
            table.insert(_G.__http_requests, { method = method, url = url })

            if _G.__force_network_error then
                return nil, "network unreachable"
            end

            local body = "OK"
            local code = 200
            if url:find("/health", 1, true) then
                body = "HEALTH"
            elseif url:find("/notebooks", 1, true) and method == "GET" then
                body = "NOTEBOOKS"
            elseif url:find("/notebooks", 1, true) and method == "POST" then
                body = "CREATE_NOTEBOOK"
            elseif url:find("/books/link", 1, true) then
                _G.__linked_book = true
                body = "LINK_BOOK"
            elseif url:find("/books/", 1, true) then
                if _G.__linked_book then
                    body = "LINK_BOOK"
                else
                    body = "NOT_FOUND"
                    code = 404
                end
            elseif url:find("/sources/upload%-file", 1, false) then
                body = "UPLOAD_SOURCE"
            elseif url:find("/ask", 1, true) then
                body = "ASK"
            end

            if req.sink then
                req.sink(body)
            end
            return true, code, {}, code == 200 and "OK" or "Not Found"
        end,
    }
end

preload["ltn12"] = function()
    return {
        sink = {
            table = function(t)
                return function(chunk)
                    if chunk then table.insert(t, chunk) end
                    return 1
                end
            end,
        },
        source = {
            string = function(value)
                local done = false
                return function()
                    if done then return nil end
                    done = true
                    return value
                end
            end,
        },
    }
end

preload["socketutil"] = function()
    return {
        set_timeout = function() end,
        reset_timeout = function() end,
    }
end

preload["json"] = function()
    return {
        encode = function(value)
            _G.__last_encoded_value = value
            return "{}"
        end,
        decode = function(value)
            if value == "HEALTH" then
                return { ok = true, adapter = "mock" }
            elseif value == "NOTEBOOKS" then
                return {
                    ok = true,
                    notebooks = {
                        { id = "mock-notebook", title = "Mock Notebook", source_count = 1 },
                    },
                }
            elseif value == "CREATE_NOTEBOOK" then
                return {
                    ok = true,
                    notebook = { id = "created-notebook", title = "Created Notebook", source_count = 0 },
                    adapter = "mock",
                }
            elseif value == "LINK_BOOK" then
                return {
                    ok = true,
                    book = {
                        book_id = "book-stub",
                        notebook_id = "created-notebook",
                        notebook_title = "Created Notebook",
                        title = "Book",
                        author = "Author",
                        path = "/tmp/book.epub",
                        source_id = "uploaded-source",
                    },
                }
            elseif value == "UPLOAD_SOURCE" then
                return {
                    ok = true,
                    source_id = "uploaded-source",
                    title = "Book",
                    notebook_id = "created-notebook",
                    adapter = "mock",
                }
            elseif value == "ASK" then
                return {
                    ok = true,
                    answer = "Mock answer from bridge\n\n" .. string.rep("Long answer paragraph from bridge. ", 200),
                    notebook_id = "created-notebook",
                    adapter = "mock",
                    sources_used = { "source-1" },
                    citations = { ["1"] = "source-1" },
                    references = {
                        {
                            source_id = "source-1",
                            citation_number = 1,
                            cited_text = "Reference text from uploaded source",
                        },
                    },
                }
            end
            return { ok = true }
        end,
    }
end
'''


def main() -> None:
    Path("/tmp/book.epub").write_bytes(b"stub epub")
    Path("/tmp/notebooklm-last-answer.md").unlink(missing_ok=True)

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{PLUGIN_DIR}/?.lua;" .. package.path')
    lua.execute(STUBS)
    plugin = lua.execute(f'return dofile("{PLUGIN_DIR / "main.lua"}")')

    lua.globals().plugin = plugin
    lua.globals().plugin.path = str(PLUGIN_DIR)
    lua.execute(
        r'''
        local menu_registered = false
        local highlight_buttons = {}
        plugin.ui = {
            document = {
                file = "/tmp/book.epub",
                getProps = function()
                    return { title = "Book", authors = "Author" }
                end,
            },
            doc_settings = {
                readSetting = function(_, key)
                    if key == "percent_finished" then return 0.25 end
                    return nil
                end,
                saveSetting = function() end,
                delSetting = function() end,
            },
            menu = {
                registerToMainMenu = function()
                    menu_registered = true
                end,
            },
            highlight = {
                addToHighlightDialog = function(_, key, fn)
                    highlight_buttons[key] = fn
                end,
            },
        }
        plugin:init()
        assert(menu_registered, "plugin did not register to main menu")
        assert(highlight_buttons["notebooklm_ask"], "missing Ask NotebookLM highlight action")
        assert(highlight_buttons["notebooklm_explain_simple"], "missing prompt highlight action")
        local menu = {}
        plugin:addToMainMenu(menu)
        assert(menu.notebooklm, "missing NotebookLM tools menu")
        local settings_menu = menu.notebooklm.sub_item_table[4]
        assert(settings_menu and settings_menu.text == "Settings", "missing NotebookLM settings menu")
        assert(settings_menu.sub_item_table and #settings_menu.sub_item_table == 3, "settings menu does not expose expected settings")
        assert(settings_menu.sub_item_table[1].text_func():find("enabled", 1, true), "source upload menu did not show enabled state")
        settings_menu.sub_item_table[1].callback()
        assert(plugin.settings:read("enable_upload") == false, "source upload toggle did not disable upload")
        settings_menu.sub_item_table[1].callback()
        assert(plugin.settings:read("enable_upload") == true, "source upload toggle did not re-enable upload")
        assert(settings_menu.sub_item_table[2].text_func():find("multipart", 1, true), "upload mode menu did not show multipart mode")
        settings_menu.sub_item_table[2].callback()
        assert(plugin.settings:read("upload_mode") == "path", "upload mode toggle did not switch to path")
        settings_menu.sub_item_table[2].callback()
        assert(plugin.settings:read("upload_mode") == "multipart", "upload mode toggle did not switch back to multipart")
        settings_menu.sub_item_table[3].callback()
        assert(plugin.settings:read("show_prompt_buttons") == false, "prompt button toggle did not disable prompt buttons")
        settings_menu.sub_item_table[3].callback()
        assert(plugin.settings:read("show_prompt_buttons") == true, "prompt button toggle did not re-enable prompt buttons")

        local unlinked_item = highlight_buttons["notebooklm_ask"]({
            selected_text = { text = "Unlinked highlighted passage" },
        })
        assert(unlinked_item and unlinked_item.callback, "Ask NotebookLM highlight item did not render")
        unlinked_item.callback()
        assert(plugin.notebooklm_ui.input_dialog and plugin.notebooklm_ui.input_dialog.title == "NotebookLM setup", "unlinked highlight did not open setup")
        assert(plugin.notebooklm_ui.input_dialog.buttons[1][1].text == "Skip", "setup does not expose a skip action")
        plugin.notebooklm_ui:_close_input()

        plugin.notebooklm_ui:show_status()

        plugin.notebooklm_ui:show_notebook_picker("", nil)
        local picker = plugin.notebooklm_ui.input_dialog
        assert(picker and picker.buttons and picker.buttons[1] and picker.buttons[1][1], "notebook picker did not render")
        picker.buttons[1][1].callback()
        local existing_link = plugin.storage:get_link(plugin.ui)
        assert(existing_link and existing_link.notebook_id == "mock-notebook", "existing notebook link was not saved")

        plugin.notebooklm_ui:create_notebook("Created Notebook", true)
        local link = plugin.storage:get_link(plugin.ui)
        assert(link and link.notebook_id == "created-notebook", "book link was not saved")
        assert(link.source_id == "uploaded-source", "uploaded source id was not saved")

        plugin.settings:write("enable_upload", false)
        plugin.notebooklm_ui:show_setup()
        local setup_without_upload = plugin.notebooklm_ui.input_dialog
        assert(setup_without_upload and #setup_without_upload.buttons[2] == 2, "upload button was not hidden when upload is disabled")
        assert(setup_without_upload.buttons[2][1].text == "List", "setup list button is missing")
        assert(setup_without_upload.buttons[2][2].text == "Create", "setup create button is missing")
        plugin.notebooklm_ui:_close_input()
        plugin.notebooklm_ui:create_notebook("Disabled Upload", true)
        local uimanager_disabled = require("ui/uimanager")
        local disabled_upload_message = uimanager_disabled.shown[#uimanager_disabled.shown]
        assert(disabled_upload_message and disabled_upload_message.text and disabled_upload_message.text:find("Source upload is disabled", 1, true), "disabled upload error was not shown")
        plugin.settings:write("enable_upload", true)

        local prompt_item = highlight_buttons["notebooklm_explain_simple"]({
            selected_text = { text = "Prompt button selected text" },
        })
        assert(prompt_item and prompt_item.callback, "prompt highlight item did not render")
        prompt_item.callback()
        local prompt_payload = _G.__last_encoded_value
        assert(prompt_payload and prompt_payload.selected_text == "Prompt button selected text", "highlight prompt selected text was not sent")
        assert(prompt_payload.prompt == plugin.prompts.get("explain_simple").prompt, "highlight prompt preset was not sent")
        assert(prompt_payload.notebook_id == "created-notebook", "highlight prompt notebook id was not sent")
        assert(prompt_payload.book and prompt_payload.book.title == "Book", "highlight prompt book title was not sent")
        assert(prompt_payload.book and prompt_payload.book.position == "25.0%", "highlight prompt book position was not sent")

        plugin.notebooklm_ui:ask_with_prompt(
            "Highlighted passage",
            "Explain this passage simply.",
            "Explica simple"
        )
        local ask_payload = _G.__last_encoded_value
        assert(ask_payload and ask_payload.selected_text == "Highlighted passage", "ask selected text was not sent")
        assert(ask_payload.prompt == "Explain this passage simply.", "ask prompt was not sent")
        assert(ask_payload.book and ask_payload.book.author == "Author", "ask book author was not sent")
        local viewer = require("ui/widget/textviewer")
        assert(viewer.last_opened == "/tmp/notebooklm-last-answer.md", "answer viewer was not opened")
        local file = io.open(viewer.last_opened, "r")
        assert(file, "answer file was not written")
        local content = file:read("*all")
        file:close()
        assert(content:find("Mock answer from bridge", 1, true), "answer content is missing")
        assert(content:find("Highlighted passage", 1, true), "highlight content is missing")
        assert(content:find("## Sources used", 1, true), "sources used section is missing")
        assert(content:find("source%-1"), "source id is missing")
        assert(content:find("Reference text from uploaded source", 1, true), "cited text is missing")
        assert(content:find("## Citations", 1, true), "citations section is missing")

        plugin.notebooklm_ui:show_custom_question("Custom highlighted passage")
        local custom_dialog = plugin.notebooklm_ui.input_dialog
        assert(custom_dialog and custom_dialog.buttons[1][2], "custom question dialog did not render")
        custom_dialog.input = "Custom question about this passage"
        custom_dialog.buttons[1][2].callback()
        local custom_viewer = require("ui/widget/textviewer")
        local custom_file = io.open(custom_viewer.last_opened, "r")
        assert(custom_file, "custom answer file was not written")
        local custom_content = custom_file:read("*all")
        custom_file:close()
        assert(custom_content:find("Custom highlighted passage", 1, true), "custom highlight content is missing")
        assert(custom_content:find("Prompt: Custom", 1, true), "custom prompt label is missing")

        local long_passage = string.rep("Long highlighted passage. ", 200)
        plugin.notebooklm_ui:ask_with_prompt(
            long_passage,
            "Summarize this passage in three bullets.",
            "Tres bullets"
        )
        local long_viewer = require("ui/widget/textviewer")
        local long_file = io.open(long_viewer.last_opened, "r")
        assert(long_file, "long answer file was not written")
        local long_content = long_file:read("*all")
        long_file:close()
        assert(long_content:find("Long highlighted passage. Long highlighted passage.", 1, true), "long highlight content is missing")
        assert(long_content:find("Long answer paragraph from bridge. Long answer paragraph from bridge.", 1, true), "long answer content is missing")

        _G.__force_network_error = true
        plugin.notebooklm_ui:show_status()
        local uimanager = require("ui/uimanager")
        local last = uimanager.shown[#uimanager.shown]
        assert(last and last.text and last.text:find("network unreachable", 1, true), "offline bridge error was not surfaced")
        '''
    )
    print("plugin runtime smoke ok")


if __name__ == "__main__":
    main()
