<#
  run_deep_expr_stack.ps1 -- a single deeply-nested expression must not be able
  to kill the indexer.

  THE BUG (found 2026-08-09 on C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj)
  ---------------------------------------------------------------------------
  DRagLint.Parser.Delphi13.Walk recurses ONCE PER EXPRESSION NODE with a
  1,776-byte frame. Against Delphi's default 1 MB stack reserve that is a
  ceiling of roughly 1,048,576 / 1,776 = 590 nested nodes; measured, the real
  parser dies between 550 and 600 because RTL frames below Walk and the guard
  page take the remainder.

  A left-nested binary expression nests one node per operand, so an N-operand
  chain costs N frames. C:\Projects\PDFlibPas\PDFlibStampAnnot.pas carries an
  810-operand string-concatenation chain. ONE file out of 1,909 in the corpus.

  What made it fatal rather than merely noisy is WHICH loop hit it:

    * folder walk   Indexer.pas:693 wraps IndexFile in try/except, so the
                    overflow printed "SKIP <file>: EStackOverflow" and the run
                    exited 0 having indexed the file to ZERO symbols. A green
                    exit code over a silently dropped file.
    * --project     CLI.pas:1646 is a bare `for F in Scope do IndexFile(F)`
                    with no guard, so the same overflow took the process down
                    with 0xC0000005 at file 692 of 709 -- and because the run
                    never reached the resolve phase, call_edges stayed 0.

  Both shapes are asserted below, because they fail DIFFERENTLY and a test that
  only covered `--project` would have called the folder path healthy.

  THE MITIGATION UNDER TEST
  -------------------------
  src\cli\drag-lint.dpr declares {$MAXSTACKSIZE 67108864} -- 64 MB, about
  37,700 nested nodes. See the comment at that directive for the arithmetic and
  for why the PE-header reserve is the right knob (all parsing is on the MAIN
  THREAD; --jobs parallelises by child PROCESS, not by TThread).

  This is a mitigation, not the fix. Making Walk iterative removes the ceiling;
  raising the reserve only moves it. This test pins the mitigation so that
  deleting the directive reddens immediately, and it keeps its value unchanged
  when Walk is eventually rewritten -- at that point the depth simply stops
  mattering, and this file still proves it.

  HOW THIS TEST COULD GO VACUOUS, STATED RATHER THAN IMPLIED
  ----------------------------------------------------------
  If a grammar change ever made a concatenation chain a FLAT node instead of a
  left-nested one, the fixture would stop being deep and every assertion here
  would pass while measuring nothing. There is no cheap way to assert nesting
  depth from outside the engine, so instead the fixture asserts the parse
  produced REAL OUTPUT (the function symbol lands, zero parse errors) rather
  than merely that nothing crashed -- "did not crash" is exactly the assertion
  that survives a fixture going shallow. The structural check on the directive
  is the second half: if the reserve is removed, this file names the cause
  instead of leaving a mysterious red.

  Depths are deliberately BRACKETING, not a single number:
    550 operands -- below the old ceiling; passed BEFORE the fix too. A control
                    that proves the harness reports green for a shallow file.
    900 operands -- above the old ceiling; the RED case. Measured against the
                    pre-fix binary: folder walk -> "SKIP ... EStackOverflow",
                    Files: 0; --project -> exit -1073741819.

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-deep-expr by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-deep-expr"
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
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# ---------------------------------------------------------------------------
# STRUCTURAL CHECK: the mitigation is declared, and declared large enough.
# Behavioural checks below would also redden if the directive vanished; this
# one exists so that red arrives NAMED. 16 MB (~9,400 nodes) is the floor --
# it covers the 810-operand file that motivated this, so anything at or above
# it is a deliberate choice rather than a regression.
# ---------------------------------------------------------------------------
Write-Host '== deep expression / parser stack ceiling ==' -ForegroundColor Cyan
$dprPath = Join-Path $Repo 'src\cli\drag-lint.dpr'
$dprText = if (Test-Path $dprPath) { Get-Content $dprPath -Raw } else { '' }
$mss = [regex]::Match($dprText, '(?im)^\s*\{\$MAXSTACKSIZE\s+(\d+)\s*\}')
Check 'src\cli\drag-lint.dpr declares {$MAXSTACKSIZE}' $mss.Success `
  'without it the parser tops out around 570 nested expression nodes'
$reserve = if ($mss.Success) { [int64]$mss.Groups[1].Value } else { 0 }
Check 'the declared reserve is at least 16 MB' ($reserve -ge 16777216) `
  ("declared $reserve bytes (~$([int]($reserve / 1776)) nested nodes at 1,776 bytes/frame)")

# ---------------------------------------------------------------------------
# FIXTURES
# ---------------------------------------------------------------------------
function New-DeepUnit([string]$Dir, [string]$UnitName, [int]$Operands) {
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $Operands; $i++) {
    if ($i -gt 0) { [void]$sb.Append(' + ') }
    [void]$sb.Append("'x$i'")
  }
  Write-Ascii (Join-Path $Dir "$UnitName.pas") @"
unit $UnitName;

interface

function MakeBig: string;

implementation

function MakeBig: string;
begin
  Result := $($sb.ToString());
end;

end.
"@
}

