<#
  run_with_fix_after_proof.ps1 -- 1.52.2 Q8 (owner ruling 2026-11-19): the with fixer of `lint --fix` (fix-all, the path
  without --fix-rule; the IDE's Fix all in unit) runs the unwith AFTER proof before it hands out an edit: the rewritten
  file is re-indexed into a COPY of the DB and every ref of the rewritten body must bind to what it bound before. Any
  difference declines the fix; the source file is left byte-identical.

  Fixture tests\fixtures\refactor\unwith (UwCases.pas, the silent-rebind case at `with M do Writeln('silent-rebind ' ...`).
  (a) DECLINE: test seam DRAGLINT_UNWITH_TEST_SKIP_PREFIX=Count leaves `Count` bare where the closure says prefix, so it
      would bind to the routine's local. `lint --fix --apply --fix-line <with>` must decline: file byte-identical, the
      note names rebind-after and Count, the real DB untouched, no after-proof copy left behind.
  (b) APPLY (positive control): the same command without the seam rewrites the with: no `with M do` on that line,
      `M.Count + M.Value` present, ASCII + CRLF kept.
  --no-compile-gate: the proof is under test, not the build (run_unwith covers the gate); no dcc needed. SKIPs when the platform library is missing.
#>
[CmdletBinding()]
param(
  [string]$Exe       = '',
  [string]$WorkDir   = "$env:TEMP\drag-lint-withfixproof-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepScratch
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green; $script:Passed++ }
  else { Write-Host "  [FAIL] $n" -ForegroundColor Red; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixture = Join-Path $Repo 'tests\fixtures\refactor\unwith'

function New-Copy([string]$Name) {
  $d = Join-Path $WorkDir $Name
  [IO.Directory]::CreateDirectory($d) | Out-Null
  Copy-Item "$Fixture\*" $d -Recurse -Force
  $env:UW_HIDDEN = ''
  $null = & { $ErrorActionPreference = 'Continue'; & $Exe index --project "$d\UwDemo.dproj" --db "$d\uw.sqlite" 2>&1 | ForEach-Object { "$_" } }
  if ($LASTEXITCODE -ne 0) { throw "index failed in $d" }
  return $d
}
function Hash-Of([string]$Path) { return (Get-FileHash $Path -Algorithm SHA256).Hash }
function With-Line([string]$Dir) {
  $Src = [IO.File]::ReadAllLines("$Dir\UwCases.pas")
  for ($i = 0; $i -lt $Src.Count; $i++) { if ($Src[$i] -match "silent-rebind '") { return $i } }  # 0-based body = 1-based with line
  throw 'silent-rebind site not found in the fixture'
}
function Invoke-Fix([string]$Dir, [int]$Line) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe lint --in "$Dir\UwCases.pas" --db "$Dir\uw.sqlite" --library-db $LibraryDb --enable with-statement --fix --fix-line $Line --apply --no-compile-gate 2>&1 | ForEach-Object { "$_" } }
  return ($o -join "`n")
}

try {
  [IO.Directory]::CreateDirectory($WorkDir) | Out-Null

  # (a) the fix would rebind Count to the local: declined, nothing written
  $D = New-Copy 'decline'
  $L = With-Line $D
  $Before = Hash-Of "$D\UwCases.pas"
  $DbBefore = Hash-Of "$D\uw.sqlite"
  $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = 'Count'
  try { $Out = Invoke-Fix $D $L } finally { $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = '' }
  Check '(a) the file is byte-identical (fix declined)' ((Hash-Of "$D\UwCases.pas") -eq $Before) $Out
  Check '(a) the note says declined, rebind-after' ($Out -match 'declined' -and $Out -match 'rebind-after') $Out
  Check '(a) the note names the rebound name Count' ($Out -match 'Count: ') $Out
  Check '(a) the real DB is not written' ((Hash-Of "$D\uw.sqlite") -eq $DbBefore)
  $Left = @(Get-ChildItem -LiteralPath 'C:\TEMP' -Recurse -Depth 1 -Filter 'after-proof.sqlite' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) -and $_.FullName -match '_unwithfix' })
  Check '(a) no after-proof DB copy left behind' ($Left.Count -eq 0) (($Left | ForEach-Object FullName) -join '; ')

  # (b) positive control: the honest rewrite proves and applies
  $D = New-Copy 'apply'
  $L = With-Line $D
  $Out = Invoke-Fix $D $L
  $Bytes = [IO.File]::ReadAllBytes("$D\UwCases.pas")
  $Text = [Text.Encoding]::ASCII.GetString($Bytes)
  $Lines = [IO.File]::ReadAllLines("$D\UwCases.pas")
  Check '(b) the with is gone' (-not ($Lines[$L - 1] -match '^\s*with M do')) "$($Lines[$L - 1]) || $Out"
  Check '(b) every member carries its prefix' ($Text -match "M\.Count \+ M\.Value") $Out
  Check '(b) ASCII kept' (-not ($Bytes | Where-Object { $_ -gt 127 }))
  Check '(b) CRLF kept (no bare LF)' (-not ($Text -match "[^`r]`n"))
}
finally {
  $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = ''
  $env:UW_HIDDEN = ''
  if (-not $KeepScratch -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ''
if ($script:Failed) { Write-Host "run_with_fix_after_proof: FAIL ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "run_with_fix_after_proof: PASS ($script:Passed checks)" -ForegroundColor Green
exit 0
