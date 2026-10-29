<#
  run_index_inc_branch.ps1 -- lane INC (2026-10-27): a PROJECT DB indexes the
  {$I}/{$INCLUDE} files the build ACTUALLY includes -- branch-aware under the
  build's define profile (platform built-ins + .dproj DCC_Define) -- and parses
  each one in its includer's define context.

  Fixture tests\fixtures\inc_branch (copied to a scratch dir per run):
    app\UMain.pas   {$DEFINE HOSTFEAT} {$I Defs.inc}
                    {$IFDEF WIN32}A.INC  {$IFDEF WIN64}C.INC  {$IFDEF UNIX}B.INC
                    {$IFDEF NEVER_DEFINED_INC_X}Dead.inc
                    {$IFDEF LOCALFEAT}LocalFeat.inc   (LOCALFEAT comes from Defs.inc)
                    {$IFDEF PRO_FEATURES}..\addon\Pro.inc   (paid add-on, other folder)
                    {$I SpFound.inc}  (only on the .dproj search path vendor\lib\sp)
                    {$I Outer.inc}    (Outer.inc includes Inner.inc -- nested)
                    implementation {$I Frag.inc}  (method bodies; HOSTFEAT branch)
    app\IncBranch.dpr  {$I DprInc.inc}  (an include in the PROGRAM file)
  A/B/C all declare PlatformTag (and OnlyInA / OnlyInB / OnlyInC).

  Checks: per-platform selection (Win32 -> A only, Win64 -> C only, B in
  neither; positive control: a UNIX define gets B), inactive include never
  indexed, define propagation from an include and from the host, nested,
  search path, program-file include, fragment parsed under the HOST's defines,
  .inc positions are .inc lines, include-only edit / delete re-parses the
  includer, a DCC_Define change flips the fingerprint and picks up Pro.inc,
  and --no-preprocess keeps the old all-branch discovery. Also the closure
  self-test (selftest closure) per profile.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-inc-branch-$PID"
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
$fx = Join-Path $WorkDir 'inc_branch'
Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\inc_branch").Path $fx -Recurse
$proj = Join-Path $fx 'app\IncBranch.dproj'

