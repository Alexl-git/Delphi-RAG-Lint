<#
  reparse-libraries.ps1 -- the re-parse after a DRAGLINT_EXTRACTOR_VERSION or
  resolver bump, in the owner's order (ruling Q5, 1.43):

    phase 1  every library platform, ALL IN PARALLEL, nothing else alongside
    phase 2  every project section (their resolve pass then reads a fresh library)
    phase 3  catch-up: one more `index --all`, which should find almost nothing

  reindex-all.ps1 stays for the old all-three-at-once shape. This runner differs
  in three ways: the order above; it waits for each phase and stops if a library
  fails; and it keeps ONE file, <OutDir>\SUMMARY.txt, whose first line is the
  progress line with an ETA:

    REPARSE phase=libraries elapsed=2h10m eta=2026-11-05T14:20 (left 5h40m) | ...

  The file ends with the single line `REPARSE DONE` on success, the marker other
  sessions already wait for, or `REPARSE FAILED <why>`.

  THE ETA IS AN ESTIMATE. Per-file cost is very uneven (1.42: a file took from
  under a second to three minutes), so the parse part extrapolates from the rate
  so far, and the post-parse and project parts use -PostParseMin, -ProjectsMin
  and -CatchUpMin, measured values from the 1.42 run. A resumed run counts only
  the files it re-parses, so its ETA starts high and corrects itself.

  ALONE MEANS ALONE. The run refuses to start while another engine is running a
  long verb (index, lint-all, ...), because concurrent work cannot be told apart
  from a slow engine afterwards. -AllowBusy overrides that and the fact is written
  to the summary. It does not stop anything: stopping lanes is the integrator's call.

  SAFE TO INTERRUPT. Per-file resume means a killed run continues where it
  stopped; re-run this script with the same -OutDir.

  Usage (from any folder; run it in the background, it waits for all phases):
    pwsh -File tools\reparse-libraries.ps1 -OutDir C:\TEMP\claude\lanes\143\reparse
    pwsh -File tools\reparse-libraries.ps1 -OutDir <dir> -Status
    pwsh -File tools\reparse-libraries.ps1 -DryRun
#>
[CmdletBinding()]
param(
  [string]$Engine = '',
  [string]$OutDir = 'C:\TEMP\draglint-reparse',
  [string]$WorkDir = 'C:\Projects',
  [string[]]$Platforms = @('win32', 'win64'),
  [string]$ProjectsCsv = '',
  [int]$ProjectJobs = 4,
  [int]$PollSec = 60,
  [double]$PostParseMin = 60,
  [double]$ProjectsMin = 75,
  [double]$CatchUpMin = 3,
  [switch]$AllowBusy,
  [switch]$DryRun,
  [switch]$Status
)

$ErrorActionPreference = 'Stop'
if ($Engine -eq '') { $Engine = Join-Path $PSScriptRoot '..\third_party\dll-win64\drag-lint.exe' }
$Summary = Join-Path $OutDir 'SUMMARY.txt'

if ($Status) {
  if (Test-Path $Summary) { Get-Content $Summary } else { "no run found in $OutDir" }
  exit 0
}

function Format-Span([double]$Seconds) {
  $s = [Math]::Max(0, [int]$Seconds)
  if ($s -ge 3600) { return '{0}h{1:00}m' -f [int][Math]::Floor($s / 3600), [int][Math]::Floor(($s % 3600) / 60) }
  return '{0}m{1:00}s' -f [int][Math]::Floor($s / 60), ($s % 60)
}

# A log the engine still holds open: share everything, never lock it.
function Read-LogLines([string]$Path) {
  if (-not (Test-Path $Path)) { return @() }
  $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite,Delete')
  try {
    $sr = New-Object IO.StreamReader($fs)
    $text = $sr.ReadToEnd()
  } finally { $fs.Dispose() }
  return @($text -split "`r?`n")
}

