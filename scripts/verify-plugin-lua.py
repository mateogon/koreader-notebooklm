#!/usr/bin/env python3
"""Load the KOReader plugin with lightweight Lua stubs.

This does not replace device/emulator testing. It catches broken `require`
paths, syntax errors, and basic plugin initialization failures without needing
a runnable KOReader desktop build.
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
    return {
        request = function()
            return true, 200, {}, "OK"
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
        encode = function() return "{}" end,
        decode = function() return { ok = true } end,
    }
end
'''


def main() -> None:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{PLUGIN_DIR}/?.lua;" .. package.path')
    lua.execute(STUBS)
    plugin = lua.execute(f'return dofile("{PLUGIN_DIR / "main.lua"}")')

    lua.globals().plugin = plugin
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
        '''
    )
    print("plugin runtime smoke ok")


if __name__ == "__main__":
    main()
