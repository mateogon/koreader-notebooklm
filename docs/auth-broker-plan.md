# Auth Broker Implementation Plan

## Goal

Let KOReader on Kindle keep using the `lua-direct` NotebookLM client for normal
reading flows, while using a phone or desktop browser only when NotebookLM auth
needs to be created or refreshed.

The broker is not a permanent query bridge. It is an occasional credential
bootstrap path.

```text
KOReader Kindle -> auth refresh request -> local auth broker
Phone/Mac browser -> Google/NotebookLM login -> local auth broker
local auth broker -> auth bundle -> KOReader Kindle
KOReader Kindle -> NotebookLM direct RPCs
```

## Non-Goals

- Do not implement Google login inside KOReader.
- Do not try to use KOReader as a full web browser.
- Do not send Google cookies through a remote hosted service.
- Do not replace the existing `bridge`, `nlm`, or `lua-direct` paths.
- Do not commit auth bundles, cookies, QR payloads, pairing tokens, or logs with
  secrets.

## MVP Shape

Run a local broker on the Mac first:

```text
Mac:      scripts/run-auth-broker-dev.sh
Kindle:   KOReader -> NotebookLM settings -> Refresh auth
Phone:    scan QR / open URL shown on Kindle
Mac:      opens Chrome for NotebookLM login, writes auth bundle
Kindle:   downloads auth bundle from broker and saves it locally
```

This keeps the phone as a login screen only. The phone should not need an app,
browser extension, SSH, or manual file handling.

## Security Model

The broker must be LAN-local and short-lived.

Required MVP controls:

- Generate a one-time pairing code per auth session.
- Expire sessions quickly, for example after 10 minutes.
- Require the pairing code for every auth session endpoint.
- Bind the broker to `127.0.0.1` by default and require explicit LAN mode.
- When LAN mode is enabled, print the LAN URL and security warning.
- Never return auth bundle contents to arbitrary clients without the pairing
  code.
- Never log cookie values, auth headers, CSRF tokens, or full auth bundle JSON.
- Store temporary auth bundles outside the repo.

Recommended later controls:

- Optional broker API token.
- QR payload includes session id plus pairing code, not secrets.
- Kindle confirms before replacing an existing auth bundle.
- Broker deletes temporary auth bundles after transfer.

## Broker API

Initial local endpoints:

```text
POST /auth/sessions
GET  /auth/sessions/{session_id}
POST /auth/sessions/{session_id}/login
GET  /auth/sessions/{session_id}/bundle
POST /auth/sessions/{session_id}/complete
```

### `POST /auth/sessions`

Creates a short-lived auth refresh session.

Response:

```json
{
  "session_id": "short-random-id",
  "pairing_code": "123456",
  "expires_at": "2026-05-28T12:00:00Z",
  "browser_url": "http://192.168.0.10:8767/auth/sessions/short-random-id?code=123456"
}
```

### `GET /auth/sessions/{session_id}`

Returns status only:

```json
{
  "status": "pending|login_started|ready|downloaded|expired|failed",
  "message": "Open the browser URL on your phone or Mac."
}
```

No secrets.

### `POST /auth/sessions/{session_id}/login`

Starts desktop browser auth on the broker host.

For the Mac MVP this can call the existing `nlm-lite-login.py` flow or the
underlying `notebooklm_lite.login` module. The phone page may show a button:

```text
Start login on this Mac
```

If the user opened the URL on a phone, the broker still starts login on the Mac.
This is acceptable for MVP because Chrome/CDP auth extraction is already local
to the Mac.

### `GET /auth/sessions/{session_id}/bundle`

Kindle polls this endpoint with the pairing code. When ready, it downloads the
portable auth bundle:

```json
{
  "base_url": "https://notebooklm.google.com",
  "cookies": [],
  "csrf_token": "...",
  "session_id": "...",
  "build_label": "...",
  "extracted_at": "..."
}
```

The broker must return `404`, `409`, or `425` while not ready.

### `POST /auth/sessions/{session_id}/complete`

Kindle calls this after saving the bundle. Broker can delete temporary files and
mark the session complete.

## KOReader UX

Add a settings action:

```text
NotebookLM -> Settings -> Refresh auth from broker
```

Flow:

1. Ask for broker URL if not configured.
2. `POST /auth/sessions`.
3. Show a dialog with:
   - URL text
   - pairing code
   - optional QR image if we can generate one cleanly
   - `Check status`
   - `Download auth`
   - `Cancel`
4. Poll session status or let user tap `Check status`.
5. When bundle is ready, download it to:

