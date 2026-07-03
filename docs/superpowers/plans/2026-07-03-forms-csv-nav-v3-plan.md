# forms-csv Navigation v3 (Interleaved Click Path) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The forms-csv Navigation column shows the full click path with intermediate form names interleaved between button captions: `frmMAIN -> 'Job List' -> frmJobList -> 'Open Folder' -> frmBlueprint4 -> ... -> Z14slctFrm`.

**Architecture:** `NavPath` in `DRagLint.FormsMap.pas` already BFSes the edge graph; it accumulates a pre-rendered string. Change it to accumulate structured hops (`THop = caption + landing form name`) and render text in ONE new function `RenderPath` (the only place hops become text -- future format changes touch only it). Bump the CSV provenance const `FORMS_CSV_ALGORITHM` `'2' -> '3'`.

**Tech Stack:** Delphi 13 (Studio 37), MSBuild via `build\build_draglint_win32|64.bat`, PowerShell smoke test `tests\autotest\run_formsmap.ps1`.

**Spec:** `docs/superpowers/specs/2026-07-03-forms-csv-nav-v3-design.md`

## Global Constraints

- `.pas` files are strict 7-bit ASCII, CRLF line endings. Never introduce Unicode or bare LF.
- Build ONLY via the project `.bat` scripts run from PowerShell `Start-Process -Wait` with output redirected to a log (never `cmd.exe /c` from the Bash tool; never the MCP build tool). Healthy build < 30 s; a long hang = locked exe (kill running `drag-lint.exe` first).
- The `Called From` column's output must remain byte-identical -- do not touch `CalledFrom` or `BuildEdges`.
- DocInsight `///` comments required on any public declaration; `THop`/`RenderPath` are implementation-private (comment kept anyway because the render-swap invariant is non-obvious).
- Delphi 13 supports dynamic-array concatenation with `+` (used for per-branch hop copies; each `+` allocates a fresh array, so BFS branches cannot alias).

---

### Task 1: NavPath v3 -- interleaved rendering (TDD)

**Files:**
- Modify: `tests/autotest/run_formsmap.ps1` (nav-path checks, ~lines 38-52)
- Modify: `src/forms/DRagLint.FormsMap.pas` (const line 70; `NavPath` lines 765-804; new `THop`/`RenderPath` immediately above `NavPath`)

**Interfaces:**
- Consumes: `TFormEdge` record (`FromClass`, `ToClass`, `Caption`: string) at FormsMap.pas:41; `TFormNode.FormName`; `AClassToNode: TDictionary<string, TFormNode>`.
- Produces: `NavPath(...)` -- signature UNCHANGED (`function NavPath(AEdges: TList<TFormEdge>; AClassToNode: TDictionary<string, TFormNode>; const ARootClass, AToClass: string): string`), new output format. Implementation-private `THop` record and `function RenderPath(const ARootName: string; const AHops: TArray<THop>): string` for later format changes.

- [ ] **Step 1: Update the smoke-test expectations (failing first)**

In `tests/autotest/run_formsmap.ps1` replace these five checks (current text shown first, replacement second):

```powershell
# OLD:
Check 'frmList nav via Lists'         ($csv -match "uDemoList,frmList,\d+,frmMain -> 'Lists',")
Check 'frmEdit nav via Lists>Edit'    ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> 'Edit Item',")
Check 'frmChild nav via named ctor'   ($csv -match "uDemoChild,frmChild,\d+,frmMain -> 'Lists' -> 'Open Child',")
Check 'action-bound caption (Reports)' ($csv -match "uDemoReports,frmReports,\d+,frmMain -> 'Reports',")
Check 'keep-the-gap via routine'       ($csv -match "uDemoGap,frmGap,\d+,frmMain -> \(via ")

# NEW (v3: landing form name follows every caption; path ends with the row's own form):
Check 'frmList nav via Lists'         ($csv -match "uDemoList,frmList,\d+,frmMain -> 'Lists' -> frmList,")
Check 'frmEdit nav via Lists>Edit'    ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> frmList -> 'Edit Item' -> frmEdit,")
Check 'frmChild nav via named ctor'   ($csv -match "uDemoChild,frmChild,\d+,frmMain -> 'Lists' -> frmList -> 'Open Child' -> frmChild,")
Check 'action-bound caption (Reports)' ($csv -match "uDemoReports,frmReports,\d+,frmMain -> 'Reports' -> frmReports,")
Check 'keep-the-gap via routine'       ($csv -match "uDemoGap,frmGap,\d+,frmMain -> \(via [^)]+\) -> frmGap,")
```

