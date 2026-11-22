<#
  run_unwith_disk_proof.ps1 -- 1.52.3 UNWITH-DISK: the unwith AFTER proof that the with fixer of `lint --fix` runs
  (UnwithProveFile) never writes the user's source file. Up to 1.52.2 it wrote the rewrite over the file, re-indexed,
  then restored the same bytes and last-write time -- so a dry run touched the file, and an editor, a watcher or a crash
  in between saw the rewrite. Now the rewrite is proven on a COPY in the run's scratch folder.

  Fixture tests\fixtures\refactor\unwith (UwCases.pas, the silent-rebind case). A FileSystemWatcher on the fixture copy
  counts every write to UwCases.pas while the command runs.
  (a) DRY RUN (`lint --fix --fix-line <with>`, no --apply): zero write events, bytes + mtime unchanged, and the proof
      ran and held (positive control: no "declined" note, the proposed edit carries M.Count + M.Value).
  (b) APPLY, PROOF DECLINES (seam DRAGLINT_UNWITH_TEST_SKIP_PREFIX=Count): zero write events, bytes + mtime unchanged,
      the note names rebind-after -- the proof on the copy still catches the rebind (not vacuous).
  (c) APPLY, PROOF HOLDS (positive control): the rewrite lands.
  SKIPs when the platform library is missing.
#>
[CmdletBinding()]
param(
  [string]$Exe       = '',
  [string]$WorkDir   = "$env:TEMP\drag-lint-unwithdisk-$PID",
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
# Runs the fix under a watcher; returns @(output, writeEventCount).
function Invoke-Watched([string]$Dir, [int]$Line, [switch]$Apply) {
  $W = New-Object IO.FileSystemWatcher $Dir, 'UwCases.pas'
  $W.NotifyFilter = [IO.NotifyFilters]'LastWrite, Size, FileName, CreationTime'
  $Src = "uwdisk-$([guid]::NewGuid())"
  $null = Register-ObjectEvent -InputObject $W -EventName Changed -SourceIdentifier "$Src-c"
  $null = Register-ObjectEvent -InputObject $W -EventName Renamed -SourceIdentifier "$Src-r"
  $null = Register-ObjectEvent -InputObject $W -EventName Deleted -SourceIdentifier "$Src-d"
  $W.EnableRaisingEvents = $true
  try {
    $A = @('lint', '--in', "$Dir\UwCases.pas", '--db', "$Dir\uw.sqlite", '--library-db', $LibraryDb, '--enable', 'with-statement',
           '--fix', '--fix-line', "$Line", '--no-compile-gate')
    if ($Apply) { $A += '--apply' }
    $o = & { $ErrorActionPreference = 'Continue'; & $Exe @A 2>&1 | ForEach-Object { "$_" } }
    Start-Sleep -Milliseconds 500   # let the watcher deliver
    $n = @(Get-Event | Where-Object { $_.SourceIdentifier -like "$Src-*" }).Count
  }
  finally {
    $W.EnableRaisingEvents = $false
    foreach ($s in 'c', 'r', 'd') { Unregister-Event -SourceIdentifier "$Src-$s" -ErrorAction SilentlyContinue }
    Get-Event | Where-Object { $_.SourceIdentifier -like "$Src-*" } | ForEach-Object { $null = Remove-Event -EventIdentifier $_.EventIdentifier }
    $W.Dispose()
  }
  return @(($o -join "`n"), $n)
}

try {
  [IO.Directory]::CreateDirectory($WorkDir) | Out-Null

  # (a) dry run: the proof runs, holds, and never touches the file
  $D = New-Copy 'dry'
  $L = With-Line $D
  $Before = Hash-Of "$D\UwCases.pas"
  $Stamp = [IO.File]::GetLastWriteTimeUtc("$D\UwCases.pas")
  $R = Invoke-Watched $D $L
  Check '(a) dry run: no write event on the source during the run' ($R[1] -eq 0) "events=$($R[1]) || $($R[0])"
  Check '(a) dry run: bytes unchanged' ((Hash-Of "$D\UwCases.pas") -eq $Before)
  Check '(a) dry run: last-write time unchanged' ([IO.File]::GetLastWriteTimeUtc("$D\UwCases.pas") -eq $Stamp)
  Check '(a) dry run: the proof held (no declined note)' (-not ($R[0] -match 'declined')) $R[0]
  Check '(a) dry run: the proposed edit qualifies the members' ($R[0] -match 'M\.Count \+ M\.Value') $R[0]

  # (b) apply, the proof declines: nothing is ever written
  $D = New-Copy 'decline'
  $L = With-Line $D
  $Before = Hash-Of "$D\UwCases.pas"
  $Stamp = [IO.File]::GetLastWriteTimeUtc("$D\UwCases.pas")
  $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = 'Count'
  try { $R = Invoke-Watched $D $L -Apply } finally { $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = '' }
  Check '(b) declined apply: no write event on the source during the run' ($R[1] -eq 0) "events=$($R[1]) || $($R[0])"
  Check '(b) declined apply: bytes unchanged' ((Hash-Of "$D\UwCases.pas") -eq $Before)
  Check '(b) declined apply: last-write time unchanged' ([IO.File]::GetLastWriteTimeUtc("$D\UwCases.pas") -eq $Stamp)
  Check '(b) the proof on the copy still catches the rebind' ($R[0] -match 'declined' -and $R[0] -match 'rebind-after' -and $R[0] -match 'Count: ') $R[0]

  # (c) positive control: the proven rewrite is applied
  $D = New-Copy 'apply'
  $L = With-Line $D
  $R = Invoke-Watched $D $L -Apply
  $Lines = [IO.File]::ReadAllLines("$D\UwCases.pas")
  Check '(c) apply: the with is gone' (-not ($Lines[$L - 1] -match '^\s*with M do')) "$($Lines[$L - 1]) || $($R[0])"
  Check '(c) apply: the members carry their prefix' (([IO.File]::ReadAllText("$D\UwCases.pas")) -match 'M\.Count \+ M\.Value') $R[0]
  Check '(c) apply: the source was written' ($R[1] -gt 0) "events=$($R[1])"
}
finally {
  $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = ''
  $env:UW_HIDDEN = ''
  if (-not $KeepScratch -and (Test-Path $WorkDir)) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ''
if ($script:Failed) { Write-Host "run_unwith_disk_proof: FAIL ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "run_unwith_disk_proof: PASS ($script:Passed checks)" -ForegroundColor Green
exit 0
