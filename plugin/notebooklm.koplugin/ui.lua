local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local NotebookLMUI = {}

function NotebookLMUI:new(opts)
    opts = opts or {}
    return setmetatable({
        plugin = opts.plugin,
        client = opts.client,
        storage = opts.storage,
        settings = opts.settings,
        prompts = opts.prompts,
        input_dialog = nil,
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

function NotebookLMUI:_book()
    return self.storage:get_book_context(self.plugin.ui)
end

function NotebookLMUI:_link()
    return self.storage:get_link(self.plugin.ui)
end

function NotebookLMUI:_sync_bridge_link()
    local book = self:_book()
    local response = self.client:get_book(book.book_id)
    if response and response.book and response.book.notebook_id then
        return self:_save_link(response.book)
    end
    return self:_link()
end

function NotebookLMUI:_save_link(link)
    return self.storage:save_link(self.plugin.ui, link)
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

function NotebookLMUI:show_setup(on_ready)
    local book = self:_book()
    local link = self:_sync_bridge_link()
    local link_text = link and link.notebook_id
        and ("Current notebook:\n" .. tostring(link.notebook_title or link.notebook_id))
        or "This book is not linked to a NotebookLM notebook yet."

    self.input_dialog = InputDialog:new{
        title = _("NotebookLM setup"),
        description = table.concat({
            tostring(book.title or "Current book"),
            "",
            link_text,
        }, "\n"),
        input_hint = _("Notebook title or notebook ID"),
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        self:_close_input()
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
                        end
                    end,
                },
            },
            {
                {
                    text = _("List"),
                    callback = function()
                        local filter = self.input_dialog:getInputText()
                        self:_close_input()
                        self:show_notebook_picker(filter, on_ready)
                    end,
                },
                {
                    text = _("Create"),
                    callback = function()
                        local title = self.input_dialog:getInputText()
                        self:_close_input()
                        self:create_notebook(title, false, on_ready)
                    end,
                },
                {
                    text = _("Create+Upload"),
                    callback = function()
                        local title = self.input_dialog:getInputText()
                        self:_close_input()
                        self:create_notebook(title, true, on_ready)
                    end,
                },
            },
        },
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:show_notebook_picker(filter, on_ready)
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
                self:show_setup(on_ready)
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

function NotebookLMUI:create_notebook(title, upload_after, on_ready)
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
    end
end

function NotebookLMUI:ask_highlight(highlighted_text)
    if not highlighted_text or highlighted_text == "" then
        self:_show_error("No highlighted text found.")
        return
    end
    local link = self:_sync_bridge_link()
    if not link or not link.notebook_id then
        self:show_setup(function()
            self:show_prompt_picker(highlighted_text)
        end)
        return
    end
    self:show_prompt_picker(highlighted_text)
end

function NotebookLMUI:ask_with_prompt(highlighted_text, prompt, prompt_label)
    if not highlighted_text or highlighted_text == "" then
        self:_show_error("No highlighted text found.")
        return
    end
    local link = self:_sync_bridge_link()
    if not link or not link.notebook_id then
        self:show_setup(function()
            self:send_ask(highlighted_text, prompt, prompt_label)
        end)
        return
    end
    self:send_ask(highlighted_text, prompt, prompt_label)
end

function NotebookLMUI:show_prompt_picker(highlighted_text)
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
                self:show_custom_question(highlighted_text)
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
        title = _("Ask NotebookLM"),
        description = "Choose a prompt for the highlighted passage.",
        input_type = "text",
        input_hint = _("Optional custom question"),
        buttons = rows,
    }
    UIManager:show(self.input_dialog)
end

function NotebookLMUI:show_custom_question(highlighted_text)
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
                    text = _("Cancel"),
                    callback = function()
                        self:_close_input()
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

function NotebookLMUI:send_ask(highlighted_text, prompt, prompt_label)
    local link = self:_sync_bridge_link()
    if not link or not link.notebook_id then
        self:_show_error("This book is not linked to a NotebookLM notebook.")
        return
    end

    local book = self:_book()
    local loading = InfoMessage:new{
        icon = "book.opened",
        text = _("Asking NotebookLM..."),
        timeout = 0,
    }
    UIManager:show(loading)
    UIManager:scheduleIn(0.1, function()
        local response, err = self.client:ask({
            notebook_id = link.notebook_id,
            selected_text = highlighted_text,
            prompt = prompt,
            book = {
                title = book.title,
                author = book.author,
                path = book.path,
                position = book.position,
            },
        })
        UIManager:close(loading)
        if err then
            self:_show_error(err)
            return
        end
        self:show_answer({
            prompt_label = prompt_label,
            prompt = prompt,
            selected_text = highlighted_text,
            answer = response.answer,
            notebook_id = response.notebook_id or link.notebook_id,
            sources_used = response.sources_used,
            references = response.references,
            citations = response.citations,
        })
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

function NotebookLMUI:show_answer(result)
    local path = DataStorage:getSettingsDir() .. "/notebooklm-last-answer.md"
    local lines = {
        "# NotebookLM",
        "",
        "Prompt: " .. tostring(result.prompt_label or "Question"),
        "Notebook ID: " .. tostring(result.notebook_id or ""),
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

    local file = io.open(path, "w")
    if not file then
        self:_show_error("Could not write NotebookLM answer file.")
        return
    end
    file:write(table.concat(lines, "\n"))
    file:write("\n")
    file:close()
    TextViewer.openFile(path)
end

return NotebookLMUI
