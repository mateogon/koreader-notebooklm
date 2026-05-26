# NotebookLM Research

Current status: placeholder plus planning-chat summary. This is not a verified research report yet.

Do not store credentials, cookies, or auth artifacts in this repository.

## Current Working Assumptions

- NotebookLM personal integration is likely session/cookie based rather than API-key based.
- `notebooklm-mcp-cli` may be useful as a CLI and implementation reference.
- MCP itself is not required for the KOReader workflow.
- The first bridge can use `nlm` by subprocess if the CLI works locally.
- A direct Python adapter can come later after the CLI path proves useful.

## Local Discovery - 2026-05-26

Local installation exists:

- `nlm` is installed at `/Users/mateo/.local/bin/nlm`.
- `notebooklm-mcp` is installed at `/Users/mateo/.local/bin/notebooklm-mcp`.
- Both are managed by `uv tool` under `notebooklm-mcp-cli`.
- Installed version: `0.6.9`.
- Latest version reported by the MCP server: `0.6.12`.
- Update command reported by the MCP server: `uv tool upgrade notebooklm-mcp-cli`.

Codex MCP configuration exists:

- `~/.codex/config.toml` has an MCP server named `notebooklm-mcp`.
- The configured command is `notebooklm-mcp`.
- The NotebookLM MCP tool is available in this Codex session.

Local auth state exists, but must not be copied into this repo:

- `nlm doctor` reports a default profile named `default`.
- Cookies are present.
- CSRF token is present.
- Headless auth is available through a saved Google login.
- Auth files live under `~/.notebooklm-mcp-cli/`.

Local source checkout exists:

- Repo path: `/Users/mateo/Developer/notebooklm-mcp-cli`.
- Origin: `https://github.com/mateogon/notebooklm-mcp-cli.git`.
- Upstream: `https://github.com/jacob-bd/notebooklm-mcp-cli.git`.
- Current branch at discovery time: `codex/add-epub-file-upload`.
- Last commit at discovery time: `6043538 feat: support epub file uploads`.

Conclusion: the installed MCP server, the `nlm` CLI, and the local repo are the same project ecosystem. The current command-line install is not an editable install from the checkout; it is a `uv tool` install.

## Real EPUB Smoke - 2026-05-26

Validated with `notebooklm-mcp-cli` / `nlm` 0.6.9:

- bridge mode: `KOREADER_NOTEBOOKLM_ADAPTER=nlm`
- source path: generated minimal EPUB
- upload endpoint: `POST /sources/upload-file`
- NotebookLM adapter command path: `nlm source add --file ... --wait`
- ask endpoint: `POST /ask`
- result: NotebookLM returned an answer with citation/reference data pointing
  to the uploaded EPUB source
- cleanup: temporary smoke notebook was deleted with `nlm notebook delete --confirm`

This proves that the current bridge path can upload EPUB files through `nlm`
and query them. It does not prove KOReader-device upload runtime behavior yet.

## Research Tasks

- Verify current `notebooklm-mcp-cli` installation and CLI commands. Done for the current local install.
- Inspect whether `nlm notebook query` supports non-interactive output suitable for a bridge. Done for JSON query output.
- Inspect auth storage paths and document how not to commit them.
- Verify source upload formats, starting with PDF.
- Check whether EPUB is accepted directly or needs conversion/extraction. Done for a generated minimal EPUB through the current `nlm` path.
- Decide whether to vendor, depend on, or only call `notebooklm-mcp-cli`.
- Keep notes on internal NotebookLM endpoint fragility in `research/notebooklm-mcp-cli-files.md`.
