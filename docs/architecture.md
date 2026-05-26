# Architecture

Initial intended flow:

```text
KOReader plugin -> local bridge -> NotebookLM adapter
```

The KOReader plugin will eventually collect selected reading text and send it to a local HTTP bridge. The bridge will own local configuration, book-to-notebook mapping, and the adapter boundary for NotebookLM.

## Plugin Boundary

The KOReader plugin should keep UI code separate from backend communication:

```text
main.lua / ui.lua -> client.lua -> http.lua -> local bridge
```

`client.lua` is the portability boundary. The first implementation will use the
local HTTP bridge, but a future Termux/small-server bridge or experimental
all-in-Kindle client should be able to replace the transport behind the same
client methods.

See [implementation plan](implementation-plan.md) for the current plugin plan.
