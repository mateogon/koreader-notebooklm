# Kindle Setup

The initial supported shape is still:

```text
Kindle KOReader plugin -> Mac/local-network bridge -> NotebookLM adapter
```

An all-in-Kindle client is a future experiment, not part of the current MVP.

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

## Bridge URL

The Kindle cannot use `127.0.0.1` to reach a bridge running on the Mac. Use the
Mac's LAN IP in the plugin menu:

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

- Real NotebookLM auth is still owned by the Mac bridge through `nlm`.
- EPUB upload support must be validated against the active `nlm` adapter.
- All-in-Kindle NotebookLM calls are intentionally not implemented yet.
