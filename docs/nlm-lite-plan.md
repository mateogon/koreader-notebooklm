# NLM Lite Plan

Status: in progress. The first bridge adapter implementation exists with
fixture-based unit tests; live validation is opt-in and still required before
the Lua port.

## Validation Summary

The plan is valid with one framing rule:

```text
nlm-lite should first become a bridge adapter, not a KOReader feature.
```

That keeps the current KOReader contract stable while we prove the NotebookLM
direct HTTP protocol in a normal Python/debugging environment. Only after the
bridge adapter reaches parity with the current `nlm` subprocess adapter should
we port the small core to Lua.

Validated against the current repo:

- The bridge already has an adapter boundary in `adapters/base.py`.
- `adapters/factory.py` can select a new adapter from
  `KOREADER_NOTEBOOKLM_ADAPTER`.
- The public bridge contract already covers the needed operations:
  `GET /notebooks`, `POST /notebooks`, `POST /ask`, `POST /ask/jobs`,
  `POST /sources/upload`, and `POST /sources/upload-file`.
- KOReader already talks through `client.lua`, so no UI changes are required
  for the first `nlm-lite` bridge tests.
- Existing `nlm` adapter behavior is the parity target.

Validated against the observed `nlm` implementation:

- Auth is cookie-based, not API-key-based.
- CSRF/session/build label can be refreshed from the NotebookLM page while
  cookies are valid.
- NotebookLM calls use private `batchexecute` RPC ids.
- File upload uses a resumable upload protocol, not ordinary multipart.
- Query/follow-up support depends on `conversation_id` and conversation history
  handling.

Main risk:

```text
The protocol is private and may drift. Keep nlm-lite small, tested with
fixtures, and easy to compare against nlm.
```

## Goal

Build a lightweight NotebookLM direct adapter inside the bridge before trying to
port anything to Kindle Lua.

The current working path is:

```text
KOReader plugin -> bridge -> nlm subprocess -> NotebookLM
```

The next experimental path is:

```text
KOReader plugin -> bridge -> nlm-lite direct HTTP -> NotebookLM
```

If that works, the future target is:

```text
KOReader Lua direct client -> NotebookLM
Mac/Windows bridge -> auth bootstrap/export only
```

`nlm-lite` is not a separate product. It is the portable core we can later
translate to Lua.

## Non-goals

- Do not implement Google login.
- Do not replace the working `nlm` adapter yet.
- Do not remove or weaken the existing `mock` adapter.
- Do not expose raw auth over LAN without pairing/token protection.
- Do not add MCP.
- Do not port to Lua until the direct HTTP protocol is proven in the bridge.
- Do not copy the full `notebooklm-mcp-cli` package into this repo.
- Do not import `notebooklm_tools` from the bridge implementation.

## Adapter Shape

Add a new bridge adapter:

```text
KOREADER_NOTEBOOKLM_ADAPTER=nlm-lite
```

The bridge HTTP contract should stay the same. KOReader should not need to know
whether the bridge uses `nlm`, `mock`, or `nlm-lite`.

Suggested package structure:

```text
bridge/src/koreader_notebooklm_bridge/notebooklm_lite/
  __init__.py
  auth.py
  client.py
  rpc.py
  parsing.py
  errors.py
```

Suggested adapter file:

```text
bridge/src/koreader_notebooklm_bridge/adapters/notebooklm_lite.py
```

Required integration points:

- Add config fields in `config.py`:
  - `auth_bundle_path`
  - `notebooklm_base_url`
  - direct request timeout
  - upload wait timeout
- Add `nlm-lite` to `adapters/factory.py`.
- Keep `NlmNotebookLMAdapter` unchanged as the stable fallback.
- Return the same Pydantic response models as `nlm` and `mock`.
- Report `adapter: "nlm-lite"` in responses and `/health`.

Suggested environment variables:

```text
KOREADER_NOTEBOOKLM_ADAPTER=nlm-lite
KOREADER_NOTEBOOKLM_AUTH_BUNDLE=/path/to/auth-bundle.json
KOREADER_NOTEBOOKLM_BASE_URL=https://notebooklm.google.com
KOREADER_NOTEBOOKLM_DIRECT_TIMEOUT_SECONDS=120
KOREADER_NOTEBOOKLM_UPLOAD_WAIT_SECONDS=600
```

## Auth Bundle

`nlm-lite` should start by reading an existing auth bundle. It should not create
or refresh Google login sessions by itself.

Minimum auth data:

```json
{
  "base_url": "https://notebooklm.google.com",
  "cookies": {},
  "csrf_token": "",
  "session_id": "",
  "build_label": "",
  "extracted_at": 0
}
```

Allowed sources:

- Explicit bundle path via `KOREADER_NOTEBOOKLM_AUTH_BUNDLE`.
- Existing local `~/.notebooklm-mcp-cli` profile/cache as a temporary bootstrap
  source while developing on Mac.

Preferred order:

1. Explicit auth bundle path.
2. Existing local `nlm` cache/profile for Mac-only development.
3. Fail clearly.

Refresh behavior:

- Use cookies to GET `https://notebooklm.google.com/`.
- Extract fresh CSRF token, session id, and build label from the page.
- If redirected to Google login or tokens cannot be found, return a clear auth
  error telling the user to re-authenticate on Mac/Windows and re-export.

Security rules:

- Never commit auth bundles.
- Never log cookie values.
- Never log full request headers.
- Never include cookies in exception messages.
- Redact auth fields in debug output.
- Write any generated auth bundle with `0600` permissions where supported.
- Keep future Kindle auth bundles out of normal KOReader settings unless there
  is no safer storage path.
- Future `/auth/export` must require API token plus pairing.

Important design choice:

```text
Auth export is a later phase. nlm-lite should first read local auth so we can
prove direct calls without designing the Kindle credential workflow too early.
```

## Core Protocol Work

Implement these pieces without importing `notebooklm_tools` and without calling
the `nlm` CLI:

- Build cookie header / cookie jar.
- Refresh page tokens from NotebookLM HTML.
- Build `batchexecute` request body.
- Build `batchexecute` URL with RPC id, `bl`, `f.sid`, `hl`, and `rt`.
- Parse anti-XSSI batchexecute responses.
- Extract RPC results.
- Parse streamed query responses.
- Normalize auth, timeout, not found, permission, quota, and parse errors.

Keep this logic small and fixture-tested because it is the future Lua porting
surface.

RPC ids should live in one small constants module. Add comments that they are
private and may change.

## Parity Target

`nlm-lite` should match current bridge-visible behavior before it is considered
portable.

| Capability | Current `nlm` adapter | `nlm-lite` target |
| --- | --- | --- |
| List notebooks | `nlm notebook list --json` | Direct RPC |
| Ask | `nlm notebook query --json` | Direct query RPC |
| Follow-up | `--conversation-id` | Same `conversation_id` contract |
| Create notebook | `nlm notebook create` | Direct create RPC |
| Source upload | `nlm source add --file` | Direct resumable upload |
| Source list repair | `nlm source list --json` | Direct source list RPC |
| Errors | stderr/stdout normalized by adapter | structured direct errors |

Do not start Lua work until this table is green for real Mac bridge tests.

## Implementation Phases

### Phase 1: Auth Bundle Read-only

Add auth bundle loading and token refresh.

Acceptance:

- Unit tests load a fixture auth bundle.
- Cookie values are redacted in logs/errors.
- Expired/missing bundle gives a clear normalized auth error.
- Token refresh can parse CSRF/session/build label from saved HTML fixtures.
- Real Mac smoke can refresh tokens from the live NotebookLM page.

Implementation detail:

- Build a tiny `AuthBundle` dataclass/Pydantic model.
- Accept cookies as either a simple name/value object or a future richer cookie
  list with domain/path metadata.
- Normalize to the format the direct client needs internally.
- Treat absent cookies as a configuration error, not as an auth-refresh attempt.

### Phase 2: List Notebooks

Implement:

```text
GET /notebooks
```

Acceptance:

- `adapter=nlm-lite` lists real notebooks on Mac.
- Tests cover batchexecute parsing with fixtures.
- No `nlm` subprocess is invoked.
- No `notebooklm_tools` import is used.
- `GET /health` identifies the adapter as `nlm-lite`.

Implementation detail:

- Add a subprocess/import guard test if practical:
  - monkeypatch `subprocess.run` to fail and prove list does not call it.
  - inspect loaded modules or use a narrow import test to avoid
    `notebooklm_tools`.

### Phase 3: Ask

Implement:

```text
POST /ask
```

Support:

- `notebook_id`
- selected text and prompt assembly
- optional `conversation_id`
- answer
- `conversation_id`
- sources used
- citations
- references

Acceptance:

- KOReader can ask a real notebook through `adapter=nlm-lite`.
- Follow-up questions preserve/use `conversation_id`.
- Error messages are at least as useful as the current `nlm` adapter.
- `/ask/jobs` works unchanged because it calls the adapter behind the same
  service boundary.

Implementation detail:

- Reuse the current question assembly behavior from `NlmNotebookLMAdapter` so
  answers are comparable.
- Preserve `BookContext` inclusion exactly unless there is a deliberate contract
  change.
