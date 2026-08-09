<#
  run_index_project_closure.ps1 -- `index --project` indexes the COMPILE
  CLOSURE, not the project's search-path FOLDERS.

  THE BUG
  ---------------------------------------------------------------------------
  DoIndex's `--project` arm resolved TProjectResolver.ResolveProjectOnly (the
  project's search-path folders) and walked them recursively. A folder walk has
  no notion of membership: every loose .pas sitting beside the .dproj -- a unit
  removed from the project years ago, a scratch copy, a vendored tree that only
  one config compiles -- lands in the project's index and is then reported on
  by the linter, counted by coverage, and offered to the doc engine as project
  API. The manifest's smClosure sections (CLI.pas:1423) already did the right
  thing; the two paths disagreed about what "a project" is.

  THE FIX
  ---------------------------------------------------------------------------
  The `--project` arm now mirrors the smClosure arm: TClosureResolver over
  TProjectResolver.ResolveLibraryPaths, the SAME define profile the indexer
  gets (so uses-discovery and symbol extraction agree about which {$IFDEF}
  branch is live), and CR.Files as the index set.

  WHY App.dpr IS STILL EXPECTED
  ---------------------------------------------------------------------------
  TClosureResolver seeds FROM the .dpr and never returns it (see Resolve: the
  project file is read, not enqueued). The .dpr is the root of the closure by
  definition -- it is what the compiler is handed -- so the arm adds it back
  explicitly. Dropping it would lose the program block, its uses list, and
  every initialization-order fact derived from them.

  THE FAIL-LOUDLY GUARD
  ---------------------------------------------------------------------------
  A .dproj that resolves to ZERO closure files exits 2 instead of falling back
  to a folder walk or writing an empty index. An empty index is the most
  dangerous artefact this tool can produce: lint, coverage and doc all report a
  clean bill of health over it. Assertion group 2 pins that.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs `python` on PATH.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_projclosure'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

$proj = Join-Path $scratch 'proj'
New-Item -ItemType Directory -Path $proj | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# --- fixture: App.dpr -> Member1 -> Member2 ; Loose.pas referenced by NOTHING -
Write-Ascii (Join-Path $proj 'App.dpr') @'
program App;

uses
  Member1 in 'Member1.pas',
  Member2 in 'Member2.pas',
  FormUnit in 'FormUnit.pas';

begin
  Member1.RunIt;
end.
'@

# A FORM: FormUnit.pas is in the closure, FormUnit.dfm is reachable only as its
# sibling ({$R *.dfm}, never `uses`). Both index arms must pick the .dfm up.
Write-Ascii (Join-Path $proj 'FormUnit.pas') @'
unit FormUnit;

interface

type
  TfrmDemo = class(TObject)
    procedure btnGoClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TfrmDemo.btnGoClick(Sender: TObject);
begin
end;

end.
'@

Write-Ascii (Join-Path $proj 'FormUnit.dfm') @'
object frmDemo: TfrmDemo
  Left = 0
  Top = 0
  Caption = 'project-closure fixture'
  object btnGo: TButton
    Left = 8
    Top = 8
    Caption = 'Go'
    OnClick = btnGoClick
  end
end
'@

Write-Ascii (Join-Path $proj 'Member1.pas') @'
unit Member1;

interface

uses
  Member2;

procedure RunIt;

implementation

procedure RunIt;
begin
  Member2.HelpMe;
end;

end.
'@

Write-Ascii (Join-Path $proj 'Member2.pas') @'
unit Member2;

interface

procedure HelpMe;

implementation

procedure HelpMe;
begin
end;

end.
'@

Write-Ascii (Join-Path $proj 'Loose.pas') @'
unit Loose;

interface

procedure NobodyCallsThis;

implementation

procedure NobodyCallsThis;
begin
end;

end.
'@

Write-Ascii (Join-Path $proj 'App.dproj') @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>App.dpr</MainSource>
        <ProjectVersion>20.3</ProjectVersion>
        <Platform>Win64</Platform>
        <Config Condition="'$(Config)'==''">Debug</Config>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="App.dpr">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
        <DCCReference Include="Member1.pas"/>
        <DCCReference Include="Member2.pas"/>
        <DCCReference Include="FormUnit.pas"/>
    </ItemGroup>
</Project>
'@

# --- fixture 2: a .dproj with NO DCCReference and NO sibling .dpr ------------
# Stray.pas sits beside it so that a silent fall-back to the folder walk would
# produce a NON-empty DB -- which is exactly what assertion 2b catches.
$empty = Join-Path $scratch 'empty'
New-Item -ItemType Directory -Path $empty | Out-Null

Write-Ascii (Join-Path $empty 'Stray.pas') @'
unit Stray;

interface

procedure NotAMember;

implementation

procedure NotAMember;
begin
end;

end.
'@