# What one library's stdout says so far: files parsed, the running post-parse
# stage, and whether the section's closing line has been written.
function Read-LibraryProgress([string]$LogPath) {
  $parsed = 0; $stage = ''; $closed = $false
  foreach ($line in (Read-LogLines $LogPath)) {
    if ($line -match ' -> \d+ symbols, \d+ refs, \d+ errors') { $parsed++; continue }
    if ($line -match '^\s*stage: (\S+) -- started') { $stage = $Matches[1]; continue }
    if ($line -match '^=== Library .* files=\d+') { $closed = $true; continue }
  }
  return [pscustomobject]@{ Parsed = $parsed; Stage = $stage; Closed = $closed }
}

function Get-LibraryFileCount([string]$Platform) {
  # Read-only, before the run. Unknown stays 0 and the ETA says so.
  try {
    $paths = (& $Engine resolve-dbs --platform $Platform --json 2>$null) -join '' | ConvertFrom-Json
    $db = @($paths | Where-Object { $_ -match '\\library-[^\\]+\.sqlite$' }) | Select-Object -Last 1
    if (-not $db) { return 0 }
    $json = (& $Engine sql --db $db --query 'select count(*) from files' --json 2>$null) -join '' | ConvertFrom-Json
    return [int]$json.rows[0][0]    # sql --json rows are positional
  } catch { return 0 }
}

