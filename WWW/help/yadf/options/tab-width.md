---
id: tab-width
title: Tab width
summary: Width assumed for an existing tab on input. YADF always emits spaces.
group: line-layout
order: 30
default: "4"
ini: TabWidth
cli: --tab-width
since: "1.0.0.0"
status: "stable"
---

# Tab width

How many spaces a leading TAB character expands to when YADF
normalizes leading whitespace. Tabs inside strings and comments
are preserved verbatim.

## Related

- [Max line length](max-len.md) - Maximum line length in columns. Long lines are reflowed when ReflowLines is true.
- [Indent step](indent.md) - Indentation step in spaces (each nesting level adds this many).
