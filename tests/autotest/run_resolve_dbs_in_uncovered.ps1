<#
run_resolve_dbs_in_uncovered.ps1 -- `resolve-dbs --in <file>` must SAY so when
no index covers the file (B-20, INBOX-2026-09-29-resolve-dbs-in-silent).

Measured on 1.31.4: for a file no manifest section covers, the verb printed
nothing at all and exited 0. An empty answer reads as "nothing to report",
which is the exact failure the index-first rule exists to prevent: the caller
falls back to Grep without knowing the index was never asked about this file.

Contract kept: stdout stays the DB list (empty, or [] with --json) and the exit
code stays 0, because scripts capture stdout as a path list. The explanation
goes to STDERR.

Arms:
  A  uncovered file: stdout empty, exit 0, stderr NOTE names the file
  B  uncovered file --json: stdout is exactly [], stderr NOTE names the file
  C  positive control: a covered file prints its DB and NO note
  D  positive control: a covered file --json is a one-element array, no note

Usage: pwsh -NoProfile -File tests\autotest\run_resolve_dbs_in_uncovered.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-resolve-in-uncovered-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) {'PASS'} else {'FAIL'}
  $color  = if ($Ok) {'Green'} else {'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
  Write-Host "  [FAIL] engine not found: $Exe" -ForegroundColor Red
  exit 1
}
$Exe = (Resolve-Path -LiteralPath $Exe).Path
try {
  New-Item -ItemType Directory -Path "$WorkDir\cov", "$WorkDir\other" -Force | Out-Null
  [IO.File]::WriteAllText("$WorkDir\cov\App.dproj", '<Project/>', [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText("$WorkDir\cov\A.pas", 'unit A;', [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText("$WorkDir\other\B.pas", 'unit B;', [Text.Encoding]::ASCII)
  $esc = $WorkDir -replace '\\', '\\'
  $cfg = "$WorkDir\m.json"
  [IO.File]::WriteAllText($cfg,
    ('{"indexes":{"outDir":"' + $esc + '\\out","sections":[{"name":"Cov","include":["' + $esc + '\\cov\\App.dproj"]}]}}'),
    [Text.Encoding]::ASCII)

  # Run from the work dir (under TEMP) so no .drag-lint.json up the tree joins in.
  function Invoke-In([string]$File, [switch]$Json) {
    $a = @('resolve-dbs', '--in', $File, '--config', $cfg)
    if ($Json) { $a += '--json' }
    $o = "$WorkDir\o.txt"; $e = "$WorkDir\e.txt"
    $p = Start-Process -FilePath $Exe -ArgumentList $a -NoNewWindow -Wait -PassThru -WorkingDirectory $WorkDir `
           -RedirectStandardOutput $o -RedirectStandardError $e
    [pscustomobject]@{
      Exit = $p.ExitCode
      Out  = ([IO.File]::ReadAllText($o)).Trim()
      Err  = ([IO.File]::ReadAllText($e)).Trim()
    }
  }
  $uncovered = "$WorkDir\other\B.pas"
  $covered   = "$WorkDir\cov\A.pas"
  $notePat   = 'NOTE: no index covers ' + [regex]::Escape($uncovered)

  $a = Invoke-In $uncovered
  Check 'A: uncovered file -- exit 0' ($a.Exit -eq 0) "exit=$($a.Exit)"
  Check 'A: uncovered file -- stdout empty' ($a.Out -eq '') "stdout='$($a.Out)'"
  Check 'A: uncovered file -- stderr NOTE names the file' ($a.Err -match $notePat) "stderr='$($a.Err)'"

  $b = Invoke-In $uncovered -Json
  Check 'B: uncovered --json -- stdout is []' ($b.Out -eq '[]') "stdout='$($b.Out)'"
  Check 'B: uncovered --json -- stderr NOTE names the file' ($b.Err -match $notePat) "stderr='$($b.Err)'"

  $c = Invoke-In $covered
  Check 'C: covered file -- prints its DB' ($c.Out -like '*App.sqlite') "stdout='$($c.Out)'"
  Check 'C: covered file -- no NOTE' ($c.Err -notmatch 'NOTE: no index covers') "stderr='$($c.Err)'"

  $d = Invoke-In $covered -Json
  $dArr = @()
  try { $dArr = @($d.Out | ConvertFrom-Json) } catch { $dArr = @() }
  Check 'D: covered --json -- one DB' (($dArr.Count -eq 1) -and ($dArr[0] -like '*App.sqlite')) "stdout='$($d.Out)'"
  Check 'D: covered --json -- no NOTE' ($d.Err -notmatch 'NOTE: no index covers') "stderr='$($d.Err)'"
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
