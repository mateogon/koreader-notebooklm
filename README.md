# KOReader NotebookLM

KOReader NotebookLM is a KOReader plugin plus a local Python bridge for sending selected text from KOReader to Google NotebookLM and reading the answer inside KOReader.

```text
KOReader Lua plugin -> local HTTP bridge -> NotebookLM adapter
```

The current bridge target is macOS. The structure is intentionally kept portable so a future Android/Termux or small local-server setup can reuse the same plugin boundary.

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
- Background `/ask/jobs` flow so long NotebookLM answers do not block KOReader.
- Conversation continuity through NotebookLM `conversation_id` for follow-up questions.
- Basic source upload path, including preserving file extensions for EPUB/PDF detection.

Known gaps:

- Real Kindle/device validation is still pending.
- Real create-and-upload from KOReader UI needs more validation and hardening.
- Bridge LAN security token is not implemented yet.
- Uploads for large books/PDFs still need memory and timeout hardening.
- NotebookLM auth is delegated to the local `nlm` CLI profile.
- `nlm-lite` is experimental and still needs live hardening before it can guide a Lua direct client.
- No direct NotebookLM auth, no MCP implementation, and no all-in-Kindle client yet.

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

## Quick Start: macOS Development

Install bridge dependencies:

```sh
cd bridge
uv sync --extra dev
```

Run the bridge in mock mode:

```sh
KOREADER_NOTEBOOKLM_ADAPTER=mock ../scripts/run-bridge-dev.sh
```

Run the bridge in real `nlm` mode:

```sh
KOREADER_NOTEBOOKLM_ADAPTER=nlm \
KOREADER_NOTEBOOKLM_NLM_COMMAND=/path/to/nlm \
../scripts/run-bridge-dev.sh
```

The real mode assumes `nlm` is already installed and authenticated. This repo does not manage NotebookLM credentials.

Run the experimental direct adapter:

```sh
KOREADER_NOTEBOOKLM_ADAPTER=nlm-lite \
KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID=<NOTEBOOK_ID> \
../scripts/run-bridge-dev.sh
```

`nlm-lite` uses an explicit auth bundle outside the repo. Create one without `nlm`:

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

Then restart KOReader and configure the bridge URL if needed:

```text
http://127.0.0.1:8765
```

## Plugin Flow

1. Select a passage in KOReader.
2. Tap `NotebookLM`.
3. Link the current book to a NotebookLM notebook if needed.
4. Choose a preset prompt or enter a custom question.
5. Continue reading while the bridge asks NotebookLM in the background.
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

When running the bridge on `0.0.0.0` for Kindle/Android testing, keep it on a trusted network. A local bridge token is planned but not implemented yet.

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

- Validate on a physical Kindle or Android/Termux KOReader setup.
- Validate real create-and-upload from KOReader UI with more EPUB/PDF samples.
- Add an optional bridge API token for LAN use.
- Improve upload handling for large files and PDFs.
- Improve answer notification UX while jobs are running.
- Harden book identity beyond path/title/author.
- Keep the all-in-Kindle path as an experimental future direction.

## Docs

- [Architecture](docs/architecture.md)
- [Bridge API](docs/api.md)
- [macOS setup](docs/setup-mac.md)
- [Fresh PC auth setup](docs/setup-pc-auth.md)
- [KOReader setup](docs/setup-koreader.md)
- [Kindle setup](docs/setup-kindle.md)
- [Roadmap](docs/roadmap.md)
- [Validation audit](docs/validation-audit.md)
- [NLM Lite plan](docs/nlm-lite-plan.md)
