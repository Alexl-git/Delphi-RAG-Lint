<#
  run_rename_inc_refuse.ps1 -- wave 3 lane I (stopgap until extractor 1.22
  emits references for {$I} included text).

  An .inc file gets a `files` row, but a code-fragment include parses on its
  own with errors and 0 refs, and the {$I} site in the host unit emits none.
  So `rename` used to rewrite the declaration and silently miss every use
  inside the include -- the renamed project no longer compiles.

  STOPGAP: rename (plan AND --apply, legacy --qname and --kind symbol) REFUSES
  with exit 2 and a message naming the .inc file(s) when the old name occurs
  as an identifier token (comments and string literals skipped) in an .inc
  file the index holds.

  FIXTURE A (bug): uHost.pas declares Helper and {$I body.inc}; body.inc
    calls Helper.  ASSERT: every rename form exits 2, names body.inc, and the
    sources are byte-identical afterwards.
  FIXTURE B (positive control): same host, but body.inc mentions Helper only
    in a comment and a string literal.
  FIXTURE C (N-06): renaming UNIT IncA, whose only other use is a uses entry in
    shared\IncB.Uses.inc -- an include with no files row (near-search only).
    ASSERT: exit 2 naming that .inc, sources byte-identical.  ASSERT: rename --apply exits 0 and
    the declaration IS rewritten (so the refusal in A is the .inc check, not
    a broken rename).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-inc-$PID"
)
try {
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

if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$HostUnit = @'
unit uHost;

interface

function Helper: Integer;
procedure DoWork;

implementation

function Helper: Integer;
begin
  Result:= 1;
end;

procedure DoWork;
var
  X: Integer;
begin
  {$I body.inc}
end;

end.
'@

function New-Fixture([string]$Name, [string]$IncBody) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  Write-Ascii (Join-Path $src 'uHost.pas') $HostUnit
  Write-Ascii (Join-Path $src 'body.inc')  $IncBody
  $db = Join-Path $dir 'idx.sqlite'
  Push-Location $dir
  try { & $Exe index $src --db $db 2>&1 | Out-Null } finally { Pop-Location }
  Check "$Name index exits 0" ($LASTEXITCODE -eq 0)
  [pscustomobject]@{ Dir = $dir; Src = $src; Db = $db }
}

function Snapshot($fx) {
  (Get-ChildItem $fx.Src -File | Sort-Object Name | ForEach-Object { $_.Name + '=' + (Get-Content -Raw $_.FullName) }) -join '|'
}

function Run-Rename($fx, [string[]]$RenameArgs) {
  Push-Location $fx.Dir
  try { $o = & $Exe rename @RenameArgs --db $fx.Db 2>&1 } finally { Pop-Location }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($o -join "`n") }
}

# ---------------- A: the include USES the name -> refuse ----------------
Write-Host 'Fixture A: body.inc calls Helper' -ForegroundColor Cyan
$a = New-Fixture 'A' "  X:= Helper; { Helper }`r`n"
$before = Snapshot $a
$forms = @(
  @{ N = 'legacy --dry-run';       A = @('--qname', 'uHost.Helper', '--to', 'Helper2', '--dry-run') },
  @{ N = 'legacy --apply';         A = @('--qname', 'uHost.Helper', '--to', 'Helper2', '--apply') },
  @{ N = '--kind symbol plan';     A = @('--kind', 'symbol', '--name', 'uHost.Helper', '--to', 'Helper2') },
  @{ N = '--kind symbol --apply';  A = @('--kind', 'symbol', '--name', 'uHost.Helper', '--to', 'Helper2', '--apply') }
)
foreach ($f in $forms) {
  $r = Run-Rename $a $f.A
  Check "A $($f.N) exits 2"          ($r.Exit -eq 2)                 "exit=$($r.Exit)"
  Check "A $($f.N) names body.inc"   ($r.Out -match 'body\.inc')     ($r.Out -split "`n" | Select-Object -Last 1)
  Check "A $($f.N) says include"     ($r.Out -match '(?i)include')
}
Check 'A sources unchanged' ((Snapshot $a) -ceq $before)

# ------- B (positive control): name only in comment / string -> proceeds -------
Write-Host 'Fixture B: body.inc mentions Helper only in a comment and a string' -ForegroundColor Cyan
$b = New-Fixture 'B' "  // Helper`r`n  X:= Length('Helper'); (* Helper *)`r`n"
$r = Run-Rename $b @('--qname', 'uHost.Helper', '--to', 'Helper2', '--apply')
Write-Host $r.Out
Check 'B legacy --apply exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
$hostAfter = Get-Content -Raw (Join-Path $b.Src 'uHost.pas')
Check 'B declaration rewritten' ($hostAfter -cmatch 'function Helper2: Integer;')

# ------- C (N-06): a UNIT named in a uses clause that lives in an include the -------
# index keeps NO files row for (found by the preprocessor's near-search in a
# subdir, which the closure resolver does not do). The include row (unit_uses
# origin_path) is the only evidence; renaming the unit must refuse naming it.
Write-Host 'Fixture C: unit IncA is used from shared\IncB.Uses.inc (no files row)' -ForegroundColor Cyan
$cDir = Join-Path $WorkDir 'C'
Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\cyclefix\incuses").Path $cDir -Recurse
New-Item -ItemType Directory (Join-Path $cDir 'shared') | Out-Null
Move-Item (Join-Path $cDir 'IncB.Uses.inc') (Join-Path $cDir 'shared\IncB.Uses.inc')
$cDb = Join-Path $WorkDir 'C.sqlite'
Push-Location $WorkDir
try { & $Exe index --project (Join-Path $cDir 'IncUses.dproj') --db $cDb --library-db none 2>&1 | Out-Null } finally { Pop-Location }
Check 'C index exits 0' ($LASTEXITCODE -eq 0)
$cSnap = (Get-ChildItem $cDir -Recurse -File -Include *.pas, *.inc, *.dpr | Sort-Object FullName | ForEach-Object { $_.Name + '=' + (Get-Content -Raw $_.FullName) }) -join '|'
Push-Location $WorkDir
try { $o = & $Exe rename --kind symbol --name IncA --to IncZ --apply --db $cDb 2>&1; $cRc = $LASTEXITCODE } finally { Pop-Location }
$cOut = $o -join "`n"
Check 'C rename of unit IncA exits 2' ($cRc -eq 2) "exit=$cRc"
Check 'C names shared\IncB.Uses.inc' ($cOut -match 'shared\\IncB\.Uses\.inc') ($cOut -split "`n" | Select-Object -Last 1)
$cAfter = (Get-ChildItem $cDir -Recurse -File -Include *.pas, *.inc, *.dpr | Sort-Object FullName | ForEach-Object { $_.Name + '=' + (Get-Content -Raw $_.FullName) }) -join '|'
Check 'C sources unchanged' ($cAfter -ceq $cSnap)

} catch {
  Write-Host "FATAL: $_" -ForegroundColor Red
  $script:Failed = $true
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
if ($script:Failed) { Write-Host 'run_rename_inc_refuse: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_rename_inc_refuse: PASS' -ForegroundColor Green
exit 0
