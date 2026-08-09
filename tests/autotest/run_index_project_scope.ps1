<#
  run_index_project_scope.ps1 -- `index --project` must index the PROJECT, not
  the machine's entire Delphi library.

  THE BUG (found 2026-08-03 on C:\Projects\DataCopy\DataCopy.dproj)
  -----------------------------------------------------------------
  `drag-lint index --project DataCopy.dproj --db DataCopy.sqlite --platform Win64`
  ran for over an hour on a project of 42 source files and was nowhere near done.

  DoIndex's --project branch resolved its scan scope through
  TProjectResolver.Resolve, which ends with an UNCONDITIONAL

      ReadLibraryPaths(List, ['Win32', 'Win64']);     // Resolver.pas:444

  -- the IDE's registry Library "Search Path" + "Browsing Path", for BOTH
  platforms, from HKCU and HKLM in both registry views. DoIndex then walked
  every folder it got back RECURSIVELY (CLI.pas:1904-1908).

  For DataCopy, which declares NO DCC_UnitSearchPath of its own, that turned a
  12-unit closure into **153 scan folders**, of which 151 came purely from the
  registry: the whole RAD Studio source tree (2,394 files), Raize (613),
  Spring4D (510), OmniThreadLibrary including its tests\ and examples\ (337),
  CatalogRepository (283). Measured mid-run: 1,000 files indexed, of which 35
  were DataCopy's -- 3.5%. Every one of those library files is ALREADY in
  library-Win32.sqlite / library-Win64.sqlite, which consumers get by passing a
  second --db.

  It also explains why `--platform Win64` appeared to be ignored: the platform
  list at Resolver.pas:444 is a hardcoded literal, so a Win64 run still pulled
  in every Win32 library folder (164 indexed paths contained \Win32\, zero
  contained \Win64\).

  THE FIX
  -------
  TProjectResolver.Resolve is NOT changed: its other two callers (check-unit at
  CLI.pas:9214 and the compile helper at CLI.pas:10013) build a COMPILER search
  path and genuinely need the library folders -- a dcc invocation must be able to
  find the RTL. Instead the resolver gained ResolveProjectOnly, which is Resolve
  minus the ReadLibraryPaths call, and DoIndex's --project branch uses that.

  WHY THIS TEST ASSERTS ON --dry-run FIRST, AND HARD-EXITS IF IT FAILS
  --------------------------------------------------------------------
  With the bug present, the real index walks the entire machine library and takes
  HOURS. A test that simply ran the index would hang the battery instead of
  failing it. So the cheap, decisive assertion -- the resolved folder list --
  runs first, and a failure exits IMMEDIATELY without ever starting an index.
  Only once the scope is proven small does the expensive assertion run.

  FIXTURE (built fresh in a temp workdir)
    App.dproj / App.dpr     -- program App; uses UsedUnit, Main;
    UsedUnit.pas            -- uses Helper
    Helper.pas
    Main.pas + Main.dfm     -- a FORM: Main.pas is in the closure, Main.dfm is
                               reachable only as its sibling. The .dfm is the
                               whole point of the pair -- a lone .dfm with no
                               .pas could never exercise the sibling rule.
    Orphan.pas              -- in the project folder, referenced by nothing

  SCOPE SEMANTICS -- THE COMPILE CLOSURE, plus .dfm siblings and the project file
  ------------------------------------------------------------------------------
  This section previously described a project-folder WALK and asserted Orphan.pas
  was indexed. That was wrong, and the reasoning that produced it is recorded here
  rather than deleted, because the second attempt looked so much like a fix.

  Dropping the registry library folders fixed the SCALE of the bug above but not
  its KIND. A folder walk has no notion of membership: every loose .pas beside the
  .dproj -- a unit retired from the project, a scratch copy, a vendored tree that
  only one config compiles -- still landed in the project's index and was then
  linted, counted by coverage, and offered to the doc engine as project API. The
  manifest's smClosure sections had always resolved the real thing, so the two
  paths disagreed about what "a project" even is.

  `index --project` now resolves the COMPILE CLOSURE (TClosureResolver), exactly
  as the manifest smClosure sections do, and both go through the same
  ExpandProjectScope helper so they cannot drift apart again. Scope is:

    * the closure     -- project members + everything they reach via `uses`/{$I}
                         that resolves project-local (library units stay in
                         library-Win32/Win64.sqlite, reached with a second --db)
    * sibling .dfm    -- a form's .dfm arrives via {$R *.dfm}, never via `uses`,
                         so the closure alone would omit it. A pure closure DB
                         proves the point: Loader.sqlite is 84 files, dfm 0.
                         Without this the wizard structure view, DFM event wiring
                         and forms-csv see ZERO forms in a VCL app and report a
                         clean result -- silence that reads as success.
    * the project file - the .dpr is the closure's ROOT (TClosureResolver seeds
                         FROM it and never returns it), and every unit-not-in-dpr
                         finding anchors to the program file or the .dproj rather
                         than to the offending unit.

  Orphan.pas is therefore ABSENT on purpose, and that assertion is now inverted:
  it pins the defect's removal instead of the defect.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-index-project-scope by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-index-project-scope"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$proj = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory $proj | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $proj 'App.dpr') @'
program App;

uses
  UsedUnit in 'UsedUnit.pas',
  Main in 'Main.pas';

begin
  DoWork;
end.
'@

Write-Ascii (Join-Path $proj 'UsedUnit.pas') @'
unit UsedUnit;

interface

uses
  Helper;

procedure DoWork;

implementation

procedure DoWork;
begin
  HelpMe;
end;

end.
'@

Write-Ascii (Join-Path $proj 'Helper.pas') @'
unit Helper;

interface

procedure HelpMe;

implementation

