# KOReader NotebookLM

KOReader NotebookLM is an experimental KOReader plugin that lets you select text
while reading, ask Google NotebookLM about that passage, and read the answer
inside KOReader.

The current direction is:

```text
Kindle / KOReader plugin -> lua-direct NotebookLM client -> NotebookLM
Mac/PC -> auth generation and sync only
```

A local Python bridge still exists for development and compatibility testing, but
the daily-use path is moving toward Kindle-side `lua-direct`.

## What Works Today

This is an early prototype, not a stable release.

Locally validated:

- Highlight-menu entry: `NotebookLM`.
- Book-to-notebook linking and relinking.
- Create notebook from KOReader.
- Upload the current book from KOReader.
- EPUB/PDF original upload attempt, with Markdown fallback extraction when
  NotebookLM rejects an EPUB during processing.
- Preset, editable preset, custom, follow-up, and new-question flows.
- Background answer jobs so long NotebookLM responses do not block reading.
- Small on-screen answer bubble while a question is running.
- Structured answer viewer with `Follow-up`, `New question`, `Details`, and
  optional automatic opening.
- Local answer history in KOReader.
- Prompt preset customization from `koreader/settings/notebooklm-prompts.lua`.
- Auth sync from Mac/PC to Kindle over USB or SSH.
- Python bridge with `mock`, `nlm`, and experimental `nlm-lite` adapters.

Important limitations:

- NotebookLM auth is generated on Mac/PC and copied to Kindle. KOReader does not
  perform Google login.
- `lua-direct` uses private NotebookLM web endpoints, so it can break if Google
  changes NotebookLM internals.
- Uploads for large books/PDFs still need more memory and timeout hardening.
- Create-and-upload works in local testing but still needs more real-book
  validation.
- This project does not implement MCP.
- This project does not include or commit NotebookLM auth cookies.

## Repository Layout

```text
bridge/   Python FastAPI bridge and NotebookLM adapters
plugin/   KOReader Lua plugin: notebooklm.koplugin
docs/     Architecture, setup notes, roadmap, validation notes
examples/ Example requests and config snippets
scripts/  Install, auth sync, prompt sync, and smoke-test helpers
research/ Research notes and reference links
AGENTS.md Development guide for future agents
```

## Prerequisites

For Kindle use:

- A Kindle or KOReader-capable device with KOReader installed.
- A Mac/PC that can open Chrome for NotebookLM login.
- USB storage access to Kindle, or SSH access to Kindle.
- A Google account with access to NotebookLM.

For bridge/dev work:

- Python with `uv`.
- KOReader desktop or a KOReader plugin directory for local testing.

## Quick Start: Kindle

1. Install the plugin while Kindle is mounted:

```sh
scripts/install-plugin-dev.sh /Volumes/Kindle/koreader/plugins --copy
```

2. Generate/sync NotebookLM auth and configure `lua-direct`:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
```

SSH alternative:

```sh
scripts/sync-auth-to-kindle.sh --ssh <kindle-ip> --port 2222
```

3. Eject Kindle, open KOReader, then run:

```text
NotebookLM -> Settings -> Lua direct smoke
```

If the smoke test succeeds, select text in a book and tap:

```text
NotebookLM -> Ask NotebookLM
```

## Reading Flow

1. Open a book in KOReader.
2. Select a passage.
3. Tap `NotebookLM`.
4. If the book is not linked, link it to an existing NotebookLM notebook or create
   a new one.
5. Pick a preset prompt, edit a preset, or type a custom question.
6. Keep reading while NotebookLM answers in the background.
7. Open the answer automatically, from the answer bubble, or later from
   `NotebookLM answers`.
8. From an answer, ask a follow-up in the same NotebookLM conversation or start a
   new question.

## Auth Model

NotebookLM authentication is intentionally desktop-assisted:

```text
Mac/PC Chrome login -> local auth bundle -> sync to Kindle -> KOReader lua-direct
```

Use:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
```

or:

```sh
scripts/sync-auth-to-kindle.sh --ssh <kindle-ip> --port 2222
```

The auth bundle is sensitive. Treat it like a password. It is ignored by git and
must never be committed.

## Book Uploads

When you choose create-and-upload, the plugin first tries to upload the original
book file with its original extension. If NotebookLM later reports a processing
failure for an EPUB, the plugin can fall back to a Markdown export generated from
KOReader's own document engine.

This gives two useful paths:

- If NotebookLM accepts the original file, keep the original source.
- If NotebookLM rejects the EPUB during processing, upload readable extracted
  Markdown instead.

This fallback is meant for practical reading workflows, not perfect book
conversion. The goal is to give NotebookLM usable text with a recognizable source
title.

## Prompt Presets

Built-in prompt defaults live in:

```text
plugin/notebooklm.koplugin/prompts.lua
```

Personal edits should live outside the plugin so updates do not overwrite them:

```text
koreader/settings/notebooklm-prompts.lua
```

Start from the example:

```sh
cp examples/notebooklm-prompts.example.lua ~/notebooklm-prompts.lua
scripts/validate-prompts.sh ~/notebooklm-prompts.lua
```

Sync to Kindle over USB:

```sh
scripts/sync-prompts-to-kindle.sh --file ~/notebooklm-prompts.lua --usb /Volumes/Kindle
```

Or over SSH:

```sh
scripts/sync-prompts-to-kindle.sh --file ~/notebooklm-prompts.lua --ssh <kindle-ip> --port 2222
```

The config can:

- Override a built-in prompt by ID.
- Disable a built-in prompt.
- Add custom prompts.
- Limit custom prompts to a language such as `en` or `es`.

Restart KOReader after syncing prompts to force a clean plugin reload.

## Language

The plugin supports English and Spanish UI/prompt presets today. The language
setting also sends NotebookLM locale hints and adds an explicit response-language
instruction to the question.

That explicit instruction matters because NotebookLM's `hl` and
`Accept-Language` hints alone were not enough in live testing to reliably control
the answer language.

## Bridge Development

Bridge mode is useful for tests, mocks, and adapter development. It is not the
normal Kindle UI path.

Install bridge dependencies:

```sh
cd bridge
uv sync --extra dev
```

Run the bridge in mock mode:

```sh
KOREADER_NOTEBOOKLM_ADAPTER=mock ../scripts/run-bridge-dev.sh
```

Run the bridge with the experimental direct Python adapter:

```sh
KOREADER_NOTEBOOKLM_ADAPTER=nlm-lite \
KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID=<NOTEBOOK_ID> \
../scripts/run-bridge-dev.sh
```

Create an `nlm-lite` auth bundle outside the repo:

```sh
scripts/nlm-lite-login.py --profile koreader-fresh --overwrite
```

If you already have a local `nlm` profile, export it as a fallback:

```sh
scripts/export-nlm-auth-bundle.py --profile koreader-fresh
```

## Development Checks

Run bridge tests:

```sh
cd bridge
uv run --extra dev pytest
```

Run the Lua plugin smoke test:

```sh
cd bridge
uv run --extra dev python ../scripts/verify-plugin-lua.py
```

Validate prompt config:

```sh
scripts/validate-prompts.sh examples/notebooklm-prompts.example.lua
```

Check the bridge:

```sh
curl http://127.0.0.1:8765/health
```

## Security

Do not commit:

- NotebookLM auth bundles
- Google cookies
- `auth.json`
- `.env` files
- books or downloaded source documents
- generated answer history
- local bridge data
- local prompt config files

The `.gitignore` excludes common local artifacts, including `.env`, auth
bundles, cookies, `bridge/data/`, local books, KOReader `.sdr` folders, generated
answers, and `notebooklm-prompts.lua`.

When running the bridge on `0.0.0.0` for Kindle/Android testing, keep it on a
trusted network. The preferred Kindle flow does not require a LAN bridge.

## Next Steps

- Validate create-and-upload with more EPUB/PDF samples.
- Harden large upload handling.
- Polish the answer bubble and answer viewer after more Kindle usage.
- Improve prompt preset customization based on real reading workflows.
- Harden book identity beyond path/title/author.
- Keep auth generation on desktop unless NotebookLM exposes a suitable official
  auth/API path.

## Documentation

- [Architecture](docs/architecture.md)
- [Bridge API](docs/api.md)
- [macOS setup](docs/setup-mac.md)
- [Fresh PC auth setup](docs/setup-pc-auth.md)
- [Auth sync](docs/auth-sync.md)
- [KOReader setup](docs/setup-koreader.md)
- [Kindle setup](docs/setup-kindle.md)
- [Roadmap](docs/roadmap.md)
- [Validation audit](docs/validation-audit.md)
- [NLM Lite plan](docs/nlm-lite-plan.md)
- [Lua port plan](docs/lua-port-plan.md)
