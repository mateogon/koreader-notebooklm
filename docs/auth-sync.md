# Auth Sync

KOReader NotebookLM can run normal NotebookLM requests directly on Kindle with
its `lua-direct` runtime. A Mac/PC is only needed occasionally to refresh Google
auth and copy the resulting auth bundle to the Kindle.

```text
Mac/PC -> Chrome login -> auth bundle -> USB/SSH sync -> Kindle
Kindle -> KOReader lua-direct -> NotebookLM
```

The auth bundle contains Google cookies and NotebookLM tokens. Treat it like a
password.

## Recommended: USB

USB is the easiest path for most users because it does not require finding the
Kindle IP address or enabling SSH.

1. Exit KOReader so the Kindle can mount as USB storage.
2. Connect the Kindle to the Mac/PC.
3. Run:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
```

If auth must be refreshed, the script opens Chrome and asks you to sign in to
NotebookLM. It then writes:

```text
/Volumes/Kindle/koreader/settings/notebooklm-auth-bundle.json
/Volumes/Kindle/koreader/settings/notebooklm.lua
```

Eject the Kindle, open KOReader, and run:

```text
NotebookLM -> Settings -> Lua direct smoke
```

## Power User: SSH

SSH is faster for development, but the Kindle must be awake with SSH enabled.

```sh
scripts/sync-auth-to-kindle.sh --ssh <kindle-ip> --port 2222
```

Example:

```sh
scripts/sync-auth-to-kindle.sh --ssh 192.168.0.105 --port 2222
```

## Common Options

Force a fresh browser login:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle --refresh
```

Reuse a specific local bundle:

```sh
scripts/sync-auth-to-kindle.sh --ssh 192.168.0.105 \
  --bundle ~/.koreader-notebooklm/auth-bundles/default-auth-bundle.json
```

Set a default NotebookLM notebook ID:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle \
  --notebook-id <NOTEBOOK_ID>
```

Preview without writing or opening Chrome:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle --dry-run
```

## Local Bundle Location

By default, auth bundles are stored outside the repo:

```text
~/.koreader-notebooklm/auth-bundles/<profile>-auth-bundle.json
```

Do not copy this file into the repository, paste it into issues, or send it in
logs.

## Troubleshooting

If KOReader says auth is missing or expired:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle --refresh
```

If USB does not mount:

- Exit KOReader.
- Unlock/wake the Kindle.
- Try another cable; many USB-C cables are charge-only.

If SSH times out:

- Wake the Kindle.
- Confirm it is on the same network.
- Confirm the IP and port.
- Use USB if you only need to refresh auth.
