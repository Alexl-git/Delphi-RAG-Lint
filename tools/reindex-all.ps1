<#
  reindex-all.ps1 -- rebuild every index, with the two library platforms in
  parallel.

  WHY THIS EXISTS: a release bump changes DRAGLINT_VERSION, which is part of the
  indexer fingerprint, so EVERY database re-parses in full on its first run under
  the new build. That is the state after v1.4.0-alpha.

  WHAT IT RUNS -- three concurrent processes:

    A  every PROJECT section          ~2,100 files   tens of minutes
    B  Library[Win32]                 thousands      HOURS
    C  Library[Win64]                 ~7,000 files   HOURS

  Projects first-class and separate on purpose: they are what the IDE needs to
  be useful on your own code, and they finish while the libraries are still
  going.

  WHY TWO MANIFESTS. `--only` filters by section NAME, and both platform
  expansions of the library share the name "Library", so `--only Library` selects
  both and runs them sequentially in one process. To get them in parallel each
  needs a manifest whose Library section lists a single platform. That is all the
  generated copies change.

  BOTH LIBRARY RUNS USE THE Win64 ENGINE. The platform being INDEXED and the
  bitness of the exe doing the indexing are different things. The Win32 exe is a
  frozen 2026-07-05 fallback and runs out of address space on a multi-gigabyte
  index -- never point this at it.

  SAFE TO INTERRUPT. Per-file resume means a killed run continues where it
  stopped rather than restarting, and the database-level stamp is only written
  when a walk completes, so an interrupted run costs time and nothing else.

  Usage:
    pwsh -File tools\reindex-all.ps1              # start all three
    pwsh -File tools\reindex-all.ps1 -ProjectsOnly
    pwsh -File tools\reindex-all.ps1 -Status      # progress of a running set
#>
[CmdletBinding()]
param(
  [switch]$ProjectsOnly,
  [switch]$Status,
  [int]$Jobs   = 3,
  [string]$LogDir = 'C:\TEMP\draglint-reindex'
)

$ErrorActionPreference = 'Stop'
$engineDir = (Resolve-Path "$PSScriptRoot\..\third_party\dll-win64").Path
$exe       = Join-Path $engineDir 'drag-lint.exe'
$manifest  = Join-Path $engineDir 'drag-lint.json'

if ($Status) {
  Write-Host ''
  if (-not (Test-Path $LogDir)) { Write-Host "no run found in $LogDir"; exit 0 }
  foreach ($f in Get-ChildItem $LogDir -Filter *.log | Sort-Object Name) {
    $txt  = Get-Content $f.FullName -ErrorAction SilentlyContinue
    $done = @($txt | Select-String '^=== ').Count
    $last = ($txt | Select-Object -Last 1)
    "{0,-12} sections done={1,-4} {2}" -f $f.BaseName, $done, ("$last" -replace '\s+', ' ').Trim()
  }
  Write-Host ''
  "engine processes running: {0}" -f @(Get-Process drag-lint -ErrorAction SilentlyContinue).Count
  exit 0
}

if (-not (Test-Path $exe)) { throw "engine not found: $exe" }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$j = Get-Content $manifest -Raw | ConvertFrom-Json
$projectSections = @($j.indexes.sections | Where-Object { $_.name -ne 'Library' } | ForEach-Object { $_.name })
Write-Host ("{0} project section(s), plus Library x {1} platform(s)" -f `
  $projectSections.Count, (@($j.indexes.sections | Where-Object { $_.name -eq 'Library' }).platforms.Count)) -ForegroundColor Cyan

function Launch([string]$Name, [string[]]$ArgList) {
  $log = Join-Path $LogDir "$Name.log"
  if (Test-Path $log) { Remove-Item $log -Force }
  # -NoNewWindow keeps it attached to this console's job; the process still
  # outlives this script. Output goes to the log because these runs are long and
  # PowerShell holds a native process's stderr until it exits.
  $p = Start-Process -FilePath $exe -ArgumentList $ArgList -WorkingDirectory $engineDir `
                     -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  "  {0,-12} pid {1}  -> {2}" -f $Name, $p.Id, $log
}

Write-Host ''
Write-Host 'starting:' -ForegroundColor Cyan

# A -- every project section, one process, sequential inside it.
Launch 'projects' @('index', '--all', '--only', ($projectSections -join ','), '--jobs', $Jobs)

if (-not $ProjectsOnly) {
  # B and C -- one manifest per platform so they can run at the same time.
  foreach ($plat in @('Win32', 'Win64')) {
    $copy = Get-Content $manifest -Raw | ConvertFrom-Json
    foreach ($s in $copy.indexes.sections) {
      if ($s.name -eq 'Library') { $s.platforms = @($plat) }
    }
    $cfg = Join-Path $LogDir "manifest-$plat.json"
    $copy | ConvertTo-Json -Depth 12 | Set-Content $cfg -Encoding ascii
    Launch ("library-$plat") @('index', '--all', '--config', $cfg, '--only', 'Library', '--jobs', $Jobs)
  }
}

Write-Host ''
Write-Host 'monitor:' -ForegroundColor Cyan
Write-Host "   pwsh -File tools\reindex-all.ps1 -Status"
Write-Host "   Get-Content $LogDir\projects.log -Tail 5"
Write-Host ''
Write-Host 'The PROJECT sections are what the IDE needs; they finish first.' -ForegroundColor Yellow
Write-Host 'The two library walks take HOURS. They are resumable -- killing them is safe.' -ForegroundColor Yellow
