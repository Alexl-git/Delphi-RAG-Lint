# Backlog 6.2 / 6.4 / 6.5 / 6.6 Design Spec

**Date:** 2026-06-26  
**Status:** Approved  
**Scope:** Four independent features; all ship together as v0.61.0-alpha.

---

## 6.2 — GridLayout Popup Note in forms-csv

### Problem
`frmGridLayout` appears as `DEAD FORM - no callers found` in forms-csv because it is
launched by the `TGridMenuPopup` component embedded in many forms, not by a direct
form-to-form call. The graph-based dead-form detection cannot see component-driven
launches.

### Design
In `src\forms\DRagLint.FormsMap.pas`, `GenerateFormsCsv` sets the Notes column to
`'DEAD FORM - no callers found'` when a form has no callers and no path from MAIN.
Add a `KnownPopupForms` constant array of `(name: string; note: string)` pairs
checked before that branch. If the form name (case-insensitive) matches an entry,
write the entry's note instead of the DEAD FORM text.

**Initial table (one entry):**
| Form name | Note |
|---|---|
| `frmGridLayout` | `popup via TGridMenuPopup (Save/Load Layout)` |

The table lives as a typed const in the `implementation` section so future entries
can be added without changing logic.

### Files changed
- `src\forms\DRagLint.FormsMap.pas` — add `KnownPopupForms` const + lookup in `GenerateFormsCsv`

---

## 6.4 — Unit-Membership Lint Rule (`unit-not-in-project`)

### Problem
A unit referenced in source (`unit_uses`) may be: (a) a Delphi/VCL/DevExpress library
unit (expected, fine); (b) a project unit properly registered in both `.dpr` and `.dproj`
(fine); or (c) a file that exists on disk somewhere but is missing from the project's
formal member list. Case (c) means the project compiles only by accident (IDE search
path) and breaks on a clean build on another machine.

### Design

**Rule ID:** `unit-not-in-project`  
**Severity:** warning  
**Category:** project-wide (`lint-project`)

`lint-project` already resolves DBs via `ResolveConsumerDbs` (Two-DB model from
v0.60.0-alpha). The rule receives both the project DB and the platform (library) DB.

**Algorithm (per used unit `U` found in `unit_uses` of the project DB):**
1. Query the platform DB: `SELECT 1 FROM symbols WHERE unit_name = U LIMIT 1`. If found → OK (library unit).
2. Check if `U.pas` exists in the project folder tree.
3. Parse the `.dpr` uses/contains clause for `U` (reuse `ExtractUsesNames` from
   `DRagLint.Lint.ProjectChecks.pas`).
4. Parse the `.dproj` `<DCCReference>` elements for `U.pas` (reuse existing XML scan).
5. If step 2 + 3 + 4 all pass → OK (project member).
6. Otherwise → emit `unit-not-in-project` warning: `"Unit '<U>' is used but not in the
   platform library and not fully registered in the project (.dpr + .dproj)."`

**CLI integration:** `DoLintProject` passes the resolved DB list to the rule checker.
The rule opens the second DB (library) read-only alongside the first (project).

**Suppressible** via `// drag-lint:ignore unit-not-in-project`.

### Files changed
- `src\lint\DRagLint.Lint.ProjectChecks.pas` — add `CheckUnitMembership` function
- `src\cli\DRagLint.CLI.pas` — wire into `DoLintProject`, pass library DB path,
  add `unit-not-in-project` to the rule allow-list

---

## 6.5 — Global-Form-Variable Lint Rule (`global-form-variable`)

### Problem
VCL auto-generates a unit-level global variable for each form:
```pascal
var
  Form1: TForm1;
```
If the form is created more than once (e.g. `ShowModal` twice), the second instance
overwrites the global and the first leaks. This is a silent memory/handle leak.

### Design

**Rule ID:** `global-form-variable`  
**Severity:** warning  
**Category:** per-file (`lint` command), built-in in `TAstChecker`

