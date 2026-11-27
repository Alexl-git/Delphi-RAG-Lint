#Requires -Version 7
<#
  run_v1541_REPOBKMSG.ps1 -- 1.54.1 INT: `repo backup --repo X <a flag the text backup does not take>` says what to do.

  A flag the text backup of the repository does not take (e.g. --json) turned the command line into a database
  backup, which then answered "--repo does not go with a database backup" -- although nobody asked for one. The
  error now names the flag and the way out; --repo with --connection says which of the two to drop.
  No database is touched: every case is refused before anything is read.

  Usage: pwsh -File tests\autotest\run_v1541_REPOBKMSG.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "SKIP: engine not found: $Exe"; exit 0 }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:Pass++; Write-Host "  PASS  $Name" } else { $script:Fail++; Write-Host "  FAIL  $Name  $Detail" }
}
function Run([string[]]$a) {
  $o = & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>&1 | ForEach-Object { "$_" } }
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = (($o | ForEach-Object { "$_" }) -join "`n") }
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v1541-repobkmsg-' + $PID)
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
  $repo = Join-Path $work 'x.dlrepo'
  $null = Run @('repo', 'init', '--repo', $repo)

  $r = Run @('repo', 'backup', '--repo', $repo, '--json')
  Check 'm1 --repo --json -> exit 1'                        ($r.Code -eq 1) $r.Out
  Check 'm2 ... does not speak of a database backup nobody asked for' ($r.Out -notmatch 'does not go with a database backup') $r.Out
  Check 'm3 ... names the flag and says to drop it'         (($r.Out -match '--json is not supported') -and ($r.Out -match 'drop --json')) $r.Out
  Check 'm4 ... names what the text backup takes'           ($r.Out -match 'only the database backup, with --connection, prints JSON') $r.Out
  Check 'm5 ... wrote no text backup'                       (-not (Test-Path -LiteralPath "$repo.txt"))

  $r = Run @('repo', 'backup', '--repo', $repo, '--connection', 'Database=C:\x.fdb;User_Name=SYSDBA;Password=pw')
  Check 'm6 --repo with --connection -> exit 1, says which to drop' (($r.Code -eq 1) -and ($r.Out -match 'drop --connection') -and ($r.Out -match 'drop --repo')) $r.Out

  $r = Run @('repo', 'backup', '--repo', $repo)
  Check 'm7 positive control: --repo alone is still the text backup' (($r.Code -eq 0) -and (Test-Path -LiteralPath "$repo.txt")) $r.Out
}
finally { try { [IO.Directory]::Delete($work, $true) } catch { } }
Write-Host ("run_v1541_REPOBKMSG: {0} pass, {1} failure(s)" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { exit 1 }
exit 0
