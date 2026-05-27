# All-in-Kindle Notes

Research snapshot: 2026-05-27.

## Question

Can the project move from:

```text
KOReader plugin -> local bridge -> NotebookLM adapter
```

to something closer to:

```text
KOReader plugin on Kindle -> NotebookLM direct client on Kindle
                         -> bridge only for auth/bootstrap
```

The goal would be to keep the Mac bridge out of the critical reading path, while
still avoiding Google/NotebookLM auth UI on the Kindle.

## Current Architecture Constraint

The right boundary already exists:

```text
main.lua / ui.lua -> client.lua -> http.lua -> bridge
```

`client.lua` should remain the portability boundary. Any future direct Kindle
implementation should replace the backend behind the same high-level methods:

- `health`
- `list_notebooks`
- `create_notebook`
- `link_book`
- `upload_source`
- `ask`
- ask job polling
- answer history

Do not let KOReader UI code depend on NotebookLM transport details.

## Current NotebookLM Auth Model

The installed `notebooklm-mcp-cli` auth model is not an API-key model.

Observed locally in `notebooklm_tools`:

- Cookies are the required credential.
- CSRF token, session id, and build label are optional cached values because the
  client can re-extract them from the NotebookLM page when cookies still work.
- Auth is cached under `~/.notebooklm-mcp-cli/`.
- The client refreshes CSRF/session by fetching `https://notebooklm.google.com/`.
- If cookies are expired, recovery expects either updated local cache or
  headless/browser auth.
- The actual RPC layer uses private NotebookLM endpoints and RPC ids.

This means a Kindle-side client needs more than one static token. At minimum it
needs valid Google cookies and enough metadata to call the private RPC protocol.
It also needs a recovery story when cookies expire.

## Kindle Runtime Reality

KOReader can run on jailbroken Kindle devices, but Kindle support is not the
same as Android/Termux:

- KOReader on Kindle requires jailbreak plus a launcher such as KUAL or a
  related launcher path.
- Kindle firmware/runtime compatibility depends on model and firmware.
- Newer hard-float firmware changed extension compatibility.
- Python on Kindle exists through community packages, but it is an old
  homebrew path, not a normal supported Python packaging target.

The installed Mac `notebooklm-mcp-cli` environment is about 84 MB and includes
compiled/heavy dependencies such as `cryptography`, `cffi`, `pydantic_core`,
`httpx`, `mcp`, and `fastmcp`. That environment will not simply copy to Kindle.

Termux/Android is a much easier target than Kindle. Kindle is possible only as a
separate constrained runtime project.

## Direct NotebookLM Protocol Surface

The direct client would need to reproduce a subset of `notebooklm_tools`:

- Cookie handling for `.google.com` and related domains.
- CSRF/session/build-label extraction from the NotebookLM HTML page.
- `batchexecute` request body encoding.
- RPC id routing and response parsing.
- Query endpoint / streamed response parsing.
- Conversation id handling.
- Source listing and notebook listing if needed.
- Resumable upload protocol if source upload moves on-device.

File upload is not just a normal multipart POST. The current implementation:

1. Registers a file source intent and gets a source id.
2. Starts a resumable upload session and gets an upload URL.
3. Streams file bytes to that upload URL.
4. Polls source processing status when requested.

Supported direct upload extensions in the current `nlm` implementation include
`.pdf`, `.txt`, `.md`, `.docx`, `.csv`, `.epub`, audio, video, and image
formats. KOReader may read more formats than NotebookLM accepts, so unsupported
ebook formats still need a text extraction fallback or manual setup path.

## Security Risks

Passing auth to Kindle is the riskiest part.

Google cookies can grant access to NotebookLM and possibly other Google
surfaces. A Kindle is easy to mount as USB storage, and KOReader settings/files
are not a secure credential store.

Avoid these designs:

- Do not store raw Google cookies in normal KOReader settings.
- Do not commit any exported auth bundle.
- Do not expose raw auth export from a LAN bridge without pairing and a local
  API token.
- Do not make the bridge listen on `0.0.0.0` with credential export enabled
  unless there is explicit local authorization.

Safer variants:

- Keep raw cookies on the Mac and use the bridge as a credentialed proxy.
- If direct Kindle auth is tested, export a short-lived auth bundle only after a
  pairing step.
- Store any temporary auth bundle outside ordinary settings if possible.
- Prefer volatile in-memory use; persist only if there is a clear UX need.

## Architecture Options

### Option A: Current Bridge Owns NotebookLM

```text
KOReader -> bridge -> nlm -> NotebookLM
```

Best for MVP. Lowest risk. Already works.

Downside: the Kindle depends on the Mac/local server for every NotebookLM
operation.

### Option B: Bridge as Credentialed Proxy

```text
KOReader -> bridge proxy -> NotebookLM
```

The bridge still owns cookies, but it becomes thinner. The bridge can expose
NotebookLM-shaped operations while avoiding business decisions.

This is safer than copying cookies to Kindle and still reduces our coupling to
the current subprocess adapter.

