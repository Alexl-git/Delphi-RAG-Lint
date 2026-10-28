# ConvRulesEditor

The visual editor for conversion rule books (`.rules` files). It puts the real property tree of
the old component beside the real property tree of the new one, both read from the drag-lint
index, and lets you pair them up. The editor authors the plan; the engine verbs
(`convert-scaffold`, `convert-validate`, `convert-apply`) do the conversion.

## Starting it
`ConvRulesEditor.exe` ships inside the Win64 drag-lint release archive (there is no Win32 build).
Open a rule book from File > Open, or start a new one with File > New. The IDE plugin can also
launch it with a conversion request (`--convert-request <file>`).

## What you do in it
* **Author rules** -- pair properties, edit conditional mappings, compose the rules for one job.
* **Convert tab** -- run a conversion, see per-step progress, and read what is left: StripDB value
  casts, cast sites to convert by hand and `uses` changes. See [Convert progress](convrules-editor-convert-progress)
  and [Qualify fix](convrules-editor-qualify-fix).
* **Work list** -- the manual to-do list after a run: [Work list](convrules-editor-work-list).
* **Reindex project** -- refresh the index between stages: [Reindex project](convrules-editor-reindex-project).

## Full manual
The task-oriented manual is `docs\converter\convrules-editor-manual.md` (rule language:
`docs\converter\convrules-dsl.md`).

## Reaching it from the IDE
The IDE plugin starts the editor with a conversion request (see above); the editor has no IDE menu of its own.

## Where to click

**Conversion > Convert... (the IDE plugin starts it with --convert-request FILE and probes --write-capabilities FILE)**
1. Choose Conversion > Convert... (opens the Convert tab)
2. Or start ConvRulesEditor.exe with `--convert-request FILE` to open it pre-filled from the IDE