# Folder-walk fixture: the deep unit plus a SHALLOW sibling. The sibling is not
# decoration -- with the bug, "Files: 0" and "Files: 1" are both plausible
# readings of a run, and the sibling makes the count discriminating: a healthy
# run indexes BOTH, the pre-fix run indexed only the shallow one.
$walkDir = Join-Path $WorkDir 'walk'
New-Item -ItemType Directory $walkDir | Out-Null
New-DeepUnit $walkDir 'DeepConcat'    900
New-DeepUnit $walkDir 'ShallowConcat' 550
Write-Ascii (Join-Path $walkDir 'Plain.pas') @'
unit Plain;

interface

procedure Nothing;

implementation

procedure Nothing;
begin
end;

end.
'@

# --project fixture: the closure form, which is the one that died 0xC0000005.
$projDir = Join-Path $WorkDir 'proj'
New-Item -ItemType Directory $projDir | Out-Null
New-DeepUnit $projDir 'DeepConcat' 900
Write-Ascii (Join-Path $projDir 'App.dpr') @'
program App;

uses
  DeepConcat in 'DeepConcat.pas';

begin
end.
'@
Write-Ascii (Join-Path $projDir 'App.dproj') @'
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
        <DCCReference Include="DeepConcat.pas"/>
    </ItemGroup>
</Project>
'@

$qpy = Join-Path $WorkDir 'q.py'
@'
import sqlite3, sys, json
c = sqlite3.connect(sys.argv[1])
out = {
  "files":   [r[0] for r in c.execute("SELECT path FROM files")],
  "symbols": [r[0] for r in c.execute("SELECT name FROM symbols")],
}
print(json.dumps(out))
c.close()
'@ | Set-Content $qpy -Encoding ascii

function Read-Db([string]$Db) {
  if (-not (Test-Path $Db)) { return $null }
  return ((& python $qpy $Db) -join "`n" | ConvertFrom-Json)
}
function HasLeaf($Rows, [string]$Leaf) { return @($Rows | Where-Object { $_ -like "*\$Leaf" }).Count -ge 1 }

# ---------------------------------------------------------------------------
# CASE 1 -- folder walk. Pre-fix: exit 0, "SKIP ...: EStackOverflow", Files: 0
# for DeepConcat.pas. A green exit code over a dropped file, which is why the
# exit code alone is NOT the assertion here.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 1: index <folder> (pre-fix: exit 0 but the file is SILENTLY SKIPPED)' -ForegroundColor Cyan
$walkDb = Join-Path $WorkDir 'walk.sqlite'
$walkOut = @((& $Exe index $walkDir --db $walkDb 2>&1) | ForEach-Object { $_.ToString() })
$walkExit = $LASTEXITCODE
Check 'index <folder> exits 0' ($walkExit -eq 0) "exit=$walkExit"

$skips = @($walkOut | Where-Object { $_ -match 'SKIP|EStackOverflow|Stack overflow' })
Check 'no file was skipped for a stack overflow' ($skips.Count -eq 0) `
  ("count=" + $skips.Count + "; " + (($skips | Select-Object -First 2) -join ' | '))

$walkDbRows = Read-Db $walkDb
Check 'folder DB was produced' ($null -ne $walkDbRows)
if ($null -ne $walkDbRows) {
  Check 'DeepConcat.pas (900 operands) is indexed'  (HasLeaf $walkDbRows.files 'DeepConcat.pas')    'above the old ~570 ceiling -- the RED case'
  Check 'ShallowConcat.pas (550 operands) is indexed' (HasLeaf $walkDbRows.files 'ShallowConcat.pas') 'below the old ceiling -- the control'
  Check 'Plain.pas is indexed'                      (HasLeaf $walkDbRows.files 'Plain.pas')         'discriminates "Files: 0" from "Files: 1"'
  # Symbols, not just files: "did not crash" is the assertion that survives a
  # fixture going shallow, so require the parse to have produced real output.
  $mk = @($walkDbRows.symbols | Where-Object { $_ -eq 'MakeBig' }).Count
  Check 'both MakeBig functions landed as symbols' ($mk -ge 2) "found $mk"
}

# ---------------------------------------------------------------------------
# CASE 2 -- --project. Pre-fix this does not fail, it DIES: exit -1073741819
# (0xC0000005, the stack guard page), mid-write, with the run's output
# truncated. CLI.pas:1646 has no per-file try/except.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Case 2: index --project (pre-fix: process death, exit -1073741819)' -ForegroundColor Cyan
$projDb = Join-Path $WorkDir 'proj.sqlite'
$projOut = @((& $Exe index --project (Join-Path $projDir 'App.dproj') --db $projDb --platform Win64 2>&1) |
             ForEach-Object { $_.ToString() })
$projExit = $LASTEXITCODE
Check 'index --project exits 0 (not 0xC0000005)' ($projExit -eq 0) `
  ("exit=$projExit" + $(if ($projExit -eq -1073741819) { '  <- ACCESS_VIOLATION: the stack guard page' } else { '' }))

$projDbRows = Read-Db $projDb
Check 'project DB was produced' ($null -ne $projDbRows)
if ($null -ne $projDbRows) {
  Check 'DeepConcat.pas is indexed via the closure' (HasLeaf $projDbRows.files 'DeepConcat.pas')
  Check 'MakeBig landed as a symbol'                (@($projDbRows.symbols | Where-Object { $_ -eq 'MakeBig' }).Count -ge 1)
}

Write-Host ''
if ($script:Failed) { Write-Host 'DEEP EXPR STACK: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'DEEP EXPR STACK: PASS' -ForegroundColor Green
exit 0
