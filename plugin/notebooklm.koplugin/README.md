# KOReader Plugin

KOReader plugin for asking NotebookLM about highlighted text through the
Kindle-side `lua-direct` runtime.

Current status:

- registers a Tools menu entry
- registers highlight-menu actions
- links the current book to a NotebookLM notebook
- can create a NotebookLM notebook
- can upload the current book file from KOReader
- sends highlighted text and preset/custom prompts to NotebookLM
- loads user prompt overrides/custom presets from `koreader/settings/notebooklm-prompts.lua`
- shows saved answers in a structured answer viewer
- exposes language, auth bundle, notebook, upload, and answer-opening settings
  from the Tools menu

The `Language` setting localizes plugin UI and prompt presets. For NotebookLM
requests it also sends the matching `hl` / `Accept-Language` values and prefixes
the internal question with an explicit response-language instruction.

Prompt defaults are versioned in `prompts.lua`. Personal prompt edits should live
outside the plugin in `koreader/settings/notebooklm-prompts.lua`; use
`examples/notebooklm-prompts.example.lua` and `scripts/validate-prompts.sh` from
the repository root before syncing to Kindle.

The plugin talks through `client.lua`; UI code does not call NotebookLM
directly.

From the repository root, run this lightweight load test:

```sh
uv run --with lupa scripts/verify-plugin-lua.py
```
