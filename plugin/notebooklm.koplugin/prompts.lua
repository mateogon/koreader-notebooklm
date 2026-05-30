local Prompts = {}

local has_datastorage, DataStorage = pcall(require, "datastorage")
local has_logger, logger = pcall(require, "logger")

Prompts.default_language = "en"
Prompts.user_config_filename = "notebooklm-prompts.lua"
Prompts.last_config_error = nil

Prompts.language_labels = {
    en = "English",
    es = "Espanol",
}

Prompts.accept_language_headers = {
    en = "en-US,en;q=0.9",
    es = "es-ES,es;q=0.9",
}

Prompts.response_language_instructions = {
    en = "Answer in English.",
    es = "Responde en espanol.",
}

Prompts.messages = {
    en = {
        ask = "Ask",
        edit = "Edit",
        custom = "Custom",
        back = "Back",
        cancel = "Cancel",
        close = "Close",
        ask_notebooklm = "Ask NotebookLM",
        answers = "NotebookLM answers",
        relink = "Relink notebook",
        link = "Link notebook",
        status = "Status",
        language = "Language",
        edit_prompt_title = "Edit prompt",
        edit_prompt_hint = "Edit the full prompt, or add what you did not understand...",
        prompt_config_ignored = "Prompt config ignored. Using defaults.",
        enter_question = "Enter a question first.",
        no_highlight = "No highlighted text found.",
        not_linked = "This book is not linked to a NotebookLM notebook.",
        already_running = "NotebookLM question already running.",
        thinking = "NotebookLM thinking...",
        still_thinking = "NotebookLM thinking",
        answer_ready = "NotebookLM answer ready. Open from answers.",
        uploading = "NotebookLM uploading source...",
        processing_source = "NotebookLM processing source",
        notebook_ready = "NotebookLM notebook ready.",
        most_recent_first = "Most recent first",
        follow_up = "Follow-up",
        new_question = "New question",
        details = "Details",
        find = "Find",
    },
    es = {
        ask = "Preguntar",
        edit = "Editar",
        custom = "Personalizada",
        back = "Volver",
        cancel = "Cancelar",
        close = "Cerrar",
        ask_notebooklm = "Preguntar a NotebookLM",
        answers = "Respuestas NotebookLM",
        relink = "Relink notebook",
        link = "Link notebook",
        status = "Estado",
        language = "Idioma",
        edit_prompt_title = "Editar prompt",
        edit_prompt_hint = "Edita el prompt completo, o agrega que no entendiste...",
        prompt_config_ignored = "Config de prompts ignorada. Usando defaults.",
        enter_question = "Escribe una pregunta primero.",
        no_highlight = "No se encontro texto seleccionado.",
        not_linked = "Este libro no esta vinculado a un notebook de NotebookLM.",
        already_running = "Ya hay una pregunta a NotebookLM en curso.",
        thinking = "NotebookLM pensando...",
        still_thinking = "NotebookLM pensando",
        answer_ready = "Respuesta lista. Abrir desde respuestas.",
        uploading = "NotebookLM subiendo fuente...",
        processing_source = "NotebookLM procesando fuente",
        notebook_ready = "NotebookLM listo.",
        most_recent_first = "Mas recientes primero",
        follow_up = "Seguimiento",
        new_question = "Nueva pregunta",
        details = "Detalles",
        find = "Buscar",
    },
}

Prompts.presets_by_language = {
    en = {
        {
            id = "explain_simple",
            label = "Explain simply",
            prompt = "Explain this passage simply and precisely. Keep the answer brief, clear, and useful so I can keep reading.",
        },
        {
            id = "why_matters",
            label = "Why it matters",
            prompt = "Explain why this passage matters within the book's argument, story, or main idea. Be concise.",
        },
        {
            id = "book_context",
            label = "Context",
            prompt = "Give the context needed to understand this passage within the book. Do not invent if the notebook does not contain enough evidence.",
        },
        {
            id = "three_bullets",
            label = "3 bullets",
            prompt = "Summarize this passage in three short, concrete bullet points.",
        },
        {
            id = "clarify_term",
            label = "Clarify term",
            prompt = "Clarify the central term, phrase, or idea in this passage. Explain the literal meaning and the meaning in context.",
        },
    },
    es = {
        {
            id = "explain_simple",
            label = "Explica simple",
            prompt = "Explica este pasaje de forma simple y precisa. Manten la respuesta breve, clara y util para seguir leyendo.",
        },
        {
            id = "why_matters",
            label = "Por que importa",
            prompt = "Explica por que este pasaje importa dentro del argumento, historia o idea del libro. Se conciso.",
        },
        {
            id = "book_context",
            label = "Contexto",
            prompt = "Da el contexto necesario para entender este pasaje dentro del libro. No inventes si el notebook no contiene evidencia suficiente.",
        },
        {
            id = "three_bullets",
            label = "3 bullets",
            prompt = "Resume este pasaje en tres puntos breves y concretos.",
        },
        {
            id = "clarify_term",
            label = "Aclara termino",
            prompt = "Aclara el termino, frase o idea central del pasaje. Explica el sentido literal y el sentido en contexto.",
        },
    },
}

Prompts.presets = Prompts.presets_by_language[Prompts.default_language]

local function log_config_warning(message)
    if has_logger and logger and logger.warn then
        logger.warn("NotebookLM prompt config ignored:", message)
    end
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function non_empty_string(value)
    if type(value) ~= "string" then
        return nil
    end
    value = trim(value)
    if value == "" then
        return nil
    end
    return value
end

local function config_path()
    if has_datastorage and DataStorage and DataStorage.getSettingsDir then
        return DataStorage:getSettingsDir() .. "/" .. Prompts.user_config_filename
    end
    return nil
