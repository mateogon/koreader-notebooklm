local Prompts = {}

Prompts.default_language = "en"

Prompts.language_labels = {
    en = "English",
    es = "Espanol",
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
        enter_question = "Enter a question first.",
        no_highlight = "No highlighted text found.",
        not_linked = "This book is not linked to a NotebookLM notebook.",
        already_running = "NotebookLM question already running.",
        thinking = "NotebookLM thinking...",
        still_thinking = "NotebookLM thinking",
        answer_ready = "NotebookLM answer ready. Open from answers.",
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
        enter_question = "Escribe una pregunta primero.",
        no_highlight = "No se encontro texto seleccionado.",
        not_linked = "Este libro no esta vinculado a un notebook de NotebookLM.",
        already_running = "Ya hay una pregunta a NotebookLM en curso.",
        thinking = "NotebookLM pensando...",
        still_thinking = "NotebookLM pensando",
        answer_ready = "Respuesta lista. Abrir desde respuestas.",
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
    return Prompts.presets_by_language[Prompts.normalize_language(language)]
end

function Prompts.text(language, key)
    language = Prompts.normalize_language(language)
    return (Prompts.messages[language] and Prompts.messages[language][key])
        or (Prompts.messages[Prompts.default_language] and Prompts.messages[Prompts.default_language][key])
        or tostring(key)
end

function Prompts.get(id, language)
    for _, prompt in ipairs(Prompts.all(language)) do
        if prompt.id == id then
            return prompt
        end
    end
    return nil
end

return Prompts