**Detection algorithm:**
1. Check if a `.dfm` file exists beside the `.pas` being analysed
   (`TFile.Exists(ChangeFileExt(AFile, '.dfm'))`). If not → skip (not a form unit).
2. Walk the AST's root-level nodes. Collect all `defType` → class declarations to find
   the form class name(s) in this unit (the class that extends TForm/TCustomForm —
   we treat any class declared at unit scope in a form unit as a candidate).
3. Walk root-level `declVars` blocks (those that are direct children of the file root,
   not nested inside any `defProc`/`defFunc`). For each variable declaration, check
   whether the declared type name matches any class name collected in step 2
   (case-insensitive).
4. If matched → emit `global-form-variable` warning at the variable's line:
   `"Global form variable '<name>: <Type>' may leak if the form is created more than once. Consider removing the global and creating/freeing the form locally."`

**Suppressible** via `// drag-lint:ignore global-form-variable`.

### Files changed
- `src\diagnostics\DRagLint.Diagnostics.AstChecks.pas` — add `CheckGlobalFormVars`
  class function in `TAstChecker`
- `src\cli\DRagLint.CLI.pas` — wire into `DoLint` (~line 3979), add rule to allow-list

### Test fixture
- `tests\lint\global-form-variable.pas` + `.dfm` stub + `.expected`

---

## 6.6 — Batch Lint Runner (`lint-all` command)

### Problem
No single command runs all lint rules (per-file + project-wide) over all project
members and captures consolidated output for AI/user review.

### Design

**New command:** `drag-lint lint-all`

**Arguments:**
| Flag | Default | Description |
|---|---|---|
| `--project <.dproj>` | required | Project file to enumerate members from |
| `--db <path>` | auto-resolved | Override project DB; if omitted, resolved via manifest (Two-DB model) |
| `--out <file>` | `<proj-dir>\lint-report-<date>.txt` | Output file path |
| `--json` | false | Emit structured JSON instead of text |
| `--rule <id>` | all | Run only this rule (same as `lint --rule`) |
| `--disable <id,...>` | none | Disable these rule IDs |

**Execution steps (`DoLintAll`):**
1. Parse `.dproj` `<DCCReference>` elements to enumerate `.pas` member paths.
2. Auto-resolve DBs via `ResolveConsumerDbs` (Two-DB model: project + library).
3. For each `.pas` member: run all per-file lint rules (same engine as `DoLint`).
4. Run all `lint-project` rules against the project DB (same engine as `DoLintProject`).
5. Aggregate all `TLintFinding` records; deduplicate by (file, line, rule, message);
   sort by severity (error → warning → info) then file then line.
6. Write output:
   - **Text:** one finding per line `file(line,col): [rule] message`; summary footer
     `N findings (E errors, W warnings, I info)`.
   - **JSON:** `{ "project": "<dproj>", "generated": "<iso8601>", "findings": [...] }`
     where each finding has `file`, `line`, `col`, `rule`, `severity`, `message`.
7. Also emit a summary to stdout regardless of `--out`.
8. Exit 1 if any `error`-severity finding; else exit 0.

**Output path default:** `<dproj-dir>\lint-report-<YYYYMMDD>.txt` (overwritten if exists).

### Files changed
- `src\cli\DRagLint.CLI.pas` — add `DoLintAll` function + wire `lint-all` subcommand
  in the command dispatcher; add `--project`, `--out` to `TArgs`
- Command dispatcher: add `'lint-all'` → `DoLintAll` entry

---

## Self-Review Checklist

- [x] No TBD/TODO placeholders
- [x] Sections consistent: each feature has problem, design, files changed
- [x] 6.4 depends on `ResolveConsumerDbs` (already in v0.60.0-alpha) — no circular dep
- [x] 6.5 `.dfm` check is deterministic and file-system-based — no tree-sitter ambiguity
- [x] 6.6 exit code policy stated (1 on error findings)
- [x] All rule IDs unique and follow existing naming convention (kebab-case)
- [x] All new rules suppressible via `// drag-lint:ignore`
- [x] 6.2 requires no DB changes — pure CSV output change
