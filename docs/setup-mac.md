# macOS Setup

## Mock Bridge

From the repository root:

```bash
cd bridge
uv run --extra dev pytest
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 127.0.0.1 --port 8765
```

## Real NotebookLM Mode

This project does not implement NotebookLM auth directly. Use the existing `nlm` CLI auth flow:

```bash
nlm doctor
nlm notebook list --json
```

Then run the bridge with the `nlm` adapter:

```bash
cd bridge
KOREADER_NOTEBOOKLM_ADAPTER=nlm \
KOREADER_NOTEBOOKLM_DEFAULT_NOTEBOOK_ID=<NOTEBOOK_ID> \
uv run uvicorn --app-dir src koreader_notebooklm_bridge.app:app --host 0.0.0.0 --port 8765
```

For a non-default `nlm` profile:

```bash
KOREADER_NOTEBOOKLM_NLM_PROFILE=<PROFILE>
```

From KOReader on the same network, the bridge URL will be:

```text
http://<mac-lan-ip>:8765
```

## Real EPUB Smoke

With the bridge running in real `nlm` mode, run the protected smoke from
another shell:

```bash
KOREADER_NOTEBOOKLM_REAL_SMOKE=1 scripts/smoke-real-epub.sh
```

This creates a temporary NotebookLM notebook, uploads a generated EPUB through
the bridge multipart endpoint, asks a question, and deletes the temporary
notebook unless `KEEP_REAL_SMOKE_NOTEBOOK=1` is set.

Do not commit NotebookLM auth files, cookies, or `auth.json`.

## KOReader macOS Runtime Smoke

KOReader does not publish macOS binaries as release assets. The official macOS
install notes point to GitHub Actions artifacts from the release commit. For
v2026.03 on Apple Silicon, the validated artifact was:

- workflow run: <https://github.com/koreader/koreader/actions/runs/23214193860>
- artifact: `KOReader-arm64-2026.03.7z`

Run the automated smoke:

```sh
scripts/smoke-koreader-macos.sh
```

The script downloads the artifact if needed, extracts it under
`/tmp/koreader-notebooklm-macos`, installs the plugin into the app bundle,
starts a mock bridge if one is not already reachable, opens a generated EPUB in
KOReader, and checks the debug log for plugin load plus Lua stack traces.

Manual download and extract, if needed:

```sh
mkdir -p /tmp/koreader-notebooklm-macos
gh api repos/koreader/koreader/actions/artifacts/5973069038/zip \
  > /tmp/koreader-notebooklm-macos/KOReader-arm64-2026.03.7z
bsdtar -xf /tmp/koreader-notebooklm-macos/KOReader-arm64-2026.03.7z \
  -C /tmp/koreader-notebooklm-macos/extracted
```

Runtime smoke used on 2026-05-26:

1. Run `scripts/smoke-koreader-macos.sh`.
2. Open a generated EPUB with:

   ```sh
   /tmp/koreader-notebooklm-macos/extracted/KOReader.app/Contents/MacOS/koreader \
     -d /tmp/koreader-notebooklm-runtime-smoke.epub
   ```

3. Confirm KOReader logs include `Plugin loaded notebooklm` and
   `RD loaded plugin notebooklm`.
4. In KOReader, open `NotebookLM -> Status` and confirm `Bridge: OK (mock)`.
5. Run `NotebookLM -> Current book setup -> Create+Upload`.
6. Reopen `NotebookLM -> Status` and confirm the book is linked to
   `mock-created-notebook`.

## KOReader Highlight UI Smoke

After the runtime smoke, validate the real highlight menu manually:

1. Start the bridge in mock mode.
2. Open an EPUB in the KOReader macOS build.
3. Select text in the page.
4. Confirm the highlight menu shows `Ask NotebookLM` and the preset
   `NotebookLM` prompt actions.
5. Tap a preset, such as `Explica simple (NotebookLM)`.
6. If the book is unlinked, complete `Create+Upload`.
7. Confirm KOReader opens:

   ```text
   ~/Library/Application Support/koreader/settings/notebooklm-last-answer.md
   ```

8. Select text again and test `Ask NotebookLM -> Custom`.

This was validated on 2026-05-26 with the generated runtime-smoke EPUB. The
bridge received two successful `POST /ask` requests from the real KOReader UI.
