# KOReader Plugin Notes

## Reference Plugins

These notes capture implementation patterns to reuse while building
`notebooklm.koplugin`. They are not copied code.

### AskGPT

Source: <https://github.com/drewbaumann/AskGPT>

Why it matters:
- Small KOReader plugin focused on asking ChatGPT about highlighted text.
- Closest shape to the first NotebookLM plugin MVP.

Useful patterns:
- Plugin object extends `InputContainer`.
- `_meta.lua` defines `name`, `fullname`, `description`, and `version`.
- `main.lua` registers one highlight-menu action with:
  `self.ui.highlight:addToHighlightDialog(...)`.
- The callback receives `_reader_highlight_instance` and reads selected text from:
  `_reader_highlight_instance.selected_text.text`.
- It uses `NetworkMgr:runWhenOnline(...)` before the remote call.
- It opens an `InputDialog` for the user question.
- It shows a loading `InfoMessage`, schedules the query, then opens a result viewer.
- HTTP logic is isolated in a separate module.

MVP implication:
- Our first real plugin can follow this simple structure:
  highlight-menu button -> question dialog -> local bridge POST `/ask` -> result dialog.

### assistant.koplugin

Source: <https://github.com/omer-faruq/assistant.koplugin>

Why it matters:
- Larger KOReader AI assistant plugin with provider settings, custom prompts,
  highlight-menu buttons, book context, and result viewing.
- Useful as a reference for later phases, not as the shape for the first MVP.

Useful patterns:
- Registers dispatcher actions for gesture bindings.
- Adds both Tools-menu entries and highlight-menu entries.
- Uses `LuaSettings` and `DataStorage:getSettingsDir()` for persisted settings.
- Uses `self.ui.menu:registerToMainMenu(self)` for the main KOReader menu.
- Registers the highlight action with:
  `self.ui.highlight:addToHighlightDialog("ai_assistant", function(_reader_highlight_instance) ...)`.
- Reads highlighted text from:
  `_reader_highlight_instance.selected_text.text`.
- Retrieves book metadata from `ui.document:getProps()`.
- Uses `InputDialog`, `InfoMessage`, `ConfirmBox`, and a custom viewer for UX.
- Wraps network work with `NetworkMgr:runWhenOnline(...)`.
- Uses helper modules for settings, prompts, query handling, and UI.

Later-phase implications:
- Add settings persistence after the minimal bridge call works.
- Add Tools-menu setup and health/status actions after the highlight flow works.
- Add prompt buttons only after the basic NotebookLM ask path is stable.
- Consider dispatcher actions for gestures after the normal UI path is tested.

## Recommended First Plugin Slice

1. Add a `NotebookLM` button to the KOReader highlight menu.
2. Show an input dialog asking for the user question.
3. Send selected text, question, and basic book metadata to the local bridge.
4. Display the bridge response in a simple KOReader dialog/viewer.
5. Keep settings minimal: bridge URL only, with a local default.

## Open Questions For Implementation

- Local bridge host default:
  `http://127.0.0.1:8765` for emulator/local desktop, or a Mac LAN IP for a
  physical Kindle/Android device?
- JSON module choice:
  first try `json`, then fall back to `rapidjson`. The reference plugins use
  both, and the plugin should not care which one the KOReader build provides.
- First response view:
  write the answer to `notebooklm-last-answer.md` under KOReader settings and
  open it with `TextViewer.openFile`. This gives a scrollable response without
  copying a large custom viewer.
- Upload transport:
  use multipart upload from KOReader to bridge by default. Keep JSON
  `file_path` upload as a bridge-local fallback for Mac smoke tests.