end

local function copy_prompt(prompt, fallback_order)
    return {
        id = prompt.id,
        label = prompt.label,
        prompt = prompt.prompt,
        language = prompt.language,
        order = prompt.order or fallback_order,
        _fallback_order = fallback_order,
    }
end

local function language_matches(entry_language, active_language)
    if entry_language == nil then
        return true
    end
    if type(entry_language) ~= "string" then
        return false
    end
    return Prompts.normalize_language(entry_language) == active_language
        and Prompts.presets_by_language[entry_language] ~= nil
end

local function apply_override(prompt, override, active_language)
    if type(override) ~= "table" then
        return prompt
    end
    if not language_matches(override.language, active_language) then
        return prompt
    end
    if override.enabled == false then
        return nil
    end

    local label = non_empty_string(override.label)
    if label then
        prompt.label = label
    end

    local prompt_text = non_empty_string(override.prompt)
    if prompt_text then
        prompt.prompt = prompt_text
    end

    if type(override.order) == "number" then
        prompt.order = override.order
    end

    if type(override.language) == "string" and Prompts.presets_by_language[override.language] then
        prompt.language = override.language
    end

    return prompt
end

local function load_user_config()
    Prompts.last_config_error = nil

    local path = config_path()
    if not path then
        return nil
    end

    local file = io.open(path, "r")
    if not file then
        return nil
    end
    file:close()

    local chunk, load_error = loadfile(path)
    if not chunk then
        Prompts.last_config_error = tostring(load_error or "could not load prompt config")
        log_config_warning(Prompts.last_config_error)
        return nil
    end

    local ok, config = pcall(chunk)
    if not ok then
        Prompts.last_config_error = tostring(config or "prompt config failed")
        log_config_warning(Prompts.last_config_error)
        return nil
    end

    if type(config) ~= "table" then
        Prompts.last_config_error = "prompt config must return a table"
        log_config_warning(Prompts.last_config_error)
        return nil
    end

    return config
end

local function append_custom_prompt(result, seen_ids, entry, active_language, fallback_order)
    if type(entry) ~= "table" then
        return fallback_order
    end
    if entry.enabled == false then
        return fallback_order
    end
    if not language_matches(entry.language, active_language) then
        return fallback_order
    end

    local id = non_empty_string(entry.id)
    local label = non_empty_string(entry.label)
    local prompt_text = non_empty_string(entry.prompt)
    if not id or not label or not prompt_text or seen_ids[id] then
        return fallback_order
    end

    local order = entry.order
    if type(order) ~= "number" then
        order = fallback_order
    end

    table.insert(result, {
        id = id,
        label = label,
        prompt = prompt_text,
        language = type(entry.language) == "string" and entry.language or nil,
        order = order,
        _fallback_order = fallback_order,
    })
    seen_ids[id] = true
    return fallback_order + 10
end

local function sort_prompts(prompts)
    table.sort(prompts, function(a, b)
        local a_order = type(a.order) == "number" and a.order or a._fallback_order or 9999
        local b_order = type(b.order) == "number" and b.order or b._fallback_order or 9999
        if a_order ~= b_order then
            return a_order < b_order
        end
        local a_fallback = a._fallback_order or 9999
        local b_fallback = b._fallback_order or 9999
        if a_fallback ~= b_fallback then
            return a_fallback < b_fallback
        end
        return tostring(a.id or "") < tostring(b.id or "")
    end)
end

function Prompts.normalize_language(language)
    language = tostring(language or "")
    if Prompts.presets_by_language[language] then
        return language
    end
    return Prompts.default_language
end

function Prompts.language_label(language)
    language = Prompts.normalize_language(language)
    return Prompts.language_labels[language] or language
end

function Prompts.all(language)
    language = Prompts.normalize_language(language)
    local config = load_user_config()
    local overrides = type(config) == "table" and type(config.overrides) == "table" and config.overrides or {}
    local custom = type(config) == "table" and type(config.custom) == "table" and config.custom or {}
    local defaults = Prompts.presets_by_language[language] or {}
    local result = {}
    local seen_ids = {}

    for index, prompt in ipairs(defaults) do
        local fallback_order = index * 10
        local merged = copy_prompt(prompt, fallback_order)
        merged = apply_override(merged, overrides[prompt.id], language)
        if merged then
            table.insert(result, merged)
            seen_ids[merged.id] = true
        end
    end

    local custom_order = (#defaults + 1) * 10
    for _, entry in ipairs(custom) do
        custom_order = append_custom_prompt(result, seen_ids, entry, language, custom_order)
    end

    sort_prompts(result)
    return result
end

function Prompts.text(language, key)
    language = Prompts.normalize_language(language)
    return (Prompts.messages[language] and Prompts.messages[language][key])
        or (Prompts.messages[Prompts.default_language] and Prompts.messages[Prompts.default_language][key])
        or tostring(key)
end

function Prompts.accept_language(language)
    language = Prompts.normalize_language(language)
    return Prompts.accept_language_headers[language] or Prompts.accept_language_headers[Prompts.default_language]
end

function Prompts.response_language_instruction(language)
    language = Prompts.normalize_language(language)
    return Prompts.response_language_instructions[language]
        or Prompts.response_language_instructions[Prompts.default_language]
        or ""
end

function Prompts.get(id, language)
    for _, prompt in ipairs(Prompts.all(language)) do
        if prompt.id == id then
            return prompt
        end
    end
    return nil
end

function Prompts.config_path()
    return config_path()
end

function Prompts.config_error()
    return Prompts.last_config_error
end

return Prompts
