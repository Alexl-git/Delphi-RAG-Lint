<#
  run_index_all_no_prune.ps1 -- `--no-prune` ON THE MANIFEST ARM, AND THE DRY LOOK.

  THE DEFECT
  ---------------------------------------------------------------------------
  BuildPlanItem never received AArgs.NoPrune, so on `index --all` out-of-scope
  eviction was UNCONDITIONAL with no opt-out -- while the help text claimed
  `--no-prune` "opts out of BOTH sweeps: it is the one 'delete nothing' switch".
  That claim held only for the single-root arm. The first `index --all` after
  eviction shipped sweeps the Library sections (4.1 GB), and an operator could
  neither preview nor suppress it.

  WHAT IS ASSERTED
  ---------------------------------------------------------------------------
    1. With `--no-prune`, a file that has LEFT THE SCOPE but is still on disk
       SURVIVES in the section DB, and the run REPORTS it as "would remove".
       Both halves: a flag that silently deletes nothing is not a preview, and
       a preview that also deletes is not an opt-out.
    2. Without the flag, the same run deletes it -- so group 1 is not passing
       because eviction is broken outright.
    3. The flag travels to the SPAWNED CHILDREN of the parallel path
       (`--jobs >1`), which is a separate code path with its own command line:
       a `--no-prune` that evaporates at the process boundary is the same bug
       one layer down.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7. Needs `python` on PATH.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_allnoprune'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$projA = Join-Path $scratch 'projA'
New-Item -ItemType Directory -Path $projA | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

