# Agent Guide

## Project Shape

`koreader-notebooklm` connects:

```text
KOReader Lua plugin -> local HTTP bridge -> NotebookLM adapter
```

Keep that boundary intact. KOReader UI code should talk to `client.lua`, `client.lua`
should talk to the bridge, and NotebookLM-specific behavior should stay behind a
bridge adapter. Do not call Google or NotebookLM directly from Lua.

Current real adapter strategy is `nlm` CLI by subprocess. This repo does not
implement NotebookLM auth, MCP server behavior, or a Kindle-only client yet.

## Development Rules

- Prefer small, reversible changes that fit the existing module boundaries.
- Keep UI logic in `plugin/notebooklm.koplugin/ui.lua`, bridge HTTP concerns in
  `client.lua`/`http.lua`, and NotebookLM integration in `bridge/src/.../adapters`.
- Preserve portability: macOS is the first target, but do not bake in assumptions
  that make Android/Termux or LAN bridge usage impossible.
- Do not commit books, generated answers, bridge data, logs, auth files, cookies,
  `auth.json`, tokens, or downloaded third-party repos.
- If the bridge listens on `0.0.0.0`, treat it as LAN-exposed. Do not add endpoints
  that mutate NotebookLM state without considering local access control.

## Validation

Run these before calling a change done:

```sh
cd bridge
uv run --extra dev pytest
uv run --extra dev python ../scripts/verify-plugin-lua.py
```

For bridge sanity:

```sh
curl -fsS http://127.0.0.1:8765/health
```

For real NotebookLM work, validate outside the bridge first:

```sh
nlm doctor
nlm notebook list --json
```

When testing inside KOReader, reinstall or copy the plugin into the active
KOReader plugins directory and restart KOReader. Do not assume Lua changes hot
reload into a running app.

## Error Handling

Do not fight repeated errors. Whenever the same error appears twice, pause and
research 3-5 plausible root-cause fixes, then choose the smallest effective fix.

## Known Failure Modes To Avoid

- **Blocking UI:** long NotebookLM calls must use background jobs and polling.
  Do not run slow HTTP/`nlm` calls synchronously from KOReader callbacks.
- **Parallel chat drift:** follow-ups should pass `conversation_id`, and asks
  should be sequenced unless explicit queueing is implemented.
- **Lost conversation context:** if a response includes `conversation_id`, persist
  it in answer history and saved answer metadata.
- **Undeclared tooling:** if a verifier imports a package, declare it in
  `bridge/pyproject.toml` dev extras and update `uv.lock`; do not rely on a global
  Python install.
- **Wrong bridge host:** `127.0.0.1` only works when KOReader and bridge run on
  the same machine. Device testing needs the Mac LAN IP and a bridge bound to
  `0.0.0.0`.
- **Gesture confusion:** KOReader single-word selection may open dictionary UI.
  Test actual multi-word highlight flows before assuming plugin menu behavior is
  broken.
- **Unreadable errors:** KOReader should show short, human-readable errors. Keep
  raw adapter output in logs or `Raw` views, not primary dialogs.
- **Large uploads:** do not casually read large EPUB/PDF files fully into memory.
  Preserve filenames/extensions and keep multipart vs bridge-local path upload
  behavior explicit.
- **Navigation dead ends:** answer/setup/history flows should support Back when
  users are in a nested NotebookLM menu. Avoid dumping users back to the native
  highlight menu after every action.

## UX Direction

The main highlight menu should expose one `NotebookLM` entry. Inside NotebookLM,
keep the primary path simple:

```text
Ask NotebookLM -> answer opens -> Follow-up / New question / Details / Close
```

Keep secondary data behind `Details`: prompt, citations, references, selected
text, sources, and raw content.