procedure HelpMe;
begin
end;

end.
'@

Write-Ascii (Join-Path $proj 'Orphan.pas') @'
unit Orphan;

interface

procedure Nobody;

implementation

procedure Nobody;
begin
end;

end.
'@

Write-Ascii (Join-Path $proj 'Main.pas') @'
unit Main;

interface

uses
  Vcl.Forms, Vcl.StdCtrls;

type
  TfrmMain = class(TForm)
    btnGo: TButton;
    procedure btnGoClick(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TfrmMain.btnGoClick(Sender: TObject);
begin
end;

end.
'@

Write-Ascii (Join-Path $proj 'Main.dfm') @'
object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'index-project-scope fixture'
  object btnGo: TButton
    Left = 8
    Top = 8
    Caption = 'Go'
    OnClick = btnGoClick
  end
end
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
        <DCCReference Include="UsedUnit.pas"/>
        <DCCReference Include="Main.pas"/>
    </ItemGroup>
</Project>
'@

$dproj = Join-Path $proj 'App.dproj'
$db    = Join-Path $WorkDir 'projscope.sqlite'

# ---------------------------------------------------------------------------
# ASSERTION 1 (cheap, decisive, runs FIRST): the resolved scan scope.
# With the bug this prints ~153 FOLDERS rooted all over the machine; correct
# behaviour is a handful of FILES, every one under the project folder. The
# assertion is about where the entries live, so it survived the folders->closure
# change untouched -- only the labels moved from "folder" to "scope entry".
# ---------------------------------------------------------------------------
Write-Host 'Resolved scan scope (index --project --dry-run)' -ForegroundColor Cyan
# 2>&1 yields ErrorRecord objects for the stderr lines; ToString() them so the
# path-line regex and .Trim() below see plain strings.
$dry = @((& $Exe index --project $dproj --db $db --platform Win64 --dry-run --quiet 2>&1) |
         ForEach-Object { $_.ToString() })
$dryExit = $LASTEXITCODE
Check 'index --project --dry-run exits 0' ($dryExit -eq 0) "exit=$dryExit"

# Scope lines are the two-space-indented entries after "Compile closure: N
# file(s):". Match on the drive-letter/UNC shape, not merely on the indent --
# the engine also writes indented stderr status lines ('  FTS5 probe: AVAILABLE')
# that 2>&1 interleaves here, and those are not paths.
$scope   = @($dry | Where-Object { $_ -match '^\s\s([A-Za-z]:\\|\\\\)' } | ForEach-Object { $_.Trim() })
$outside = @($scope | Where-Object { $_ -notlike "$proj*" })

Write-Host ("  resolved {0} scope entry/entries; {1} outside the project tree" -f $scope.Count, $outside.Count)
Check 'no scope entry lies outside the project tree' ($outside.Count -eq 0) `
  ("first offenders: " + (($outside | Select-Object -First 5) -join ' | '))

$libLike = @($scope | Where-Object { $_ -match '(?i)embarcadero|\\Raize\\|CatalogRepository|Spring4D|OmniThread' })
Check 'no IDE library / registry path in the index scope' ($libLike.Count -eq 0) `
  ("count=" + $libLike.Count + "; e.g. " + (($libLike | Select-Object -First 3) -join ' | '))

# HARD STOP: never start a real index while the scope is machine-wide -- with the
# original bug that runs for hours and would hang the battery rather than fail it.
if ($script:Failed) {
  Write-Host ''
  Write-Host 'Scope assertions failed -- SKIPPING the real index on purpose (it would' -ForegroundColor Yellow
  Write-Host 'walk the entire machine library and take hours). See this file''s header.' -ForegroundColor Yellow
  Write-Host 'FAIL' -ForegroundColor Red
  exit 1
}

# ---------------------------------------------------------------------------
# ASSERTION 2: the real index writes only project-local rows.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Real index' -ForegroundColor Cyan
$idx = & $Exe index --project $dproj --db $db --platform Win64 --quiet 2>&1
$idxExit = $LASTEXITCODE
Check 'index --project exits 0' ($idxExit -eq 0) "exit=$idxExit; $(($idx | Select-Object -Last 2) -join ' | ')"

$py = Join-Path $WorkDir 'files.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
rows = [r[0] for r in c.execute("SELECT path FROM files ORDER BY path")]
print(json.dumps(rows))
c.close()
'@ | Set-Content $py -Encoding ascii

$indexed = @((& python $py $db) -join "`n" | ConvertFrom-Json)
Write-Host ("  indexed {0} file(s)" -f $indexed.Count)

$stray = @($indexed | Where-Object { $_ -notlike "$proj*" })
Check 'ZERO indexed files outside the project tree' ($stray.Count -eq 0) `
  ("count=" + $stray.Count + "; e.g. " + (($stray | Select-Object -First 3) -join ' | '))

function Has([string]$Leaf) { return @($indexed | Where-Object { $_ -like "*\$Leaf" }).Count -ge 1 }

Check 'UsedUnit.pas is indexed'  (Has 'UsedUnit.pas')  'a project member'
Check 'Helper.pas is indexed'    (Has 'Helper.pas')    'reached transitively via uses'
Check 'Main.pas is indexed'      (Has 'Main.pas')      'the form unit, a project member'
Check 'App.dpr is indexed'       (Has 'App.dpr')       'the closure ROOT: TClosureResolver seeds from it and never returns it'
Check 'Main.dfm is indexed'      (Has 'Main.dfm')      'sibling of a closure unit; arrives via {$R *.dfm}, never via uses -- the closure alone omits it'
Check 'Orphan.pas is NOT indexed' (-not (Has 'Orphan.pas')) `
  'INVERTED 2026-08-09: a folder walk drags in loose unreferenced units, the compile closure must not'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
