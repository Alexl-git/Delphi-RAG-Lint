# drag-lint Linter -- Backlog & Resume Point

> Last updated 2026-06-29 (handoff). **v0.65.1-alpha SHIPPED + RELEASED** (origin/main @ 0613e48,
> tag v0.65.1-alpha, GitHub PRERELEASE, harness **80/80**). Git clean + pushed. Since v0.63: v0.64.x
> robustness, v0.65.0 FP-8/FP-9 project-membership fixes, v0.65.1 = R2 IDE job queue + dock status bar
> + clickable lint Messages (double-click -> file:line) + float-equality & string-equality FP fixes
> (skip quoted non-alpha literal operands). Coverage gap doc: `docs/lint/MISSING-FEATURES.md`.
> **M1 CORE COMPLETE 2026-06-29 (autonomous run).** Resolver infra + 3 of 5 rule upgrades shipped to
> `main` (4 commits, harness 80/80): 9ffc642 P1 heritage (SCHEMA 11), ed65c22 P2 type_ancestors +
> ResolveAncestry + IsDescendantOf/Implements + `query ancestors`, 63e8104 P3 ResolveTypeCategory +
> skTypeAlias capture + `query typecat`, b4aafb5 P4-core float-equality/freeandnil-on-interface/
> win64-pointer-cast store-aware. Validated on real `src/` code. Plan + full status:
> `docs/superpowers/plans/2026-06-29-m1-type-resolver-plan.md` (STATUS section at bottom).
> **NOT YET CUT as a release** (VERSION still 0.65.1) -- user wants M1+M2 bundled.
> **RESUME -> finish M1 then start M2:**
>   1. **M1 remainder (P4b + P5):** (a) index method virtual/override-ness (parser+schema, like heritage)
>      -> `GetVirtualMethodsIncludingAncestors` -> virtual-method-in-constructor cross-unit; (b)
>      string-equality store-path built-in + `.scm` coexistence; (c) cross-DB library-ancestry bridge
>      (resolve RTL bases via library-Win64/Win32.sqlite by name) + ORM3 before/after counts.
>   2. **M2 = the data-flow / CFG / def-use engine** (MISSING-FEATURES.md S3 + (M2) tags) -- per-routine
>      control-flow graph + def-use to unlock used-before-assignment, write-only-field, function-result-
>      not-set, overwrite-before-read, cross-call ownership/lifetime. This is "the long pole / biggest
>      effort / engine work, not rule-writing" -- needs its OWN brainstorming + writing-plans design
>      session before coding. Do NOT start the engine without scoping it with the user.
>   3. **#12 Ergonomics** (SARIF, quick-fixes/autofix, baseline file, severity profiles) = the release
>      AFTER the M1+M2 release. Each phase: fixture -> green harness -> Win64 build -> commit. Keep
>      `tests/lint/run_lint_tests.ps1` green.
> **Pending (not in a tagged release after v0.65.1):** float-equality fix + string-equality non-alpha
> guard are on main (commits c869073, d845976) -- fold into v0.67 or cut a quick v0.65.2.
> **Stale branches** v0.22..v0.35 etc. are old dev branches (no pending work) -- deletable.
> **IDE build gotchas:** any BPL change needs RAD Studio CLOSED (bpl lock) + a manual test cycle; a VCL
> control must NOT read ClientHeight/Width (or any handle-bound prop) in its ctor before being parented
> (forces CreateWnd -> "control has no parent window") -- lay out in a Resize override.
> **Roadmap (the through-line):** `docs/superpowers/specs/2026-06-28-lint-completeness-roadmap-design.md`
> -- R1 robustness -> R2 IDE job queue -> M1 type resolver (early) -> Waves A-E (no-resolver rules,
> naming on-by-default, metrics/CK, type-dependent, cross-call-graph frontier). Decisions: serialize
> heavy IDE jobs (keep LSP live), build type resolver EARLY, naming ON by default, FP policy = when
> unsure don't report but keep the rule.
> Companion research: [REPORT-1-delphi-lint-landscape.md](REPORT-1-delphi-lint-landscape.md) (the field),
> [REPORT-2-draglint-implementation-plan.md](REPORT-2-draglint-implementation-plan.md) (original waves).
> Last lint-all ORM3 report: `C:\Projects\DB\ORM3\lint-report-20260628-122356.txt`.
> This file = what is DONE, how to resume, and what is NOT done yet (ideas/plans).

