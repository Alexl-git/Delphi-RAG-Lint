# convert-apply Verb Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. **This plan is sub-project B; it depends on sub-project A (ref-gap G) being shipped before Task 6 (surface #4). Tasks 1-5 are buildable without A.**

**Goal:** Ship a `convert-apply` CLI verb that converts a real component in a real `.pas` + sibling `.dfm`, rewriting five surfaces (declaration type, uses, DFM block, property/event access, runtime creators) so the result compiles (modulo runtime-creator TODO markers), with dry-run by default and a versioned-backup + recovery.txt safety protocol.

**Architecture:** A new orchestrator unit `DRagLint.Convert.Apply.pas` locates the converted instances (from the .dfm object list + .pas field list, filtered by `#convert` rules + `--only`), then builds an edit set across five surfaces by REUSING shipped engines: `ReemitComponent` (2a-i, .dfm), `TFindUnitRefactoring` (uses), `TTextEditApplier`/`TTextEdit` (byte edits), `BuildPropTree` (T-tree), `ParseConversionRules`/`ValidateConversionRules` (rules), and the ref index (`member-access` from ref-gap G for #4; `call_edges` for #5). A new backup/recovery layer wraps the writes with the `.BCK<n>` + recovery.txt + in-file-comment protocol. The CLI verb `DoConvertApply` drives it dry-run-by-default.

**Tech Stack:** Delphi 13 (RAD Studio 37); SQLite ref index; tree-sitter (via the reused engines); FireDAC not involved; PowerShell autotest driving `src/cli/Win64/Debug/drag-lint.exe`.

## Global Constraints

- **Encoding:** all new/edited `.pas` and `.ps1` files strict 7-bit ASCII, NO BOM, CRLF. No Unicode/em-dashes -- use `--`.
- **Dry-run is the DEFAULT and writes NOTHING** (prints a unified diff + report). `--apply` writes with the backup/recovery protocol. `--no-backup` skips the `.BCK<n>` backups.
- **Reuse, do not reimplement:** `ReemitComponent` (`DRagLint.Convert.DfmReemit`), `TFindUnitRefactoring.Build` + `TTextEditApplier.Apply`/`RenderDryRun` + `TTextEdit` (`DRagLint.Refactor.TextEdit`), `BuildPropTree` (`DRagLint.Convert.PropTree`), `ParseConversionRules`/`ValidateConversionRules` (`DRagLint.Convert.Rules`), the store-open + proptree pattern from `DoConvertReemit`/`DoConvertValidate` (`DRagLint.CLI.pas`).
- **Backup protocol (the user's exact design):** on `--apply` (unless `--no-backup`): (1) back up each touched file to the NEXT-FREE `NAME.EXT.BCK<n>` (lowest unused positive integer for THAT file); (2) APPEND a timestamped `original -> backup` block (+ rules file) to `recovery.txt` in the unit's folder, WRITTEN BEFORE any conversion write; (3) perform the conversion; (4) prepend a `// drag-lint convert-apply <ts> ... backup: ... rules: ...` comment block atop the converted `.pas`.
- **Freshness guard:** before trusting the index for F/T trees + refs, verify the F and T types are indexed and current (mtime/sha vs disk); WARN in dry-run, REFUSE on `--apply` (exit 1) if stale/unindexed.
- **Re-validate rules before applying:** run `ValidateConversionRules`; refuse (exit 1) on errors.
- **A-dependency:** surface #4 (property/event access, Task 6) requires ref-gap G's `member-access` kind. If G is not shipped, #4 runs in REPORT-ONLY mode (list the sites, no rewrite) and Tasks 1-5 still deliver a real conversion. In our build order G ships first, so #4 is a full rewrite.
- **DocInsight/CDD:** every public type/function carries `///` DocInsight; comment and test agree.
- **Build recipe:** CLI Win64 Debug via rsvars + msbuild `src/cli/drag-lint.dproj` through PowerShell `Start-Process -Wait`; read log for `BUILD_EXITCODE=0` + no `[dcc] Error`. Exe: `src/cli/Win64/Debug/drag-lint.exe`. NO MCP build tool; NO `cmd.exe /c build.bat` from Bash. Add any new unit to BOTH `src/cli/drag-lint.dproj` DCCReference AND the CLI uses clause (the .dproj-not-compiled trap).

---

## File Structure

- **Create** `src/report/DRagLint.Convert.Apply.pas` -- the applier orchestrator: instance location, the five-surface edit builder, the structured report. Reuses the shipped engines.
- **Create** `src/report/DRagLint.Convert.Backup.pas` -- the backup/recovery layer: next-free `.BCK<n>`, `recovery.txt` append (written first), in-file comment prepend. Pure-ish (file I/O only; no store).
- **Modify** `src/cli/DRagLint.CLI.pas` -- `DoConvertApply` verb + `--unit`/`--only` args (reuse `RulesFile`/`Apply`/`NoBackup`) + dispatch + DOCUMENTED help text.
- **Modify** `src/cli/drag-lint.dproj` -- DCCReference for the two new units.
- **Create** `tests/autotest/run_convert_apply.ps1` -- fixture (.pas + .dfm + rules) + dry-run + --apply assertions.
- **Modify** docs: `docs/CONVERSION-RULES.md` (apply workflow), `README.md`/`docs/AI-USAGE.md`, `CHANGELOG.md`.

---

## Task 1: Instance location + the applier skeleton

**Files:**
- Create: `src/report/DRagLint.Convert.Apply.pas` (skeleton: types + `BuildApplyPlan` returning an empty result)
- Modify: `src/cli/drag-lint.dproj` (DCCReference)
- Test: (compile gate this task; runtime location asserted in Task 2)

**Interfaces:**
- Consumes: `TConversionRuleSet` (rules), `ISymbolStore` (index).
- Produces:
  - `TConvertInstance = record InstanceName: string; FromType: string; ToType: string; end;` -- one component to convert.
  - `TApplyReport = record` with `TArray<string>` fields: `Converted` (per-instance summary), `AccessSites`, `CreatorSites`, `Todos`, `ReemitNotes`, `Warnings`.
  - `TApplyResult = record Edits: TArray<TTextEdit>; Report: TApplyReport; Ok: Boolean; Error: string; end;` (TTextEdit from `DRagLint.Refactor.TextEdit`).
  - `function BuildApplyPlan(const AStore: ISymbolStore; const AUnitPas, ADfmPath: string; const ARules: TConversionRuleSet; const AOnly: TArray<string>): TApplyResult;` -- the orchestrator (body filled across Tasks 2-6; a stub returning Ok=False/'not implemented' here).
  - `function FindConvertInstances(const ADfmText: string; const ARules: TConversionRuleSet; const AOnly: TArray<string>): TArray<TConvertInstance>;` -- parse the .dfm top-level objects (reuse `ParseDfmBlock` from 2a-i on the whole form, or a lighter object-header scan), match each object's class to a `#convert FromType` rule (and `--only` if given), return the instances to convert. Implemented in Task 2.

- [ ] **Step 1: Confirm the reused signatures**

Read the real signatures the applier depends on:

Run: `grep -n "class function Build\|class function Apply\|class function RenderDryRun\|TTextEdit = record" src/refactor/DRagLint.Refactor.TextEdit.pas`
Run: `grep -n "function ReemitComponent\|function ParseDfmBlock\|TReemitResult" src/report/DRagLint.Convert.DfmReemit.pas`
Run: `grep -n "function BuildPropTree\|TPropTreeOptions" src/report/DRagLint.Convert.PropTree.pas`
Note `TTextEdit`'s fields (FilePath, offsets/line-col, replacement text) -- the edit set is `TArray<TTextEdit>` and `TTextEditApplier.Apply(edits, writeBackups)` / `RenderDryRun(edits)` consume it.

- [ ] **Step 2: Create the skeleton unit + wire it**

Create `src/report/DRagLint.Convert.Apply.pas` with the interface types above and stub bodies (`BuildApplyPlan` -> Ok=False/'not implemented'; `FindConvertInstances` -> nil). Full DocInsight on the public types + functions. Uses: `System.SysUtils`, `System.Generics.Collections`, `DRagLint.Core.Interfaces`, `DRagLint.Convert.Rules`, `DRagLint.Convert.DfmReemit`, `DRagLint.Convert.PropTree`, `DRagLint.Refactor.TextEdit`.

Add to `src/cli/drag-lint.dproj` after the DfmReemit DCCReference:
```xml
        <DCCReference Include="..\report\DRagLint.Convert.Apply.pas"/>
```
Temporarily add `DRagLint.Convert.Apply` to the CLI uses clause (Task 7 keeps it) so it compiles (the .dproj-trap).

- [ ] **Step 3: Build to verify it compiles**

Build (Win64 Debug). Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`. Verify the new file is ASCII/CRLF (python byte-check).

- [ ] **Step 4: Commit**

```bash
git add src/report/DRagLint.Convert.Apply.pas src/cli/drag-lint.dproj src/cli/DRagLint.CLI.pas
git commit -m "feat(convert-apply): applier skeleton (types + stubs + wiring)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Surface #1 (declaration type) + #2 (uses) + instance location + the CLI verb (dry-run)

**Files:**
- Modify: `src/report/DRagLint.Convert.Apply.pas` (`FindConvertInstances` + surfaces #1/#2 in `BuildApplyPlan`)
- Modify: `src/cli/DRagLint.CLI.pas` (`DoConvertApply` verb, dry-run only)
- Create/extend: `tests/autotest/run_convert_apply.ps1`

**Interfaces:**
- Consumes: `FindConvertInstances`, `TFindUnitRefactoring.Build`, `TTextEditApplier.RenderDryRun`, the store-open pattern from `DoConvertReemit`.
- Produces: `convert-apply --unit F.pas --rules R --db D [--only ...]` prints a dry-run diff covering the .pas declaration retype + the uses-add for each ToType. Exit 0.

- [ ] **Step 1: Write the failing test (dry-run, surfaces #1+#2)**

Create `tests/autotest/run_convert_apply.ps1`. Fixture: a tiny form unit + .dfm + rules.
```pascal
// MyForm.pas
unit MyForm;
interface
uses Classes, OldEditUnit;
type
  TMyForm = class(TForm)
    Edit1: TOldEdit;
  end;
implementation
{$R *.dfm}
end.
```
```
// MyForm.dfm
object MyForm: TMyForm
  object Edit1: TOldEdit
    Caption = 'Hi'
  end
end
```
```
// rules: #convert TOldEdit -> TNewEdit, NewEditUnit
//        #link Text <- Caption
```
Both TOldEdit (unit OldEditUnit) and TNewEdit (unit NewEditUnit) must be defined in indexable fixture units so proptree + find-unit resolve them.

Assert dry-run output (`convert-apply --unit MyForm.pas --rules r --db db`, NO --apply):
- shows `Edit1: TOldEdit` -> `Edit1: TNewEdit` (declaration retype).
- shows a uses-add of `NewEditUnit` (surface #2 via find-unit).
- exit 0; NO files written (assert MyForm.pas is byte-unchanged on disk after the dry-run).

Run against the current exe -> FAIL (no convert-apply verb). Capture RED.

- [ ] **Step 2: Implement FindConvertInstances**

In `BuildApplyPlan`/`FindConvertInstances`: read the .dfm text, enumerate its top-level + nested `object Name: Class` headers (reuse `ParseDfmBlock` per top-level object, or a light scan of `object <Name>: <Class>` lines). For each, if `<Class>` matches a `#convert FromType` (and, when `AOnly` non-empty, `<Name>` is in `AOnly`), add a `TConvertInstance{Name, FromType, ToType}`. Return them.

- [ ] **Step 3: Implement surface #1 (declaration retype) + #2 (uses)**

For each instance: locate its field declaration in the .pas (the published `Name: FromType;` in the form class -- find via the store's symbol for that field, or a scoped text search for `<Name>\s*:\s*<FromType>`). Emit a `TTextEdit` replacing the `FromType` token with `ToType`. For each distinct `ToType`, call `TFindUnitRefactoring.Build(Store, ToType, AUnitPas, unit, already)` and append its edits (skip if `already`). Collect all edits into `TApplyResult.Edits`; add per-instance lines to `Report.Converted`.

- [ ] **Step 4: Implement DoConvertApply (dry-run)**

In `DRagLint.CLI.pas`: add `--unit` (reuse or add an arg -> a new `Result.ConvUnit` or reuse `GhostUnit`/`InFile`; pick one and be consistent) and `--only` (comma-split -> `TArray<string>`) parsing. Add `DoConvertApply`: open the store (copy `DoConvertReemit`'s pattern), resolve the sibling .dfm (same base name, `.dfm`, same folder as `--unit`), parse+validate the rules (refuse on errors), call `BuildApplyPlan`. In dry-run (no `--apply`), print `TTextEditApplier.RenderDryRun(Result.Edits)` + the report. Dispatch `convert-apply` -> `DoConvertApply`. Add DOCUMENTED help text. Exit 0/1/2 per the spec.

- [ ] **Step 5: Build + run the test (GREEN dry-run)**

Build (Win64 Debug). Run: `pwsh -File tests/autotest/run_convert_apply.ps1`. Expected: PASS -- the dry-run shows the retype + uses-add, no writes. Byte-check both edited files ASCII/CRLF.

- [ ] **Step 6: Commit**

```bash
git add src/report/DRagLint.Convert.Apply.pas src/cli/DRagLint.CLI.pas tests/autotest/run_convert_apply.ps1
git commit -m "feat(convert-apply): instance location + .pas decl retype + uses-add (dry-run)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Surface #3 (.dfm block re-emit) wired to real file bytes

**Files:**
- Modify: `src/report/DRagLint.Convert.Apply.pas` (surface #3 in `BuildApplyPlan`)
- Extend: `tests/autotest/run_convert_apply.ps1`

**Interfaces:**
- Consumes: `ReemitComponent` (2a-i), `BuildPropTree`, the .dfm text + byte offsets of each instance's object block.
- Produces: a `TTextEdit` replacing each F object block in the .dfm with the re-emitted T block.

- [ ] **Step 1: Extend the test (dry-run shows the .dfm re-emit)**

Add assertions: the dry-run diff for MyForm.dfm shows `object Edit1: TOldEdit ... Caption = 'Hi'` -> `object Edit1: TNewEdit ... Text = 'Hi'` (the #link Text<-Caption applied by ReemitComponent). Still no writes. Run -> FAIL (surface #3 not built).

- [ ] **Step 2: Implement surface #3**

For each instance: build the F and T property trees via `BuildPropTree(Store, '<unit>.<FromType>' / '<ToType qname>', opts)` (opts.Depth=6, ToPersistent=True -- copy `DoConvertReemit`). Extract the instance's F object block text + its byte span from the .dfm (from `FindConvertInstances`/`ParseDfmBlock` positions). Call `ReemitComponent(FBlock, ARules, FromTree, ToTree)`. If `Ok`, emit a `TTextEdit` on the .dfm replacing the F block bytes with `Result.DfmText`; fold the reemit `Report` into `Report.ReemitNotes`. If not Ok, add a `Report.Warnings` entry and skip that instance's .dfm edit (keep the .pas edits? -- NO: if the .dfm re-emit fails, skip the WHOLE instance and warn, to avoid a half-converted component; document this).

- [ ] **Step 3: Build + run (GREEN)**

Build. Run the test. Expected: PASS -- dry-run now shows .pas retype + uses + .dfm re-emit. Byte-check.

- [ ] **Step 4: Commit**

```bash
git add src/report/DRagLint.Convert.Apply.pas tests/autotest/run_convert_apply.ps1
git commit -m "feat(convert-apply): surface #3 -- .dfm block re-emit via ReemitComponent

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Backup/recovery layer + --apply + freshness guard

**Files:**
- Create: `src/report/DRagLint.Convert.Backup.pas`
- Modify: `src/report/DRagLint.Convert.Apply.pas` (freshness guard), `src/cli/DRagLint.CLI.pas` (--apply path)
- Modify: `src/cli/drag-lint.dproj` (DCCReference for the backup unit)
- Extend: `tests/autotest/run_convert_apply.ps1`

**Interfaces:**
- Consumes: the edit set from Tasks 2-3; `TTextEditApplier.Apply`.
- Produces:
  - `function NextBackupName(const APath: string): string;` -- `<path>.BCK<n>` with the lowest free n.
  - `procedure WriteRecoveryRecord(const AUnitFolder, ATimestamp, ARulesFile: string; const AMappings: TArray<string>);` -- APPEND the timestamped block to `recovery.txt` (written BEFORE conversion).
  - `procedure BackupFiles(const APaths: TArray<string>; out AMappings: TArray<string>);` -- copy each to its NextBackupName, return `orig -> backup` strings.
  - `procedure PrependConvertComment(const APasPath, ATimestamp, ARulesFile: string; const AMappings: TArray<string>);` -- prepend the `// drag-lint convert-apply ...` block atop the .pas.
  - The applier's `--apply` sequence: freshness guard -> compute edits -> BackupFiles -> WriteRecoveryRecord (FIRST) -> apply edits (write) -> PrependConvertComment.

- [ ] **Step 1: Write the test (--apply writes + backups + recovery.txt + comment)**

Extend `run_convert_apply.ps1` with an `--apply` case (copy the fixture to a fresh dir first so the dry-run cases stay clean). Assert AFTER `--apply`:
- MyForm.pas + MyForm.dfm are CONVERTED on disk (retype + uses + re-emit present).
- `MyForm.pas.BCK1` and `MyForm.dfm.BCK1` exist and equal the ORIGINAL bytes.
- Re-running `--apply` again produces `.BCK2` (next-free n; .BCK1 untouched).
- `recovery.txt` exists in the folder with a timestamped block naming both mappings + the rules file.
- MyForm.pas starts with the `// drag-lint convert-apply ...` comment block.
- `--no-backup` variant: converts but writes NO .BCK / NO recovery.txt (assert absence).
Run -> FAIL (no --apply path / no backup unit). Capture RED.

Note: the test can't use a real fixed timestamp (Date/time). Assert the STRUCTURE (a `[.*] convert-apply` line + the two mapping lines), not an exact timestamp.

- [ ] **Step 2: Implement the backup unit**

Create `src/report/DRagLint.Convert.Backup.pas` with the four routines above. `NextBackupName`: loop n=1.. testing `FileExists(APath+'.BCK'+IntToStr(n))`, return the first free. `WriteRecoveryRecord`: append (create if absent) `recovery.txt` in the folder; block format per the spec (`[<ts>] convert-apply --rules <f>` then `  <orig> -> <backup>` lines). `BackupFiles`: `TFile.Copy` each to its NextBackupName. `PrependConvertComment`: read the .pas, prepend the comment block + CRLF, write back (ASCII/CRLF preserved). Full DocInsight. Add DCCReference + uses.

- [ ] **Step 3: Implement the freshness guard**

In `BuildApplyPlan` (or the verb before it): for the F and T types, get the indexed source file + its indexed mtime/sha, compare vs the file on disk. If stale or the type is unindexed, set a `Report.Warnings` entry; return a flag the verb uses to WARN (dry-run) or REFUSE (--apply, exit 1). Reuse whatever staleness check the codebase already has (grep for `mtime`/`sha`/`stale`/freshness in the store/index code; if none, compare `TFile.GetLastWriteTime` vs the stored file mtime).

- [ ] **Step 4: Implement the --apply path in DoConvertApply**

When `--apply`: run the freshness guard (refuse on stale). Compute the edit set (Tasks 2-3). Collect the distinct touched file paths. If not `--no-backup`: `BackupFiles` -> `WriteRecoveryRecord` (BEFORE writing edits). Apply the edits (write) via `TTextEditApplier.Apply(edits, AWriteBackups:=False)` -- pass False because OUR backup layer already backed up; do NOT double-backup with the applier's own .bak. Then `PrependConvertComment` on each converted .pas. Print the report. Exit 0.

- [ ] **Step 5: Build + run (GREEN)**

Build. Run the test. Expected: PASS -- --apply converts + backs up (.BCK<n>) + recovery.txt-first + in-file comment; --no-backup skips backups; re-run increments n. Byte-check all written files ASCII/CRLF.

- [ ] **Step 6: Commit**

```bash
git add src/report/DRagLint.Convert.Backup.pas src/report/DRagLint.Convert.Apply.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/autotest/run_convert_apply.ps1
git commit -m "feat(convert-apply): --apply path + .BCK<n>/recovery.txt/in-file-comment safety + freshness guard

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Surface #5 (runtime creators + generic creator + TODO markers)

**Files:**
- Modify: `src/report/DRagLint.Convert.Apply.pas` (surface #5)
- Extend: `tests/autotest/run_convert_apply.ps1`

**Interfaces:**
- Consumes: the ref index construction sites (`TOldEdit.Create` reads / `call_edges` receiver-typed to the instance); the store's constructor lookup for the ToType.
- Produces: a `TTextEdit` rewriting the type name at each `.Create` site + a TODO marker comment; `Report.CreatorSites`/`Report.Todos` entries.

- [ ] **Step 1: Write the test (runtime creator rewrite + TODO)**

Extend the fixture: add a method body that constructs the instance:
```pascal
  Edit1 := TOldEdit.Create(Self);
```
Add assertions (dry-run): the diff shows `TOldEdit.Create(Self)` -> `TNewEdit.Create(Self)` (type rewritten) AND a `{ TODO: drag-lint convert -- verify creator for TNewEdit (was TOldEdit.Create) ... }` marker at that site. `Report.Todos` lists it. Run -> FAIL (surface #5 not built).

- [ ] **Step 2: Implement surface #5**

Find construction sites: query the index for refs to `<FromType>.Create` (kind='read'/'call') OR, more precisely, the `call_edges` whose receiver types to the converted instance, within this unit. For each site in the .pas: emit a `TTextEdit` replacing the `<FromType>` token in `<FromType>.Create` with `<ToType>`. Look up `<ToType>`'s available public constructors via the store (constructor-kind children + inherited); pick a generic one (prefer `Create(AOwner: TComponent)`); if the existing call's args don't match the generic shape, still rewrite the type but emit the TODO marker (a `{ TODO: ... }` comment `TTextEdit` inserted at the site). Add `Report.CreatorSites` + `Report.Todos` entries. (For 2b, ALWAYS emit the TODO marker at a rewritten creator site -- T's ctor/init may differ; the marker is the safety net. Do not attempt to auto-fix the args.)

- [ ] **Step 3: Build + run (GREEN)**

Build. Run the test. Expected: PASS -- creator type rewritten + TODO marker + report entry. Byte-check.

- [ ] **Step 4: Commit**

```bash
git add src/report/DRagLint.Convert.Apply.pas tests/autotest/run_convert_apply.ps1
git commit -m "feat(convert-apply): surface #5 -- runtime-creator retype + generic-creator TODO markers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Surface #4 (property/event access rewrite via ref-gap G)

**Files:**
- Modify: `src/report/DRagLint.Convert.Apply.pas` (surface #4)
- Extend: `tests/autotest/run_convert_apply.ps1`

**Interfaces:**
- Consumes: ref-gap G's `member-access` refs (kind='member-access', NameText=member) + the companion base-identifier `read` refs (receiver name), within the unit.
- Produces: a `TTextEdit` rewriting each renamed member token (`.Caption` -> `.Text`) at instance-scoped access sites; `Report.AccessSites` entries.

**DEPENDENCY:** requires sub-project A (ref-gap G) shipped. VERIFY first: `drag-lint index <fixture> --db db` then a `member-access` query returns the fixture's access sites. If G is NOT present, implement #4 in REPORT-ONLY mode (list the sites from the base-identifier reads, emit NO rewrite edits) and mark the test's rewrite assertions pending -- but in our build order G ships first, so implement the full rewrite.

- [ ] **Step 1: Confirm ref-gap G is available + finalize the query**

Run: `grep -rn "member-access" src/parser/DRagLint.Parser.Delphi13.pas` (confirm G shipped).
Index the fixture; run the `member-access` query (the verb ref-gap G's test used) and inspect the JSON rows for `Edit1.Caption`. Confirm the row shape (NameText=member, position, the companion base read). Finalize the exact join: for each `#link ToMember <- FromMember` where ToMember != FromMember, find `member-access` refs with NameText=FromMember whose companion base-identifier read (same site/line) names a converted instance.

- [ ] **Step 2: Write the test (property-access rewrite)**

Extend the fixture method body:
```pascal
  Edit1.Caption := 'x';
  y := Edit1.Caption;
  Other.Caption := 'z';   // NOT a converted instance -- must NOT be rewritten
```
Assert (dry-run): `Edit1.Caption` (both sites) -> `Edit1.Text`; `Other.Caption` UNCHANGED (Other is not a converted instance). `Report.AccessSites` lists the Edit1 rewrites. Run -> FAIL (surface #4 not built). Capture RED.

- [ ] **Step 3: Implement surface #4**

For each renaming `#link ToMember <- FromMember` (ToMember != FromMember): query `member-access` refs in the unit with NameText=FromMember. For each, resolve the receiver name from the companion base-identifier `read` ref at the same site; if the receiver name is one of the converted instance names (from `FindConvertInstances`), emit a `TTextEdit` replacing the member token bytes FromMember -> ToMember. Add `Report.AccessSites` entries. Events (On* handler-property `#link`s) are the same shape. Do NOT rewrite accesses on non-converted receivers (the `Other.Caption` negative).

- [ ] **Step 4: Build + run (GREEN)**

Build. Run the test. Expected: PASS -- Edit1.Caption -> Edit1.Text at both sites, Other.Caption untouched. Now the FULL conversion (all 5 surfaces) is in the dry-run + --apply. Byte-check.

- [ ] **Step 5: Commit**

```bash
git add src/report/DRagLint.Convert.Apply.pas tests/autotest/run_convert_apply.ps1
git commit -m "feat(convert-apply): surface #4 -- instance-scoped property/event access rewrite via ref-gap G

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: End-to-end conversion test + docs + ledger

**Files:**
- Extend: `tests/autotest/run_convert_apply.ps1` (a full 5-surface --apply + a compiles-conceptually check)
- Modify: `docs/CONVERSION-RULES.md`, `README.md`/`docs/AI-USAGE.md`, `CHANGELOG.md`, `.superpowers/sdd/progress.md`

**Interfaces:**
- Consumes: everything built.
- Produces: a full end-to-end assertion + the published docs.

- [ ] **Step 1: Add the full end-to-end --apply case**

One `--apply` run of a component with a renamed property, a nested moved-depth prop, an event, and a runtime creator. Assert ALL surfaces landed in the written files: .pas decl retyped, uses added, .dfm re-emitted (renamed + moved-depth), .pas access rewritten, creator retyped + TODO marker, plus the .BCK<n>/recovery.txt/comment. This is the real-life-shaped smoke.

- [ ] **Step 2: Run the full suite (no regression)**

Run: `pwsh -File tests/autotest/run_convert_apply.ps1` (all cases).
Run: `pwsh -File tests/autotest/run_dfm_reemit.ps1` (2a-i, must stay green).
Run: `pwsh -File tests/autotest/run_convert_rules.ps1` + `run_member_access_refs.ps1` (deps, green).

- [ ] **Step 3: Docs + ledger**

`docs/CONVERSION-RULES.md`: add the apply workflow (scaffold -> validate -> convert-apply dry-run -> --apply, the backup/recovery scheme, the TODO markers, the freshness guard). `README.md`/`docs/AI-USAGE.md`: add `convert-apply` to the verb inventory. `CHANGELOG.md`: the convert-apply feature. `.superpowers/sdd/progress.md`: the convert-apply section (per-surface, the reused engines, the backup protocol, per-task commits).

- [ ] **Step 4: Commit**

```bash
git add tests/autotest/run_convert_apply.ps1 docs/ README.md CHANGELOG.md .superpowers/sdd/progress.md
git commit -m "test+docs(convert-apply): end-to-end 5-surface conversion + workflow docs + ledger

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:** all 5 surfaces -> Tasks 2 (#1,#2), 3 (#3), 5 (#5), 6 (#4); instance location + per-unit input -> Task 2; dry-run default + --apply + --no-backup -> Tasks 2/4; the `.BCK<n>`/recovery.txt-first/in-file-comment safety -> Task 4 (exactly the user's scheme); freshness guard -> Task 4; re-validate rules -> Task 2 Step 4; the report -> accumulated across tasks; the A-dependency for #4 -> Task 6 (with report-only fallback noted); reuse of find-unit/ReemitComponent/edit-applier/proptree -> every task. Covered.

**2. Placeholder scan:** no TBD. The one genuine external dependency (ref-gap G for #4) is explicit with a degradable fallback. The `--unit` arg (new vs reuse GhostUnit/InFile) is flagged as a pick-one-be-consistent choice, not left ambiguous mid-code. The freshness-check mechanism says "reuse the codebase's if present, else mtime compare" -- concrete either way.

**3. Type consistency:** `TConvertInstance`, `TApplyReport`, `TApplyResult`, `BuildApplyPlan`, `FindConvertInstances` names are consistent Task 1 -> 6. `TTextEdit`/`TTextEditApplier.Apply`/`RenderDryRun` and `TFindUnitRefactoring.Build` are the real shipped signatures (confirmed). The backup routines (`NextBackupName`/`WriteRecoveryRecord`/`BackupFiles`/`PrependConvertComment`) are consistent Task 4. `member-access` matches ref-gap G's kind (Task 6).

**4. Safety ordering:** Task 4 makes explicit that recovery.txt is written BEFORE the conversion writes (crash-safe), and that OUR backup layer replaces the applier's built-in .bak (Apply called with writeBackups:=False) to avoid double-backup -- a real integration detail that would otherwise cause stray .bak files.
