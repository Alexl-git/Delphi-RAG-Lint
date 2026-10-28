---
id: convrules-curate
title: Curate rule books
summary: "ConvRulesEditor: split, delete, merge and compose #convert blocks across rule books on disk"
product: DL
group: component-conversion
order: 60007
since: 1.20.0-alpha
status: shipped
updated: 1.36.0-alpha
---

# Curate rule books

ConvRulesEditor: split, delete, merge and compose #convert blocks across rule books on disk.

Move rules between books or build one composed book for the engine without editing text.

## Details

File > Curate... in ConvRulesEditor opens the block-level curation window. It moves whole
`#convert` blocks between rule books, removes them, or composes the working set into one
file for the engine.

### Reaching it
ConvRulesEditor menu: File > Curate... (no shortcut). The window works on the file on disk,
so the editor offers to save first. Answer No to curate the on-disk version (nothing is
discarded); answer Yes and, if the save fails, the whole operation stops instead of curating
a stale file.

### What the toolbar does (on the checked blocks)
* **Split...** moves the checked blocks out into another file.
* **Delete** removes them.
* **Merge...** brings another file in.
* **Compose** writes the working set into one file for the engine: the whole set, or only
  the checked rules.

### There is no Copy
A rule lives in exactly one file. Rules may be moved between books, not copied: the same
conversion in two places is how two versions of it appear and diverge. To put a rule
elsewhere, Split it out. A composed book is generated output for the engine's `--rules`, so
it may carry duplicates (it holds the `#mapping` groups its rules `#apply`).

See the user manual, section "Composing the rules for one job".

### Where to click

**File > Curate...**
1. Open a rule book (File > Open...)
2. Choose File > Curate... and answer the save question
3. Check blocks, then click Split..., Delete, Merge... or Compose

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