---

## 1. Status (what shipped)

**10 GitHub releases, v0.47.0-alpha .. v0.56.0-alpha (each "Latest"), all on `main`.** ~53 distinct
lint rule ids. Harness `tests/lint/run_lint_tests.ps1` = **51 fixtures green**; `selftest unused-locals`
PASS. Win64+Win32 zips bundle the `rules/` folder + `INSTALL.md` (self-contained).

Categories covered: bug-patterns (empty/bare except, raise-bare/reraise/raise-in-finally,
off-by-one, not-in/not-comparison precedence, comparison-same-operands, division-by-zero,
self-assignment, code-after-exit, nil/boolean/classname compares, redundant-not-not, empty-conditional/
loop/case), resource+lifetime (unprotected-object-free, use-after-free, freeandnil-on-interface,
missing-inherited-ctor/dtor, control-flow-in-finally, **interface-reference-cycle** ARC),
concurrency (**ui-access-in-thread**), security (sql-injection-concat, hardcoded credential/
connection-string/ip/path), platform (win64-pointer-cast, locale-sensitive-conversion, float-equality
incl. TDateTime, gettickcount-wraparound, inline-assembly), complexity/structure (too-many-parameters/
locals, method-too-long, deep-nesting, god-class, public-field, with-multiple-items, **layering-violation**
config-driven, unused-public-symbol), FireDAC (firedac-open-execsql-mismatch), plus assert-call,
uppercase-compare, outputdebugstring, length-zero-compare, magic numbers, etc.

Infra: `// drag-lint:ignore [rule...]` suppression; `lint --disable id1,id2`; `lint --rules-dir <dir>`;
`lint-project --db <idx> [--layers <json>]` (project-wide rules); bundled `rules/`; `build/pack-lint-release.ps1`.

---

## 2. Resume point (start here next session)

- Repo `C:\Projects\Delphi-RAG-lint`, branch **`main`** (single branch; the feature branch was merged + deleted).
- **Two rule engines:** (A) external `.scm`+`.json` in `rules\` (hot-loaded, no recompile); (B) Pascal
  built-ins in `src\diagnostics\DRagLint.Diagnostics.AstChecks.pas` (class `TAstChecker`) + project-wide
  rules in `src\lint\DRagLint.Lint.ProjectRules.pas`.
- **Add a `.scm` rule:** drop `rules\<id>.scm` + `<id>.json`; add `tests\lint\<id>.pas` + `<id>.expected`;
  run `pwsh tests\lint\run_lint_tests.ps1`. No rebuild.
- **Add a built-in:** new `class function TAstChecker.CheckXxx(const AFile): TArray<TLintFinding>` (copy an
  existing one's parse boilerplate); wire one line in `DoLint` (CLI ~line 3979+) + add the id to the
  `--rule` allow-list (CLI, the `unknown rule` guard) + its message; add a `tests\lint` fixture; rebuild.
- **Add a project rule:** extend `TProjectLintRules` (Store-based) or call a `TAstChecker` file-list fn
  from `DoLintProject`; test via `tests\lint-project\` (index a fixture, run `lint-project --db`).
- **Build (Win64 Release):** `build\pack-lint-release.ps1 -Version X` builds win64+win32, deploys the win64
  exe to `third_party\dll-win64`, and zips with `rules\`. (Or plain msbuild; ~7s.)
- **Release:** bump `VERSION` const (CLI.pas line 6), CHANGELOG top entry, `rules\README.md`; commit; push;
  `git tag vX` ; `gh release create vX --repo Alexl-git/Delphi-RAG-Lint --latest --notes-file ... <zips>`.
- **CRITICAL gotchas:** Edit/Write emit LF -> **normalize touched `.pas` to CRLF** before commit
  (`(t -replace "\r\n","\n") -replace "\n","\r\n"`, UTF8-no-BOM); strict 7-bit ASCII; DocInsight `///` on
  new public decls. A NEW unit must be added to BOTH the `.dpr` `uses ... in '..'` AND the `.dproj`
  `<DCCReference>` (the .dpr uses is what the compiler resolves; missing it = F2613). The canonical
  `third_party\dll-win64\drag-lint.exe` is gitignored (ships via release zip, not git).
