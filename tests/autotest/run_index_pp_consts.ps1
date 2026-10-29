<#
  run_index_pp_consts.ps1 -- lane INC3 (2026-10-27): {$IF} sees the true
  constants Delphi lets it see -- declared earlier in the same file (active text
  only), or in a unit of the uses clause (a project unit, scanned by a per-unit
  pre-pass so index order does not matter; a library unit, answered from the
  library DB's const signature). Typed constants are not true constants (dcc
  rejects them in $IF). Declared(X) asks the same symbol table. A name nothing
  resolves keeps the False branch AND raises the pp-unresolved-if hint.

  Fixture tests\fixtures\pp_consts (copied to a scratch dir per run):
    lib\LibConsts.pas  LIB_BASE = 4; LIB_LEVEL = LIB_BASE + 5; TLibThing (library DB)
    app\UConsts.pas    PROJ_LEVEL = 2 + 3          (listed AFTER UMain in the .dpr)
    app\UMain.pas      DEBUG2 = 3; LOCAL_SUM = DEBUG2 * 2 + 1; TYPED_C: Integer = 3;
                       GHOST = 1 only inside {$IFDEF NEVERDEFINED}; one {$IF} per case,
                       each picking <CASE>_YES.INC or <CASE>_NO.INC.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-pp-consts-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Failed = $false; $script:Passed = 0; $script:FailedN = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed = $true; $script:FailedN++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$fx = Join-Path $WorkDir 'pp_consts'
Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\pp_consts").Path $fx -Recurse
$proj = Join-Path $fx 'app\PPC.dproj'
$main = Join-Path $fx 'app\UMain.pas'

function Run([string[]]$argv, [string]$tag) {
  Push-Location $WorkDir
  try { $o = & $Exe @argv 2>&1 | Out-String } finally { Pop-Location }
  [IO.File]::WriteAllText((Join-Path $WorkDir "$tag.log"), $o)
  return $o
}
# sql --json rows are POSITIONAL arrays (see feedback_sql_json_rows_are_positional).
function Col0([string]$db, [string]$q) {
  Push-Location $WorkDir
  try { $j = & $Exe sql --db $db --query $q --json 2>$null | Out-String } finally { Pop-Location }
  try { return ,@((($j | ConvertFrom-Json).rows) | ForEach-Object { [string]$_[0] }) } catch { return ,@() }
}
function IncLeaves([string]$db) {
  return ,@((Col0 $db "SELECT path FROM files WHERE path LIKE '%.inc'") | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object)
}
function Has([string[]]$set, [string]$leaf) { return [bool]($set | Where-Object { $_ -ieq $leaf }) }
function Picks([string[]]$set, [string]$case, [string]$want) {
  $other = if ($want -eq 'YES') { 'NO' } else { 'YES' }
  return (Has $set "$($case)_$want.INC") -and -not (Has $set "$($case)_$other.INC")
}

# ---- the library DB (LibConsts is NOT on the project's search path) ------------------
$libDb = Join-Path $WorkDir 'lib.sqlite'
$null = Run @('index', (Join-Path $fx 'lib'), '--db', $libDb, '--library-db', 'none') 'idxlib'
$sig = (Col0 $libDb "SELECT signature FROM symbols WHERE name = 'LIB_LEVEL' AND kind = 'const'") -join ''
Check 'library DB: LIB_LEVEL const carries its value signature' ($sig -match 'LIB_BASE\s*\+\s*5') $sig