Also replace the Task 7b regression check near line 49:

```powershell
# OLD:
Check 'root regression: frmEdit still reachable'  ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> 'Edit Item',")
# NEW:
Check 'root regression: frmEdit still reachable'  ($csv -match "uDemoEdit,frmEdit,\d+,frmMain -> 'Lists' -> frmList -> 'Edit Item' -> frmEdit,")
```

And ADD one new check right after the five nav checks:

```powershell
# v3: intermediate landing forms are interleaved between captions
Check 'nav interleaves landing forms'  ($csv -match "-> 'Lists' -> frmList -> 'Edit Item' ->")
```

Leave untouched: `frmMain is root (blank nav)`, `unreachable form`, `row count is 7 forms + 2 header lines`, `called-from for frmEdit`, backup/duplicate checks.

- [ ] **Step 2: Run the smoke test -- expect the updated checks to FAIL**

```powershell
pwsh -File c:\Projects\Delphi-RAG-lint\tests\autotest\run_formsmap.ps1
```

Expected: exit 1; FAIL on `frmList nav via Lists`, `frmEdit nav via Lists>Edit`, `frmChild nav via named ctor`, `action-bound caption (Reports)`, `keep-the-gap via routine`, `nav interleaves landing forms`, `root regression: frmEdit still reachable`. All other checks PASS.

- [ ] **Step 3: Implement THop + RenderPath + NavPath rewrite, bump algorithm const**

In `src/forms/DRagLint.FormsMap.pas`:

(a) Line 70 -- bump the provenance const:

```pascal
  FORMS_CSV_ALGORITHM = '3'; // bump when BuildEdges / NavPath algorithm changes
```

(b) Replace the whole `NavPath` function (currently lines 765-804) with:

```pascal
type
  /// <summary>One navigation hop: the button caption (or synthetic '(via X)'
  /// marker) and the FormName of the form the click lands on.</summary>
  THop = record
    Caption    : string;
    LandingName: string;
  end;

/// <summary>Renders the root form name plus hops into the Navigation cell text.
/// v3 (interleaved): every caption is followed by the landing form's name, e.g.
/// frmMAIN -> 'Job List' -> frmJobList -> ... -> Z14slctFrm. Quoted captions keep
/// quotes; synthetic '(...)' captions render unquoted. This is the SOLE place hop
/// data becomes text -- change future path formats here only.</summary>
function RenderPath(const ARootName: string; const AHops: TArray<THop>): string;
var
  H: THop;
begin
  Result:= ARootName;
  for H in AHops do
  begin
    if Copy(H.Caption, 1, 1) = '(' then Result:= Result + ' -> ' + H.Caption
    else Result:= Result + ' -> ''' + H.Caption + '''';
    Result:= Result + ' -> ' + H.LandingName;
  end; // for
end; // function

function NavPath(AEdges: TList<TFormEdge>; AClassToNode: TDictionary<string, TFormNode>; const ARootClass, AToClass: string): string;
type
  TStep = record Cls: string; Hops: TArray<THop>; end;
var
  Queue   : TQueue<TStep>               ;
  Visited : TDictionary<string, Boolean>;
  Cur     : TStep                       ;
  Nxt     : TStep                       ;
  E       : TFormEdge                   ;
  RootNode: TFormNode                   ;
  RootName: string                      ;
  ToNode  : TFormNode                   ;
  Hop     : THop                        ;
begin
  Result:= '';
  if SameText(ARootClass, AToClass) then Exit;
  Queue:= TQueue<TStep>.Create;
  Visited:= TDictionary<string, Boolean>.Create;
  try
    if AClassToNode.TryGetValue(ARootClass, RootNode) then RootName:= RootNode.FormName
    else RootName:= ARootClass;
    Cur.Cls := ARootClass;
    Cur.Hops:= nil;
    Queue.Enqueue(Cur);
    Visited.Add(ARootClass, True);
    while Queue.Count > 0 do
    begin
      Cur:= Queue.Dequeue;
      for E in AEdges do
        if SameText(E.FromClass, Cur.Cls) and not Visited.ContainsKey(E.ToClass) then
        begin
          Hop.Caption:= E.Caption;
          if AClassToNode.TryGetValue(E.ToClass, ToNode) then Hop.LandingName:= ToNode.FormName
          else Hop.LandingName:= E.ToClass; // defensive: edges target inventory nodes today
          Nxt.Cls := E.ToClass;
          Nxt.Hops:= Cur.Hops + [Hop]; // fresh array per branch -- no aliasing
          if SameText(E.ToClass, AToClass) then Exit(RenderPath(RootName, Nxt.Hops));
          Visited.Add(E.ToClass, True);
          Queue.Enqueue(Nxt);
        end;
    end; // while
  finally
    Queue.Free;
    Visited.Free;
  end; // try
end; // function
```