- **tree-sitter node kinds:** discover via `C:\Projects\tree-sitter-delphi13\tree-sitter.exe parse <f>`.
  Key: a NO-paren call (`X.Open`, `GetTickCount`) is `exprDot`/`identifier`, NOT `exprCall`; anon method =
  `lambda`; `if`(no else) vs `ifElse`; `TFoo.Create` no-paren = `exprDot`. `.` anchors work for concrete
  node kinds but an anchored `(_)` wildcard does NOT constrain child count.

---

## 3. Big-ticket NOT done: a cross-unit type resolver

The single largest remaining investment. Several shipped rules are HEURISTIC because there is no real
type resolution: `float-equality-comparison`, `win64-pointer-cast`, `freeandnil-on-interface` use a
flat per-file name->type map (string prefixes), and `interface-reference-cycle` uses the I-prefix
convention. A resolver would make them EXACT and unlock new precise rules.

**Plan (multi-step, each could be its own release):**
1. Expose a symbol's resolved declared type from the index (the `symbols` table has `signature`; the
   `unit_uses` graph gives scope). Add an `ISymbolStore` query: given a unit + identifier, return its
   declared type, and given a type name, return its kind (class/interface/enum/record/alias) + ancestry.
2. Build a per-routine scope chain (locals -> params -> fields -> unit-level -> used-units) so an
   identifier resolves to a symbol -> type. (Today's flat map ignores scope/shadowing.)
3. Resolve type ancestry (class parent chain, implemented interfaces) cross-unit -> makes
   interface-reference-cycle exact (no I-prefix guess) and enables `non-linear-cast` (hard cast between
   unrelated classes), `redundant-cast` (X already that type), exact Ansi/Unicode lossy cast.
4. Rewrite the heuristic rules to use the resolver; add the new exact rules above + `exhaustive-enum-case`
   (case over an enum missing values -- needs enum member count), `stringlist-duplicates-unsorted`,
   `format-argument-type-mismatch`.

This is infrastructure first; budget it as a milestone, not a single rule.

---

## 4. Rule-idea backlog (no type resolver needed -- "more small batches")

Detectable from AST / index today; pick batches of these:

- **FireDAC:** `parambyname-in-loop` (extend the existing `field-by-name-in-loop` walk to `.ParamByName`);
  `dataset-open-without-close` (Open/Connected:=True without try-finally Close -- flow-ish);
  `query-created-without-owner-never-freed` (flow); `fetchall-on-large` (low signal).
- **Resource:** `stream-not-freed` / `criticalsection-not-released` / `file-not-closed` (Enter/Leave,
  FileOpen/CloseFile pairing per routine, like CheckUnprotectedFree); `double-free` (X.Free twice).
- **Security:** `unsanitized-shellexecute` (ShellExecute/CreateProcess/WinExec with a non-literal arg);
  `weak-random-for-security` (Random near token/password identifiers); `unsafe-string-api`
  (StrCopy/StrCat/StrPCopy -- unbounded); `path-traversal` (file API with concatenated path var).
- **Control-flow / expr:** `constant-condition` (`if True`/`while False`); `loop-executes-at-most-once`
  (unconditional Exit/Break/raise in a loop body); `ifthen-both-branches` (SysUtils.IfThen evaluates both
  args -- a pitfall); `assignment-result-ignored` (function called as a statement).
- **Maintainability:** `commented-out-code` (comment that parses as Pascal -- info, FP-prone);
  `duplicated-code` / clones (token-hash across impl ranges); `magic-string`; `multiple-statements-per-line`
  (needs same-line sibling detection -> built-in).
- **Metrics:** `cyclomatic-complexity` / `cognitive-complexity` (count decision points incl. and/or in a
  routine body -- verify `kAnd`/`kOr` node names first); `too-many-nested-routines`; `too-many-exit-points`.
- **Platform:** `pchar-arithmetic`; `variant-record-type-punning`; `deprecated-rtl-function` (StrCopy, Str/Val,
  GetMem-without-FreeMem); `sizeof-pointer-assumption` (`SizeOf(Pointer) = 4`).
- **Naming (low-FP subset already partly covered):** `field-not-f-prefixed`, `class-not-t-prefixed`,
  `interface-not-i-prefixed`, `exception-not-e-prefixed`, `param-prefix`, `unit-name-mismatch-file`
  (needs unit name vs filename) -- ship OFF-by-default or as a separate "conventions" profile to avoid noise.

---

## 5. Infra / UX backlog (high adoption value)

- **SARIF output** (`--format sarif`) for GitHub code-scanning / CI. (JSON + text exist.)
- **Per-`.scm` enable/disable**: honor `"enabled": false` in each `.json` + `--enable <id>` (today only
  `--disable` exists; `.scm` rules otherwise always run). Lets naming/style rules ship off-by-default.
- **Persistent config file** `drag-lint-lint.json` (CWD): `{ "disabled":[...], "enabled":[...],
  "thresholds": { "too-many-parameters": 7, ... }, "severity": { "<id>":"warning" } }`. Today thresholds
  are hardcoded conservative defaults; `--disable` is per-run only.
- **IDE-plugin deploy of `rules\`**: confirm the OTAPI plugin ships/points `rules\` beside the spawned exe
  (or passes `--rules-dir`); otherwise `.scm` rules are dormant in the IDE.
- **Quick-fixes / autofix** (the SonarDelphi/DelphiLint differentiator): e.g. `Assigned(X)` for `X <> nil`,
  remove redundant `as TObject`, `- 1` for off-by-one, `SameText` for uppercase-compare.
- **Baseline / suppression file** (ignore the existing N findings; only flag new ones) for adoption on
  large legacy codebases.
- **CI exit-code policy** by severity (fail build on `error`/`warning` but not `info`).
- **A unified test runner** that also exercises the `lint-project` rules (index a fixture + assert) -- today
  those are manual (`tests/lint-project/README.md`).

---

## 6. forms-csv + indexing backlog (new 2026-06-26d)

These items were added by the user after the forms-csv false-DEAD investigation concluded.
Priority order: 1 -> 2 -> 3 -> 4 -> 5 -> 6.

### 6.1 hg post-commit auto-reindex hook (ORM3 repo) -- DONE 2026-06-26

**Status: IMPLEMENTED.** User-level hook fires for all ORM3 sub-repos.

**Files delivered:**
- `C:\Users\alexanderl\mercurial.ini` -- added `[hooks] post-commit.orm3reindex = python:...`
- `C:\Users\alexanderl\hg-hooks\orm3_reindex.py` -- Python hook; checks `repo.root` contains
  `ORM3`; spawns `drag-lint index C:\Projects\DB\ORM3 --db C:\Projects\DB\ORM3\drag-lint.sqlite`
  as a background process (CREATE_NO_WINDOW); logs to `C:\Users\alexanderl\hg-hooks\orm3_reindex.log`.

**Verify:** commit any .pas in CLIENT/COMMON/SERVER/PACKAGE/tools, then:
  `Get-Content C:\Users\alexanderl\hg-hooks\orm3_reindex.log`

### 6.2 GridLayout: "popup on grid" note in forms-csv

**Problem:** GridLayout (frmGridLayout, C:\Projects\DB\ORM3\CLIENT\GridLayout.pas) appears
as "DEAD FORM - no callers found" in forms-csv because it is NOT launched by a form-to-form
call. It is launched by the `TGridMenuPopup` component embedded in many forms, for Save
Layout As / Load Layout functionality.

**Fix:** Hard-code a special note for GridLayout in `DRagLint.FormsMap.pas` or use a
"known popup forms" table. The note should say something like: "popup on grid (TGridMenuPopup
Save/Load Layout)" in the Notes column instead of "DEAD FORM".

**Alternative:** Detect `TGridMenuPopup` as a call site in BuildEdges -- query for refs to
frmGridLayout from TGridMenuPopup and emit an edge like "TGridMenuPopup (Save Layout As)".

**File:** src/forms/DRagLint.FormsMap.pas

### 6.3 Two-DB indexing model (Platform + Project) -- DONE v0.60.0-alpha 2026-06-26

**User request:** "For indexing let's use 2 libraries:
1. Platform -- Delphi Library and browsing path for the given platform selected for the
   current project (changes when platform changes)
2. Project -- All project members compiled and scanned as forms, pas, Inc, etc...
By default drag-lint should be working with these 2 SQLite DBs."

**Spec:** `docs/superpowers/specs/2026-06-26-two-db-model-design.md` (committed ee10b25)
**Plan:** `docs/superpowers/plans/2026-06-26-two-db-model.md` (committed a04f24a) -- 4 tasks ALL DONE
**Commits:** cda2876 (CLI platform detect), 4ab9018 (plugin), 65da564 (index auto-DB), 92576bc (release)

**Design (approved 2026-06-26):**
- Platform DB: one DB per target platform (Win32/Win64) covering Delphi RTL + VCL +
  DevExpress (all dirs on the IDE's Library Path and Browse Path for that platform).
  Already partially exists as `C:\Projects\.drag-lint\library-Win32.sqlite` /
  `library-Win64.sqlite` -- needs to become the canonical "Platform" DB.
- Project DB: covers all units in the project's .dpr/.dproj (including COMMON/OBJECTS,
  not just CLIENT). Already exists as `C:\Projects\DB\ORM3\drag-lint.sqlite`.
- CLI consumers (query, lint, forms-csv) would auto-load both when no --db given;
  `resolve-dbs --platform <p>` already does something similar via the manifest.
- Model change: manifest `indexes` array -> tag each DB as `platform` or `project`; CLI
  resolves by platform tag + project working dir.

### 6.4 Unit-membership lint rule

**User request:** "Lint function -- checks all used units if they do not belong to the
Platform they must be in the project folder and must be member of both dpr and dproj.
If not there should be a warning about it."

**Implementation (not yet started):**
- Walk all units in the Project DB; for each unit's `unit_uses` entries, check if the
  used unit is in the Platform DB OR (exists in the project folder AND is listed in
  both the .dpr uses clause AND the .dproj DCCReference list).
- Report warning: `unit-not-in-project` (used unit not in Platform DB and not in .dpr/.dproj).
- Requires parsing .dpr and .dproj to enumerate listed units -- .dpr `uses..in` clauses
  and .dproj `<DCCReference Include="...">` elements.
- Can be a `lint-project` rule (Store-based, operates on the whole index + project files).

### 6.5 Form global-variable lint rule

**User request:** "Forms often have global variables with the same name associated with
them. I think we should comment this all out and report as a warning. The use of these
may cause 2 different forms creating 2 TForm and saving it in the same variable causing a leak."

**Background:** VCL's auto-generated unit-level global `var Form1: TForm1;` -- if two
instances are created (ShowModal twice, or Show + ShowModal), the second overwrites the
global pointer and the first leaks (no reference to Free it).

**Implementation (not yet started):**
- Detect unit-level variable declarations where:
  (a) The variable type is a class that descends from TForm (or TCustomForm)
  (b) The variable name matches the class name minus the `frm`/`T` prefix convention
- Report as `global-form-variable` warning with message:
  "Global form variable '<name>' may leak if the form is created more than once.
   Consider removing the global and creating/freeing the form locally."
- Can be a `.scm` rule or a built-in in TAstChecker.
- For the "comment out" part: this would be an autofix suggestion (future; not in scope now).

### 6.6 Batch lint runner

**User request:** "There should be a function to run Lint over all project members.
The output should be captured in some place that AI or user can read and AI can action upon it."

**Background:** `lint-project --db <idx>` already runs project-wide rules; `lint <file>` runs
per-file rules. What's missing is a single command that runs all rules over all project
members and captures the consolidated output.

**Implementation (not yet started):**
- `drag-lint lint-all --project <dproj> --db <db> --out <report.txt|json|sarif>`:
  (a) enumerate all .pas units in the .dproj
  (b) run `lint` on each file (all per-file rules)
  (c) run `lint-project` rules against the full index
  (d) aggregate findings, deduplicate, sort by severity then file
  (e) write to --out (default: `<project-dir>\docs\lint-report-<date>.txt`)
- Output format should be AI-friendly: structured JSON with file, line, rule id, message.
  Also a human summary (counts by severity/rule).
- The AI can then read the report and action on the highest-severity items.
- Relates to 6.3 (2-DB model): batch runner should auto-load Platform + Project DBs.

---

## 7. IDE plugin -- lint-all menu command (target v0.63)

**User request (2026-06-28):** "Create code that would generate such a report after
parsing all .dpr/.dproj that I could invoke in the drag-lint menu in the IDE."

**Goal:** A single IDE menu item "Run Lint All (Full Report)" that:
1. Reads the currently-active project path from the IDE via OTAPI
   (`(BorlandIDEServices as IOTAProjectManager).GetCurrentProject.FileName`)
2. Resolves the two-DB pair (Platform + Project) via the manifest / `resolve-dbs`
   logic already in the CLI -- or just hard-codes the manifest path for now.
3. Spawns `drag-lint lint-all --project <active.dproj> --db <project.sqlite>` as a
   background process (non-blocking -- the IDE must not freeze).
4. Writes the report to `<project-dir>\docs\lint-report-<date>.txt`.
5. On completion, opens the report file in the IDE's default editor
   (`(BorlandIDEServices as IOTAFileSystem).OpenFile(reportPath)` or `ShellExecute`
   to notepad if the IDE file system API is unavailable).
6. Shows a brief status in the IDE's message view: "Lint-all complete: N findings
   (E errors, W warnings) -- report: <path>".

**Implementation notes:**
- The wizard already has a toolbar/menu integration point (`TDragLintWizard`,
  `dclDragLintWizard.bpl`). Add a new `TAction` / `TMenuItem` entry there.
- Background process: use `TProcess` or `CreateProcess` + a `TThread` that waits on
  the process handle and posts completion back to the main thread via
  `TThread.Synchronize` (same pattern as existing index-on-save).
- Requires BPL rebuild and re-deploy (`build\pack-lint-release.ps1`).
- Must work even when the IDE currently has no project open (disable the menu item
  in that case via `OnUpdate`).

**Design doc:** `docs/superpowers/specs/2026-06-28-new-lint-rules-v062-v063-design.md`
(see section 8 -- IDE lint-all menu).

---

## 8. Pointers

- Rule list (user-facing): `rules/README.md`. Per-file harness: `tests/lint/`. Project-rule fixtures:
  `tests/lint-project/`. Release script: `build/pack-lint-release.ps1`.
- The two research reports (landscape + plan) sit beside this file in `docs/lint/`.
