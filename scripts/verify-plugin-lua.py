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

preload["logger"] = function()
    return {
        info = function() end,
        warn = function() end,
        dbg = function() end,
    }
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
        looper = {
            add_callback = function(_, fn)
                local co = coroutine.create(fn)
                local ok, yielded = coroutine.resume(co)
                assert(ok, yielded)
                if coroutine.status(co) == "suspended" then
                    local ok_resume, err = coroutine.resume(co, yielded)
                    assert(ok_resume, err)
                end
            end,
        },
        initLooper = function(self)
            return self.looper
        end,
        setInputTimeout = function() end,
        resetInputTimeout = function() end,
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
preload["ui/widget/buttondialog"] = function() return class() end
preload["ui/widget/infomessage"] = function() return class() end
preload["ui/widget/textviewer"] = function()
    local TextViewer = class()
    TextViewer.last_opened = nil
    TextViewer.last_viewer = nil
    function TextViewer:new(o)
        o = o or {}
        setmetatable(o, { __index = self })
        self.last_viewer = o
        if o.notebooklm_path then
            self.last_opened = o.notebooklm_path
        end
        return o
    end
    function TextViewer.openFile(path)
        package.loaded["ui/widget/textviewer"].last_opened = path
    end
    function TextViewer:onSwipe()
        return "original-swipe"
    end
    return TextViewer
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
    _G.__multipart_upload_seen = false
    _G.__path_upload_seen = false
    _G.__last_path_upload_payload = nil
    _G.__last_request_body = nil
    _G.__last_multipart_body = nil
    return {
        request = function(req)
            local url = req.url or ""
            local method = req.method or "GET"
            table.insert(_G.__http_requests, { method = method, url = url })

            if req.source then
                local chunks = {}
                while true do
                    local chunk = req.source()
                    if chunk == nil then break end
                    table.insert(chunks, chunk)
                end
                _G.__last_request_body = table.concat(chunks)
            end

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
            elseif url:find("/books/", 1, true) and method == "DELETE" then
                _G.__linked_book = false
                body = "OK"
            elseif url:find("/books/", 1, true) then
                if _G.__linked_book then
                    body = "LINK_BOOK"
                else
                    body = "NOT_FOUND"
                    code = 404
                end
            elseif url:find("/sources/upload%-file", 1, false) then
                _G.__multipart_upload_seen = true
                _G.__last_multipart_body = _G.__last_request_body
                body = "UPLOAD_SOURCE"
            elseif url:find("/sources/upload", 1, true) then
                _G.__path_upload_seen = true
                _G.__last_path_upload_payload = _G.__last_encoded_value
                body = "UPLOAD_SOURCE"
            elseif url:find("/ask/jobs/", 1, true) and method == "GET" then
                body = "ASK_JOB_DONE"
            elseif url:find("/ask/jobs", 1, true) and method == "POST" then
                body = "ASK_JOB"
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

preload["ssl.https"] = function()
    _G.__direct_requests = {}
    _G.__direct_upload_started = false
    _G.__direct_upload_finalized = false
    local function read_fixture(name)
        local path = _G.nlm_lite_fixture_dir .. "/" .. name
        local file = assert(io.open(path, "r"), "missing fixture: " .. path)
        local body = file:read("*all")
        file:close()
        return body
    end
    return {
        request = function(req)
            local chunks = {}
            if req.source then
                while true do
                    local chunk = req.source()
                    if chunk == nil then break end
                    table.insert(chunks, chunk)
                end
            end
            local body = table.concat(chunks)
            table.insert(_G.__direct_requests, {
                method = req.method,
                url = req.url,
                headers = req.headers,
                body = body,
            })

            local response = "OK"
            if req.url:find("rpcids=wXbhsf", 1, true) then
                response = read_fixture("notebook_list_response.fixture")
            elseif req.url:find("rpcids=rLM1Ne", 1, true) then
                if _G.__direct_upload_finalized then
                    response = ")]}'\n0\n[[\"wrb.fr\",\"rLM1Ne\",\"[[\\\"Direct Created\\\",[[[\\\"src-direct-upload\\\"],\\\"Direct Source\\\",null,[null,2]]],\\\"created-direct\\\"]]\",null,null,null]]"
                else
                    response = read_fixture("get_notebook_response.fixture")
                end
            elseif req.url:find("rpcids=CCqFvf", 1, true) then
                response = ")]}'\n0\n[[\"wrb.fr\",\"CCqFvf\",\"[\\\"Direct Created\\\",null,\\\"created-direct\\\"]\",null,null,null]]"
            elseif req.url:find("rpcids=o4cbdc", 1, true) then
                response = ")]}'\n0\n[[\"wrb.fr\",\"o4cbdc\",\"[[[\\\"src-direct-upload\\\"]]]\",null,null,null]]"
            elseif req.url:find("/upload/_/?authuser=0", 1, true) then
                _G.__direct_upload_started = true
                response = ""
                if req.sink then
                    req.sink(response)
                end
                return true, 200, { ["x-goog-upload-url"] = "https://upload.test/session" }, "OK"
            elseif req.url == "https://upload.test/session" then
                _G.__direct_upload_finalized = true
                response = ""
            elseif req.url:find("GenerateFreeFormStreamed", 1, true) then
                response = read_fixture("query_response.fixture")
            end
            if req.sink then
                req.sink(response)
            end
            return true, 200, {}, "OK"
        end,
    }
end

preload["turbo"] = function()
    return { log = { categories = { success = true, warning = true } } }
end

preload["httpclient"] = function()
    local function read_fixture(name)
        local path = _G.nlm_lite_fixture_dir .. "/" .. name
        local file = assert(io.open(path, "r"), "missing fixture: " .. path)
        local body = file:read("*all")
        file:close()
        return body
    end
    local HTTPClient = {}
    function HTTPClient:new()
        return setmetatable({}, { __index = self })
    end
    function HTTPClient:request(request, callback)
        local headers = {}
        if request.on_headers then
            request.on_headers({
                add = function(_, key, value)
                    headers[key] = value
                end,
            })
        end
        table.insert(_G.__direct_requests, {
            method = request.method,
            url = request.url,
            headers = headers,
            body = request.body,
        })
        local response = "OK"
        if request.url:find("rpcids=wXbhsf", 1, true) then
            response = read_fixture("notebook_list_response.fixture")
        elseif request.url:find("rpcids=rLM1Ne", 1, true) then
            response = read_fixture("get_notebook_response.fixture")
        elseif request.url:find("GenerateFreeFormStreamed", 1, true) then
            response = read_fixture("query_response.fixture")
        end
        callback({ code = 200, body = response })
    end
    return HTTPClient
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
                    conversation_id = "mock-conversation",
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
            elseif value == "ASK_JOB" then
                return {
                    ok = true,
                    job_id = "mock-ask-job",
                    status = "queued",
                }
            elseif value == "ASK_JOB_DONE" then
                return {
                    ok = true,
                    job_id = "mock-ask-job",
                    status = "succeeded",
                    result = {
                        ok = true,
                        answer = "Mock answer from bridge\n\n" .. string.rep("Long answer paragraph from bridge. ", 200),
                        notebook_id = "created-notebook",
                        adapter = "mock",
                        conversation_id = "mock-conversation",
                        sources_used = { "source-1" },
                        citations = { ["1"] = "source-1" },
                        references = {
                            {
                                source_id = "source-1",
                                citation_number = 1,
                                cited_text = "Reference text from uploaded source",
                            },
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
    Path("/tmp/book.pdf").write_bytes(b"%PDF-1.4\nstub pdf\n")
    Path("/tmp/notebooklm-direct-auth-bundle.json").write_text(
        '{"base_url":"https://notebooklm.google.com","cookies":{"SID":"fake"},"csrf_token":"csrf-token","session_id":"session-id","build_label":"build-label"}',
        encoding="utf-8",
    )
    Path("/tmp/notebooklm-last-answer.md").unlink(missing_ok=True)
    Path("/tmp/notebooklm-prompts.lua").unlink(missing_ok=True)
    for answer_file in Path("/tmp").glob("notebooklm-answer-*.md"):
        answer_file.unlink(missing_ok=True)

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{PLUGIN_DIR}/?.lua;" .. package.path')
    lua.execute(STUBS)
    lua.globals().nlm_lite_fixture_dir = str(ROOT / "bridge" / "tests" / "fixtures" / "nlm_lite")
    lua.execute(
        r'''
        local Json = require("direct.codec")
        local Rpc = require("direct.rpc")
        local Parsing = require("direct.parsing")
        local AuthBundle = require("direct.auth_bundle")
        local Transport = require("direct.transport")
        local DirectClient = require("direct.client")
        local SourceExport = require("source_export")
        local SourceExportCRE = require("source_export_cre")
        local Prompts = require("prompts")

        local function read_fixture(name)
            local path = nlm_lite_fixture_dir .. "/" .. name
            local file = assert(io.open(path, "r"), "missing fixture: " .. path)
            local body = file:read("*all")
            file:close()
            return body
        end

        local function url_decode(value)
            value = tostring(value or ""):gsub("+", " ")
            return (value:gsub("%%(%x%x)", function(hex)
                return string.char(tonumber(hex, 16))
            end))
        end

        local function form_values(body)
            local values = {}
            for key, value in tostring(body):gmatch("([^=&]+)=([^&]*)&?") do
                values[url_decode(key)] = url_decode(value)
            end
            return values
        end

        local function decode_rpc_body(body)
            local values = form_values(body)
            local f_req = Json.decode(values["f.req"])
            local call = f_req[1][1]
            return call[1], Json.decode(call[2]), call[3], call[4], values
        end

        local prompt_config_path = "/tmp/notebooklm-prompts.lua"
        os.remove(prompt_config_path)
        assert(Prompts.config_path() == prompt_config_path, "prompt config path should use KOReader settings dir")
        assert(#Prompts.all("es") == 5, "Spanish defaults should load without user prompt config")
        assert(Prompts.get("why_matters", "es") ~= nil, "Spanish default prompt missing")

        local function write_prompt_config(body)
            local file = assert(io.open(prompt_config_path, "w"))
            file:write(body)
            file:close()
        end

        write_prompt_config([[
return {
    version = 1,
    overrides = {
        explain_simple = {
            label = "Simple mio",
            prompt = "Explica esto con mi estilo.",
            enabled = true,
            order = 5,
        },
        why_matters = {
            enabled = false,
        },
    },
    custom = {
        {
            id = "connect_to_book",
            label = "Conecta con libro",
            language = "es",
            enabled = true,
            order = 15,
            prompt = "Conecta este pasaje con el argumento general del libro.",
        },
        {
            id = "connect_to_book",
            label = "Duplicado",
            language = "es",
            enabled = true,
            order = 16,
            prompt = "Este duplicado no debe aparecer.",
        },
        {
            id = "english_only",
            label = "English only",
            language = "en",
            enabled = true,
            order = 17,
            prompt = "Only show this in English.",
        },
    },
}
]])
        local merged_prompts = Prompts.all("es")
        assert(Prompts.get("explain_simple", "es").label == "Simple mio", "prompt override label did not apply")
        assert(Prompts.get("explain_simple", "es").prompt == "Explica esto con mi estilo.", "prompt override body did not apply")
        assert(Prompts.get("why_matters", "es") == nil, "disabled default prompt should not be shown")
        assert(Prompts.get("connect_to_book", "es").label == "Conecta con libro", "custom Spanish prompt did not load")
        assert(Prompts.get("english_only", "es") == nil, "custom prompt for another language should not show")
        assert(Prompts.get("english_only", "en") ~= nil, "custom English prompt should show in English")
        local duplicate_count = 0
        for _, prompt in ipairs(merged_prompts) do
            if prompt.id == "connect_to_book" then
                duplicate_count = duplicate_count + 1
            end
        end
        assert(duplicate_count == 1, "duplicate custom prompt IDs should keep only first valid entry")
        assert(merged_prompts[1].id == "explain_simple", "prompt order override was not deterministic")

        write_prompt_config("return {")
        assert(#Prompts.all("es") == 5, "invalid prompt config should fall back to defaults")
        assert(Prompts.get("why_matters", "es") ~= nil, "invalid prompt config should not keep stale disabled prompts")
        assert(Prompts.config_error() ~= nil, "invalid prompt config should expose a short error")
        os.remove(prompt_config_path)

        local auth = assert(AuthBundle.load("/tmp/notebooklm-direct-auth-bundle.json"))
        assert(auth.base_url == "https://notebooklm.google.com", "auth bundle base_url did not load")
        assert(auth.csrf_token == "csrf-token", "auth bundle csrf_token did not load")
        local filtered_cookie_auth = {
            cookies = {
                { name = "SID", value = "google", domain = ".google.com" },
                { name = "OSID", value = "notebooklm", domain = "notebooklm.google.com" },
                { name = "ACCOUNT_CHOOSER", value = "accounts", domain = "accounts.google.com" },
                { name = "SID", value = "youtube", domain = ".youtube.com" },
            },
        }
        local filtered_cookie_header = AuthBundle.cookie_header(filtered_cookie_auth)
        assert(filtered_cookie_header:find("SID=google", 1, true), "google.com cookie was not sent")
        assert(filtered_cookie_header:find("OSID=notebooklm", 1, true), "notebooklm host cookie was not sent")
        assert(not filtered_cookie_header:find("ACCOUNT_CHOOSER", 1, true), "accounts.google.com cookie leaked into NotebookLM request")
        assert(not filtered_cookie_header:find("SID=youtube", 1, true), "youtube cookie leaked into NotebookLM request")

        local rpc_id, params, null_value, mode, values = decode_rpc_body(
            Rpc.build_batchexecute_body(Rpc.RPC_LIST_NOTEBOOKS, Rpc.params_list_notebooks(), "csrf-token")
        )
        assert(rpc_id == Rpc.RPC_LIST_NOTEBOOKS, "list notebooks rpc id changed")
        assert(params[1] == Json.null and params[2] == 1 and params[3] == Json.null and params[4][1] == 2, "list notebooks params changed")
        assert(null_value == Json.null, "batchexecute placeholder was not null")
        assert(mode == "generic", "batchexecute mode changed")
        assert(values["at"] == "csrf-token", "csrf token was not encoded in batchexecute body")
        local list_url = Rpc.build_batchexecute_url("https://notebooklm.google.com", Rpc.RPC_LIST_NOTEBOOKS, {
            build_label = "build-label",
            session_id = "session-id",
        })
        assert(list_url:find("/_/LabsTailwindUi/data/batchexecute?", 1, true), "batchexecute URL path changed")
        assert(list_url:find("rpcids=wXbhsf", 1, true), "batchexecute URL missing list rpc id")
        assert(list_url:find("source%-path=%%2F"), "batchexecute URL missing escaped root source path")
        assert(list_url:find("bl=build%-label"), "batchexecute URL missing build label")
        assert(list_url:find("f%.sid=session%-id"), "batchexecute URL missing session id")

        rpc_id, params = decode_rpc_body(
            Rpc.build_batchexecute_body(Rpc.RPC_GET_NOTEBOOK, Rpc.params_get_notebook("nb-golden"), "csrf-token")
        )
        assert(rpc_id == Rpc.RPC_GET_NOTEBOOK, "get notebook rpc id changed")
        assert(params[1] == "nb-golden" and params[2] == Json.null and params[3][1] == 2 and params[4] == Json.null and params[5] == 0, "get notebook params changed")

        rpc_id, params = decode_rpc_body(
            Rpc.build_batchexecute_body(Rpc.RPC_CREATE_NOTEBOOK, Rpc.params_create_notebook("Golden Notebook"), "csrf-token")
        )
        assert(rpc_id == Rpc.RPC_CREATE_NOTEBOOK, "create notebook rpc id changed")
        assert(params[1] == "Golden Notebook" and params[4][1] == 2 and params[5][1] == 1 and params[5][11][1] == 1, "create notebook params changed")

        rpc_id, params = decode_rpc_body(
            Rpc.build_batchexecute_body(Rpc.RPC_ADD_SOURCE_FILE, Rpc.params_register_file_source("nb-golden", "Golden Source.pdf"), "csrf-token")
        )
        assert(rpc_id == Rpc.RPC_ADD_SOURCE_FILE, "register source rpc id changed")
        assert(params[1][1][1] == "Golden Source.pdf" and params[2] == "nb-golden" and params[3][1] == 2, "register source params changed")

        local query_body = Rpc.build_query_body({
            source_ids = { "src-golden" },
            query_text = "Why does this matter?",
            conversation_id = "conv-golden",
            conversation_history = Json.array(
                Json.array("Earlier answer.", Json.null, 2),
                Json.array("Earlier question?", Json.null, 1)
            ),
            csrf_token = "csrf-token",
        })
        values = form_values(query_body)
        local query_f_req = Json.decode(values["f.req"])
        local query_params = Json.decode(query_f_req[2])
        assert(query_f_req[1] == Json.null, "query f.req first slot changed")
        assert(query_params[1][1][1][1] == "src-golden", "query source shape changed")
        assert(query_params[2] == "Why does this matter?", "query text changed")
        assert(query_params[3][1][1] == "Earlier answer.", "query history answer shape changed")
        assert(query_params[3][2][3] == 1, "query history question role changed")
        assert(query_params[4][1] == 2 and query_params[4][2] == Json.null and query_params[4][3][1] == 1, "query mode shape changed")
        assert(query_params[5] == "conv-golden", "query conversation id changed")
        assert(values["at"] == "csrf-token", "csrf token was not encoded in query body")
        local query_url = Rpc.build_query_url("https://notebooklm.google.com", {
            build_label = "build-label",
            session_id = "session-id",
            request_id = 123456,
        })
        assert(query_url:find("GenerateFreeFormStreamed", 1, true), "query URL endpoint changed")
        assert(query_url:find("_reqid=123456", 1, true), "query URL missing request id")
        assert(query_url:find("bl=build%-label"), "query URL missing build label")
        assert(query_url:find("f%.sid=session%-id"), "query URL missing session id")

        local list_result = assert(Parsing.parse_batchexecute_response(
            read_fixture("notebook_list_response.fixture"),
            Rpc.RPC_LIST_NOTEBOOKS
        ))
        local notebooks = Parsing.parse_notebooks(list_result)
        assert(#notebooks == 1 and notebooks[1].id == "nb-golden", "notebook list fixture did not parse")
        assert(notebooks[1].sources[1].id == "src-golden" and notebooks[1].sources[1].status == "ready", "notebook source fixture did not parse")

        local notebook_result = assert(Parsing.parse_batchexecute_response(
            read_fixture("get_notebook_response.fixture"),
            Rpc.RPC_GET_NOTEBOOK
        ))
        local sources = Parsing.parse_sources_from_notebook_data(notebook_result)
        assert(#sources == 1 and sources[1].title == "Golden Source", "get notebook fixture did not parse")
        local transient_sources = Parsing.parse_sources_from_notebook({
            "Transient Notebook",
            {
                {
                    { "src-transient" },
                    "Transient EPUB",
                    { Json.null, Json.null, { 1, 2 }, Json.null, 0 },
                    { Json.null, 3 },
                },
            },
            "nb-transient",
        })
        assert(transient_sources[1].status == "error", "transient source status did not parse")
        assert(transient_sources[1].source_type == 0, "transient source type did not parse")

        local answer = assert(Parsing.parse_query_response(read_fixture("query_response.fixture")))
        assert(answer.answer == "Golden answer with citation [1].", "query answer fixture did not parse")
        assert(answer.conversation_id == "conv-golden", "query conversation id did not parse")
        assert(answer.citations["1"] == "src-golden", "query citation mapping did not parse")
        assert(answer.references[1].cited_text == "Golden cited passage.", "query cited text did not parse")

        local fake_settings = {
            values = { direct_auth_bundle_path = "/tmp/notebooklm-direct-auth-bundle.json" },
            read = function(self, key) return self.values[key] end,
        }
        local direct_client = DirectClient:new(fake_settings, nil)
        assert(direct_client:is_enabled() == true, "Lua direct client should always be enabled")
        assert(direct_client:load_auth().csrf_token == "csrf-token", "direct client did not load auth")
        assert(direct_client:build_list_notebooks(auth).body:find("wXbhsf", 1, true), "direct client did not build list request")
        assert(direct_client:build_get_notebook(auth, "nb-golden").url:find("source%-path=%%2Fnotebook%%2Fnb%-golden"), "direct client did not build get notebook URL")
        assert(direct_client:build_create_notebook(auth, "Direct Created").body:find("CCqFvf", 1, true), "direct client did not build create notebook request")
        assert(direct_client:build_register_file_source(auth, "nb-golden", "Book.epub").body:find("o4cbdc", 1, true), "direct client did not build source registration request")
        assert(direct_client:build_upload_start_body("nb-golden", "Book.epub", "src-golden"):find('"PROJECT_ID":"nb%-golden"'), "direct client did not build upload start body")
        assert(direct_client:build_ask(auth, { source_ids = { "src-golden" }, prompt = "Prompt?", conversation_id = "conv-golden" }).url:find("GenerateFreeFormStreamed", 1, true), "direct client did not build ask URL")
        assert(direct_client:parse_ask(read_fixture("query_response.fixture")).answer:find("Golden answer", 1, true), "direct client did not parse ask response")
        local live_notebooks = assert(direct_client:list_notebooks())
        assert(live_notebooks.adapter == "lua-direct" and live_notebooks.notebooks[1].id == "nb-golden", "direct client list_notebooks did not use Lua HTTPS transport")
        local first_direct_request = _G.__direct_requests[1]
        assert(first_direct_request.headers["Cookie"]:find("SID=fake", 1, true), "direct transport did not send cookie header")
        assert(first_direct_request.headers["X-Goog-Csrf-Token"] == "csrf-token", "direct transport did not send csrf header")
        assert(first_direct_request.headers["X-Same-Domain"] == "1", "direct transport did not send same-domain header")
        assert(first_direct_request.headers["Content-Type"] == "application/x-www-form-urlencoded;charset=UTF-8", "direct transport content type changed")
        assert(first_direct_request.headers["Accept"] == "*/*", "direct transport did not send accept header")
        assert(first_direct_request.headers["Accept-Language"] == "en-US,en;q=0.9", "direct transport did not default to English accept-language")
        assert(first_direct_request.headers["User-Agent"]:find("Chrome", 1, true), "direct transport did not send browser-like user-agent")
        assert(first_direct_request.body:find("f.req=", 1, true), "direct transport did not send form body")
        fake_settings.values.language = "es"
        local spanish_auth = direct_client:auth_for_request(auth)
        assert(spanish_auth.language == "es", "direct client did not attach Spanish hl language")
        assert(spanish_auth.accept_language == "es-ES,es;q=0.9", "direct client did not attach Spanish accept-language")
        assert(Transport._test_headers("body", spanish_auth)["Accept-Language"] == "es-ES,es;q=0.9", "direct transport did not use Spanish accept-language")
        local spanish_question = direct_client:build_question({
            prompt = "Explica esto.",
            selected_text = "Texto seleccionado.",
        })
        assert(spanish_question:find("Responde en espanol.", 1, true), "Spanish language instruction was not added to NotebookLM question")
        local spanish_query = direct_client:build_ask(spanish_auth, {
            source_ids = { "src-golden" },
            query_text = spanish_question,
            conversation_id = "conv-es",
        })
        assert(spanish_query.url:find("hl=es", 1, true), "direct ask URL did not use Spanish hl parameter")
        values = form_values(spanish_query.body)
        query_f_req = Json.decode(values["f.req"])
        query_params = Json.decode(query_f_req[2])
        assert(query_params[2]:find("Responde en espanol.", 1, true), "NotebookLM query body did not include the Spanish language instruction")
        fake_settings.values.language = nil
        local live_notebook = assert(direct_client:get_notebook("nb-golden"))
        assert(live_notebook.sources[1].id == "src-golden", "direct client get_notebook did not parse sources")
        local created_direct = assert(direct_client:create_notebook("Direct Created"))
        assert(created_direct.notebook.id == "created-direct", "direct client create_notebook did not parse notebook id")
        local uploaded_direct = assert(direct_client:upload_source("created-direct", {
            file_path = "/tmp/book.pdf",
            title = "Direct Source.pdf",
            wait = true,
        }))
        local register_request
        local upload_start_request
        for _, request in ipairs(_G.__direct_requests) do
            if request.url:find("rpcids=o4cbdc", 1, true) then
                register_request = request
            elseif request.url:find("/upload/_/?authuser=0", 1, true) then
                upload_start_request = request
            end
        end
        local register_rpc_id, register_params = decode_rpc_body(assert(register_request, "direct upload did not register file source").body)
        assert(register_rpc_id == "o4cbdc", "direct upload registered the wrong RPC")
        assert(register_params[1][1][1] == "Direct Source.pdf", "direct upload should prefer readable source title when registering source")
        assert(assert(upload_start_request, "direct upload did not start resumable upload").body:find('"SOURCE_NAME":"Direct Source.pdf"', 1, true), "direct upload start should preserve readable source title")
        assert(uploaded_direct.source_id == "src-direct-upload", "direct client upload_source did not return source id")
        assert(_G.__direct_upload_started == true and _G.__direct_upload_finalized == true, "direct client upload_source did not use resumable upload")
        local fallback_wait_client = DirectClient:new(fake_settings, nil)
        fallback_wait_client.get_notebook = function()
            return {
                sources = {
                    {
                        id = "src-original",
                        status = "error",
                        status_code = 3,
                        source_type = 0,
                    },
                },
            }
        end
        local fallback_ready, fallback_wait_err, fallback_wait_meta = fallback_wait_client:wait_for_source_ready(
            "created-direct",
            "src-original",
            1,
            { fail_on_any_error = true }
        )
        assert(fallback_ready == nil, "primary upload error should not be treated as ready")
        assert(tostring(fallback_wait_err):find("processing failed", 1, true), "primary upload error did not return terminal failure")
        assert(fallback_wait_meta and fallback_wait_meta.terminal_source_error == true, "primary upload error did not request fallback")
        local live_answer = assert(direct_client:ask({
            notebook_id = "nb-golden",
            selected_text = "Lua direct selected text",
            prompt = "Explain this.",
            book = { title = "Fixture Book", position = "smoke" },
        }))
        assert(live_answer.adapter == "lua-direct" and live_answer.answer:find("Golden answer", 1, true), "direct client ask did not parse answer")

        local converted_html = SourceExportCRE.html_to_markdown("<html><body><h1>Chapter One</h1><p>Hello <em>world</em>.</p><ul><li>First</li></ul></body></html>")
        assert(converted_html:find("# Chapter One", 1, true), "CRE HTML conversion did not preserve heading")
        assert(converted_html:find("Hello world.", 1, true), "CRE HTML conversion did not preserve paragraph text")
        assert(converted_html:find("- First", 1, true), "CRE HTML conversion did not preserve list item")

        local passthrough_source = assert(SourceExport.prepare({ path = "/tmp/book.pdf", title = "PDF Book" }, nil, {
            output_dir = "/tmp/notebooklm-source-test",
        }))
        assert(passthrough_source.file_path == "/tmp/book.pdf", "PDF source should pass through without conversion")
        assert(passthrough_source.method == "passthrough-pdf", "PDF source used the wrong export method")

        local html_doc = {
            getHTMLFromXPointer = function()
                error("whole-document HTML extraction should not run by default")
            end,
        }
        local html_source, html_err = SourceExport.prepare({ path = "/tmp/book.epub", title = "Exported Book" }, html_doc, {
            output_dir = "/tmp/notebooklm-source-test",
        })
        assert(html_source == nil, "EPUB export should not use risky whole-document HTML fallback by default")
        assert(tostring(html_err):find("page text extraction", 1, true), "EPUB export should report page text extraction failure")

        local html_only = assert(SourceExportCRE.extract_whole_html({
            getHTMLFromXPointer = function(_, xpointer)
                assert(xpointer == ".0", "whole document export used the wrong xpointer")
                return "<html><body><h1>Export Title</h1><p>Extracted <strong>book</strong> text.</p></body></html>"
            end,
        }))
        assert(html_only.method == "cre-dom-html", "explicit HTML extraction test should keep the helper available")
        assert(html_only.text:find("# Export Title", 1, true), "explicit HTML extraction did not preserve heading")
        assert(html_only.text:find("Extracted book text.", 1, true), "explicit HTML extraction did not preserve text")

        local page_doc = {
            getHTMLFromXPointer = function() return nil end,
            getPageCount = function() return 2 end,
            getPageXPointer = function(_, page) return ".page" .. tostring(page) end,
            getTextFromXPointers = function(_, pos0, pos1)
                return "Range " .. tostring(pos0) .. " to " .. tostring(pos1)
            end,
        }
        local page_source = assert(SourceExport.prepare({ path = "/tmp/book.epub", title = "Paged Book" }, page_doc, {
            output_dir = "/tmp/notebooklm-source-test",
        }))
        assert(page_source.method == "cre-page-xpointers", "EPUB export should fall back to page xpointer text")
        local page_file = assert(io.open(page_source.file_path, "r"))
        local page_body = page_file:read("*all")
        page_file:close()
        assert(page_body:find("Range .page1 to .page2", 1, true), "page export should include first page range")
        assert(page_body:find("Range .page2 to .page3", 1, true), "page export should include final page range")

        local rendered = false
        local render_doc = {
            getHTMLFromXPointer = function() return nil end,
            setViewDimen = function(_, dimen)
                assert(dimen.w == 600 and dimen.h == 800, "export render fallback should set stable view dimensions")
            end,
            setViewMode = function(_, mode)
                assert(mode == "page", "export render fallback should set page mode")
            end,
            render = function() rendered = true end,
            getPageCount = function() return rendered and 1 or 0 end,
            getPageXPointer = function(_, page) return ".rendered" .. tostring(page) end,
            getTextFromXPointers = function(_, pos0, pos1)
                return "Rendered " .. tostring(pos0) .. " to " .. tostring(pos1)
            end,
        }
        local render_source = assert(SourceExport.prepare({ path = "/tmp/book.epub", title = "Rendered Book" }, render_doc, {
            output_dir = "/tmp/notebooklm-source-test",
        }))
        assert(render_source.method == "cre-page-xpointers", "render fallback should still use page xpointer export")
        assert(rendered == true, "render fallback did not render an unpaginated CRE document")

        local Client = require("client")
        local pending_async = {}
        local async_transport = {
            post_form_async = function(url, body, _, _, callback)
                table.insert(pending_async, { url = url, body = body, callback = callback })
            end,
        }
        local async_direct = DirectClient:new(fake_settings, async_transport)
        local async_client = Client:new(fake_settings, {})
        async_client.direct_client = async_direct
        local async_job = assert(async_client:start_ask_job({
            notebook_id = "nb-golden",
            selected_text = "Async selected text",
            prompt = "Explain async.",
            book = { title = "Fixture Book" },
        }))
        assert(async_job.status == "running", "lua-direct start_ask_job should return before NotebookLM answers")
        assert(#pending_async == 1 and pending_async[1].url:find("rpcids=rLM1Ne", 1, true), "lua-direct async ask should first request notebook sources")
        local running_job = assert(async_client:get_ask_job(async_job.job_id))
        assert(running_job.status == "running", "lua-direct async job should remain running before callbacks")
        pending_async[1].callback(read_fixture("get_notebook_response.fixture"), nil, 200)
        assert(#pending_async == 2 and pending_async[2].url:find("GenerateFreeFormStreamed", 1, true), "lua-direct async ask should request answer after sources")
        pending_async[2].callback(read_fixture("query_response.fixture"), nil, 200)
        local completed_job = assert(async_client:get_ask_job(async_job.job_id))
        assert(completed_job.status == "succeeded", "lua-direct async job did not complete")
        assert(completed_job.result.answer:find("Golden answer", 1, true), "lua-direct async job did not parse answer")
        '''
    )
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
                getHTMLFromXPointer = function()
                    return "<html><body><h1>Book</h1><p>Stub EPUB content exported by KOReader.</p></body></html>"
                end,
                getPageCount = function()
                    return 1
                end,
                getPageXPointer = function(_, page)
                    return ".bookpage" .. tostring(page)
                end,
                getTextFromXPointers = function()
                    return "Stub EPUB content exported by KOReader."
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
                closed_keep = nil,
                cleared = false,
                addToHighlightDialog = function(_, key, fn)
                    highlight_buttons[key] = fn
                end,
                onClose = function(self, keep_highlight)
                    self.closed_keep = keep_highlight
                    if not keep_highlight then
                        self:clear()
                    end
                end,
                clear = function(self)
                    self.cleared = true
                end,
            },
        }
        plugin:init()
        assert(menu_registered, "plugin did not register to main menu")
        assert(highlight_buttons["notebooklm"], "missing NotebookLM highlight action")
        assert(highlight_buttons["notebooklm_explain_simple"] == nil, "prompt highlight action should not be registered directly")
        local menu = {}
        plugin:addToMainMenu(menu)
        assert(menu.notebooklm, "missing NotebookLM tools menu")
        assert(menu.notebooklm.sub_item_table[2].text == "Answers", "missing NotebookLM answers menu")
        local settings_menu = menu.notebooklm.sub_item_table[4]
        assert(settings_menu and settings_menu.text == "Settings", "missing NotebookLM settings menu")
        assert(settings_menu.sub_item_table and #settings_menu.sub_item_table == 7, "settings menu does not expose expected settings")
        assert(settings_menu.sub_item_table[1].text_func():find("English", 1, true), "language menu did not show English default")
        settings_menu.sub_item_table[1].callback()
        assert(plugin.settings:read("language") == "es", "language toggle did not switch to Spanish")
        settings_menu.sub_item_table[1].callback()
        assert(plugin.settings:read("language") == "en", "language toggle did not switch back to English")
        assert(settings_menu.sub_item_table[2].text_func():find("not set", 1, true), "lua direct auth bundle menu did not show unset state")
        settings_menu.sub_item_table[2].callback()
        assert(plugin.notebooklm_ui.input_dialog == nil, "lua direct auth bundle menu should not use NotebookLMUI input dialog")
        local uimanager_for_lua_direct = require("ui/uimanager")
        local auth_dialog = uimanager_for_lua_direct.shown[#uimanager_for_lua_direct.shown]
        assert(auth_dialog and auth_dialog.title == "Lua direct auth bundle", "lua direct auth bundle dialog did not render")
        auth_dialog.input = "/tmp/notebooklm-direct-auth-bundle.json"
        auth_dialog.buttons[1][2].callback()
        assert(plugin.settings:read("direct_auth_bundle_path") == "/tmp/notebooklm-direct-auth-bundle.json", "lua direct auth bundle path was not saved")
        assert(settings_menu.sub_item_table[3].text_func():find("auto", 1, true), "lua direct notebook menu did not show auto state")
        settings_menu.sub_item_table[3].callback()
        local notebook_dialog = uimanager_for_lua_direct.shown[#uimanager_for_lua_direct.shown]
        assert(notebook_dialog and notebook_dialog.title == "Lua direct notebook ID", "lua direct notebook dialog did not render")
        notebook_dialog.input = "nb-golden"
        notebook_dialog.buttons[1][2].callback()
        assert(plugin.settings:read("direct_notebook_id") == "nb-golden", "lua direct notebook id was not saved")
        settings_menu.sub_item_table[4].callback()
        local smoke_result = uimanager_for_lua_direct.shown[#uimanager_for_lua_direct.shown]
        assert(smoke_result and smoke_result.text and smoke_result.text:find("Lua direct smoke OK", 1, true), "lua direct smoke did not complete through HTTPS stub")
        assert(settings_menu.sub_item_table[5].text_func():find("enabled", 1, true), "source upload menu did not show enabled state")
        settings_menu.sub_item_table[5].callback()
        assert(plugin.settings:read("enable_upload") == false, "source upload toggle did not disable upload")
        settings_menu.sub_item_table[5].callback()
        assert(plugin.settings:read("enable_upload") == true, "source upload toggle did not re-enable upload")
        assert(settings_menu.sub_item_table[6].text_func():find("multipart", 1, true), "upload mode menu did not show multipart mode")
        settings_menu.sub_item_table[6].callback()
        assert(plugin.settings:read("upload_mode") == "path", "upload mode toggle did not switch to path")
        settings_menu.sub_item_table[6].callback()
        assert(plugin.settings:read("upload_mode") == "multipart", "upload mode toggle did not switch back to multipart")
        assert(settings_menu.sub_item_table[7].text_func():find("enabled", 1, true), "open answer setting did not show enabled state")
        settings_menu.sub_item_table[7].callback()
        assert(plugin.settings:read("open_answer_automatically") == false, "open answer toggle did not disable auto-open")
        settings_menu.sub_item_table[7].callback()
        assert(plugin.settings:read("open_answer_automatically") == true, "open answer toggle did not re-enable auto-open")

        local unsafe_value = function() return "unsafe" end
        local sanitized_link = plugin.storage:save_link(plugin.ui, {
            notebook_id = "unsafe-notebook",
            notebook_title = unsafe_value,
            title = unsafe_value,
            author = unsafe_value,
            path = unsafe_value,
            source_id = unsafe_value,
            linked_at = unsafe_value,
        })
        assert(sanitized_link.notebook_id == "unsafe-notebook", "string link field was not preserved")
        assert(sanitized_link.notebook_title == nil, "function notebook title was not dropped")
        assert(sanitized_link.title == "Book", "unsafe title did not fall back to book title")
        assert(sanitized_link.author == "Author", "unsafe author did not fall back to book author")
        assert(sanitized_link.path == "/tmp/book.epub", "unsafe path did not fall back to book path")
        assert(sanitized_link.source_id == nil, "function source id was not dropped")
        assert(type(sanitized_link.linked_at) == "string", "unsafe linked_at did not fall back to an ISO string")
        plugin.storage:clear_link(plugin.ui)

        plugin.settings:write("direct_notebook_id", "nb-golden")
        plugin.notebooklm_ui:show_setup()
        local direct_setup = plugin.notebooklm_ui.input_dialog
        assert(direct_setup and direct_setup.buttons[2] and #direct_setup.buttons[2] == 3, "lua-direct setup should expose list/create/upload actions")
        assert(direct_setup.buttons[2][1].text == "List", "lua-direct setup should keep notebook listing")
        assert(direct_setup.buttons[2][2].text == "Create", "lua-direct setup should expose notebook creation")
        assert(direct_setup.buttons[2][3].text == "Create+Upload", "lua-direct setup should expose source upload")
        local direct_link = plugin.storage:get_link(plugin.ui)
        assert(direct_link == nil, "lua-direct direct_notebook_id should not auto-link the local book")
        plugin.notebooklm_ui:_close_input()
        plugin.client.start_create_upload_job = function(_, request)
            assert(request.title == "Direct UI Created" or request.title == "Created Notebook", "create+upload job did not receive title")
            assert(request.file_path == "/tmp/book.epub", "create+upload job should try the original EPUB first")
            assert(request.source_title == "book.epub", "create+upload job did not use original source title")
            assert(request.source_export_method == "original-epub", "create+upload job did not report original source method")
            assert(request.fallback_file_path and request.fallback_file_path:find("/tmp/notebooklm%-sources/"), "create+upload job did not prepare Markdown fallback path")
            assert(request.fallback_file_path:find("%.md$"), "create+upload Markdown fallback should be a Markdown file")
            assert(request.fallback_source_title == "Book.md", "create+upload job did not use readable Markdown fallback title")
            assert(request.fallback_source_export_method == "cre-page-xpointers", "create+upload job did not report fallback export method")
            assert(request.wait_timeout == 600, "create+upload job did not request a long processing wait")
            return { ok = true, job_id = "upload-job", status = "running" }
        end
        plugin.client.get_create_upload_job = function(_, job_id)
            assert(job_id == "upload-job", "create+upload polled the wrong job")
            return {
                ok = true,
                status = "succeeded",
                result = {
                    notebook = { id = "created-direct", title = "Direct UI Created" },
                    upload = { source_id = "src-direct-upload" },
                },
            }
        end
        plugin.notebooklm_ui:create_notebook("Direct UI Created", true)
        local direct_ui_link = plugin.storage:get_link(plugin.ui)
        assert(direct_ui_link and direct_ui_link.notebook_id == "created-direct", "lua-direct create+upload did not save local link")
        assert(direct_ui_link.source_id == "src-direct-upload", "lua-direct create+upload did not save uploaded source id")
        local direct_request_count = #_G.__direct_requests
        plugin.notebooklm_ui:ask_with_prompt(
            "Lua direct highlighted passage",
            "Explain this direct passage.",
            "Direct"
        )
        local direct_viewer = require("ui/widget/textviewer")
        assert(direct_viewer.last_viewer and direct_viewer.last_viewer.title == "NotebookLM - Answer", "lua-direct ask did not open the structured answer viewer")
        assert(direct_viewer.last_viewer.text:find("Golden answer with citation", 1, true), "lua-direct ask did not render the NotebookLM answer")
        assert(#_G.__direct_requests >= direct_request_count + 2, "lua-direct normal ask did not call NotebookLM get+ask RPCs")
        plugin.storage:clear_link(plugin.ui)
        plugin.settings:write("direct_notebook_id", "")

        local unlinked_item = highlight_buttons["notebooklm"]({
            selected_text = { text = "Unlinked highlighted passage" },
        })
        assert(unlinked_item and unlinked_item.callback, "NotebookLM highlight item did not render")
        assert(unlinked_item.text == "NotebookLM", "highlight menu should expose one NotebookLM entry")
        unlinked_item.callback()
        assert(plugin.notebooklm_ui.input_dialog and plugin.notebooklm_ui.input_dialog.title:find("NotebookLM", 1, true), "unlinked highlight did not open NotebookLM submenu")
        assert(plugin.notebooklm_ui.input_dialog.buttons[1][1].text == "Ask NotebookLM", "submenu missing ask action")
        assert(plugin.notebooklm_ui.input_dialog.buttons[2][1].text == "NotebookLM answers", "submenu missing answers action")
        plugin.notebooklm_ui.input_dialog.buttons[1][1].callback()
        assert(plugin.notebooklm_ui.input_dialog and plugin.notebooklm_ui.input_dialog.title == "NotebookLM setup", "unlinked ask did not open setup")
        assert(plugin.notebooklm_ui.input_dialog.buttons[1][1].text == "Back", "setup does not expose a back action when opened from the NotebookLM hub")
        plugin.notebooklm_ui.input_dialog.buttons[1][1].callback()
        assert(plugin.notebooklm_ui.input_dialog and plugin.notebooklm_ui.input_dialog.buttons[1][1].text == "Ask NotebookLM", "setup back did not return to the NotebookLM hub")
        plugin.notebooklm_ui.input_dialog.buttons[3][1].callback()
        assert(plugin.notebooklm_ui.input_dialog and plugin.notebooklm_ui.input_dialog.title == "NotebookLM setup", "highlight link action did not open setup")
        plugin.notebooklm_ui.input_dialog.buttons[2][1].callback()
        local highlight_link_picker = plugin.notebooklm_ui.input_dialog
        assert(highlight_link_picker and highlight_link_picker.title == "Link existing notebook", "highlight link setup did not open notebook picker")
        highlight_link_picker.buttons[1][1].callback()
        assert(plugin.notebooklm_ui.input_dialog and plugin.notebooklm_ui.input_dialog.title:find("Ask NotebookLM", 1, true), "highlight link did not continue to prompt picker")
        plugin.notebooklm_ui:_close_input()
        plugin.storage:clear_link(plugin.ui)

        plugin.notebooklm_ui:show_status()

        plugin.notebooklm_ui:show_notebook_picker("", nil)
        local picker = plugin.notebooklm_ui.input_dialog
        assert(picker and picker.buttons and picker.buttons[1] and picker.buttons[1][1], "notebook picker did not render")
        picker.buttons[1][1].callback()
        local existing_link = plugin.storage:get_link(plugin.ui)
        assert(existing_link and existing_link.notebook_id == "nb-golden", "existing notebook link was not saved")
        plugin.notebooklm_ui:show_setup()
        local linked_setup = plugin.notebooklm_ui.input_dialog
        assert(linked_setup and linked_setup.buttons[3] and linked_setup.buttons[3][1].text == "Clear link", "linked setup did not expose clear link")
        linked_setup.buttons[3][1].callback()
        assert(plugin.storage:get_link(plugin.ui) == nil, "clear link did not remove local link")

        plugin.notebooklm_ui:create_notebook("Created Notebook", true)
        local link = plugin.storage:get_link(plugin.ui)
        assert(link and link.notebook_id == "created-direct", "book link was not saved")
        assert(link.source_id == "src-direct-upload", "uploaded source id was not saved")
        plugin.settings:write("upload_mode", "multipart")

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

        local prompt_item = highlight_buttons["notebooklm"]({
            selected_text = { text = "Prompt button selected text" },
        })
        assert(prompt_item and prompt_item.callback, "NotebookLM highlight item did not render")
        prompt_item.callback()
        local prompt_hub = plugin.notebooklm_ui.input_dialog
        assert(prompt_hub and prompt_hub.buttons[1][1].text == "Ask NotebookLM", "NotebookLM submenu did not render after link")
        assert(prompt_hub.buttons[3][1].text == "Relink notebook", "linked submenu did not expose relink")
        prompt_hub.buttons[1][1].callback()
        local prompt_picker = plugin.notebooklm_ui.input_dialog
        assert(prompt_picker and prompt_picker.title:find("Ask NotebookLM", 1, true), "ask action did not open prompt picker")
        prompt_picker.buttons[1][2].callback()
        local edit_prompt_dialog = plugin.notebooklm_ui.input_dialog
        assert(edit_prompt_dialog and edit_prompt_dialog.title:find("Edit prompt", 1, true), "preset edit prompt dialog did not render")
        assert(edit_prompt_dialog.input and edit_prompt_dialog.input:find("Explain this passage", 1, true), "preset edit prompt did not preload the full prompt")
        edit_prompt_dialog.input = edit_prompt_dialog.input .. "\nAlso explain the part I did not understand."
        edit_prompt_dialog.buttons[1][2].callback()
        assert(require("ui/widget/textviewer").last_viewer.text:find("Golden answer", 1, true), "edited preset prompt did not return an answer")
        prompt_item.callback()
        prompt_hub = plugin.notebooklm_ui.input_dialog
        prompt_hub.buttons[1][1].callback()
        prompt_picker = plugin.notebooklm_ui.input_dialog
        assert(prompt_picker.buttons[6][2].text == "Back", "prompt picker did not expose back navigation")
        prompt_picker.buttons[6][2].callback()
        assert(plugin.notebooklm_ui.input_dialog and plugin.notebooklm_ui.input_dialog.buttons[1][1].text == "Ask NotebookLM", "prompt back did not return to the NotebookLM hub")
        plugin.notebooklm_ui.input_dialog.buttons[1][1].callback()
        prompt_picker = plugin.notebooklm_ui.input_dialog
        plugin.ui.highlight.closed_keep = nil
        plugin.ui.highlight.cleared = false
        prompt_picker.buttons[1][1].callback()
        assert(plugin.ui.highlight.closed_keep == false, "highlight dialog was not closed with selection reset during ask")
        assert(plugin.ui.highlight.cleared == true, "highlight selection was not cleared immediately after starting ask")

        plugin.notebooklm_ui:ask_with_prompt(
            "Highlighted passage",
            "Explain this passage simply.",
            "Explica simple"
        )
        local viewer = require("ui/widget/textviewer")
        assert(viewer.last_opened and viewer.last_opened:find("/tmp/notebooklm%-answer%-"), "answer viewer was not opened with a saved answer")
        assert(viewer.last_viewer and viewer.last_viewer.title == "NotebookLM - Answer", "structured answer viewer did not open on Answer")
        assert(viewer.last_viewer.text:find("Golden answer", 1, true), "structured answer viewer is missing answer text")
        assert(not viewer.last_viewer.text:find("##", 1, true), "structured answer viewer exposed markdown headings")
        assert(viewer.last_viewer.buttons_table[1][1].text == "Follow-up", "answer viewer missing follow-up action")
        assert(viewer.last_viewer.buttons_table[1][2].text == "New question", "answer viewer missing new question action")
        assert(viewer.last_viewer.buttons_table[2][1].text == "Details", "answer viewer missing details action")
        assert(type(viewer.last_viewer.onSwipe) == "function", "answer viewer missing swipe handler")
        viewer.last_viewer.buttons_table[2][1].callback()
        assert(viewer.last_viewer and viewer.last_viewer.title == "NotebookLM - Prompt", "details did not open prompt section")
        viewer.last_viewer.buttons_table[2][2].callback()
        assert(viewer.last_viewer and viewer.last_viewer.title == "NotebookLM - References", "references tab did not open")
        assert(viewer.last_viewer.text:find("Golden cited passage", 1, true), "references tab is missing cited text")
        viewer.last_viewer.buttons_table[4][2].callback()
        assert(viewer.last_viewer and viewer.last_viewer.title == "NotebookLM - Answer", "details back did not return to answer")
        viewer.last_viewer.buttons_table[1][1].callback()
        local followup_dialog = plugin.notebooklm_ui.input_dialog
        assert(followup_dialog and followup_dialog.title == "NotebookLM follow-up", "follow-up input did not open")
        followup_dialog.input = "Follow up on this answer"
        followup_dialog.buttons[1][2].callback()
        assert(viewer.last_viewer and viewer.last_viewer.text:find("Golden answer", 1, true), "follow-up did not return an answer")
        local file = io.open(viewer.last_opened, "r")
        assert(file, "answer file was not written")
        local content = file:read("*all")
        file:close()
        assert(content:find("Golden answer", 1, true), "answer content is missing")
        assert(content:find("Highlighted passage", 1, true), "highlight content is missing")
        assert(content:find("Conversation ID: conv%-golden"), "conversation id is missing")
        assert(content:find("## Sources used", 1, true), "sources used section is missing")
        assert(content:find("src%-golden"), "source id is missing")
        assert(content:find("Golden cited passage", 1, true), "cited text is missing")
        assert(content:find("## Citations", 1, true), "citations section is missing")
        local last_answer_file = io.open("/tmp/notebooklm-last-answer.md", "r")
        assert(last_answer_file, "last answer file was not written")
        last_answer_file:close()
        plugin.notebooklm_ui:show_answers()
        local answers_dialog = plugin.notebooklm_ui.input_dialog
        assert(answers_dialog and answers_dialog.title:find("NotebookLM answers", 1, true), "answers list did not render")
        assert(answers_dialog.buttons[1][1].text:find("Follow%-up") or answers_dialog.buttons[1][1].text:find("Explica simple", 1, true), "answers list did not show question context first")
        answers_dialog.buttons[1][1].callback()
        assert(viewer.last_opened and viewer.last_opened:find("/tmp/notebooklm%-answer%-"), "saved answer did not reopen")
        assert(viewer.last_viewer and viewer.last_viewer.title == "NotebookLM - Answer", "saved answer did not reopen in structured viewer")
        plugin.notebooklm_ui:show_answers(function()
            plugin.notebooklm_ui:show_highlight_menu("History highlighted passage")
        end)
        local answers_back_dialog = plugin.notebooklm_ui.input_dialog
        local answers_last_row = answers_back_dialog.buttons[#answers_back_dialog.buttons]
        assert(answers_last_row and answers_last_row[1].text == "Back", "answers list did not expose back navigation")
        answers_last_row[1].callback()
        assert(plugin.notebooklm_ui.input_dialog and plugin.notebooklm_ui.input_dialog.buttons[1][1].text == "Ask NotebookLM", "answers back did not return to the NotebookLM hub")
        plugin.notebooklm_ui:_close_input()

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

        local before_no_auto_open = custom_viewer.last_opened
        plugin.settings:write("open_answer_automatically", false)
        plugin.notebooklm_ui:ask_with_prompt(
            "Do not auto open this passage",
            "Save the answer but do not open it.",
            "No auto open"
        )
        assert(custom_viewer.last_opened == before_no_auto_open, "auto-open disabled ask unexpectedly changed viewer state")
        local uimanager_no_auto_open = require("ui/uimanager")
        local saved_message = uimanager_no_auto_open.shown[#uimanager_no_auto_open.shown]
        assert(saved_message and saved_message.text and saved_message.text:find("answer saved", 1, true), "auto-open disabled ask did not show saved message")
        plugin.settings:write("open_answer_automatically", true)

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
        assert(long_content:find("Golden answer", 1, true), "long answer content is missing")
        '''
    )
    print("plugin runtime smoke ok")


if __name__ == "__main__":
    main()
