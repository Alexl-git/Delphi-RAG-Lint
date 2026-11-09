---
id: mcp-get-neighbors
title: MCP get_neighbors
summary: "MCP tool: the call-graph neighbourhood of a symbol within 1..3 hops"
product: DL
group: editor-integration
order: 110019
since: 1.46.0-alpha
status: shipped
updated: 1.48.0-alpha
---

# MCP get_neighbors

MCP tool: the call-graph neighbourhood of a symbol within 1..3 hops.

Ask an MCP client for get_neighbors to see everything one to three resolved call edges away from a symbol, callers and callees alike, each with its fewest hops. The answer is capped at 200 rows and always states how many were omitted.

## Details

An MCP tool that answers "what is around this symbol in the call graph". It returns
every symbol reachable from the seed within 1..3 resolved call edges, callers and
callees alike, each with the fewest hops that reach it (the seed itself is hop 0).

### Calling it
`tools/call` with `name` = `get_neighbors` and arguments:
- `qname` (required): qualified name, e.g. `Unit.TClass.Method`.
- `hops` (optional): radius 1..3, default 1 (larger values are clamped).
- `db` (optional): path to a .sqlite index when the server was started without one.

The reply is JSON: `{"qname":..,"hops":N,"neighbors":[{"qname":..,"hop":N}],"omitted":N}`,
sorted by hop then name. At most 200 rows are returned; `omitted` is the number the cap
dropped, so a short answer can be told from a clipped one. An unknown name gives an empty list.

### What it needs
An index. It opens the index read-only like every other MCP tool; see Register-MCP-Server
for wiring a client.

### Example
Illustrative only: `{"qname":"uNbB.RunB","hops":2}` returns the seed at hop 0, its direct
caller and callee at hop 1, and their neighbours at hop 2.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
