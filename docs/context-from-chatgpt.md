# Context From Planning Chat

This file records the useful decisions and assumptions extracted from the prior ChatGPT planning conversation.

## Product Shape

The project is intentionally named `koreader-notebooklm` so it is easy to find by searching for KOReader and NotebookLM. Avoid creative naming for the repo and plugin.

Recommended names:

- Project: `KOReader NotebookLM`
- Repo: `koreader-notebooklm`
- Plugin: `notebooklm.koplugin`
- Bridge package: `koreader-notebooklm-bridge`
- Local API: `KOReader NotebookLM Bridge`
- Future DB/mapping file: `koreader-notebooklm.sqlite`

Visible label inside KOReader:

- `Ask NotebookLM`
- Spanish localization later: `Preguntar a NotebookLM`

## Architecture Decision

Primary architecture:

```text
KOReader Lua plugin -> bridge HTTP JSON -> NotebookLM adapter
```

The plugin should not know how NotebookLM works. It should only know the bridge URL, user settings, selected text, prompt choice, and response display.

## Why Start With A Bridge

KOReader can handle selection capture, highlight-menu actions, settings, local state, prompts, and response display. The hard and fragile parts are NotebookLM authentication, source upload, session handling, and internal Google/NotebookLM changes. Those belong behind a bridge boundary first.

MCP is not needed for the product flow. The `notebooklm-mcp-cli` project may still be useful as a CLI or reference implementation, but KOReader should not talk MCP.

## Avoid In The MVP

- KOReader calling NotebookLM directly.
- KOReader talking MCP.
- Running the full `notebooklm-mcp-cli` package on Kindle.
- Automatic book upload on day one.
- Notebook creation or linking from KOReader on day one.
- Hardcoding the Mac IP address into the plugin.

## NotebookLM CLI Assumption To Validate

The planning chat assumed that `notebooklm-mcp-cli` provides an `nlm` CLI with operations around login, notebook listing, notebook creation, querying, and source upload.

Examples mentioned in the chat:

```bash
nlm login
nlm login --check
nlm doctor
nlm notebook list --json
nlm notebook create "KOReader Bridge Test"
nlm source add <NOTEBOOK_ID> --file ./test.pdf --wait
nlm notebook query <NOTEBOOK_ID> "Explain this document simply"
```

This must be verified locally before building real bridge behavior.

## Authentication Context

Authentication is intentionally deferred. The chat framed NotebookLM auth as likely session/cookie based rather than an API-key flow.

Never commit:

- cookies
- `auth.json`
- browser session exports
- CSRF/session metadata
- profile auth directories

## Future All-in-Kindle Track

Do not discard all-in-Kindle, but keep it separate from the main MVP.

First viability checks on a Kindle would include:

```bash
uname -a
df -h
free -m || sed -n '1,8p' /proc/meminfo
python3 --version
python --version
pip --version || python3 -m pip --version
which curl
openssl version
```

If Python, HTTPS, certificates, cookies, CPU, and memory are workable, a future path could be:

```text
KOReader Lua -> mini local Python/Lua client -> NotebookLM
```

The preferred future all-in-Kindle route would be a small client with only list/create/upload/query behavior, not a full port of `notebooklm-mcp-cli`.

## Key Risk

NotebookLM personal does not have a stable official consumer API for this use case. Treat its integration as adapter-backed and replaceable. The stable part of this project should be KOReader UX plus the local bridge contract.

