# Local Reference Repositories

These repositories are downloaded only as local implementation references.
They are not project dependencies and must not be committed.

The local folder is ignored by git:

```text
vendor-references/
```

## AskGPT

- URL: <https://github.com/drewbaumann/AskGPT>
- Local path: `vendor-references/AskGPT`
- Reviewed snapshot: `70f9a44`
- Main files to inspect:
  - `main.lua`
  - `dialogs.lua`
  - `gpt_query.lua`
  - `chatgptviewer.lua`

Use this as the reference for the minimal highlighted-text flow.

## assistant.koplugin

- URL: <https://github.com/omer-faruq/assistant.koplugin>
- Local path: `vendor-references/assistant.koplugin`
- Reviewed snapshot: `5f1d7df`
- Main files to inspect:
  - `main.lua`
  - `assistant_dialog.lua`
  - `assistant_settings.lua`
  - `assistant_viewer.lua`
  - `assistant_utils.lua`
  - `assistant_prompts.lua`

Use this as the reference for richer KOReader UI, settings, prompt buttons,
and response viewing.

## Refresh

To refresh manually:

```sh
git -C vendor-references/AskGPT pull --ff-only
git -C vendor-references/assistant.koplugin pull --ff-only
```

If these snapshots are refreshed, update the commit hashes in this file.