- Include a comparison smoke:
  - same notebook id
  - same selected text
  - same prompt
  - compare `nlm` vs `nlm-lite` for successful answer shape, not exact wording.

### Phase 4: Create Notebook

Implement:

```text
POST /notebooks
```

Acceptance:

- Create a real notebook.
- Parse and return the new notebook id.
- Clear error if creation fails due to auth/permission/internal API change.
- Notebook URL matches the existing bridge response format.

### Phase 5: Sources List

Implement internal source listing if needed for upload validation and result
repair.

Acceptance:

- Can list source ids/titles for a notebook.
- Can detect new source ids after upload if upload output is incomplete.
- Can return source titles stable enough for UI/debugging.

### Phase 6: Upload

Implement file source upload last.

Required flow:

```text
register file source intent -> source_id
start resumable upload -> upload URL
stream file bytes
poll source status
```

Acceptance order:

1. `.txt` or `.md`
2. `.epub`
3. `.pdf`

Guardrails:

- Stream files; do not read large files fully into memory.
- Validate file extension and size before upload.
- Normalize timeout/processing failure messages.
- Keep unsupported KOReader formats on fallback/manual setup path.
- Preserve filename/title clearly. Avoid UUID-only source titles when the caller
  supplied a readable title.
- Clean up temporary bridge-uploaded files according to the existing bridge
  storage policy.

Implementation detail:

- Keep `/sources/upload-file` behavior unchanged from KOReader's perspective.
- The bridge may still receive multipart from KOReader; `nlm-lite` only replaces
  the NotebookLM side of the upload.
- Upload polling should use a longer timeout than ask.

## Test Strategy

Use three layers:

1. Unit tests with saved HTML and batchexecute fixtures.
2. Bridge integration tests with `adapter=nlm-lite` on Mac.
3. KOReader smoke test against the existing bridge contract.

Fixtures should cover:

- NotebookLM page token extraction.
- Successful notebook list.
- Successful ask response with citations/references.
- Auth expired.
- RPC not found.
- Permission denied.
- Parse failure.
- Source upload status ready/failure.

Add regression checks:

- `adapter=mock` tests still pass.
- `adapter=nlm` tests still pass.
- `adapter=nlm-lite` unit tests do not require live credentials.
- Live `adapter=nlm-lite` tests must be opt-in and skipped by default unless an
  env var is present.

Suggested opt-in variable:

```text
KOREADER_NOTEBOOKLM_RUN_LIVE_NLM_LITE_TESTS=1
```

## Failure Handling

Normalize failures into a small set before they reach KOReader:

- `auth_missing`
- `auth_expired`
- `permission_denied`
- `not_found`
- `timeout`
- `rate_limited`
- `notebooklm_changed`
- `parse_error`
- `upload_failed`

Each error should have:

- short user-facing message
- longer debug message without secrets
- original status/RPC code when available

If the same protocol/parsing error repeats twice during development, stop and
compare against the latest `nlm` behavior before layering more guesses.

## Observability

Add debug logging that helps compare `nlm` and `nlm-lite` without leaking auth:

- operation name
- notebook id
- selected/prompt character counts
- RPC id
- request timeout
- response status
- parse result type
- source id/title for upload

Do not log:

- cookies
- CSRF token
- full auth bundle
- full selected text
- full answer by default

## Lua Port Readiness Criteria

Do not start the Lua direct client until `nlm-lite` can:

- List real notebooks.
- Ask a real notebook.
- Preserve follow-up `conversation_id`.
- Create a real notebook.
- Upload a real EPUB.
- Return clear auth/timeout/not-found errors.
- Pass fixture tests for RPC parsing.
- Run without `nlm` subprocess.
- Run without importing `notebooklm_tools`.

Also require:

- The protocol core is isolated from FastAPI and bridge routes.
- The protocol core has fixture tests that a Lua port can reuse as examples.
- Auth bundle shape is stable and documented.
- Upload code proves streaming behavior.
- The direct client has a clean feature matrix showing what is implemented and
  what remains bridge-only.

## Future Lua Target

Once ready, port only the small `notebooklm_lite` core to Lua behind the same
plugin boundary:

```text
ui.lua/main.lua -> client.lua -> direct_notebooklm.lua/http.lua
```

The Mac/Windows bridge would then become an auth bootstrap service:

```text
POST /auth/pair
POST /auth/export
POST /auth/refresh
```

The Kindle client should use the exported auth bundle to call NotebookLM
directly. Login and re-authentication remain the responsibility of the desktop
host.

The Lua port should start with query-only:

```text
fixed linked notebook -> selected text -> ask -> answer viewer
```

Then add:

1. notebook list/link
2. create notebook
3. source list
4. upload
5. auth refresh/export UX

Do not port upload first.
