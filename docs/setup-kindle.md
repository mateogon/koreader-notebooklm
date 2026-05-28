# Kindle Setup

The preferred Kindle shape is now:

```text
KOReader on Kindle -> lua-direct -> NotebookLM
Mac/PC -> auth sync only when credentials need refresh
```

The Mac/PC is not required for normal reading once the auth bundle has been
copied to the Kindle.

## Install Plugin

When the Kindle is mounted on the Mac, copy the plugin directory:

```sh
scripts/install-plugin-dev.sh /Volumes/Kindle/koreader/plugins --copy
```

If working directly on the Kindle shell, the target is usually:

```text
/mnt/us/koreader/plugins/notebooklm.koplugin
```

Restart KOReader after copying.

Then run a safe preflight from the Mac while the Kindle is mounted:

```sh
scripts/koreader-runtime-preflight.sh /Volumes/Kindle/koreader/plugins http://<mac-lan-ip>:8765
```

If working from a Kindle shell, use the on-device path:

```sh
scripts/koreader-runtime-preflight.sh /mnt/us/koreader/plugins http://<mac-lan-ip>:8765
```

## Auth Sync

Recommended USB flow:

```sh
scripts/sync-auth-to-kindle.sh --usb /Volumes/Kindle
```

Power-user SSH flow:

```sh
scripts/sync-auth-to-kindle.sh --ssh <kindle-ip> --port 2222
```

Both flows write the auth bundle to:

```text
/mnt/us/koreader/settings/notebooklm-auth-bundle.json
```

and configure KOReader for `backend = "lua-direct"`.

For more detail, see [Auth sync](auth-sync.md).

## Bridge URL

Bridge mode still exists for development and compatibility testing. The Kindle
cannot use `127.0.0.1` to reach a bridge running on the Mac. Use the Mac's LAN
IP in the plugin menu:

```text
NotebookLM -> Bridge URL
```

Example:

```text
http://192.168.1.20:8765
```

Start the bridge bound to the LAN interface when testing from Kindle:

```sh
cd bridge
KOREADER_NOTEBOOKLM_HOST=0.0.0.0 ../scripts/run-bridge-dev.sh
```

## Logs

After a plugin failure, check KOReader logs on the Kindle:

```text
/mnt/us/koreader/crash.log
```

If that file is absent, search under `/mnt/us/koreader` for recent `.log` files.

## Current Limits

- `lua-direct` uses a copied auth bundle generated on Mac/Windows.
- Direct upload support depends on NotebookLM's private resumable upload
  protocol and should be tested with small EPUB/PDF files first.
