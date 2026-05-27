local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local logger = require("logger")
local LuaSettings = require("luasettings")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local NotebookLMUI = {}
local MAX_ANSWER_HISTORY = 30
local ASK_POLL_INTERVAL_SECONDS = 2
local ASK_MAX_POLLS = 120

local function compact_text(value)
    return tostring(value or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function shorten(value, limit)
    local text = compact_text(value)
    if #text <= limit then
        return text
    end
    return text:sub(1, math.max(1, limit - 3)) .. "..."
end

local function trim_blank_lines(lines)
    while #lines > 0 and lines[1] == "" do
        table.remove(lines, 1)
    end
    while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
    end
    return lines
end

local function plain_line(line)
    line = tostring(line or "")
    line = line:gsub("^%s*#+%s*", "")
    line = line:gsub("^%s*>%s?", "")
    line = line:gsub("^%s*%*%s+", "- ")
    line = line:gsub("%*%*", "")
    line = line:gsub("`", "")
    return line
end

local function plain_text(value)
    local lines = {}
    for line in tostring(value or ""):gmatch("([^\n]*)\n?") do
        if line == "" and #lines > 0 and lines[#lines] == "" then
            -- Collapse repeated blank lines.
        else
            table.insert(lines, plain_line(line))
        end
    end
    return table.concat(trim_blank_lines(lines), "\n")
end

local function timestamp_id()
    local timestamp = os.date("!%Y%m%dT%H%M%SZ")
    local clock = math.floor((os.clock() or 0) * 1000)
    return string.format("%s-%d-%06d", timestamp, clock, math.random(0, 999999))
end

function NotebookLMUI:new(opts)
    opts = opts or {}
    return setmetatable({
        plugin = opts.plugin,
        client = opts.client,
        storage = opts.storage,
        settings = opts.settings,
        prompts = opts.prompts,
        input_dialog = nil,
        active_ask = false,
    }, { __index = self })
end

function NotebookLMUI:_close_input()
    if self.input_dialog then
        UIManager:close(self.input_dialog)
        self.input_dialog = nil
    end
end

function NotebookLMUI:_show_error(message)
    UIManager:show(InfoMessage:new{
        icon = "notice-warning",
        text = tostring(message or _("Unknown NotebookLM error")),
        timeout = 6,
    })
end

function NotebookLMUI:_show_info(message)
    UIManager:show(InfoMessage:new{
        text = tostring(message),
        timeout = 4,
    })
end

function NotebookLMUI:_close_reader_highlight(keep_highlight)
    local highlight = self.plugin and self.plugin.ui and self.plugin.ui.highlight
    if highlight and highlight.onClose then
        local ok, err = pcall(function()
            highlight:onClose(keep_highlight)
        end)
        if not ok then
            logger.warn("NotebookLM: could not close reader highlight dialog", tostring(err))
        end
    elseif highlight and highlight.highlight_dialog then
        UIManager:close(highlight.highlight_dialog)
        highlight.highlight_dialog = nil
        if not keep_highlight then
            self:_clear_reader_highlight()
        end
    end
end

function NotebookLMUI:_clear_reader_highlight()
    local highlight = self.plugin and self.plugin.ui and self.plugin.ui.highlight
    if highlight and highlight.clear then
        local ok, err = pcall(function()
            highlight:clear()
        end)
        if not ok then
            logger.warn("NotebookLM: could not clear reader highlight", tostring(err))
        end
    end
end

function NotebookLMUI:_book()
    return self.storage:get_book_context(self.plugin.ui)
end

function NotebookLMUI:_link()
    return self.storage:get_link(self.plugin.ui)
end

function NotebookLMUI:_answers_settings()
    return LuaSettings:open(DataStorage:getSettingsDir() .. "/notebooklm-answers.lua")
end

function NotebookLMUI:_read_answers()
    local settings = self:_answers_settings()
    local answers = settings:readSetting("answers", {})
    if type(answers) ~= "table" then
        return {}
    end

    local normalized = {}
    for _, entry in ipairs(answers) do
        if type(entry) == "table" and entry.path and entry.question then
            table.insert(normalized, entry)
        end
    end
    return normalized
end

function NotebookLMUI:_save_answers(answers)
    local settings = self:_answers_settings()
    settings:saveSetting("answers", answers)
    settings:flush()
end

function NotebookLMUI:_remember_answer(result, path, id)
    local book = self:_book()
    local answers = self:_read_answers()
    table.insert(answers, 1, {
        id = id or timestamp_id(),
        path = path,
        created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        book_title = tostring(book.title or ""),
        notebook_id = tostring(result.notebook_id or ""),
        prompt_label = tostring(result.prompt_label or "Question"),
        question = tostring(result.prompt or ""),
        conversation_id = tostring(result.conversation_id or ""),
        selected_preview = shorten(result.selected_text or "", 120),
        answer_preview = shorten(result.answer or "", 180),
    })
    while #answers > MAX_ANSWER_HISTORY do
        table.remove(answers)
    end
    self:_save_answers(answers)
end

function NotebookLMUI:_sync_bridge_link()
    local book = self:_book()
    local response, err, code = self.client:get_book(book.book_id)
    if response and response.book and response.book.notebook_id then
        logger.info("NotebookLM: bridge mapping found for book", book.book_id, "notebook", response.book.notebook_id)
        return self:_save_link(response.book)
    end
    if code == 404 then
        logger.info("NotebookLM: bridge has no mapping for book", book.book_id, "ignoring local link until relink")
        return nil
    end
    if err then
        logger.warn("NotebookLM: bridge mapping lookup failed for book", book.book_id, err)
    end
    local local_link = self:_link()
    if local_link and local_link.notebook_id then
        logger.info("NotebookLM: using local link for book", book.book_id, "notebook", local_link.notebook_id)
    end
    return local_link
end

function NotebookLMUI:_save_link(link)
    return self.storage:save_link(self.plugin.ui, link)
end

function NotebookLMUI:_clear_link()
    local book = self:_book()
    logger.info("NotebookLM: clearing local link for book", book.book_id)
    local _, err = self.client:clear_book(book.book_id)
    if err then
        logger.warn("NotebookLM: bridge clear link failed for book", book.book_id, err)
    end
    self.storage:clear_link(self.plugin.ui)
end

function NotebookLMUI:_bridge_link(notebook_id, notebook_title, source_id)
    local book = self:_book()
    local link = {
        book_id = book.book_id,
        notebook_id = notebook_id,
        notebook_title = notebook_title,
        title = book.title,
        author = book.author,
        path = book.path,
        source_id = source_id,
    }
    local _, err = self.client:link_book(link)
    if err then
        return nil, err
    end
    return self:_save_link(link), nil
end

function NotebookLMUI:show_status()
    local book = self:_book()
    local local_link = self:_sync_bridge_link()
    local health, health_err = self.client:health()
    local bridge_line
    if health then
        bridge_line = string.format("Bridge: OK (%s)", health.adapter or "unknown")
    else
        bridge_line = "Bridge: " .. tostring(health_err)
    end

    local link_line = "Notebook: not linked"
    if local_link and local_link.notebook_id then
        link_line = string.format(
            "Notebook: %s\nNotebook ID: %s",
            local_link.notebook_title or "(linked)",
            local_link.notebook_id
        )
    end

    UIManager:show(ConfirmBox:new{
        icon = "notice-info",
        face = Font:getFace("smallinfofont"),
        text = table.concat({
            "KOReader NotebookLM",
            "",
            bridge_line,
            "",
            "Book: " .. tostring(book.title or "Unknown"),
            "Book ID: " .. tostring(book.book_id),
            link_line,
            "",
            "Bridge URL: " .. tostring(self.settings:read("bridge_url")),
        }, "\n"),
        ok_text = _("Setup"),
        ok_callback = function()
            self:show_setup()
        end,
        cancel_text = _("Close"),
    })
end

function NotebookLMUI:show_setup(on_ready, on_back)
    local book = self:_book()
    local link = self:_sync_bridge_link()
    local link_text = link and link.notebook_id
        and ("Current notebook:\n" .. tostring(link.notebook_title or link.notebook_id))
        or "This book is not linked to a NotebookLM notebook yet."
    local action_row = {
        {
            text = _("List"),
            callback = function()
                local filter = self.input_dialog:getInputText()
                self:_close_input()
                self:show_notebook_picker(filter, on_ready, on_back)
            end,
        },
        {
            text = _("Create"),
            callback = function()
                local title = self.input_dialog:getInputText()
                self:_close_input()
                self:create_notebook(title, false, on_ready, on_back)
            end,
        },
    }
    if self.settings:read("enable_upload") then
        table.insert(action_row, {
            text = _("Create+Upload"),
            callback = function()
                local title = self.input_dialog:getInputText()
                self:_close_input()
                self:create_notebook(title, true, on_ready, on_back)
            end,
        })
    end
    local buttons = {
        {
            {
                text = on_back and _("Back") or _("Skip"),
                callback = function()
                    self:_close_input()
                    if on_back then
                        on_back()
                    end
                end,
            },
            {
                text = _("Use ID"),
                callback = function()
                    local notebook_id = self.input_dialog:getInputText()
                    if not notebook_id or notebook_id == "" then
                        self:_show_error("Enter a NotebookLM notebook ID first.")
                        return
                    end
                    self:_close_input()
                    local saved, err = self:_bridge_link(notebook_id, notebook_id, nil)
                    if err then
                        self:_show_error(err)
                        return
                    end
                    self:_show_info("Book linked to NotebookLM.")
                    if on_ready then
                        on_ready(saved)
                    elseif on_back then
                        on_back()
                    end
                end,
            },
        },
        action_row,
    }
    if link and link.notebook_id then
        table.insert(buttons, {
            {
                text = _("Clear link"),
                callback = function()
                    self:_close_input()
                    self:_clear_link()
                    self:_show_info("NotebookLM link cleared.")
                    self:show_setup(on_ready, on_back)
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    self:_close_input()
                end,
            },
        })
    end

    self.input_dialog = InputDialog:new{
        title = _("NotebookLM setup"),
        description = table.concat({
            tostring(book.title or "Current book"),
            "",
            link_text,
        }, "\n"),
        input_hint = _("Notebook title or notebook ID"),
        input_type = "text",
        buttons = buttons,
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:show_notebook_picker(filter, on_ready, on_back)
    local result, err = self.client:list_notebooks()
    if err then
        self:_show_error(err)
        return
    end

    local filter_lc = filter and filter:lower() or ""
    local rows = {}
    local current_row = {}
    local count = 0
    for _, notebook in ipairs(result.notebooks or {}) do
        local label = notebook.title or notebook.id
        local matches = filter_lc == ""
            or tostring(label):lower():find(filter_lc, 1, true)
            or tostring(notebook.id):lower():find(filter_lc, 1, true)
        if matches then
            count = count + 1
            table.insert(current_row, {
                text = label,
                callback = function()
                    self:_close_input()
                    local saved, link_err = self:_bridge_link(notebook.id, notebook.title, nil)
                    if link_err then
                        self:_show_error(link_err)
                        return
                    end
                    self:_show_info("Book linked to NotebookLM.")
                    if on_ready then
                        on_ready(saved)
                    elseif on_back then
                        on_back()
                    end
                end,
            })
            if #current_row == 1 then
                table.insert(rows, current_row)
                current_row = {}
            end
        end
        if count >= 12 then
            break
        end
    end

    table.insert(rows, {
        {
            text = _("Back"),
            callback = function()
                self:_close_input()
                self:show_setup(on_ready, on_back)
            end,
        },
        {
            text = _("Cancel"),
            callback = function()
                self:_close_input()
            end,
        },
    })

    self.input_dialog = InputDialog:new{
        title = _("Link existing notebook"),
        description = count > 0
            and "Showing up to 12 matching notebooks. Use setup search to filter."
            or "No matching notebooks found.",
        input_type = "text",
        input_hint = _("Filter text"),
        buttons = rows,
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:create_notebook(title, upload_after, on_ready, on_back)
    local book = self:_book()
    title = title and title ~= "" and title or ("KOReader - " .. tostring(book.title or "Untitled book"))

    local created, err = self.client:create_notebook(title)
    if err then
        self:_show_error(err)
        return
    end
    local notebook = created.notebook
    if not notebook or not notebook.id then
        self:_show_error("Bridge did not return a created notebook ID.")
        return
    end

    local source_id = nil
    if upload_after then
        if not self.settings:read("enable_upload") then
            self:_show_error("Source upload is disabled in NotebookLM settings.")
            return
        end
        if not book.path or book.path == "" then
            self:_show_error("This book does not expose a file path for upload.")
            return
        end
        local upload, upload_err = self.client:upload_source(notebook.id, {
            file_path = book.path,
            title = book.title,
            wait = true,
        })
        if upload_err then
            self:_show_error(upload_err)
            return
        end
        source_id = upload and upload.source_id or nil
    end

    local saved, link_err = self:_bridge_link(notebook.id, notebook.title or title, source_id)
    if link_err then
        self:_show_error(link_err)
        return
    end

    self:_show_info(upload_after and "Notebook created, source uploaded, and book linked." or "Notebook created and book linked.")
    if on_ready then
        on_ready(saved)
    elseif on_back then
        on_back()
    end
end

function NotebookLMUI:show_highlight_menu(highlighted_text)
    if not highlighted_text or highlighted_text == "" then
        self:_show_error("No highlighted text found.")
        return
    end
    local link = self:_sync_bridge_link()
    local notebook_line = link and link.notebook_id
        and ("Notebook: " .. tostring(link.notebook_title or link.notebook_id))
        or "Notebook: not linked"
    local setup_text = link and link.notebook_id and _("Relink notebook") or _("Link notebook")
    local function back_to_hub()
        self:show_highlight_menu(highlighted_text)
    end

    self.input_dialog = ButtonDialog:new{
        title = table.concat({
            "NotebookLM",
            notebook_line,
            "Text: " .. shorten(highlighted_text, 90),
        }, "\n"),
        buttons = {
            {
                {
                    text = _("Ask NotebookLM"),
                    callback = function()
                        self:_close_input()
                        self:ask_highlight(highlighted_text, back_to_hub)
                    end,
                },
            },
            {
                {
                    text = _("NotebookLM answers"),
                    callback = function()
                        self:_close_input()
                        self:show_answers(back_to_hub)
                    end,
                },
            },
            {
                {
                    text = setup_text,
                    callback = function()
                        self:_close_input()
                        self:show_setup(nil, back_to_hub)
                    end,
                },
                {
                    text = _("Status"),
                    callback = function()
                        self:_close_input()
                        self:show_status()
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        self:_close_input()
                    end,
                },
            },
        },
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:ask_highlight(highlighted_text, on_back)
    if not highlighted_text or highlighted_text == "" then
        self:_show_error("No highlighted text found.")
        return
    end
    local link = self:_sync_bridge_link()
    if not link or not link.notebook_id then
        self:show_setup(function()
            self:show_prompt_picker(highlighted_text, on_back)
        end, on_back)
        return
    end
    self:show_prompt_picker(highlighted_text, on_back)
end

function NotebookLMUI:ask_with_prompt(highlighted_text, prompt, prompt_label, on_back)
    if not highlighted_text or highlighted_text == "" then
        self:_show_error("No highlighted text found.")
        return
    end
    local link = self:_sync_bridge_link()
    if not link or not link.notebook_id then
        self:show_setup(function()
            self:send_ask(highlighted_text, prompt, prompt_label)
        end, on_back)
        return
    end
    self:send_ask(highlighted_text, prompt, prompt_label)
end

function NotebookLMUI:show_answers(on_back)
    local answers = self:_read_answers()
    if #answers == 0 then
        self:_show_info("No NotebookLM answers saved yet.")
        if on_back then
            on_back()
        end
        return
    end

    local rows = {}
    local limit = math.min(#answers, 12)
    for i = 1, limit do
        local entry = answers[i]
        local label = shorten(
            tostring(entry.prompt_label or "Question") .. ": " .. tostring(entry.question or ""),
            64
        )
        table.insert(rows, {
            {
                text = label,
                callback = function()
                    self:_close_input()
                    self:show_saved_answer(entry.path)
                end,
                hold_callback = function()
                    self:_show_info(shorten(entry.answer_preview or "", 220))
                end,
            },
        })
    end
    if on_back then
        table.insert(rows, {
            {
                text = _("Back"),
                callback = function()
                    self:_close_input()
                    on_back()
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    self:_close_input()
                end,
            },
        })
    else
        table.insert(rows, {
            {
                text = _("Close"),
                callback = function()
                    self:_close_input()
                end,
            },
        })
    end

    self.input_dialog = ButtonDialog:new{
        title = _("NotebookLM answers") .. "\n" .. _("Most recent first"),
        buttons = rows,
        rows_per_page = 8,
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:show_prompt_picker(highlighted_text, on_back)
    local rows = {}
    for _, prompt in ipairs(self.prompts.presets) do
        table.insert(rows, {
            {
                text = prompt.label,
                callback = function()
                    self:_close_input()
                    self:send_ask(highlighted_text, prompt.prompt, prompt.label)
                end,
            },
        })
    end
    table.insert(rows, {
        {
            text = _("Custom"),
            callback = function()
                self:_close_input()
                self:show_custom_question(highlighted_text, function()
                    self:show_prompt_picker(highlighted_text, on_back)
                end)
            end,
        },
        {
            text = on_back and _("Back") or _("Cancel"),
            callback = function()
                self:_close_input()
                if on_back then
                    on_back()
                end
            end,
        },
    })
    if on_back then
        table.insert(rows, {
            {
                text = _("Close"),
                callback = function()
                    self:_close_input()
                end,
            },
        })
    end

    self.input_dialog = ButtonDialog:new{
        title = _("Ask NotebookLM") .. "\n" .. ("Text: " .. shorten(highlighted_text, 90)),
        buttons = rows,
        rows_per_page = 8,
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:show_custom_question(highlighted_text, on_back)
    self.input_dialog = InputDialog:new{
        title = _("Ask NotebookLM"),
        input_hint = _("Ask about the highlighted text..."),
        input_type = "text",
        input_height = 6,
        allow_newline = true,
        input_multiline = true,
        buttons = {
            {
                {
                    text = on_back and _("Back") or _("Cancel"),
                    callback = function()
                        self:_close_input()
                        if on_back then
                            on_back()
                        end
                    end,
                },
                {
                    text = _("Ask"),
                    is_enter_default = true,
                    callback = function()
                        local question = self.input_dialog:getInputText()
                        if not question or question == "" then
                            self:_show_error("Enter a question first.")
                            return
                        end
                        self:_close_input()
                        self:send_ask(highlighted_text, question, "Custom")
                    end,
                },
            },
        },
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:send_ask(highlighted_text, prompt, prompt_label, options)
    options = options or {}
    if self.active_ask then
        self:_show_error("NotebookLM question already running.")
        return
    end

    local link = nil
    if options.notebook_id then
        link = { notebook_id = options.notebook_id }
    else
        link = self:_sync_bridge_link()
    end
    if not link or not link.notebook_id then
        self:_show_error("This book is not linked to a NotebookLM notebook.")
        return
    end

    local book = self:_book()
    if options.close_highlight ~= false then
        self:_close_reader_highlight(false)
    end
    logger.info(
        "NotebookLM: starting ask job",
        "notebook", link.notebook_id,
        "prompt_label", tostring(prompt_label),
        "selected_chars", tostring(#highlighted_text)
    )

    self.active_ask = true
    local job, err = self.client:start_ask_job({
        notebook_id = link.notebook_id,
        conversation_id = options.conversation_id,
        selected_text = highlighted_text,
        prompt = prompt,
        book = {
            title = book.title,
            author = book.author,
            path = book.path,
            position = book.position,
        },
    })
    if err then
        self.active_ask = false
        self:_show_error(err)
        return
    end
    if not job or not job.job_id then
        self.active_ask = false
        self:_show_error("Bridge did not return an ask job ID.")
        return
    end
    self:poll_ask_job(job.job_id, {
        prompt_label = prompt_label,
        prompt = prompt,
        selected_text = highlighted_text,
        fallback_notebook_id = link.notebook_id,
        conversation_id = options.conversation_id,
        poll_count = 0,
    })
end

function NotebookLMUI:poll_ask_job(job_id, context)
    context.poll_count = (context.poll_count or 0) + 1
    if context.poll_count > ASK_MAX_POLLS then
        self.active_ask = false
        self:_show_error("NotebookLM answer timed out. Check NotebookLM answers later.")
        return
    end

    UIManager:scheduleIn(ASK_POLL_INTERVAL_SECONDS, function()
        local job, err = self.client:get_ask_job(job_id)
        if err then
            self.active_ask = false
            self:_show_error(err)
            return
        end
        if not job then
            self.active_ask = false
            self:_show_error("Bridge did not return ask job status.")
            return
        end
        if job.status == "queued" or job.status == "running" then
            self:poll_ask_job(job_id, context)
            return
        end
        if job.status == "failed" then
            self.active_ask = false
            self:_show_error(job.error or "NotebookLM ask job failed.")
            return
        end
        if job.status ~= "succeeded" or type(job.result) ~= "table" then
            self.active_ask = false
            self:_show_error("NotebookLM ask job returned an unknown status.")
            return
        end

        local response = job.result
        self.active_ask = false
        self:show_answer({
            prompt_label = context.prompt_label,
            prompt = context.prompt,
            selected_text = context.selected_text,
            answer = response.answer,
            notebook_id = response.notebook_id or context.fallback_notebook_id,
            conversation_id = response.conversation_id or context.conversation_id,
            sources_used = response.sources_used,
            references = response.references,
            citations = response.citations,
        }, self.settings:read("open_answer_automatically") ~= false)
    end)
end

local function reference_label(reference, index)
    local citation_number = reference.citation_number or index
    local label = "[" .. tostring(citation_number) .. "]"
    if reference.title and reference.title ~= "" then
        return label .. " " .. tostring(reference.title)
    end
    if reference.source_id and reference.source_id ~= "" then
        return label .. " Source " .. tostring(reference.source_id)
    end
    return label .. " Reference"
end

local function reference_body(reference, index)
    local lines = {
        string.format("%d. %s", index, reference_label(reference, index)),
    }
    local cited_text = reference.cited_text or reference.text
    if cited_text and cited_text ~= "" then
        table.insert(lines, "")
        table.insert(lines, tostring(cited_text))
    end
    return table.concat(lines, "\n")
end

local function references_to_text(references)
    if type(references) ~= "table" or #references == 0 then
        return "No references returned."
    end
    local lines = {}
    for index, reference in ipairs(references) do
        table.insert(lines, reference_body(reference, index))
        table.insert(lines, "")
    end
    return plain_text(table.concat(lines, "\n"))
end

local function citations_to_text(citations)
    if type(citations) ~= "table" then
        return "No citations returned."
    end
    local lines = {}
    for citation, source_id in pairs(citations) do
        table.insert(lines, "[" .. tostring(citation) .. "] " .. tostring(source_id))
    end
    if #lines == 0 then
        return "No citations returned."
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

local function sources_to_text(sources_used)
    if type(sources_used) ~= "table" or #sources_used == 0 then
        return "No sources returned."
    end
    local lines = {}
    for _, source_id in ipairs(sources_used) do
        table.insert(lines, tostring(source_id))
    end
    return table.concat(lines, "\n")
end

local function answer_sections_from_result(result, path)
    local prompt_label = tostring(result.prompt_label or "Question")
    local prompt = tostring(result.prompt or "")
    local notebook_id = tostring(result.notebook_id or "")
    local conversation_id = tostring(result.conversation_id or "")
    return {
        path = path,
        prompt_label = prompt_label,
        notebook_id = notebook_id,
        conversation_id = conversation_id,
        answer = plain_text(result.answer or ""),
        prompt = plain_text(table.concat({
            "Prompt preset: " .. prompt_label,
            "Question: " .. prompt,
            "Notebook ID: " .. notebook_id,
            "Conversation ID: " .. conversation_id,
        }, "\n")),
        selected = plain_text(result.selected_text or ""),
        references = references_to_text(result.references),
        citations = citations_to_text(result.citations),
        sources = sources_to_text(result.sources_used),
        raw = nil,
    }
end

local function parse_saved_answer(content, path)
    local parsed = {
        path = path,
        prompt_label = "Question",
        prompt = "",
        notebook_id = "",
        conversation_id = "",
        selected = "",
        answer = "",
        references = "",
        citations = "",
        sources = "",
        raw = content,
    }
    local buckets = {
        selected = {},
        answer = {},
        references = {},
        citations = {},
        sources = {},
    }
    local section = nil
    for line in tostring(content or ""):gmatch("([^\n]*)\n?") do
        local prompt_label = line:match("^Prompt:%s*(.*)$")
        local prompt = line:match("^Question:%s*(.*)$")
        local notebook_id = line:match("^Notebook ID:%s*(.*)$")
        local conversation_id = line:match("^Conversation ID:%s*(.*)$")
        if prompt_label then
            parsed.prompt_label = prompt_label
        elseif prompt then
            parsed.prompt = prompt
        elseif notebook_id then
            parsed.notebook_id = notebook_id
        elseif conversation_id then
            parsed.conversation_id = conversation_id
        elseif line == "## Selected text" then
            section = "selected"
        elseif line == "## Answer" then
            section = "answer"
        elseif line == "## References" then
            section = "references"
        elseif line == "## Citations" then
            section = "citations"
        elseif line == "## Sources used" then
            section = "sources"
        elseif section and buckets[section] then
            table.insert(buckets[section], line)
        end
    end
    parsed.answer = plain_text(table.concat(buckets.answer, "\n"))
    parsed.selected = plain_text(table.concat(buckets.selected, "\n"))
    parsed.references = plain_text(table.concat(buckets.references, "\n"))
    parsed.citations = plain_text(table.concat(buckets.citations, "\n"))
    parsed.sources = plain_text(table.concat(buckets.sources, "\n"))
    parsed.prompt = plain_text(table.concat({
        "Prompt preset: " .. tostring(parsed.prompt_label or "Question"),
        "Question: " .. tostring(parsed.prompt or ""),
        "Notebook ID: " .. tostring(parsed.notebook_id or ""),
        "Conversation ID: " .. tostring(parsed.conversation_id or ""),
    }, "\n"))
    return parsed
end

function NotebookLMUI:show_saved_answer(path)
    local file = io.open(path, "r")
    if not file then
        self:_show_error("Could not open NotebookLM answer file.")
        return
    end
    local content = file:read("*all")
    file:close()
    self:show_answer_viewer(parse_saved_answer(content, path), "answer")
end

function NotebookLMUI:show_answer_viewer(sections, section_id)
    section_id = section_id or "answer"
    if section_id ~= "answer" then
        self:show_answer_details_viewer(sections, section_id)
        return
    end
    local text = sections.answer
    if not text or text == "" then
        text = "No content for this section."
    end
    local viewer
    local function ask_followup(use_conversation)
        return function()
            UIManager:close(viewer)
            local conversation_id = nil
            if use_conversation and sections.conversation_id and sections.conversation_id ~= "" then
                conversation_id = sections.conversation_id
            end
            self:show_answer_question(
                sections,
                conversation_id,
                function()
                    self:show_answer_viewer(sections, "answer")
                end
            )
        end
    end
    local buttons = {
        {
            { text = _("Follow-up"), callback = ask_followup(true) },
            { text = _("New question"), callback = ask_followup(false) },
        },
        {
            {
                text = _("Details"),
                callback = function()
                    UIManager:close(viewer)
                    self:show_answer_details_viewer(sections, "prompt")
                end,
            },
            {
                text = _("Close"),
                callback = function()
                    UIManager:close(viewer)
                end,
            },
        },
    }
    viewer = TextViewer:new{
        title = "NotebookLM - Answer",
        title_multilines = true,
        text = text,
        text_type = "lookup",
        buttons_table = buttons,
        notebooklm_path = sections.path,
        notebooklm_section = "answer",
    }
    UIManager:show(viewer)
end

function NotebookLMUI:show_answer_question(sections, conversation_id, on_back)
    local has_conversation = conversation_id and conversation_id ~= ""
    local title = has_conversation and _("NotebookLM follow-up") or _("NotebookLM question")
    self.input_dialog = InputDialog:new{
        title = title,
        input_hint = _("Ask about this notebook..."),
        input_type = "text",
        input_height = 6,
        allow_newline = true,
        input_multiline = true,
        buttons = {
            {
                {
                    text = on_back and _("Back") or _("Cancel"),
                    callback = function()
                        self:_close_input()
                        if on_back then
                            on_back()
                        end
                    end,
                },
                {
                    text = _("Ask"),
                    is_enter_default = true,
                    callback = function()
                        local question = self.input_dialog:getInputText()
                        if not question or question == "" then
                            self:_show_error("Enter a question first.")
                            return
                        end
                        local selected = sections.selected
                        if not selected or selected == "" then
                            selected = "Question asked from the NotebookLM answer viewer."
                        end
                        self:_close_input()
                        self:send_ask(selected, question, has_conversation and "Follow-up" or "Question", {
                            notebook_id = sections.notebook_id,
                            conversation_id = has_conversation and conversation_id or nil,
                            close_highlight = false,
                        })
                    end,
                },
            },
        },
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:show_answer_details_viewer(sections, section_id)
    section_id = section_id or "prompt"
    local section_titles = {
        answer = "Answer",
        prompt = "Prompt",
        citations = "Citations",
        references = "References",
        selected = "Selected text",
        sources = "Sources",
        raw = "Raw",
    }
    local text = sections[section_id]
    if not text or text == "" then
        text = "No content for this section."
    end
    local viewer
    local function switch_to(next_section)
        return function()
            UIManager:close(viewer)
            self:show_answer_details_viewer(sections, next_section)
        end
    end
    local buttons = {
        {
            { text = _("Answer"), callback = switch_to("answer") },
            { text = _("Prompt"), callback = switch_to("prompt") },
        },
        {
            { text = _("Citations"), callback = switch_to("citations") },
            { text = _("References"), callback = switch_to("references") },
        },
        {
            { text = _("Selected"), callback = switch_to("selected") },
            { text = _("Sources"), callback = switch_to("sources") },
        },
        {
            { text = _("Raw"), callback = switch_to("raw") },
            {
                text = _("Back"),
                callback = function()
                    UIManager:close(viewer)
                    self:show_answer_viewer(sections, "answer")
                end,
            },
        },
    }
    viewer = TextViewer:new{
        title = "NotebookLM - " .. tostring(section_titles[section_id] or section_id),
        title_multilines = true,
        text = text,
        text_type = "lookup",
        buttons_table = buttons,
        notebooklm_path = sections.path,
        notebooklm_section = section_id,
    }
    UIManager:show(viewer)
end

function NotebookLMUI:show_answer(result, open_answer)
    if open_answer == nil then
        open_answer = true
    end
    local id = timestamp_id()
    local path = DataStorage:getSettingsDir() .. "/notebooklm-answer-" .. id .. ".md"
    local last_path = DataStorage:getSettingsDir() .. "/notebooklm-last-answer.md"
    local lines = {
        "# NotebookLM",
        "",
        "Prompt: " .. tostring(result.prompt_label or "Question"),
        "Question: " .. tostring(result.prompt or ""),
        "Notebook ID: " .. tostring(result.notebook_id or ""),
        "Conversation ID: " .. tostring(result.conversation_id or ""),
        "",
        "## Selected text",
        "",
        tostring(result.selected_text or ""),
        "",
        "## Answer",
        "",
        tostring(result.answer or ""),
    }
    if type(result.sources_used) == "table" and #result.sources_used > 0 then
        table.insert(lines, "")
        table.insert(lines, "## Sources used")
        table.insert(lines, "")
        for _, source_id in ipairs(result.sources_used) do
            table.insert(lines, "- " .. tostring(source_id))
        end
    end

    if type(result.references) == "table" and #result.references > 0 then
        table.insert(lines, "")
        table.insert(lines, "## References")
        table.insert(lines, "")
        for index, reference in ipairs(result.references) do
            table.insert(lines, string.format("%d. %s", index, reference_label(reference, index)))
            local cited_text = reference.cited_text or reference.text
            if cited_text and cited_text ~= "" then
                table.insert(lines, "")
                table.insert(lines, "> " .. tostring(cited_text):gsub("\n", "\n> "))
                table.insert(lines, "")
            end
        end
    end

    if type(result.citations) == "table" then
        local citation_lines = {}
        for citation, source_id in pairs(result.citations) do
            table.insert(citation_lines, "[" .. tostring(citation) .. "] " .. tostring(source_id))
        end
        if #citation_lines > 0 then
            table.sort(citation_lines)
            table.insert(lines, "")
            table.insert(lines, "## Citations")
            table.insert(lines, "")
            for _, citation in ipairs(citation_lines) do
                table.insert(lines, "- " .. citation)
            end
        end
    end

    local function write_file(write_path)
        local file = io.open(write_path, "w")
        if not file then
            return false
        end
        file:write(table.concat(lines, "\n"))
        file:write("\n")
        file:close()
        return true
    end

    if not write_file(path) then
        self:_show_error("Could not write NotebookLM answer file.")
        return
    end
    write_file(last_path)
    self:_remember_answer(result, path, id)
    if open_answer then
        self:show_saved_answer(path)
    else
        self:_show_info("NotebookLM answer saved. Open it from NotebookLM answers.")
    end
    return path
end

return NotebookLMUI
