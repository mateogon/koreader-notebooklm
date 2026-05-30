-- Copy this file to koreader/settings/notebooklm-prompts.lua and edit it there.
-- Do not edit plugin/notebooklm.koplugin/prompts.lua for personal prompts.

return {
    version = 1,
    overrides = {
        explain_simple = {
            label = "Explain simply",
            prompt = "Explain this passage in plain language, with one analogy if it helps.",
            enabled = true,
            order = 10,
        },
        why_matters = {
            enabled = false,
        },
    },
    custom = {
        {
            id = "connect_to_book",
            label = "Connect to book",
            language = "en",
            enabled = true,
            order = 50,
            prompt = "Connect this passage to the book's larger argument. Be concise and cite the source when possible.",
        },
        {
            id = "conecta_con_libro",
            label = "Conecta con libro",
            language = "es",
            enabled = true,
            order = 50,
            prompt = "Conecta este pasaje con el argumento general del libro. Se breve y cita la fuente si es posible.",
        },
    },
}