function Write-ProjA([bool]$WithMember2) {
  if ($WithMember2) {
    Write-Ascii (Join-Path $projA 'App.dpr') @'
program App;

uses
  Member1 in 'Member1.pas',
  Member2 in 'Member2.pas';

begin
  Member1.RunOne;
  Member2.RunTwo;
end.
'@
    $refs = "        <DCCReference Include=`"Member1.pas`"/>`r`n        <DCCReference Include=`"Member2.pas`"/>"
  } else {
    Write-Ascii (Join-Path $projA 'App.dpr') @'
program App;

uses
  Member1 in 'Member1.pas';

begin
  Member1.RunOne;
end.
'@
    $refs = "        <DCCReference Include=`"Member1.pas`"/>"
  }
  Write-Ascii (Join-Path $projA 'App.dproj') @"
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <MainSource>App.dpr</MainSource>
        <ProjectVersion>20.3</ProjectVersion>
        <Platform>Win64</Platform>
        <Config Condition="'`$(Config)'==''">Debug</Config>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="App.dpr">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
$refs
    </ItemGroup>
</Project>
"@
}

Write-Ascii (Join-Path $projA 'Member1.pas') @'
unit Member1;

interface

procedure RunOne;

implementation

procedure RunOne;
var
  S: string;
begin
  S:= 'zzqqmemberonemarker';
end;

end.
'@

Write-Ascii (Join-Path $projA 'Member2.pas') @'
unit Member2;

interface

type
  TSecondThing = class(TObject)
  public
    procedure Alpha;
  end;

procedure RunTwo;

implementation

procedure TSecondThing.Alpha;
begin
end;

procedure RunTwo;
var
  S: string;
begin
  S:= 'zzqqmembertwomarker';
end;

end.
'@

# rows.py <db> files|symbols|orphans [pattern]
$rowsPy = Join-Path $scratch 'rows.py'
@'
import sqlite3, sys, os
db, what = sys.argv[1], sys.argv[2]
pat = ('%' + sys.argv[3].lower() + '%') if len(sys.argv) > 3 else '%'
if not os.path.exists(db):
    print('MISSING-DB')
    sys.exit(0)
c = sqlite3.connect(db)
try:
    if what == 'files':
        n = c.execute("SELECT COUNT(*) FROM files WHERE LOWER(path) LIKE ?", (pat,)).fetchone()[0]
    elif what == 'symbols':
        n = c.execute("SELECT COUNT(*) FROM symbols s JOIN files f ON f.id = s.file_id "
                      "WHERE LOWER(f.path) LIKE ?", (pat,)).fetchone()[0]
    else:
        n = c.execute("SELECT COUNT(*) FROM symbols WHERE file_id NOT IN "
                      "(SELECT id FROM files)").fetchone()[0]
    print(n)
except sqlite3.Error as e:
    print('ERROR:' + str(e))
c.close()
'@ | Set-Content $rowsPy -Encoding ascii
function Rows([string]$Db, [string]$What, [string]$Pat = '') {
  if ($Pat -eq '') { return ((& python $rowsPy $Db $What) -join '') }
  return ((& python $rowsPy $Db $What $Pat) -join '')
}

# A "would remove" report names the file AND says it was suppressed. Matching
# both keeps a plain eviction line (which also names the file) from passing.
function SaysWouldRemove($Lines, [string]$Leaf) {
  $txt = ($Lines | ForEach-Object { $_.ToString() }) -join "`n"
  return ($txt -match '(?i)would\s+remove') -and ($txt -match '(?i)no-prune') -and ($txt -like "*$Leaf*")
}

$cfg = Join-Path $scratch 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "NoPruneSection", "db": "np.sqlite", "include": ["projA\\App.dproj"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
$sectionDb = Join-Path $scratch 'out\np.sqlite'

Push-Location C:\TEMP
try {
  # ==========================================================================
  # 1. --no-prune SUPPRESSES eviction on `index --all` AND reports the dry look.
  # ==========================================================================
  Write-ProjA $true
  $o = @(& $exePath index --all --config $cfg --only NoPruneSection --jobs 1 2>&1)
  $rc = $LASTEXITCODE
  Check '1a. initial index --all exits 0' ($rc -eq 0) "exit=$rc"
  Check '1a. both members indexed' `
    (((Rows $sectionDb 'files' 'member1.pas') -eq '1') -and ((Rows $sectionDb 'files' 'member2.pas') -eq '1')) `
    "m1=$(Rows $sectionDb 'files' 'member1.pas') m2=$(Rows $sectionDb 'files' 'member2.pas')"
  $m2Syms = Rows $sectionDb 'symbols' 'member2.pas'
  Check '1a. Member2 has symbols' ([int]$m2Syms -gt 0) "symbols=$m2Syms -- a zero makes 1c vacuous"

  Write-ProjA $false   # drop Member2 from the project; the FILE STAYS ON DISK
  $o = @(& $exePath index --all --config $cfg --only NoPruneSection --jobs 1 --recompile --no-prune 2>&1)
  $rc = $LASTEXITCODE
  Check '1b. index --all --no-prune exits 0' ($rc -eq 0) "exit=$rc"
  Check '1c. --no-prune KEPT the out-of-scope file' ((Rows $sectionDb 'files' 'member2.pas') -eq '1') `
    "files rows=$(Rows $sectionDb 'files' 'member2.pas') -- the flag must reach BuildPlanItem"
  Check '1c. and its symbols' ((Rows $sectionDb 'symbols' 'member2.pas') -eq $m2Syms) `
    "before=$m2Syms after=$(Rows $sectionDb 'symbols' 'member2.pas')"
  Check '1d. the run REPORTED the would-be removal (dry look)' (SaysWouldRemove $o 'Member2.pas') `
    "a 4.1 GB sweep is only safe to approve if it can be previewed; output=$(($o | Select-Object -Last 6) -join ' | ')"
  Check '1e. Member1 is untouched' ((Rows $sectionDb 'files' 'member1.pas') -eq '1') `
    "files rows=$(Rows $sectionDb 'files' 'member1.pas')"

  # ==========================================================================
  # 2. WITHOUT the flag the same run deletes it -- group 1 is not vacuous.
  # ==========================================================================
  $o = @(& $exePath index --all --config $cfg --only NoPruneSection --jobs 1 --recompile 2>&1)
  $rc = $LASTEXITCODE
  Check '2a. index --all --recompile exits 0' ($rc -eq 0) "exit=$rc"
  Check '2b. without --no-prune the out-of-scope file IS evicted' ((Rows $sectionDb 'files' 'member2.pas') -eq '0') `
    "files rows=$(Rows $sectionDb 'files' 'member2.pas')"
  Check '2b. its symbols went with it' ((Rows $sectionDb 'symbols' 'member2.pas') -eq '0') `
    "symbols=$(Rows $sectionDb 'symbols' 'member2.pas')"
  Check '2b. no orphaned symbols' ((Rows $sectionDb 'orphans') -eq '0') "orphans=$(Rows $sectionDb 'orphans')"

  # ==========================================================================
  # 3. THE FLAG SURVIVES THE PROCESS BOUNDARY of the parallel path (--jobs >1),
  #    which builds its child command line by hand.
  # ==========================================================================
  Write-ProjA $true
  & $exePath index --all --config $cfg --only NoPruneSection --jobs 1 --recompile 2>&1 | Out-Null
  Check '3a. Member2 is back in the section' ((Rows $sectionDb 'files' 'member2.pas') -eq '1') `
    "files rows=$(Rows $sectionDb 'files' 'member2.pas')"
  Write-ProjA $false
  $o = @(& $exePath index --all --config $cfg --only NoPruneSection --jobs 2 --recompile --no-prune 2>&1)
  $rc = $LASTEXITCODE
  Check '3b. parallel index --all --no-prune exits 0' ($rc -eq 0) "exit=$rc"
  Check '3c. the child honoured --no-prune' ((Rows $sectionDb 'files' 'member2.pas') -eq '1') `
    "files rows=$(Rows $sectionDb 'files' 'member2.pas') -- the flag must be on the child command line"
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
