# Alpha Validation Checklist

Use this before tagging or publishing an alpha zip. The goal is to prove the
Kindle `lua-direct` path works with real reading material, not just mocks.

## Build Gate

Run from the repository root:

```sh
scripts/validate-prompts.sh examples/notebooklm-prompts.example.lua
cd bridge
uv run --extra dev python ../scripts/verify-plugin-lua.py
uv run --extra dev pytest
```

Package the plugin:

```sh
scripts/package-plugin.sh --version v0.1.0-alpha
```

Expected artifact:

```text
dist/notebooklm.koplugin-v0.1.0-alpha.zip
```

## Install Gate

USB path:

```sh
scripts/install-plugin-dev.sh /Volumes/Kindle/koreader/plugins --copy
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
```

SSH path:

```sh
scripts/install-plugin-dev.sh /path/to/local/plugins --copy
scripts/sync-auth-to-kindle.sh --ssh <kindle-ip> --port 2222
```

Then restart KOReader and run:

```text
NotebookLM -> Settings -> Lua direct smoke
```

Pass criteria:

- Smoke test shows NotebookLM notebooks.
- Smoke test returns a NotebookLM answer.
- No Lua traceback appears.

## Real Book Matrix

Test at least these cases:

| Case | Expected result |
| --- | --- |
| Existing notebook + small EPUB | Link succeeds, ask returns answer. |
| Create+Upload + EPUB accepted by NotebookLM | Original EPUB remains as source, ask works. |
| Create+Upload + EPUB rejected by NotebookLM | Markdown fallback uploads, ask works. |
| Existing notebook + PDF | Link succeeds, ask returns answer. |
| Large book | Either succeeds or shows a clear size/timeout error. |

For each case, validate:

- `NotebookLM` highlight entry appears for multi-word selection.
- Link/relink works.
- Prompt preset ask works.
- Edited preset ask works.
- Custom ask works.
- Answer opens automatically or from the answer bubble.
- Follow-up keeps conversation context.
- `NotebookLM answers` shows the latest answer.
- KOReader remains usable while waiting for the answer.
- No raw auth/cookie data is shown in UI or logs.

## Prompt Customization Gate

Create a local prompt config:

```sh
cp examples/notebooklm-prompts.example.lua ~/notebooklm-prompts.lua
scripts/validate-prompts.sh ~/notebooklm-prompts.lua
scripts/sync-prompts-to-kindle.sh --file ~/notebooklm-prompts.lua --ssh <kindle-ip> --port 2222
```

Restart KOReader.

Pass criteria:

- A disabled default prompt disappears.
- A custom prompt appears.
- The custom prompt sends and returns an answer.
- Invalid prompt config falls back to defaults without crashing.

## Release Notes Minimum

Before publishing an alpha, document:

- Tested KOReader version.
- Tested device.
- Tested auth sync method: USB or SSH.
- Tested book formats and approximate sizes.
- Known upload failures.
- Any NotebookLM private endpoint breakage.
- Exact commit SHA used for the zip.
