# KOReader Plugin

Initial KOReader plugin for asking NotebookLM about highlighted text through a
local bridge.

Current status:

- registers a Tools menu entry
- registers highlight-menu actions
- links the current book to a NotebookLM notebook
- can create a notebook through the bridge
- can upload the current book file through the bridge multipart endpoint
- sends highlighted text and preset/custom prompts to `/ask`
- shows the last answer in KOReader's text viewer

The plugin talks through `client.lua`; UI code does not call HTTP directly.

From the repository root, run this lightweight load test:

```sh
uv run --with lupa scripts/verify-plugin-lua.py
```
