# NotebookLM MCP CLI Files

Local checkout:

```text
/Users/mateo/Developer/notebooklm-mcp-cli
```

Useful files found during local discovery:

```text
src/notebooklm_tools/cli/main.py
src/notebooklm_tools/cli/commands/notebook.py
src/notebooklm_tools/cli/commands/source.py
src/notebooklm_tools/cli/commands/doctor.py
src/notebooklm_tools/core/client.py
src/notebooklm_tools/core/auth.py
src/notebooklm_tools/core/notebooks.py
src/notebooklm_tools/core/sources.py
src/notebooklm_tools/services/notebooks.py
src/notebooklm_tools/services/sources.py
src/notebooklm_tools/mcp/server.py
src/notebooklm_tools/mcp/tools/notebooks.py
src/notebooklm_tools/mcp/tools/sources.py
```

Installed commands:

```text
nlm -> notebooklm_tools.cli.main:cli_main
notebooklm-mcp -> notebooklm_tools.mcp.server:main
```

The bridge should initially call `nlm` as a subprocess or use the NotebookLM MCP only for our own development/testing. The KOReader-facing product should remain a plain local HTTP bridge, not an MCP client.

## Code Reading Notes - 2026-05-26

The project has three useful layers:

```text
CLI commands -> services -> NotebookLMClient/core mixins
MCP tools    -> services -> NotebookLMClient/core mixins
```

This means the MCP server is not a separate NotebookLM implementation. It wraps the same service layer as the CLI.

Important files:

- `src/notebooklm_tools/cli/commands/notebook.py`
  - `nlm notebook list` calls `client.list_notebooks()` directly.
  - `nlm notebook create` calls `services.notebooks.create_notebook`.
  - `nlm notebook query` calls `services.chat.query`.
  - Supports `--json`, `--conversation-id`, `--source-ids`, `--profile`, and `--timeout`.
- `src/notebooklm_tools/services/chat.py`
  - Validates query text.
  - Optionally checks that the notebook has sources.
  - Calls `client.query(...)`.
  - Returns `answer`, `conversation_id`, `sources_used`, `citations`, and `references`.
- `src/notebooklm_tools/core/conversation.py`
  - Implements the streamed query call directly against NotebookLM internal endpoints.
  - Builds source IDs, conversation history, request body, CSRF param, `_reqid`, `bl`, and session parameters.
  - Uses the endpoint `GenerateFreeFormStreamed`.
- `src/notebooklm_tools/services/sources.py`
  - Validates source types: `url`, `text`, `drive`, `file`.
  - Routes source addition to client methods.
  - For file uploads, forces `wait=True` if a title rename is requested.
- `src/notebooklm_tools/core/sources.py`
  - Implements URL/text/Drive/file source addition.
  - File upload uses a resumable upload protocol.
  - Supported file extensions include `.pdf`, `.txt`, `.md`, `.docx`, `.csv`, `.epub`, audio, video, and images.
- `src/notebooklm_tools/cli/utils.py`
  - `get_client(profile)` loads auth from `NOTEBOOKLM_COOKIES` or the configured profile via `AuthManager`.
  - It builds a `NotebookLMClient` with cookies, CSRF token, session ID, and build label.
- `src/notebooklm_tools/mcp/tools/_utils.py`
  - MCP tools use a singleton `NotebookLMClient`.
  - Auth is loaded from env or cached tokens.
  - Sensitive params are sanitized from MCP logs.

## Bridge Adapter Recommendation

For the first real bridge adapter, use `nlm` by subprocess.

Reasons:

- It avoids importing unstable internal Python APIs into this repo immediately.
- The CLI already has JSON output for the key query/list operations.
- It naturally uses the user's existing auth profile.
- It keeps the bridge boundary simple and replaceable.

Likely first subprocess commands:

```bash
nlm notebook list --json
nlm notebook query --json --timeout 120 <NOTEBOOK_ID> "<QUESTION>"
```

Later, when the bridge contract is stable, consider an import-based adapter:

```python
from notebooklm_tools.cli.utils import get_client
from notebooklm_tools.services import chat as chat_service
from notebooklm_tools.services import notebooks as notebooks_service
from notebooklm_tools.services import sources as sources_service
```

That direct adapter would avoid subprocess overhead and parsing, but it creates tighter coupling to an unofficial internal API. It should be phase 2, not the first implementation.

## Caveats

- Local checkout `pyproject.toml` says `0.6.8`, while the installed `uv tool` command reports `0.6.9`.
- The MCP server reports latest available version `0.6.12`.
- Internal NotebookLM RPC IDs and request shapes are private and may break.
- Query responses may take up to 120 seconds by default.
- Source uploads can take longer, especially audio/video; CLI upload wait timeout defaults to 600 seconds.