# ---- the project --------------------------------------------------------------------
$db = Join-Path $WorkDir 'p.sqlite'
$null = Run @('index', '--project', $proj, '--db', $db, '--platform', 'win64', '--library-db', $libDb) 'idx'
$inc = IncLeaves $db
Write-Host ("  .inc rows: {0}" -f ($inc -join ','))
Check 'owner case: same-file const DEBUG2 = 3 -> only A.INC indexed' ((Has $inc 'A.INC') -and -not (Has $inc 'B.INC'))
Check 'same-file const expression LOCAL_SUM = DEBUG2 * 2 + 1 -> SUM_YES' (Picks $inc 'SUM' 'YES')
Check 'const from a used PROJECT unit (UConsts, indexed later) -> PROJ_YES' (Picks $inc 'PROJ' 'YES')
Check 'const from a used LIBRARY unit (library DB, LIB_BASE + 5) -> LIB_YES' (Picks $inc 'LIB' 'YES')
Check 'const declared only in an inactive branch does NOT count -> GHOST_NO' (Picks $inc 'GHOST' 'NO')
Check 'typed const is not a true constant (like dcc) -> TYPED_NO' (Picks $inc 'TYPED' 'NO')
Check 'Declared(): same-file const, library type, unknown name -> DECL_YES' (Picks $inc 'DECL' 'YES')
Check 'unresolved name keeps the False branch -> NOSUCH_NO' (Picks $inc 'NOSUCH' 'NO')
Check 'EXT-E4: typed const from a LIBRARY unit is not a true constant -> LTYPED_NO' (Picks $inc 'LTYPED' 'NO')
# ---- EXT-E4: symbols.modifiers marks a TYPED constant; signatures unchanged ---------------
function ConstRow([string]$d, [string]$n) {
  Push-Location $WorkDir
  try { $j = & $Exe sql --db $d --json --query "SELECT COALESCE(modifiers,''), COALESCE(signature,'') FROM symbols WHERE name = '$n' AND kind = 'const'" 2>$null | Out-String } finally { Pop-Location }
  try { $r = @(($j | ConvertFrom-Json).rows); if ($r.Count -gt 0) { return ,@([string]$r[0][0], [string]$r[0][1]) } } catch { }
  return ,@('<none>', '<none>')
}
$tc = ConstRow $db 'TYPED_C'; $d2 = ConstRow $db 'DEBUG2'; $lt = ConstRow $libDb 'LIB_TYPED'; $lb = ConstRow $libDb 'LIB_BASE'
Check 'EXT-E4: TYPED_C modifiers carry typed' ($tc[0] -match '\btyped\b') ("mods='" + $tc[0] + "'")
Check 'EXT-E4: TYPED_C signature unchanged (Integer = 3)' ($tc[1] -eq 'Integer = 3') ("sig='" + $tc[1] + "'")
Check 'EXT-E4: true const DEBUG2 has no typed modifier' (($d2[0] -ne '<none>') -and ($d2[0] -notmatch '\btyped\b')) ("mods='" + $d2[0] + "'")
Check 'EXT-E4: true const DEBUG2 signature unchanged (Integer = 3)' ($d2[1] -eq 'Integer = 3') ("sig='" + $d2[1] + "'")
Check 'EXT-E4: library LIB_TYPED modifiers carry typed' ($lt[0] -match '\btyped\b') ("mods='" + $lt[0] + "'")
Check 'EXT-E4: library true const LIB_BASE has no typed modifier' (($lb[0] -ne '<none>') -and ($lb[0] -notmatch '\btyped\b')) ("mods='" + $lb[0] + "'")

# ---- pp-unresolved-if ----------------------------------------------------------------
$lj = Run @('lint', $main, '--db', $db, '--library-db', $libDb, '--project', $proj, '--platform', 'win64', '--rule', 'pp-unresolved-if', '--json') 'lint'
$lines = @()
try {
  $jtxt = $lj.Substring($lj.IndexOf('['))
  $lines = @(($jtxt | ConvertFrom-Json) | Where-Object { $_.rule -eq 'pp-unresolved-if' } | ForEach-Object { [int]$_.start_line })
} catch { }
Write-Host ("  pp-unresolved-if lines: {0}" -f ($lines -join ','))
Check 'pp-unresolved-if fires on {$IF NOSUCHNAME = 1} (line 64)' ($lines -contains 64)
Check 'pp-unresolved-if fires on the inactive-only GHOST (line 46)' ($lines -contains 46)
Check 'pp-unresolved-if fires on the typed const TYPED_C (line 52)' ($lines -contains 52)
Check 'EXT-E4: pp-unresolved-if fires on the LIBRARY typed const LIB_TYPED (line 70)' ($lines -contains 70)
$msgs = @()
try { $msgs = @(($jtxt | ConvertFrom-Json) | Where-Object { $_.rule -eq 'pp-unresolved-if' } | ForEach-Object { '{0}|{1}' -f $_.start_line, $_.message }) } catch { }
$m52 = ($msgs | Where-Object { $_ -like '52|*' }) -join ' '; $m70 = ($msgs | Where-Object { $_ -like '70|*' }) -join ' '; $m64 = ($msgs | Where-Object { $_ -like '64|*' }) -join ' '
Check 'EXT-E4: hint names TYPED_C as a typed constant' ($m52 -match 'TYPED_C \(typed constant') $m52
Check 'EXT-E4: hint names LIB_TYPED as a typed constant' ($m70 -match 'LIB_TYPED \(typed constant') $m70
Check 'EXT-E4 control: NOSUCHNAME hint does NOT say typed constant' (($m64 -match 'NOSUCHNAME') -and ($m64 -notmatch 'typed constant')) $m64
foreach ($ok in 22, 28, 34, 40, 58) { Check "pp-unresolved-if silent on resolved line $ok" (-not ($lines -contains $ok)) }

# ---- positive control: DEBUG2 = 4 -> only B.INC ---------------------------------------
$t = [IO.File]::ReadAllText($main)
[IO.File]::WriteAllText($main, $t.Replace('DEBUG2 = 3;', 'DEBUG2 = 4;'), [Text.Encoding]::ASCII)
$null = Run @('index', '--project', $proj, '--db', $db, '--platform', 'win64', '--library-db', $libDb) 'flip'
$inc2 = IncLeaves $db
Write-Host ("  after DEBUG2 = 4: {0}" -f ($inc2 -join ','))
Check 'positive control: DEBUG2 = 4 -> only B.INC indexed' ((Has $inc2 'B.INC') -and -not (Has $inc2 'A.INC'))
Check 'positive control: LOCAL_SUM = 9 now -> SUM_NO' (Picks $inc2 'SUM' 'NO')
} finally {
  Write-Host ''
  Write-Host ("RESULT: {0} passed, {1} failed" -f $script:Passed, $script:FailedN)
}
if ($script:Failed) { exit 1 } else { exit 0 }