# Engines busy with a long verb. An IDE plugin's or an editor's LSP engine serves
# queries and is not load of this kind, so only the named verbs count.
function Get-BusyEngines {
  $long = 'index|lint-all|lint-project|document-all|cycles|convert-apply|reconcile-project'
  $me = $PID
  @(Get-CimInstance Win32_Process -Filter "Name='drag-lint.exe'" |
    Where-Object { $_.ProcessId -ne $me -and $_.CommandLine -match "\.exe`"?\s+($long)\b" } |
    ForEach-Object { '{0} {1}' -f $_.ProcessId, $_.CommandLine })
}

$Steps = New-Object System.Collections.Generic.List[object]
foreach ($plat in $Platforms) {
  $Steps.Add([pscustomobject]@{ Name = "library-$plat"; Phase = 'libraries'; Platform = $plat
    Args = @('index', '--all', '--only', 'Library', '--platform', $plat, '--jobs', '1', '--rule-cache-warm', 'off')
    Proc = $null; Exit = $null; Started = $null; Ended = $null; Total = 0 })
}

if ($ProjectsCsv -eq '' -and -not (Test-Path $Engine)) { throw "engine not found: $Engine" }
if ($ProjectsCsv -eq '') {
  $manifest = Join-Path (Split-Path $Engine -Parent) 'drag-lint.json'
  $j = Get-Content $manifest -Raw | ConvertFrom-Json
  $ProjectsCsv = (@($j.indexes.sections | Where-Object { $_.name -ne 'Library' } | ForEach-Object { $_.name })) -join ','
}
$ProjectCount = @($ProjectsCsv -split ',').Count
$Steps.Add([pscustomobject]@{ Name = 'projects'; Phase = 'projects'; Platform = ''
  Args = @('index', '--all', '--only', $ProjectsCsv, '--jobs', "$ProjectJobs", '--rule-cache-warm', 'off')
  Proc = $null; Exit = $null; Started = $null; Ended = $null; Total = $ProjectCount })
$Steps.Add([pscustomobject]@{ Name = 'catchup'; Phase = 'catchup'; Platform = ''
  Args = @('index', '--all', '--jobs', "$ProjectJobs", '--rule-cache-warm', 'off')
  Proc = $null; Exit = $null; Started = $null; Ended = $null; Total = 0 })

if ($DryRun) {
  foreach ($s in $Steps) { '{0,-10} {1,-14} {2} {3}' -f $s.Phase, $s.Name, $Engine, (($s.Args | ForEach-Object { if ($_.Length -gt 60) { $_.Substring(0, 57) + '...' } else { $_ } }) -join ' ') }
  exit 0
}

if (-not (Test-Path $Engine)) { throw "engine not found: $Engine" }
[void][IO.Directory]::CreateDirectory($OutDir)

$Notes = New-Object System.Collections.Generic.List[string]
$busy = @(Get-BusyEngines)
if ($busy.Count -gt 0) {
  $msg = "$($busy.Count) other engine(s) busy at the start"
  if (-not $AllowBusy) {
    $text = @("REPARSE REFUSED $msg (-AllowBusy overrides)") + $busy
    [IO.File]::WriteAllLines($Summary, [string[]]$text)
    $text | ForEach-Object { Write-Host $_ }
    exit 3
  }
  $Notes.Add("NOT ALONE: $msg; timings are not comparable")
}

foreach ($s in $Steps) {
  if ($s.Phase -eq 'libraries') { $s.Total = Get-LibraryFileCount $s.Platform }
}

$T0 = Get-Date

function Start-Step($Step) {
  $log = Join-Path $OutDir "$($Step.Name).log"
  foreach ($f in @($log, "$log.err")) { if (Test-Path $f) { [IO.File]::Delete($f) } }
  $Step.Started = Get-Date
  $Step.Proc = Start-Process -FilePath $Engine -ArgumentList $Step.Args -WorkingDirectory $WorkDir -PassThru `
    -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError "$log.err"
  [void]$Step.Proc.Handle   # keeps ExitCode readable after the process ended
}

# Seconds this step still needs, from its log. Finished steps need none.
function Get-StepLeft($Step) {
  if ($null -ne $Step.Exit) { return 0.0 }
  switch ($Step.Phase) {
    'libraries' {
      if ($null -eq $Step.Started) { return ($PostParseMin * 60) }
      $p = Read-LibraryProgress (Join-Path $OutDir "$($Step.Name).log")
      $el = ((Get-Date) - $Step.Started).TotalSeconds
      if ($p.Stage -ne '') { return [Math]::Max(60, ($PostParseMin * 60) - ($el - $Step.ParseSec)) }
      if ($p.Parsed -le 0 -or $Step.Total -le 0) { return -1.0 }   # unknown yet
      return ([Math]::Max(0, $Step.Total - $p.Parsed) * $el / $p.Parsed) + ($PostParseMin * 60)
    }
    'projects' {
      if ($null -eq $Step.Started) { return ($ProjectsMin * 60) }
      return [Math]::Max(60, ($ProjectsMin * 60) - ((Get-Date) - $Step.Started).TotalSeconds)
    }
    default {
      if ($null -eq $Step.Started) { return ($CatchUpMin * 60) }
      return [Math]::Max(30, ($CatchUpMin * 60) - ((Get-Date) - $Step.Started).TotalSeconds)
    }
  }
}

function Get-StepLine($Step) {
  if ($null -eq $Step.Started) { return '{0,-14} waiting' -f $Step.Name }
  $endAt = if ($null -ne $Step.Ended) { $Step.Ended } else { Get-Date }
  $el = Format-Span (($endAt - $Step.Started).TotalSeconds)
  $state = if ($null -ne $Step.Exit) { "exit=$($Step.Exit)" } else { 'running' }
  $log = Join-Path $OutDir "$($Step.Name).log"
  if ($Step.Phase -eq 'libraries') {
    $p = Read-LibraryProgress $log
    $tot = if ($Step.Total -gt 0) { "$($Step.Total)" } else { '?' }
    $parseSec = if ($Step.ParseSec -gt 0) { $Step.ParseSec } else { ($endAt - $Step.Started).TotalSeconds }
    $rate = if ($p.Parsed -gt 0) { '{0:N2} s/file' -f ($parseSec / $p.Parsed) } else { 'no rate yet' }
    $stage = if ($p.Stage -ne '') { " stage=$($p.Stage)" } else { '' }
    return '{0,-14} {1} {2} parsed {3}/{4} {5}{6}' -f $Step.Name, $state, $el, $p.Parsed, $tot, $rate, $stage
  }
  if ($Step.Phase -eq 'projects') {
    $done = @(Read-LogLines $log | Where-Object { $_ -match '^=== .* files=\d+' }).Count
    return '{0,-14} {1} {2} sections {3}/{4}' -f $Step.Name, $state, $el, $done, $Step.Total
  }
  return '{0,-14} {1} {2}' -f $Step.Name, $state, $el
}

function Write-Summary([string]$Phase, [string]$Tail) {
  $left = 0.0; $unknown = $false
  $libLeft = 0.0
  foreach ($s in $Steps) {
    $l = Get-StepLeft $s
    if ($l -lt 0) { $unknown = $true; continue }
    if ($s.Phase -eq 'libraries') { $libLeft = [Math]::Max($libLeft, $l) } else { $left += $l }
  }
  $left += $libLeft
  $elapsed = Format-Span ((Get-Date) - $T0).TotalSeconds
  $eta = if ($unknown) { 'eta=unknown (no rate yet)' }
         elseif ($Phase -in 'done', 'failed') { 'eta=-' }
         else { 'eta={0:yyyy-MM-ddTHH:mm} (left {1})' -f (Get-Date).AddSeconds($left), (Format-Span $left) }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("REPARSE phase=$Phase elapsed=$elapsed $eta | updated $(Get-Date -Format s)")
  $lines.Add("started $($T0.ToString('s'))  engine $Engine")
  foreach ($n in $Notes) { $lines.Add($n) }
  foreach ($s in $Steps) { $lines.Add((Get-StepLine $s)) }
  if ($Tail -ne '') { $lines.Add($Tail) }
  # Whole-file replace: a reader never sees half a summary.
  $tmp = "$Summary.tmp"
  [IO.File]::WriteAllLines($tmp, [string[]]$lines)
  [IO.File]::Copy($tmp, $Summary, $true)
  [IO.File]::Delete($tmp)
}

# Starts the steps of one phase, waits for them all, returns the failed names.
function Invoke-Phase([string]$Phase) {
  $mine = @($Steps | Where-Object { $_.Phase -eq $Phase })
  foreach ($s in $mine) { Start-Step $s }
  while ($true) {
    $running = 0
    foreach ($s in $mine) {
      if ($null -ne $s.Exit) { continue }
      if ($s.Proc.HasExited) {
        $s.Proc.WaitForExit()
        $s.Exit = $s.Proc.ExitCode
        $s.Ended = Get-Date
        continue
      }
      $running++
      if ($s.Phase -eq 'libraries' -and $s.ParseSec -eq 0) {
        $p = Read-LibraryProgress (Join-Path $OutDir "$($s.Name).log")
        if ($p.Stage -ne '') { $s.ParseSec = ((Get-Date) - $s.Started).TotalSeconds }
      }
    }
    Write-Summary $Phase ''
    if ($running -eq 0) { break }
    Start-Sleep -Seconds $PollSec
  }
  return @($mine | Where-Object { $_.Exit -ne 0 } | ForEach-Object { "$($_.Name)=$($_.Exit)" })
}

foreach ($s in $Steps) { $s | Add-Member -NotePropertyName ParseSec -NotePropertyValue 0.0 }

foreach ($phase in @('libraries', 'projects', 'catchup')) {
  $failed = @(Invoke-Phase $phase)
  if ($failed.Count -gt 0) {
    Write-Summary 'failed' "REPARSE FAILED in phase $phase`: $($failed -join ', ') (per-file resume: fix, then re-run with the same -OutDir)"
    Write-Host "REPARSE FAILED in phase $phase`: $($failed -join ', ')"
    exit 1
  }
}
Write-Summary 'done' 'REPARSE DONE'
Write-Host 'REPARSE DONE'
exit 0
