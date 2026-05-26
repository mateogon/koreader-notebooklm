# KOReader NotebookLM

`koreader-notebooklm` is a KOReader plugin and local bridge project that will let a reader send selected text from KOReader to Google NotebookLM and view the response inside KOReader.

Current status: bridge implementation exists and can run in `mock` mode or real `nlm` mode. KOReader highlight-menu integration is not implemented yet.

Target architecture:

```text
KOReader Lua plugin -> local HTTP bridge -> NotebookLM adapter
```

For now, the bridge is shaped for local macOS development while keeping the structure portable enough for future Android/Termux or small local server setups.

## Non-goals for now

- No MCP implementation.
- No direct NotebookLM authentication inside this repo. Real mode delegates auth to the local `nlm` CLI profile.
- No all-in-Kindle implementation.

NotebookLM auth files, cookies, and generated auth artifacts such as `auth.json` must never be committed.

## Planning Docs

- [MVP plan](docs/mvp-plan.md)
- [Context from planning chat](docs/context-from-chatgpt.md)
- [NotebookLM research notes](docs/notebooklm-research.md)
