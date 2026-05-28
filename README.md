# KOReader NotebookLM

KOReader NotebookLM is a KOReader plugin for sending selected text from KOReader
to Google NotebookLM and reading the answer inside KOReader.

```text
Kindle / KOReader lua-direct -> NotebookLM
Mac/PC -> auth sync only when credentials need refresh
```

A local Python bridge still exists for development and compatibility testing,
but the current product direction is Kindle-side `lua-direct` for daily use.

## Current Status

This is an early prototype, not a release.

Implemented and locally validated:

- KOReader plugin menu entry for selected text.
- Book-to-notebook linking and relinking.
- Preset and custom prompts.
- Local answer history in KOReader.
- Structured answer viewer with `Follow-up`, `New question`, `Details`, and optional automatic opening.
- Local FastAPI bridge with `mock` and `nlm` adapters.
- Experimental `nlm-lite` bridge adapter that talks to NotebookLM directly over HTTP without calling the `nlm` subprocess.
- Experimental KOReader `lua-direct` backend that talks to NotebookLM directly from Kindle/KOReader using a synced auth bundle.
- Auth sync script for Mac/PC to Kindle over USB or SSH.
- Background `/ask/jobs` flow so long NotebookLM answers do not block KOReader.
- Conversation continuity through NotebookLM `conversation_id` for follow-up questions.
- Basic source upload path, including preserving file extensions for EPUB/PDF detection.

Known gaps:

- Real create-and-upload from KOReader UI needs more validation and hardening.
- Bridge LAN security token is not implemented yet.
- Uploads for large books/PDFs still need memory and timeout hardening.
- NotebookLM auth generation is desktop-assisted; KOReader/Kindle does not perform Google login.
- `lua-direct` uses NotebookLM private web endpoints and needs continued hardening.
- No MCP implementation.

## Repository Layout

```text
bridge/   Python FastAPI bridge and NotebookLM adapters
plugin/   KOReader Lua plugin: notebooklm.koplugin
docs/     Architecture, setup notes, API, roadmap, validation notes
examples/ Example requests and config snippets
scripts/  Dev and smoke-test helpers
research/ Research notes and reference links
AGENTS.md Development guide for future agents
```

## Quick Start: Kindle

Install the plugin while Kindle is mounted:

```sh
scripts/install-plugin-dev.sh /Volumes/Kindle/koreader/plugins --copy
```

Sync NotebookLM auth and configure `lua-direct`:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
```

Eject Kindle, open KOReader, then run:

```text
NotebookLM -> Settings -> Lua direct smoke
```

SSH alternative:

```sh
scripts/sync-auth-to-kindle.sh --ssh <kindle-ip> --port 2222
```

## Quick Start: Bridge Development

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

`nlm-lite` uses an explicit auth bundle outside the repo. Create one:

```sh
scripts/nlm-lite-login.py --profile koreader-fresh --overwrite
```

If you already have a local `nlm` profile, you can also export it as a fallback:

```sh
scripts/export-nlm-auth-bundle.py --profile koreader-fresh
```

Install the plugin into a KOReader plugin directory:

```sh
scripts/install-plugin-dev.sh /path/to/koreader/plugins --copy
```

For bridge mode, restart KOReader and configure the bridge URL if needed:

```text
http://127.0.0.1:8765
```

## Plugin Flow

1. Select a passage in KOReader.
2. Tap `NotebookLM`.
3. Link the current book to a NotebookLM notebook if needed.
4. Choose a preset prompt or enter a custom question.
5. Continue reading while NotebookLM answers in the background.
6. Open the answer automatically, or find it later under `NotebookLM answers`.
7. From an answer, ask a follow-up in the same NotebookLM conversation or start a new question.

## Security

Do not commit NotebookLM auth files, cookies, local bridge data, books, downloaded sources, or generated answers.

The `.gitignore` excludes common local artifacts, including:

- `.env` files
- `auth.json`, cookies, token and credential files
- `bridge/data/`
- local books such as `.epub`, `.pdf`, `.azw3`, `.kfx`
- KOReader `.sdr` folders
- generated NotebookLM answer files
- downloaded reference repos

When running the bridge on `0.0.0.0` for Kindle/Android testing, keep it on a
trusted network. The preferred Kindle flow does not require a LAN bridge.

## Useful Commands

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

Check the bridge:

```sh
curl http://127.0.0.1:8765/health
```

## Next Steps

- Validate real create-and-upload from KOReader UI with more EPUB/PDF samples.
- Polish `scripts/sync-auth-to-kindle.sh` through more USB/SSH setups.
- Improve upload handling for large files and PDFs.
- Improve answer notification UX while jobs are running.
- Harden book identity beyond path/title/author.
- Keep auth generation on desktop unless NotebookLM exposes a suitable official auth/API path.

## Docs

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
