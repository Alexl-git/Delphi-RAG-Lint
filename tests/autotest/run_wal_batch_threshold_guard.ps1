<#
  run_wal_batch_threshold_guard.ps1 -- PARSE-THROUGHPUT (1.43).

  A CLI walk must raise wal_autocheckpoint for its connection: at the default
  1000 pages every group commit of a re-parse ran a checkpoint, 55-70% of the walk
  on a 33-file sample. The engine prints the value SQLite itself
  returned for the pragma under DRAGLINT_PROFILE, so this reads the connection's
  state rather than the source.

  Positive control: -ControlExe <engine built before the fix> must FAIL check A.
  Also pinned: the run still leaves a self-contained main file (Checkpoint folds a
  WAL that the raised threshold kept large), and a second walk over the same files
  works, because a statement left in progress by the pragma would fail its commits.
#>
param([string]$Engine = '', [string]$Scratch = '', [string]$ControlExe = '')

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Engine -eq '') { $Engine = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe' }
if ($ControlExe -ne '') { $Engine = $ControlExe }
if ($Scratch -eq '') { $Scratch = Join-Path ([IO.Path]::GetTempPath()) "wal_batch_guard_$PID" }
$src = Join-Path $Scratch 'src'
[void][IO.Directory]::CreateDirectory($src)
$db = Join-Path $Scratch 'g.sqlite'
foreach ($f in @($db, "$db-wal", "$db-shm")) { if (Test-Path $f) { [IO.File]::Delete($f) } }

foreach ($i in 1..3) {
  $text = "unit U$i;`r`ninterface`r`nprocedure P$i;`r`nimplementation`r`nprocedure P$i;`r`nbegin`r`nend;`r`nend.`r`n"
  [IO.File]::WriteAllText((Join-Path $src "U$i.pas"), $text, (New-Object Text.ASCIIEncoding))
}

$fails = 0; $passes = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:passes++; "PASS $Name" }
  else { $script:fails++; "FAIL $Name $Detail" }
}

function Invoke-Index([string[]]$Extra) {
  $env:DRAGLINT_PROFILE = '1'
  $o = Join-Path $Scratch 'o.txt'; $e = Join-Path $Scratch 'e.txt'
  $args2 = @('index', "`"$src`"", '--db', "`"$db`"", '--rule-cache-warm', 'off') + $Extra
  $p = Start-Process $Engine -ArgumentList $args2 -RedirectStandardOutput $o -RedirectStandardError $e -PassThru -WindowStyle Hidden -WorkingDirectory $Scratch
  [void]$p.Handle
  $p.WaitForExit()
  $env:DRAGLINT_PROFILE = ''
  [pscustomobject]@{ Exit = $p.ExitCode; Err = [IO.File]::ReadAllText($e) }
}

function Get-FileCount {
  $j = (& $Engine sql --db $db --query 'select count(*) from files' --json 2>$null) -join '' | ConvertFrom-Json
  [int]$j.rows[0][0]    # sql --json rows are positional
}

$r = Invoke-Index @()
Check 'A a walk raises wal_autocheckpoint, as SQLite reports it' ($r.Err -match 'file batch: wal_autocheckpoint 65536 page\(s\)') ($r.Err.Substring(0, [Math]::Min(300, $r.Err.Length)))
Check 'B first walk exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
$walLen = if (Test-Path "$db-wal") { ([IO.FileInfo]"$db-wal").Length } else { 0 }
Check 'C the WAL was folded into the main file' ($walLen -eq 0) "wal=$walLen bytes"
Check 'D the rows are there' ((Get-FileCount) -eq 3)
$r = Invoke-Index @('--force-reparse')
Check 'E a re-parse over existing rows commits' ($r.Exit -eq 0 -and $r.Err -notmatch 'statements in progress') "exit=$($r.Exit)"
Check 'F still three files' ((Get-FileCount) -eq 3)

"run_wal_batch_threshold_guard: $passes passed, $fails failed"
if ($fails -gt 0) { exit 1 }
exit 0
