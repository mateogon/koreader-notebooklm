local Prompts = {}

Prompts.presets = {
    {
        id = "explain_simple",
        label = "Explica simple",
        prompt = "Explica esta frase de forma simple y precisa. Manten la respuesta breve, clara y util para seguir leyendo.",
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
}

function Prompts.get(id)
    for _, prompt in ipairs(Prompts.presets) do
        if prompt.id == id then
            return prompt
        end
    end
    return nil
end

return Prompts
