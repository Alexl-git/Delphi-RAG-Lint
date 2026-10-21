---
id: convrules-editor
title: ConvRulesEditor
summary: Visual rulebook editor for the conversion rules; its Convert tab reports StripDB value casts, cast sites to convert by hand and uses changes (engine 1.27)
product: DL
group: component-conversion
order: 60006
since: 0.0.0
status: shipped
updated: 1.33.0-alpha
---

# ConvRulesEditor

Visual rulebook editor for the conversion rules; its Convert tab reports StripDB value casts, cast sites to convert by hand and uses changes (engine 1.27).

Edit conversion-rules books visually, run a conversion and see what is left to do by hand.

## Details

The visual editor for conversion rule books (`.rules` files). It puts the real property tree of
the old component beside the real property tree of the new one, both read from the drag-lint
index, and lets you pair them up. The editor authors the plan; the engine verbs
(`convert-scaffold`, `convert-validate`, `convert-apply`) do the conversion.

### Starting it
`ConvRulesEditor.exe` ships inside the Win64 drag-lint release archive (there is no Win32 build).
Open a rule book from File > Open, or start a new one with File > New. The IDE plugin can also
launch it with a conversion request (`--convert-request <file>`).

### What you do in it
* **Author rules** -- pair properties, edit conditional mappings, compose the rules for one job.
* **Convert tab** -- run a conversion, see per-step progress, and read what is left: StripDB value
  casts, cast sites to convert by hand and `uses` changes. See [Convert progress](convrules-convert-progress.md)
  and [Qualify fix](convrules-qualify-fix.md).
* **Work list** -- the manual to-do list after a run: [Work list](convrules-work-list.md).
* **Reindex project** -- refresh the index between stages: [Reindex project](convrules-reindex-project.md).

### Full manual
The task-oriented manual is `docs\converter\convrules-editor-manual.md` (rule language:
`docs\converter\convrules-dsl.md`).

### Reaching it from the IDE
The IDE plugin starts the editor with a conversion request (see above); the editor has no IDE menu of its own.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
