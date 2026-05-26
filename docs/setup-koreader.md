# KOReader Setup

Current status: the plugin has an initial real implementation, but still needs
testing inside KOReader on a device or emulator.

## Install For Local Testing

Copy or symlink this directory into KOReader's plugin directory:

```sh
plugin/notebooklm.koplugin
```

Typical target paths:

- Kindle: `/mnt/us/koreader/plugins/notebooklm.koplugin`
- Desktop/dev KOReader checkout: `koreader/plugins/notebooklm.koplugin`

Restart KOReader after installing the plugin.

## Configure The Bridge

Start the bridge on the Mac:

```sh
cd bridge
KOREADER_NOTEBOOKLM_ADAPTER=mock ./../scripts/run-bridge-dev.sh
```

For a physical Kindle, set the plugin bridge URL to the Mac LAN address from
KOReader's `NotebookLM -> Bridge URL` menu item, for example:

```text
http://192.168.1.20:8765
```

`127.0.0.1` only works when KOReader and the bridge run on the same device.

## Plugin Flow

From the Tools menu:

- `NotebookLM -> Status`
- `NotebookLM -> Current book setup`
- `NotebookLM -> Bridge URL`

From highlighted text:

- `Ask NotebookLM`
- prompt preset buttons such as `Explica simple (NotebookLM)`

If the current book is not linked, the plugin opens setup first.

## Upload Modes

The plugin defaults to multipart upload, where KOReader sends the book file to
the bridge via `POST /sources/upload-file`.

The bridge still supports JSON `file_path` upload via `POST /sources/upload`
for Mac-local smoke tests where the bridge can already see the file path.

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