function Run([string[]]$argv, [string]$tag) {
  Push-Location $WorkDir
  try { $o = & $Exe @argv 2>&1 | Out-String } finally { Pop-Location }
  [IO.File]::WriteAllText((Join-Path $WorkDir "$tag.log"), $o)
  return $o
}
function Index([string]$db, [string]$plat, [string]$tag, [string[]]$extra = @()) {
  return Run (@('index', '--project', $proj, '--db', $db, '--platform', $plat, '--library-db', 'none') + $extra) $tag
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
function SetDefines([string]$defs) {
  $t = [IO.File]::ReadAllText($proj)
  $t = [regex]::Replace($t, '<DCC_Define>BASEMARK[^<]*</DCC_Define>', "<DCC_Define>BASEMARK$defs;`$(DCC_Define)</DCC_Define>")
  [IO.File]::WriteAllText($proj, $t, [Text.Encoding]::ASCII)
}
function WriteSrc([string]$rel, [string]$text) {
  [IO.File]::WriteAllText((Join-Path $fx $rel), $text.Replace("`r`n", "`n").Replace("`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Fp([string]$db) { return (Col0 $db "SELECT value FROM schema_meta WHERE key = 'indexer_fingerprint'") -join '' }

# ---- closure self-test --------------------------------------------------------------
$cl32 = Run @('selftest', 'closure', '--project', $proj, '--platform', 'win32') 'closure32'
$leaf32 = @($cl32 -split "`r?`n" | ForEach-Object { [IO.Path]::GetFileName($_.Trim()) })
Check 'closure win32: A.INC discovered' (Has $leaf32 'A.INC')
Check 'closure win32: C.INC / B.INC / Dead.inc / Pro.inc NOT discovered' (-not ((Has $leaf32 'C.INC') -or (Has $leaf32 'B.INC') -or (Has $leaf32 'Dead.inc') -or (Has $leaf32 'Pro.inc')))
Check 'closure win32: nested Inner.inc and program-file DprInc.inc discovered' ((Has $leaf32 'Inner.inc') -and (Has $leaf32 'DprInc.inc'))
Check 'closure win32: LocalFeat.inc discovered (define from Defs.inc)' (Has $leaf32 'LocalFeat.inc')
$clRaw = Run @('selftest', 'closure', '--project', $proj, '--platform', 'win32', '--no-preprocess') 'closureRaw'
$leafRaw = @($clRaw -split "`r?`n" | ForEach-Object { [IO.Path]::GetFileName($_.Trim()) })
Check 'closure --no-preprocess: old all-branch scan keeps A, B, C and Dead' ((Has $leafRaw 'A.INC') -and (Has $leafRaw 'B.INC') -and (Has $leafRaw 'C.INC') -and (Has $leafRaw 'Dead.inc'))

# ---- Win32 DB --------------------------------------------------------------------------
$db32 = Join-Path $WorkDir 'w32.sqlite'
$log = Index $db32 'win32' 'w32'
$inc = IncLeaves $db32
Write-Host ("  win32 .inc rows: {0}" -f ($inc -join ','))
Check 'win32: A.INC indexed' (Has $inc 'A.INC')
Check 'win32: C.INC and B.INC NOT indexed' (-not ((Has $inc 'C.INC') -or (Has $inc 'B.INC')))
$tags = Col0 $db32 "SELECT f.path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.name = 'PlatformTag'"
Check 'win32: exactly one PlatformTag, declared in A.INC' (($tags.Count -eq 1) -and ([IO.Path]::GetFileName($tags[0]) -ieq 'A.INC')) "n=$($tags.Count)"
Check 'win32: Dead.inc (inactive branch) NOT indexed' (-not (Has $inc 'Dead.inc'))
Check 'win32: Pro.inc NOT indexed without PRO_FEATURES (file exists)' ((-not (Has $inc 'Pro.inc')) -and (Test-Path (Join-Path $fx 'addon\Pro.inc')))
Check 'win32: Defs.inc + LocalFeat.inc indexed (include-made define reaches the host)' ((Has $inc 'Defs.inc') -and (Has $inc 'LocalFeat.inc'))
Check 'win32: SpFound.inc indexed (search path only)' (Has $inc 'SpFound.inc')
Check 'win32: Outer.inc + nested Inner.inc indexed' ((Has $inc 'Outer.inc') -and (Has $inc 'Inner.inc'))
Check 'win32: DprInc.inc (included by the .dpr) indexed' (Has $inc 'DprInc.inc')
$innerLine = Col0 $db32 "SELECT s.start_line FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.name = 'InnerConst' AND f.path LIKE '%Inner.inc'"
Check 'win32: InnerConst sits on Inner.inc line 3 (positions are .inc lines)' (($innerLine.Count -eq 1) -and ($innerLine[0] -eq '3')) "got=$($innerLine -join ',')"
$fragRefs = Col0 $db32 "SELECT r.name_text FROM refs r JOIN files f ON f.id = r.file_id WHERE f.path LIKE '%Frag.inc'"
Check 'win32: Frag.inc parsed under the HOST defines: HostFeatOnCall ref present' (Has $fragRefs 'HostFeatOnCall') "refs=$($fragRefs -join ',')"
Check 'win32: Frag.inc parsed under the HOST defines: HostFeatOffCall ref absent' (-not (Has $fragRefs 'HostFeatOffCall'))
$onLine = Col0 $db32 "SELECT r.start_line FROM refs r JOIN files f ON f.id = r.file_id WHERE f.path LIKE '%Frag.inc' AND r.name_text = 'HostFeatOnCall'"
Check 'win32: HostFeatOnCall ref on Frag.inc line 5' (($onLine.Count -ge 1) -and ($onLine[0] -eq '5')) "got=$($onLine -join ',')"

# ---- Win64 DB --------------------------------------------------------------------------
$db64 = Join-Path $WorkDir 'w64.sqlite'
$null = Index $db64 'win64' 'w64'
$inc64 = IncLeaves $db64
Check 'win64: C.INC indexed, A.INC and B.INC NOT' ((Has $inc64 'C.INC') -and -not ((Has $inc64 'A.INC') -or (Has $inc64 'B.INC'))) "rows=$($inc64 -join ',')"
$tags64 = Col0 $db64 "SELECT f.path FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.name = 'PlatformTag'"
Check 'win64: exactly one PlatformTag, declared in C.INC' (($tags64.Count -eq 1) -and ([IO.Path]::GetFileName($tags64[0]) -ieq 'C.INC'))

# ---- incremental: no-change, include-only edit, include delete ------------------------
Start-Sleep -Milliseconds 1100
$noop = Index $db32 'win32' 'noop'
Check 'noop: a no-change reindex re-parses nothing' ($noop -match 'Done\. Files: (\d+),.*skipped \1 up-to-date') (($noop -split "`r?`n" | Where-Object { $_ -like 'Done.*' }) -join ' ')
WriteSrc 'app\A.INC' "// Win32 build only.`nconst`n  PlatformTag = 'A';`n  OnlyInA = 1;`n  OnlyInA2 = 5;`n"
Start-Sleep -Milliseconds 1100
$ed = Index $db32 'win32' 'edit'
Check 'edit A.INC only: the includer UMain.pas is re-parsed' ($ed -match 'UMain\.pas -> \d+ symbols')
$a2 = Col0 $db32 "SELECT s.name FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.name = 'OnlyInA2' AND f.path LIKE '%A.INC'"
Check 'edit A.INC only: the new constant is indexed' ($a2.Count -eq 1)
[IO.File]::Delete((Join-Path $fx 'app\LocalFeat.inc'))
Start-Sleep -Milliseconds 1100
$del = Index $db32 'win32' 'delete'
Check 'delete LocalFeat.inc: the includer UMain.pas is re-parsed' ($del -match 'UMain\.pas -> \d+ symbols')
Check 'delete LocalFeat.inc: its row is gone' (-not (Has (IncLeaves $db32) 'LocalFeat.inc'))

# ---- DCC_Define change: fingerprint flips, Pro.inc picked up --------------------------
$fp0 = Fp $db32
SetDefines ';PRO_FEATURES'
$pro = Index $db32 'win32' 'pro'
$fp1 = Fp $db32
Check 'PRO_FEATURES added to DCC_Define: indexer fingerprint changed' (($fp0 -ne '') -and ($fp0 -ne $fp1)) "$fp0 -> $fp1"
Check 'PRO_FEATURES added: Pro.inc (other folder) is now indexed' (Has (IncLeaves $db32) 'Pro.inc')

# ---- positive control: a UNIX profile gets B.INC --------------------------------------
SetDefines ';UNIX'
$dbU = Join-Path $WorkDir 'unix.sqlite'
$null = Index $dbU 'win32' 'unix'
$incU = IncLeaves $dbU
Check 'UNIX define (positive control): B.INC indexed' (Has $incU 'B.INC') "rows=$($incU -join ',')"

# ---- --no-preprocess keeps the old all-branch discovery -------------------------------
SetDefines ''
$dbR = Join-Path $WorkDir 'raw.sqlite'
$null = Index $dbR 'win32' 'raw' @('--no-preprocess')
$incR = IncLeaves $dbR
Check '--no-preprocess: all-branch includes indexed (A, B, C, Dead)' ((Has $incR 'A.INC') -and (Has $incR 'B.INC') -and (Has $incR 'C.INC') -and (Has $incR 'Dead.inc')) "rows=$($incR -join ',')"

} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("passed={0} failed={1}" -f $script:Passed, $script:FailedN)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
