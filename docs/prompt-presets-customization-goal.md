# Goal: Customizable Prompt Presets

## Goal

Implement customizable NotebookLM prompt presets for the KOReader plugin while keeping the built-in defaults versioned in code and allowing user-specific overrides/custom prompts from an external settings file that is easy to edit on Mac/PC and sync to Kindle.

## Context

- Current built-in prompt presets live in `plugin/notebooklm.koplugin/prompts.lua`.
- KOReader text input on Kindle is slow, so serious prompt editing should be done on Mac/PC.
- Kindle UI should stay focused on fast reading flow: choose preset, optionally edit once, ask.
- Default prompts should remain editable without modifying `prompts.lua`, because plugin updates would overwrite direct edits.
- The desired model is:

```text
defaults in prompts.lua + user overrides/custom prompts in settings/notebooklm-prompts.lua
```

## Proposed User Config

Create a user-editable file:

```text
koreader/settings/notebooklm-prompts.lua
```

Example:

```lua
return {
    version = 1,
    overrides = {
        explain_simple = {
            label = "Explica simple",
            prompt = "Explica este pasaje en lenguaje simple, con una analogia si ayuda.",
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
            label = "Conecta con libro",
            language = "es",
            enabled = true,
            order = 50,
            prompt = "Conecta este pasaje con el argumento general del libro.",
        },
    },
}
```

## Implementation Plan

1. Add prompt config loading.
   - Add a small module or extend `prompts.lua` to load `DataStorage:getSettingsDir() .. "/notebooklm-prompts.lua"`.
   - Keep current built-in prompts as defaults.
   - Merge `overrides` by prompt `id`.
   - Append `custom` prompts.
   - Filter `enabled=false`.
   - Sort by `order`, falling back to built-in order.
   - Preserve language behavior: prompts can specify `language`; defaults come from current plugin language.

2. Make invalid user config safe.
   - If `notebooklm-prompts.lua` is missing, use defaults.
   - If the file has syntax/runtime errors, show a short warning and fall back to defaults.
   - Ignore malformed entries instead of breaking the plugin.
   - Detect duplicate custom IDs and keep the first valid one.

3. Add Mac/PC workflow scripts.
   - `scripts/validate-prompts.sh`
   - `scripts/sync-prompts-to-kindle.sh`
   - Optional later: `scripts/edit-prompts-mac.sh`
   - Validation should check:
     - file returns a table
     - prompt IDs are strings
     - labels/prompts are non-empty strings when provided
     - `enabled` is boolean or nil
     - `order` is number or nil
     - language is supported or nil

4. Add starter example.
   - Add `examples/notebooklm-prompts.example.lua`.
   - Include examples for overriding a default, disabling a default, and adding a custom prompt.

5. Improve KOReader UI lightly.
   - Keep the prompt picker simple.
   - Continue showing preset rows with `Send` and `Edit`.
   - Add `Save custom as preset` only if it can be done cleanly without turning Kindle into a full prompt editor.
   - Do not build a complex prompt manager on Kindle yet.

6. Update docs.
   - Document `notebooklm-prompts.lua` in `README.md` and `plugin/notebooklm.koplugin/README.md`.
   - Document Mac/PC edit and USB/SSH sync flow.
   - Explain that `prompts.lua` is for built-in defaults and user edits belong in `notebooklm-prompts.lua`.

## Constraints

- Do not require editing `prompts.lua` for user customization.
- Do not make Kindle text entry the primary customization workflow.
- Do not break existing defaults if user config is absent or invalid.
- Do not add NotebookLM-specific business logic to UI code beyond prompt selection/editing.
- Keep the highlight flow fast: `NotebookLM -> Ask -> prompt -> answer`.
- Keep all auth, cookies, books, generated answers, and user prompt files out of git unless they are examples.

## Stop Rules

- Pause before building a full Kindle-side prompt manager with reorder/delete/edit screens.
- Pause if config persistence requires a format more complex than a Lua table.
- Pause if syncing prompts starts overlapping with auth sync in a way that could overwrite auth settings.
- Pause if adding scripts risks copying private prompt files into the repo.

## Done Means

- Built-in defaults still work without any user config.
- A user can override a built-in prompt by ID from `notebooklm-prompts.lua`.
- A user can disable a built-in prompt from `notebooklm-prompts.lua`.
- A user can add a custom prompt from `notebooklm-prompts.lua`.
- Prompt picker shows merged prompts in deterministic order.
- Invalid prompt config does not crash KOReader.
- Example config exists under `examples/`.
- Validation passes:

```sh
cd bridge
uv run --extra dev python ../scripts/verify-plugin-lua.py
uv run --extra dev pytest
```

## Suggested First Steps

1. Refactor `prompts.lua` so `Prompts.all(language)` returns merged defaults plus user config.
2. Add tests to `scripts/verify-plugin-lua.py` for override, disable, custom prompt, and invalid config fallback.
3. Add `examples/notebooklm-prompts.example.lua`.
4. Add a small validator/sync script only after the loader format is stable.
