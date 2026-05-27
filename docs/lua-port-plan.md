# Lua Port Plan

This document freezes the current `nlm-lite` protocol knowledge before any
direct KOReader Lua client is attempted.

The current supported path remains:

```text
KOReader Lua plugin -> bridge HTTP -> nlm-lite Python adapter -> NotebookLM
```

The future experimental path is:

```text
KOReader Lua plugin -> Lua NotebookLM client -> NotebookLM
Mac/Windows bridge -> auth bootstrap/export only
```

Do not start the Lua port until the Python `nlm-lite` bridge keeps passing the
golden tests and at least one live smoke.

## Boundaries

- The KOReader UI should keep using the existing plugin `client.lua` boundary.
- The first Lua port should be query-first: auth bundle loading, list notebooks,
  get notebook, and ask.
- Upload should be ported after query is stable because resumable upload has
  more file and memory risk on Kindle.
- Auth generation stays on Mac/Windows first. Kindle should consume a portable
  auth bundle; it should not drive browser login.
- Do not commit cookies, CSRF tokens, auth bundles, Chrome profiles, books,
  PDFs, generated answers, or bridge data.

## Python To Lua Map

| Python source | Current responsibility | Future Lua responsibility |
| --- | --- | --- |
| `notebooklm_lite/auth.py` | Load auth bundle, normalize cookies, refresh page tokens. | `auth_bundle.lua`: read external bundle, validate schema, expose cookies/CSRF/session/build label without logging secrets. |
| `notebooklm_lite/login.py` | Standalone Chrome/CDP login on desktop. | No Kindle port initially. Keep on Mac/Windows bridge or helper CLI only. |
| `notebooklm_lite/rpc.py` | Private RPC ids plus `batchexecute` and streamed query URL/body builders. | `rpc.lua`: produce byte-for-byte equivalent form bodies and URLs for list/get/create/register/ask. |
| `notebooklm_lite/parsing.py` | Parse `batchexecute`, streamed ask chunks, citations, source status, and RPC errors. | `parsing.lua`: parse the same fixture responses and normalize answers/references/errors. |
| `notebooklm_lite/client.py` | Direct HTTP orchestration for list/get/create/ask/upload and in-memory conversation history. | `notebooklm_client.lua`: call `rpc.lua`, `http.lua`, and `parsing.lua`; preserve the bridge-visible response contract. |
| `notebooklm_lite/errors.py` | Normalize private NotebookLM drift/auth/timeout errors. | `errors.lua`: map RPC codes and HTTP failures into short user-facing error kinds. |
| `adapters/notebooklm_lite.py` | Bridge adapter implementing the existing bridge interface. | Compatibility layer only if Lua continues to talk through bridge-shaped tables. |

## Protocol Pieces To Preserve

### Auth Bundle Loading

The Lua client should read a bundle outside the repo and outside book folders.
Minimum fields:

- `base_url`
- cookies
- `csrf_token`
- `session_id`
- `build_label`

Never print cookie values, token values, auth headers, or bundle JSON.

### Token Refresh

Python currently refreshes page tokens from NotebookLM HTML using valid cookies.
Lua should keep this as a separate function:

```text
refresh_page_tokens(auth_bundle) -> updated_auth_bundle
```

If refresh fails with 400/401/403 or missing token fields, return an
`auth_expired` style error and ask the user to refresh auth on Mac/Windows.

### Batchexecute RPC

The Lua body builder must match the Python shape:

```text
f.req=<urlencoded JSON>&at=<urlencoded csrf>&
```

The inner `f.req` call shape is:

```json
[[["RPC_ID", "PARAMS_AS_JSON_STRING", null, "generic"]]]
```

Golden tests currently cover list notebooks, get notebook, create notebook, and
file source registration.

### Streamed Ask

The streamed query body shape is:

```json
[null, "PARAMS_AS_JSON_STRING"]
```

The params array is:

```json
[sources_array, query_text, conversation_history, [2, null, [1]], conversation_id]
```

Conversation history is local cache only for now:

```json
[["previous answer", null, 2], ["previous question", null, 1]]
```

### Response Parsing

Lua parsing must handle:

- Google `)]}'` response prefix.
- Length-prefixed JSON chunks.
- `wrb.fr` records.
- RPC error records with Google RPC codes.
- Longest final answer vs intermediate thinking text.
- Source IDs, citation number mapping, and cited text snippets.