Note: `NavPath` is implementation-only (not in the unit's interface section); `THop`/`RenderPath` go in the implementation section immediately above it. Keep strict ASCII + CRLF.

- [ ] **Step 4: Build Win32 (the smoke test runs `src\cli\Win32\Debug\drag-lint.exe`)**

```powershell
$log = "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\build-navv3-32.log"
$p = Start-Process cmd.exe -ArgumentList "/c","`"c:\Projects\Delphi-RAG-lint\build\build_draglint_win32.bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru
"exit: $($p.ExitCode)"; Get-Content $log -Tail 3
```

Expected: `exit: 0`, log tail contains `OK: staged Win32 drag-lint.exe`, no `[dcc32 Error]`/`Fatal` (hints H2077/H2164 are OK).

- [ ] **Step 5: Run the smoke test -- expect ALL checks PASS**

```powershell
pwsh -File c:\Projects\Delphi-RAG-lint\tests\autotest\run_formsmap.ps1
```

Expected: exit 0, final line `PASS`, including the new `nav interleaves landing forms` check.

- [ ] **Step 6: Commit**

```powershell
cd c:\Projects\Delphi-RAG-lint
git add src/forms/DRagLint.FormsMap.pas tests/autotest/run_formsmap.ps1
git commit -m @'
feat(forms-csv): Navigation v3 -- interleave landing form names in the click path

NavPath now accumulates structured hops (THop = caption + landing FormName)
and renders via a single RenderPath function; the Navigation column reads
frmMAIN -> 'Job List' -> frmJobList -> ... -> Z14slctFrm so a tester knows
which form each button is pressed on. FORMS_CSV_ALGORITHM 2 -> 3.
Called From column unchanged. Spec: docs/superpowers/specs/
2026-07-03-forms-csv-nav-v3-design.md.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

### Task 2: Release v0.84.0-alpha -- version, changelog, both platforms, real-data verify

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas:6` (VERSION const)
- Modify: `CHANGELOG.md` (new section under `## Unreleased`)

**Interfaces:**
- Consumes: Task 1's committed NavPath v3 (no code interfaces; this task is release mechanics + end-to-end verification).
- Produces: staged `third_party/dll-win32/drag-lint.exe` + `third_party/dll-win64/drag-lint.exe` reporting `0.84.0-alpha` with v3 Navigation output.

- [ ] **Step 1: Bump VERSION**

In `src/cli/DRagLint.CLI.pas` line 6:

```pascal
  VERSION = '0.84.0-alpha';
```

- [ ] **Step 2: CHANGELOG entry**

In `CHANGELOG.md`, insert directly under the `## Unreleased` line:

```markdown
## v0.84.0-alpha -- 2026-07-03

### Changed
- **forms-csv Navigation column (algorithm v3)** -- the click path now interleaves the landing form's
  name after every button caption and ends with the target form, e.g.
  `frmMAIN -> 'Job List' -> frmJobList -> 'Open Folder' -> frmBlueprint4 -> 'Exit to Control Plan 2'
  -> frmControlPlan2 -> 'Plan' -> Z14slctFrm` -- a tester can now tell WHICH form each button is
  pressed on. Rendering is isolated in one `RenderPath` function for future format changes
  (e.g. tester sentences). Called From column unchanged. CSV provenance header reports `algorithm v3`.
```

- [ ] **Step 3: Build BOTH platforms and stage to third_party**

```powershell
$log = "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\build-navv3-64.log"
$p = Start-Process cmd.exe -ArgumentList "/c","`"c:\Projects\Delphi-RAG-lint\build\build_draglint_win64.bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru
"win64 exit: $($p.ExitCode)"; Get-Content $log -Tail 2
$log32 = "C:\TEMP\claude\c--Projects-Delphi-RAG-lint\build-navv3-32b.log"
$p = Start-Process cmd.exe -ArgumentList "/c","`"c:\Projects\Delphi-RAG-lint\build\build_draglint_win32.bat`"" -RedirectStandardOutput $log32 -RedirectStandardError "$log32.err" -NoNewWindow -Wait -PassThru
"win32 exit: $($p.ExitCode)"; Get-Content $log32 -Tail 2
```

Expected: both `exit: 0`, both logs end `OK: staged ...`.

- [ ] **Step 4: Run the full test battery**

```powershell
pwsh -File c:\Projects\Delphi-RAG-lint\tests\autotest\run_formsmap.ps1        # expect PASS (exit 0)
pwsh -File c:\Projects\Delphi-RAG-lint\tests\autotest\run_migrate_v12.ps1     # expect PASS (exit 0, 8/8)
pwsh -File c:\Projects\Delphi-RAG-lint\tests\lint-store\run_store_tests.ps1   # expect 16 pass / 0 fail (exit 0)
```

Expected: all three exit 0. (formsmap uses the freshly built Win32 exe; migrate + store use `third_party\dll-win64`.)

- [ ] **Step 5: Real-data verification (spec acceptance case)**

```powershell
$out = "$env:TEMP\navv3-orm3-forms.csv"
& "C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe" forms-csv --project "C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj" --db "C:\Projects\DB\ORM3\drag-lint.sqlite" --out $out
"exit: $LASTEXITCODE"
Get-Content $out -TotalCount 1                                   # header must say: algorithm v3
Get-Content $out | Where-Object { $_ -match 'Z14SLCT' }
```

Expected: exit 0; header line contains `# forms-csv algorithm v3`; the Z14SLCT row's Navigation cell contains `frmControlPlan2 -> 'Plan' -> Z14slctFrm` and interleaves `frmJobList` and `frmBlueprint4` (full expected cell:
`frmMAIN -> 'Job List' -> frmJobList -> 'Open Folder' -> frmBlueprint4 -> 'Exit to Control Plan 2' -> frmControlPlan2 -> 'Plan' -> Z14slctFrm` -- BFS tie-breaks could vary captions slightly; the invariant is caption/form interleaving and the trailing `-> Z14slctFrm`).

