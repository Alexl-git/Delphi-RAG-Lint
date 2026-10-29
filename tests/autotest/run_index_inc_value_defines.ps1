<#
  run_index_inc_value_defines.ps1 -- lane INC2 (2026-10-27): an include is
  chosen under the EXACT preprocessor values in effect -- a DCC_Define that
  carries a value (DEBUG2=3), compiler switches for {$IFOPT}, and the compiler's
  own CompilerVersion.

  Fixture tests\fixtures\inc_value_defines (copied to a scratch dir per run):
    app\VDef.dproj  Base DCC_Define 'BASEMARK;DEBUG2=3;FEATX'; active config Debug
                    (DCC_RangeChecking true)
    app\UMain.pas   {$IF DEBUG2 = 3} A.INC {$ELSE} B.INC
                    {$IF Defined(FEATX) and (DEBUG2 > 1)} C.INC
                    {$IFDEF DEBUG2} D.INC
                    {$IFOPT R+} ROn.inc {$ELSE} ROff.inc
                    {$R-} {$IFOPT R-} RLocal.inc     (an in-source switch)
                    {$IF CompilerVersion >= 37} CV.inc

  Checks: the define profile carries the value (pp-profile: 'debug2' is a
  define, 'debug2=3' a value, never a define name); the right includes are
  indexed; flipping DEBUG2=3 -> DEBUG2=4 changes the indexer fingerprint and
  swaps A.INC for B.INC; a delphilsp.json -D value and -$R+ switch serve the
  same way when the .dproj has no Config marker.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-inc-value-$PID"
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
$fx = Join-Path $WorkDir 'inc_value_defines'
Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\inc_value_defines").Path $fx -Recurse
$proj = Join-Path $fx 'app\VDef.dproj'

function Run([string[]]$argv, [string]$tag) {
  Push-Location $WorkDir
  try { $o = & $Exe @argv 2>&1 | Out-String } finally { Pop-Location }
  [IO.File]::WriteAllText((Join-Path $WorkDir "$tag.log"), $o)
  return $o
}
function Index([string]$p, [string]$db, [string]$tag) {
  return Run @('index', '--project', $p, '--db', $db, '--platform', 'win64', '--library-db', 'none') $tag
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
function Fp([string]$db) { return (Col0 $db "SELECT value FROM schema_meta WHERE key = 'indexer_fingerprint'") -join '' }

# ---- the profile carries the value ---------------------------------------------------
$prof = @((Run @('pp-profile', '--dproj', $proj, '--platform', 'Win64', '--config', 'Debug') 'profile') -split "`r?`n" | ForEach-Object { $_.Trim() })
Check 'pp-profile: debug2 is a define' ($prof -contains 'debug2')
Check 'pp-profile: debug2=3 is a value line' ($prof -contains 'debug2=3')
Check 'pp-profile: compilerversion=37 is a value line (compiler built-in)' ($prof -contains 'compilerversion=37')
Check 'pp-profile: $r+ (DCC_RangeChecking of the Debug config)' ($prof -contains '$r+')

# ---- index: the includes the exact values select -------------------------------------
$db = Join-Path $WorkDir 'v.sqlite'
$null = Index $proj $db 'idx'
$inc = IncLeaves $db
Write-Host ("  .inc rows: {0}" -f ($inc -join ','))
Check '{$IF DEBUG2 = 3}: A.INC indexed, B.INC not' ((Has $inc 'A.INC') -and -not (Has $inc 'B.INC'))
Check '{$IF Defined(FEATX) and (DEBUG2 > 1)}: C.INC indexed' (Has $inc 'C.INC')
Check '{$IFDEF DEBUG2} (a value define is defined): D.INC indexed' (Has $inc 'D.INC')
Check '{$IFOPT R+} under DCC_RangeChecking=true: ROn.inc indexed, ROff.inc not' ((Has $inc 'ROn.inc') -and -not (Has $inc 'ROff.inc'))
Check '{$R-} then {$IFOPT R-}: RLocal.inc indexed (in-source switch)' (Has $inc 'RLocal.inc')
Check '{$IF CompilerVersion >= 37}: CV.inc indexed' (Has $inc 'CV.inc')

# ---- flip the value: the fingerprint flips, the other include is indexed ---------------
$fp0 = Fp $db
$t = [IO.File]::ReadAllText($proj)
[IO.File]::WriteAllText($proj, $t.Replace('DEBUG2=3', 'DEBUG2=4'), [Text.Encoding]::ASCII)
$null = Index $proj $db 'flip'
$fp1 = Fp $db
$inc2 = IncLeaves $db
Write-Host ("  after DEBUG2=4: {0}" -f ($inc2 -join ','))
Check 'DEBUG2=3 -> DEBUG2=4: indexer fingerprint changed' (($fp0 -ne '') -and ($fp0 -ne $fp1)) "$fp0 -> $fp1"
Check 'DEBUG2=4: B.INC indexed, A.INC gone' ((Has $inc2 'B.INC') -and -not (Has $inc2 'A.INC'))
Check 'DEBUG2=4: C.INC still indexed (4 > 1)' (Has $inc2 'C.INC')

# ---- delphilsp.json: the -D value and the -$ switch ------------------------------------
$lspDir = Join-Path $WorkDir 'lsp'
Copy-Item (Join-Path $fx 'app') $lspDir -Recurse
$lspProj = Join-Path $lspDir 'VDef.dproj'
$t = [IO.File]::ReadAllText($lspProj)
$t = $t.Replace("<Config Condition=`"'`$(Config)'==''`">Debug</Config>", '').Replace('DEBUG2=4', 'BASEONLY')
[IO.File]::WriteAllText($lspProj, $t, [Text.Encoding]::ASCII)
$json = '{ "settings": { "project": "file:///x/VDef.dpr", "dllname": "dcc64370.dll", "dccOptions": "-$O- -$R+ -DDEBUG2=3;FEATX -E.\\Win64\\Debug" } }'
[IO.File]::WriteAllText((Join-Path $lspDir 'VDef.delphilsp.json'), $json, [Text.Encoding]::ASCII)
$lspDb = Join-Path $WorkDir 'lsp.sqlite'
$null = Index $lspProj $lspDb 'lsp'
$incL = IncLeaves $lspDb
Write-Host ("  delphilsp .inc rows: {0}" -f ($incL -join ','))
Check 'delphilsp -DDEBUG2=3: A.INC indexed, B.INC not' ((Has $incL 'A.INC') -and -not (Has $incL 'B.INC'))
Check 'delphilsp -$R+: ROn.inc indexed' (Has $incL 'ROn.inc')
} finally {
  Write-Host ''
  Write-Host ("RESULT: {0} passed, {1} failed" -f $script:Passed, $script:FailedN)
}
if ($script:Failed) { exit 1 } else { exit 0 }