### Resumable Upload

Port upload last. The Python flow is:

1. Register file source through `RPC_ADD_SOURCE_FILE`.
2. Start upload at `/upload/_/?authuser=0`.
3. Send file bytes to returned `x-goog-upload-url` with
   `x-goog-upload-command: upload, finalize`.
4. Poll notebook sources until the registered source is ready.

On Kindle, avoid reading large files fully into memory. Stream or enforce a
size limit before upload.

### Bridge Compatibility

The Lua direct client should return the same high-level tables the plugin
already expects from `client.lua`:

- `ok`
- `answer`
- `notebook_id`
- `conversation_id`
- `sources_used`
- `citations`
- `references`
- `error` / `detail`

That keeps the UI independent from whether transport is bridge HTTP, local
Termux, or direct NotebookLM Lua.

## Port Order

1. Keep Python `nlm-lite` green and fixture-tested.
2. Add Lua auth bundle reader with no network calls. Current spike: done in
   `plugin/notebooklm.koplugin/direct/auth_bundle.lua`.
3. Port RPC body/URL builders and compare against golden request shapes.
   Current spike: fixture-verified in `direct/rpc.lua`.
4. Port response parsers and compare against sanitized fixtures. Current spike:
   fixture-verified in `direct/parsing.lua`.
5. Implement list/get notebook over HTTP.
6. Implement ask over HTTP with one conversation ID.
7. Add conversation history cache.
8. Add create notebook.
9. Add upload only after query/list/create are stable.
10. Switch plugin backend behind `client.lua`, not inside UI code.

## Regression Harness

Before porting or changing private NotebookLM protocol code, run:

```sh
cd bridge
uv run --extra dev pytest -q
uv run --extra dev python ../scripts/verify-plugin-lua.py
```

For live bridge validation, start the bridge with `adapter=nlm-lite` and a local
auth bundle outside the repo, then run:

```sh
KOREADER_NOTEBOOKLM_BRIDGE_URL=http://127.0.0.1:8766 ../scripts/smoke-nlm-lite.sh
KOREADER_NOTEBOOKLM_BRIDGE_URL=http://127.0.0.1:8766 ../scripts/smoke-koreader-bridge-flow.sh
```

The golden tests are intentionally sanitized. If NotebookLM changes the private
protocol, update Python first, then update fixtures, then port Lua.

## Current Lua Direct Spike

The first isolated Lua core lives under:

```text
plugin/notebooklm.koplugin/direct/
```

It includes:

- `codec.lua`: small JSON codec used by this spike so `null` positions are
  preserved in private NotebookLM request arrays.
- `auth_bundle.lua`: external auth bundle loader and validator.
- `transport.lua`: direct `ssl.https`/`socket.http` form POST transport with
  NotebookLM cookies, CSRF, origin, referer, and `X-Same-Domain` headers.
- `rpc.lua`: private RPC constants and request builders.
- `parsing.lua`: sanitized batchexecute/query response parsing.
- `client.lua`: minimal feature-flagged facade for list notebooks, get
  notebook, and ask.

The bridge UX remains the default. The direct client reports enabled only when
settings contain:

```text
backend = lua-direct
```

This spike intentionally does not perform live NotebookLM HTTPS requests from
the normal highlight UX yet. It also does not implement Lua upload, Lua browser
login, auth export, or source creation as a user-facing feature.

The macOS KOReader runtime exposes a debug path under:

```text
NotebookLM -> Settings -> Lua direct smoke
```

To use it:

1. Set `NotebookLM -> Settings -> Backend` to `lua-direct`.
2. Set `Lua direct auth bundle` to an auth bundle path outside the repo.
3. Optionally set `Lua direct notebook` to a real notebook ID.
4. Run `Lua direct smoke`.

The smoke performs:

```text
list_notebooks -> get_notebook -> ask
```

It is intentionally synchronous and debug-only. The normal selected-text UX
still goes through the bridge unless this backend is explicitly enabled, and
upload remains unsupported in Lua direct mode.

Run the Lua spike tests through the existing verifier:

```sh
cd bridge
uv run --extra dev python ../scripts/verify-plugin-lua.py
```

The verifier checks the Lua request builders against the same sanitized golden
fixtures used by Python tests.