### Option C: Bridge as Auth Broker, Kindle Direct Client

```text
KOReader -> bridge /auth/session
KOReader -> NotebookLM direct RPCs
```

The bridge only bootstraps auth. Kindle calls NotebookLM directly.

This is the target idea, but it has hard problems:

- Secrets live on Kindle at least temporarily.
- Cookie expiry/re-auth still needs the Mac or another browser-capable host.
- Private RPC changes now break the Kindle client directly.
- Implementing and debugging RPC parsing on Kindle is slower than on Mac.

### Option D: All-in-Kindle Including Auth

```text
KOReader -> NotebookLM direct, auth on Kindle
```

Not recommended now. NotebookLM auth currently expects a browser/cookie flow.
Doing Google auth inside Kindle/KOReader would be fragile and a distraction.

## Recommended Migration Path

### Phase 0: Keep MVP Stable

Do not interrupt the current bridge MVP. Keep `client.lua` as the portability
boundary and keep bridge-backed flows working.

### Phase 1: Extract a Minimal Direct Protocol Spike on Mac

Create a separate experimental script that uses only:

- exported cookie bundle from local `nlm` profile
- `httpx` or a very small HTTP client
- copied protocol logic for:
  - refresh CSRF/session/build label from NotebookLM HTML
  - list notebooks
  - ask a fixed notebook

Success criteria:

- no import from `notebooklm_tools`
- no `nlm` subprocess
- ask works against one fixed notebook
- conversation id is preserved
- errors are understandable

This tells us whether we understand the minimum protocol before fighting Kindle
runtime constraints.

### Phase 2: Define Backend Interface in Plugin

Keep the current bridge backend, but make the setting explicit:

```text
backend = bridge
backend = direct-experimental
```

The UI still calls the same `client.lua` methods. The direct backend may be
disabled or hidden unless a developer flag is set.

### Phase 3: Auth Broker Prototype

Add bridge endpoints only for local experimental pairing:

```text
GET /auth/status
POST /auth/pair
POST /auth/session
POST /auth/refresh
```

The session response should contain the minimum browser-derived data needed by
the direct client:

```json
{
  "base_url": "https://notebooklm.google.com",
  "cookies": {},
  "csrf_token": "",
  "session_id": "",
  "build_label": "",
  "expires_at": ""
}
```

This must require the bridge API token and a one-time pairing code before it can
return credentials.

### Phase 4: Kindle Direct Query Only

Try the smallest useful direct feature on the real device:

```text
fixed notebook id -> selected text -> ask -> answer viewer
```

Do not include create notebook or upload yet. Query-only validates networking,
TLS certificates, auth bundle shape, JSON parsing, and UI behavior.

### Phase 5: List/Link/Create

Add notebook listing and linking. Create notebook can come after ask is stable.
Book-to-notebook mapping should still remain in plugin storage.

### Phase 6: Upload, Only If Needed

Move upload last. It needs resumable upload, streaming, file-size guardrails,
format validation, and long polling.

For unsupported formats, keep a fallback:

```text
extract text locally if KOReader exposes it, or ask the user to upload manually
```

## Python Helper vs Lua Direct Client

### Python Helper

Pros:

- Easier to port existing protocol logic.
- Better JSON/HTTP ergonomics.
- Easier to test on Mac before Kindle.

Cons:

- Python packaging on Kindle is the biggest unknown.
- Compiled dependencies are painful.
- The current `nlm` environment is too large/heavy to copy.

If using Python, build a tiny helper with minimal dependencies, ideally standard
library plus a small vendored HTTP/TLS strategy if feasible.

### Lua Direct Client

Pros:

- Runs inside KOReader's existing runtime.
- No separate Python packaging layer.
- Keeps install surface smaller.

Cons:

- Reimplementing NotebookLM RPC protocol, streaming, escaping, and upload in Lua
  is slower and more fragile.
- Auth/cookie handling and response parsing will be harder to debug.

Lua is attractive only after the protocol spike proves the minimum calls are
small and stable.

## Current Recommendation

Do not jump directly to all-in-Kindle.

The best next research milestone is:

```text
Mac direct-client spike:
ask a fixed NotebookLM notebook without nlm subprocess and without importing
notebooklm_tools, using an exported local auth bundle.
```

If that works, the next milestone is:

```text
Kindle runtime spike:
run the smallest possible HTTPS JSON/RPC client on the jailbroken Kindle.
```

Only after both pass should the project add a hidden `direct-experimental`
backend to `client.lua`.

## Useful Sources

- KOReader development guide: https://koreader.rocks/doc/topics/Development_guide.md.html
- KOReader Kindle install notes: https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices
- KindleModding KOReader install notes: https://kindlemodding.org/jailbreaking/post-jailbreak/koreader.html
- KindleModding jailbreak FAQ: https://kindlemodding.org/jailbreaking/jailbreak-faq.html
- MobileRead Python on Kindle: https://wiki.mobileread.com/wiki/Python_on_Kindle
- notebooklm-mcp-cli repository: https://github.com/jacob-bd/notebooklm-mcp-cli
