# KOReader Setup

TODO: Document how to install `notebooklm.koplugin` into KOReader.

## Reference Pattern

The first plugin implementation should follow the same broad KOReader pattern
used by existing AI/highlight plugins:

- register a highlight-menu button with `ui.highlight:addToHighlightDialog`
- read selected text from `_reader_highlight_instance.selected_text.text`
- open an input dialog for the user's question
- call the local bridge, not NotebookLM directly
- show the returned answer inside KOReader

Reference plugins reviewed:

- <https://github.com/drewbaumann/AskGPT>
- <https://github.com/omer-faruq/assistant.koplugin>