Write-Ascii (Join-Path $empty 'Empty.dproj') @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectVersion>20.3</ProjectVersion>
        <Platform>Win64</Platform>
    </PropertyGroup>
    <ItemGroup>
    </ItemGroup>
</Project>
'@

$py = Join-Path $scratch 'files.py'
@'
import sqlite3, sys, json, os
db = sys.argv[1]
if not os.path.exists(db):
    print(json.dumps([]))
    sys.exit(0)
c = sqlite3.connect(db)
try:
    rows = [r[0] for r in c.execute("SELECT path FROM files ORDER BY path")]
except sqlite3.Error:
    rows = []
c.close()
print(json.dumps(rows))
'@ | Set-Content $py -Encoding ascii

Push-Location C:\TEMP
try {
  # ==========================================================================
  # 1. the closure is the index scope
  # ==========================================================================
  $dproj = Join-Path $proj 'App.dproj'
  $db    = Join-Path $scratch 'closure.sqlite'

  $out = & $exePath index --project $dproj --db $db --platform Win64 --quiet 2>&1
  $rc  = $LASTEXITCODE
  Check 'index --project exits 0' ($rc -eq 0) "exit=$rc; $(($out | Select-Object -Last 2) -join ' | ')"

  $indexed = @((& python $py $db) -join "`n" | ConvertFrom-Json)
  Write-Host ("  indexed {0} file(s): {1}" -f $indexed.Count,
    (($indexed | ForEach-Object { Split-Path $_ -Leaf }) -join ', '))

  function Has([string]$Leaf) { return @($indexed | Where-Object { $_ -like "*\$Leaf" }).Count -ge 1 }

  Check 'Member1.pas is indexed'  (Has 'Member1.pas')  'DCCReference member'
  Check 'Member2.pas is indexed'  (Has 'Member2.pas')  'reached transitively via uses'
  Check 'FormUnit.pas is indexed' (Has 'FormUnit.pas') 'the form unit'
  Check 'FormUnit.dfm is indexed' (Has 'FormUnit.dfm') 'sibling of a closure unit -- arrives via {$R *.dfm}, never via uses'
  Check 'App.dpr is indexed'      (Has 'App.dpr')      'the closure root itself'
  Check 'Loose.pas is NOT indexed' (-not (Has 'Loose.pas')) `
    'referenced by nothing -- a folder walk drags it in, the closure must not'

  $stray = @($indexed | Where-Object { $_ -notlike "$proj*" })
  Check 'no indexed file lies outside the project tree' ($stray.Count -eq 0) `
    ("count=" + $stray.Count + "; e.g. " + (($stray | Select-Object -First 3) -join ' | '))

  # ==========================================================================
  # 2. an unresolvable project fails LOUDLY -- it never falls back to a walk
  # ==========================================================================
  $edproj = Join-Path $empty 'Empty.dproj'
  $edb    = Join-Path $scratch 'guard.sqlite'

  $gout = & $exePath index --project $edproj --db $edb --platform Win64 --quiet 2>&1
  $grc  = $LASTEXITCODE
  Check 'a .dproj with an empty closure exits 2' ($grc -eq 2) `
    "exit=$grc; $(($gout | Select-Object -Last 2) -join ' | ')"
  # Must be an ERROR line naming the project -- the arm also echoes a plain
  # "Project: <path>" banner, which would satisfy a bare name match.
  Check 'an ERROR line names the project file' `
    (@($gout | Where-Object { $t = $_.ToString(); ($t -like '*ERROR*') -and ($t -like '*Empty.dproj*') }).Count -ge 1) `
    "output: $(($gout | Select-Object -Last 3) -join ' | ')"

  $gfiles = @((& python $py $edb) -join "`n" | ConvertFrom-Json)
  Check 'the guarded run wrote ZERO files rows' ($gfiles.Count -eq 0) `
    ("count=" + $gfiles.Count + "; e.g. " + (($gfiles | Select-Object -First 3) -join ' | '))

  # ==========================================================================
  # 3. THE OTHER ARM. A manifest smClosure section over the SAME fixture must
  #    produce the SAME scope. Both arms call ExpandProjectScope; this group is
  #    what stops them drifting apart again, which is the failure Task 1 exists
  #    to remove. Before this change the manifest arm indexed .pas/.inc only
  #    (real evidence: Loader.sqlite, 84 files, dfm 0, dpr 0).
  # ==========================================================================
  $mdb = 'section.sqlite'
  $cfg = Join-Path $scratch 'manifest.drag-lint.json'
  @"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 0 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "ProjClosure", "db": "$mdb", "include": ["proj\\App.dproj"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii

  $mout = & $exePath index --all --config $cfg --only ProjClosure 2>&1
  $mrc  = $LASTEXITCODE
  Check 'index --all (smClosure section) exits 0' ($mrc -eq 0) `
    "exit=$mrc; $(($mout | Select-Object -Last 2) -join ' | ')"

  $mfiles = @((& python $py (Join-Path $scratch "out\$mdb")) -join "`n" | ConvertFrom-Json)
  Write-Host ("  section indexed {0} file(s): {1}" -f $mfiles.Count,
    (($mfiles | ForEach-Object { Split-Path $_ -Leaf }) -join ', '))
  function HasM([string]$Leaf) { return @($mfiles | Where-Object { $_ -like "*\$Leaf" }).Count -ge 1 }

  Check 'section: FormUnit.dfm is indexed'  (HasM 'FormUnit.dfm') 'the manifest arm had dfm 0 before this change'
  Check 'section: App.dpr is indexed'       (HasM 'App.dpr')      'the manifest arm had dpr 0 before this change'
  Check 'section: Loose.pas is NOT indexed' (-not (HasM 'Loose.pas'))
  Check 'both arms resolve the SAME scope' `
    ((($mfiles | ForEach-Object { $_.ToLower() } | Sort-Object) -join ';') -eq
     (($indexed | ForEach-Object { $_.ToLower() } | Sort-Object) -join ';')) `
    "section=$($mfiles.Count) vs --project=$($indexed.Count)"

  # ==========================================================================
  # 4. THE FAILURE RULE, unified -- but with `index --all` semantics.
  #    A dead section must fail the RUN without starving the other sections:
  #    `index --project` is one project so it exits 2, `index --all` is many, and
  #    one mistyped path must never stop every other index from refreshing.
  #    Dead is listed FIRST on purpose -- if a future "fail fast" refactor aborts
  #    the run at the first bad section, assertion (a) is what catches it.
  #    --jobs 1 pins the sequential path so the assertions do not depend on how
  #    child-process output interleaves (the parallel path is not covered here).
  # ==========================================================================
  $cfg2 = Join-Path $scratch 'manifest2.drag-lint.json'
  @"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out2",
    "sections": [
      { "name": "MissingSection", "db": "missing.sqlite", "include": ["proj\\NoSuchProject.dproj"] },
      { "name": "DeadSection",    "db": "dead.sqlite",    "include": ["empty\\Empty.dproj"] },
      { "name": "HealthySection", "db": "healthy.sqlite", "include": ["proj\\App.dproj"] }
    ]
  }
}
"@ | Set-Content $cfg2 -Encoding ascii

  $2out = @((& $exePath index --all --config $cfg2 --jobs 1 2>&1) | ForEach-Object { $_.ToString() })
  $2rc  = $LASTEXITCODE

  # (b) the run as a whole must not report success
  Check 'a dead section makes the RUN exit non-zero' ($2rc -ne 0) "exit=$2rc"

  # (c) the failing section is named, and so is its project file
  $named = @($2out | Where-Object {
    ($_ -like '*ERROR*') -and ($_ -like '*DeadSection*') -and ($_ -like '*Empty.dproj*') })
  Check 'the failing section and its project file are named in the output' ($named.Count -ge 1) `
    ("matched=" + $named.Count + "; " + (($named | Select-Object -First 1) -join ''))
  $distinct = @($2out | Where-Object { ($_ -like '*DeadSection*') -and ($_ -like '*FAILED*') })
  Check 'the dead section reports FAILED, not a small file count' ($distinct.Count -ge 1) `
    (($distinct | Select-Object -First 1) -join '')

  # A project file that is not THERE used to be a silent "(skip, ...)" -- the same
  # silent-success bug wearing a different hat. It must fail too, and say which of
  # the two failures it was, because they want different fixes.
  $missing = @($2out | Where-Object {
    ($_ -like '*ERROR*') -and ($_ -like '*MissingSection*') -and ($_ -like '*NOT FOUND*') })
  Check 'a MISSING project file fails its section and says NOT FOUND' ($missing.Count -ge 1) `
    (($missing | Select-Object -First 1) -join '')

  # (a) THE ONE THAT MATTERS: the healthy section still built, after the dead one
  $hfiles = @((& python $py (Join-Path $scratch 'out2\healthy.sqlite')) -join "`n" | ConvertFrom-Json)
  Write-Host ("  healthy section indexed {0} file(s)" -f $hfiles.Count)
  Check 'the HEALTHY section still indexed its files' ($hfiles.Count -eq $mfiles.Count) `
    "healthy=$($hfiles.Count) vs expected=$($mfiles.Count) -- one bad section must not starve the others"

  $dfiles = @((& python $py (Join-Path $scratch 'out2\dead.sqlite')) -join "`n" | ConvertFrom-Json)
  Check 'the dead section wrote no source rows' ($dfiles.Count -eq 0) `
    ("count=" + $dfiles.Count + "; e.g. " + (($dfiles | Select-Object -First 3) -join ' | '))
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
