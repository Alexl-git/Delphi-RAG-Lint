---
id: v152-disable-rule
title: Disable rule (this line, this unit, this project)
summary: "Silence one lint rule for a line (dl:ok marker), a unit or the project (rule_overrides in drag-lint-lint.json), with a reason and date; rules enable undoes it"
product: DL
group: linting
order: 30070
since: 1.52.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# Disable rule (this line, this unit, this project)

Silence one lint rule for a line (dl:ok marker), a unit or the project (rule_overrides in drag-lint-lint.json), with a reason and date; rules enable undoes it.

Read this when a finding is right for most of the code but not here: disable the rule for this line, this unit or this project from the RAD Studio editor's right-click menu or with rules disable, and undo it with rules enable. Unit and project scope never write into the source.

## How to run it

```text
drag-lint rules disable|enable --rule <id> --scope line|unit|project [--in <F> --line <N>] --reason "<text>" [--project <.dproj>] [--config <drag-lint-lint.json>] [--json]   (line = a dl:ok marker on the line; unit / project = rule_overrides in the project lint config, with reason and date; enable undoes one disable)
```

Full flag list: [rules in the CLI reference](../cli.md#rules).

## Flags

| Flag | Argument | Meaning | Default |
| --- | --- | --- | --- |
| `--rule` | `<id>` |  |  |
| `--scope` | `line\|unit\|project` |  |  |
| `--in` | `<F>` |  |  |
| `--line` | `<N>` |  |  |
| `--reason` | `<text>` |  |  |
| `--project` | `<.dproj>` |  |  |
| `--config` | `<drag-lint-lint.json>` |  |  |
| `--json` |  |  |  |

## Where to click

* RAD Studio main menu: **drag-lint > Code Quality > Disable Rule...**
   1. Put the caret on a line that shows a drag-lint finding
   2. Choose drag-lint > Code Quality > Disable Rule...
   3. Pick Disable here (this line), Disable in this unit or Disable in this project
   4. Type a one-line reason and press OK
* Right-click in the Editor: **drag-lint > Disable Rule...**
   1. Put the caret on a line that shows a drag-lint finding
   2. Right-click in the editor, open the drag-lint submenu and choose Disable Rule...
   3. Pick Disable here (this line), Disable in this unit or Disable in this project
   4. Type a one-line reason and press OK

## Details

A finding can be right for most of the code and wrong in one place. Instead of switching the rule off everywhere, disable it exactly as wide as it needs to be, and say why. Every disable carries a one-line reason and a date; `rules enable` undoes it.

### The three scopes

| Scope | What is written | Where |
|---|---|---|
| This line | `// dl:ok <rule>@<hash> -- REVIEWED <yyyy-mm-dd>: <reason>` on the finding's line, the same marker `drag-lint allow` writes | the source file (it moves with the code; the hash makes it stale when the line changes) |
| This unit | `"rule_overrides": { "<rule>": { "exclude_units": ["<Unit>"], "reason": "...", "date": "..." } }` | the project's `drag-lint-lint.json`; the source is not touched |
| This project | `"rule_overrides": { "<rule>": { "enabled": false, "reason": "...", "date": "..." } }` | the same file (the one the Lint Options dock saves) |

There is no machine-wide scope here: a rule that is wrong for every project is a rule to fix or to switch off in the catalogue, not something to hide from one editor.

### RAD Studio

Put the caret on the line that shows the finding, then either right-click in the editor and choose `Disable Rule...` from its drag-lint submenu, or use the main menu `drag-lint > Code Quality > Disable Rule...`. Pick one of the three command links (`Disable here (this line)`, `Disable in this unit`, `Disable in this project`), type a reason and press OK. Line scope saves all open files first, because the engine edits the file on disk. The engine's answer is shown in a message box.

### Command line

```text
drag-lint rules disable --rule empty-except --scope line --in Src\Unit1.pas --line 18 --reason "logged by the caller"
drag-lint rules disable --rule empty-except --scope unit --in Src\Unit1.pas --reason "legacy unit, kept as is"
drag-lint rules disable --rule empty-except --scope project --project App.dproj --reason "team ruling 2026-11"
drag-lint rules enable  --rule empty-except --scope unit --in Src\Unit1.pas
```

* `--scope` is required. Line scope needs `--in` (alias `--file`) and `--line`; unit scope needs `--in` (the unit name is the file name without `.pas`).
* `--reason` is required by `disable` and ignored by `enable`. The reason must be 7-bit ASCII for line scope (the source stays ASCII); in the config file a non-ASCII character is written as a `\uXXXX` escape.
* The config file: `--config` when given; else beside `--project` (or in its `_D-RAG` folder when only that one exists; a new file is created beside the `.dproj`); else the nearest `drag-lint-lint.json` above `--in`, the same order `lint` uses to find it. Every other key in the file is kept; the file is written as 7-bit ASCII with CRLF line ends.
* `--json` prints one object: `action`, `rule`, `scope`, `file` + `line` (line scope) or `config`, `changed`, `exit`, `message`.
* Exit codes: 0 done; 1 nothing to do (already disabled, or nothing to enable); 2 usage error or refused (nothing is written).

### What `rules enable` undoes

* Line: removes that rule's entry from the line's `dl:ok` marker (the whole comment goes when it held nothing else), so the line is back to its original bytes.
* Unit: removes the unit from `exclude_units`.
* Project: removes `"enabled": false`, and also removes the rule from the top-level `"disabled"` list, where the Lint Options dock records a project-wide disable.

An override entry left with nothing in it is removed, and so is an empty `rule_overrides` block.

### Limits

* Line scope refuses the whole-routine metric rules (method-too-long, cyclomatic-complexity and the others whose marker records the measured value): use `drag-lint allow <file> --fix-line <N> --fix-rule <id> --apply`, or disable them for the unit or the project.
* Line scope refuses `review-marker-*` and `parser-error`, exactly as `allow` does: they are not findings about code.
* A line that carries no code (blank, comment) or where a marker would not parse back (inside a block comment or a string) is refused; disable the rule for the unit instead.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