```text
/mnt/us/koreader/settings/notebooklm-auth-bundle.json
```

6. Save `direct_auth_bundle_path` to that path.
7. Run a small `lua-direct` smoke:

```text
list_notebooks
```

8. Show success or a short error.

MVP can start without QR generation. A visible URL plus pairing code is enough.
QR is a UX improvement after the broker flow works.

## Implementation Phases

## Current MVP Implementation

Implemented first cut:

- FastAPI auth broker endpoints under `/auth/sessions`.
- One-time pairing code per session.
- Short-lived in-memory session state.
- Browser page with `Start login on this Mac`.
- Desktop Chrome login reuse through `notebooklm_lite.login.login_with_browser`.
- Temporary auth bundle storage outside the repo.
- KOReader setting for auth broker URL.
- KOReader `Refresh auth from broker` action that downloads the bundle, saves it
  to KOReader settings, updates `direct_auth_bundle_path`, and runs a small
  lua-direct notebook-list smoke.

Run locally:

```sh
scripts/run-auth-broker-dev.sh
```

For Kindle LAN testing:

```sh
KOREADER_NOTEBOOKLM_HOST=0.0.0.0 scripts/run-auth-broker-dev.sh
```

Use only on a trusted network. The pairing URL is short-lived but still controls
credential transfer for that session.

### Phase 1: Broker Skeleton

Files:

```text
bridge/src/koreader_notebooklm_bridge/auth_broker/
scripts/run-auth-broker-dev.sh
docs/auth-broker-plan.md
```

Tasks:

- Add an in-memory session store.
- Add `POST /auth/sessions`.
- Add status endpoint.
- Add a tiny HTML page for phone/Mac browser.
- Add short session expiry.
- Add tests for session creation, expiry, bad pairing code, and no-secret status.

### Phase 2: Desktop Login Integration

Files:

```text
bridge/src/koreader_notebooklm_bridge/notebooklm_lite/login.py
bridge/src/koreader_notebooklm_bridge/auth_broker/routes.py
scripts/nlm-lite-login.py
```

Tasks:

- Reuse `login_with_browser`.
- Write auth bundle to a temp path outside the repo.
- Store only metadata in session state.
- Normalize login errors.
- Add tests with login mocked.

### Phase 3: Kindle Bundle Download

Files:

```text
plugin/notebooklm.koplugin/client.lua
plugin/notebooklm.koplugin/http.lua
plugin/notebooklm.koplugin/main.lua
plugin/notebooklm.koplugin/settings.lua
plugin/notebooklm.koplugin/ui.lua
```

Tasks:

- Add broker URL setting.
- Add `Refresh auth from broker`.
- Create auth session.
- Display URL and pairing code.
- Poll status.
- Download bundle.
- Save bundle outside normal answer/history files.
- Update `direct_auth_bundle_path`.
- Run `lua-direct` list smoke after import.

### Phase 4: QR UX

Options:

- Generate QR on the broker as plain SVG/PNG and show URL to it.
- Generate QR in Lua only if a small pure-Lua implementation is acceptable.
- Keep text URL fallback forever.

MVP should not block on QR.

### Phase 5: Hardening

Tasks:

- Optional broker token for LAN mode.
- Confirm overwrite of existing auth bundle.
- Delete temp auth bundle after `complete`.
- Add docs for phone/Mac refresh.
- Add redaction tests for logs/errors.
- Add device checklist.

## Validation Checklist

Mac-only:

```text
[ ] Start auth broker on localhost.
[ ] Create auth session.
[ ] Status does not expose secrets.
[ ] Login mock marks session ready.
[ ] Bundle endpoint requires pairing code.
[ ] Complete deletes temp bundle.
```

Kindle + Mac:

```text
[ ] KOReader can create broker session.
[ ] URL and pairing code are readable on Kindle.
[ ] Phone opens URL on LAN.
[ ] Mac broker runs Chrome login.
[ ] Kindle downloads bundle.
[ ] Bundle is saved under KOReader settings.
[ ] lua-direct list_notebooks works after refresh.
[ ] Existing ask flow works without bridge.
[ ] Expired/bad pairing code shows short human error.
```

Security:

```text
[ ] No cookies in repo.
[ ] No cookies in logs.
[ ] No auth bundle in git status.
[ ] LAN mode prints warning.
[ ] Session expires.
```

## Recommended First Cut

Implement Phase 1 and Phase 2 on Mac first, with mocked Kindle download. Then
add the KOReader UI in Phase 3.

Do not start with QR. The QR is polish; the critical path is a secure,
short-lived auth session and reliable bundle import.