- [ ] **Step 6: Commit**

```powershell
cd c:\Projects\Delphi-RAG-lint
git add src/cli/DRagLint.CLI.pas CHANGELOG.md
git commit -m @'
chore(release): v0.84.0-alpha -- forms-csv Navigation v3 (interleaved click path)

Both platforms rebuilt + staged to third_party. Harnesses green:
formsmap smoke, migrate-v12 8/8, lint-store 16/16. Real-data check:
Micronite2027 Z14SLCT row renders the full interleaved chain.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

---

## Self-Review

- Spec coverage: format/interleave (T1 S3), trailing target (T1 S1/S3), synthetic captions (T1 S1 gap check + RenderPath '(' branch), root-blank + no-path unchanged (untouched checks), Called From byte-identical (constraint; BuildEdges/CalledFrom untouched), header v3 (T1 S3a, verified T2 S5), swappable renderer (RenderPath), tests-first (T1 S1-S2), real-data Z14SLCT (T2 S5), version+changelog+both-platform staging (T2). No gaps.
- Placeholders: none; all steps carry exact code/commands.
- Type consistency: `THop{Caption, LandingName}` used identically in RenderPath/NavPath; `NavPath` public signature unchanged; `FORMS_CSV_ALGORITHM` string const stays a string ('3').
