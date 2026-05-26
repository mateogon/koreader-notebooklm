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

## Research Tasks

- Verify current `notebooklm-mcp-cli` installation and CLI commands. Initial install discovery is done; live NotebookLM query still needs a controlled test.
- Inspect whether `nlm notebook query` supports non-interactive output suitable for a bridge.
- Inspect auth storage paths and document how not to commit them.
- Verify source upload formats, starting with PDF.
- Check whether EPUB is accepted directly or needs conversion/extraction.
- Decide whether to vendor, depend on, or only call `notebooklm-mcp-cli`.
- Keep notes on internal NotebookLM endpoint fragility in `research/notebooklm-mcp-cli-files.md`.
