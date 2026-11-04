---
id: convrules-editor
title: ConvRulesEditor
summary: Visual rulebook editor for the conversion rules; its Convert tab reports StripDB value casts, cast sites to convert by hand and uses changes (engine 1.27)
product: DL
group: component-conversion
order: 60008
since: 0.0.0
status: shipped
updated: 1.42.0-alpha
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
* **Inherited units, ancestors first** -- adding a unit walks its class chain to the root and offers
  every ancestor that still holds a From type of the checked books (intermediate classes included),
  root first. Convert never runs a descendant above its ancestor: it asks to reorder the list
  ancestor-first (No runs nothing). An unconverted ancestor that is not in the run at all blocks the same
  way: Convert asks to add the missing ancestors root-first (Yes) or cancels the whole run (No) -- a No
  when the unit was added does not exempt it later. An ancestor class that is in neither the project
  index nor the platform library index blocks the run until its unit is added to the `.dproj`/`.dpr`
  and reindexed; a library class (`TForm`, a vendor base the library declares) ends the chain. A class
  that two project units declare is ambiguous: it blocks with its own message (remove the duplicate or
  qualify the class), never as "not in a project". If the platform library cannot be asked, only
  `TForm`, `TFrame`, `TDataModule` and their `TCustom*` forms still count as roots; any other class blocks. The
  1.42 engine orders a batch ancestor-first too, as a second net.
* **Work list** -- the manual to-do list after a run: [Work list](convrules-work-list.md).
* **Reindex project** -- refresh the index between stages: [Reindex project](convrules-reindex-project.md).

### Full manual
The task-oriented manual is `docs\converter\convrules-editor-manual.md` (rule language:
`docs\converter\convrules-dsl.md`).

### Reaching it from the IDE
The IDE plugin starts the editor with a conversion request (see above); the editor has no IDE menu of its own.

### Where to click

**Conversion > Convert... (the IDE plugin starts it with --convert-request FILE and probes --write-capabilities FILE)**
1. Choose Conversion > Convert... (opens the Convert tab)
2. Or start ConvRulesEditor.exe with `--convert-request FILE` to open it pre-filled from the IDE

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
