<#
  run_comment_facts_parity.ps1 -- wave 151 lane W1, acceptance (b): the
  comment_facts producer (src\index\DRagLint.Index.CommentFacts.pas) carries the
  SAME `///` doc blocks, dl:ok markers and dl:bk anchors that today's scanners
  (Parser.DocComments / Lint.ReviewMarker / Lint.Bookmarks) compute, on every
  Pascal file under the roots (default: the repo's src\ plus the W1 fixture).

  Builds tests\fixtures\comment-facts-151\harness\CommentFactsParity.dpr with
  dcc64 into a TEMP work dir (nothing is written into the tree), runs it, and:
    P1  harness builds
    P2  parity run: mismatches=0, exit 0
    P3  non-vacuous: >= 1000 `///` blocks, >= 50 dl:ok markers, >= 1 dl:bk
        anchor on BOTH sides
    PC1 positive control: --drop-kind '//' -> exit 1 with OK mismatches
    PC2 positive control: --drop-kind '///' -> exit 1 with DOC mismatches
  The SUMMARY line's extract_ms is the producer's own cost (acceptance (c)).

  -SearchFirst <dir>: a directory put FIRST on the unit path, e.g. one holding
  the 151 ST stub of DRagLint.Index.CommentFacts.pas -- the RED run (P2 fails).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string[]]$Roots = @(), [string]$SearchFirst = '')

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { Write-Host 'run_comment_facts_parity: needs pwsh 7' -ForegroundColor Red; exit 2 }
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if ($Roots.Count -eq 0) { $Roots = @((Join-Path $repo 'src'), (Join-Path $repo 'tests\fixtures\comment-facts-151\src')) }
$work = Join-Path $env:TEMP ('dl-cf-parity-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

$script:fail = 0
$script:pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "  PASS  $Name  $Detail" -ForegroundColor Green }
  else     { $script:fail++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}

# ---- P1 build ---------------------------------------------------------------
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$dirs = @('core', 'parser', 'lint', 'index') | ForEach-Object { Join-Path $repo "src\$_" }
if ($SearchFirst -ne '') { $dirs = @($SearchFirst) + $dirs }
$harnessDir = Join-Path $repo 'tests\fixtures\comment-facts-151\harness'
$bat = Join-Path $work 'build.bat'
$log = Join-Path $work 'build.log'
$batText = @(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$harnessDir`""
  "dcc64 -B -Q -U`"$($dirs -join ';')`" -E`"$work`" -N0`"$work`" CommentFactsParity.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%'
) -join "`r`n"
[IO.File]::WriteAllText($bat, $batText, [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
$blog = Get-Content $log -Raw -ErrorAction SilentlyContinue
$exe = Join-Path $work 'CommentFactsParity.exe'
$built = ($blog -match 'BUILD_EXITCODE=0') -and ($blog -notmatch '(?m)\bError\b|Fatal:') -and (Test-Path $exe)
Check 'P1 CommentFactsParity.dpr builds (dcc64)' $built $(if ($built) { '' } else { (($blog -split "`r?`n" | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 5) -join ' | ') })
if (-not $built) { Write-Host "run_comment_facts_parity: 0 passed, 1 failed (build log $log)" -ForegroundColor Red; exit 1 }

function Run-Harness([string[]]$HArgs) {
  $out = & $exe @HArgs 2>&1 | ForEach-Object { "$_" }
  [pscustomobject]@{ Rc = $LASTEXITCODE; Lines = @($out); Summary = (@($out) | Where-Object { $_ -like 'SUMMARY *' } | Select-Object -Last 1) }
}
function Summary-Field([string]$Summary, [string]$Name) {
  if ($Summary -match "\b$Name=(\d+)(?:/(\d+))?") { return @([int]$Matches[1], $(if ($Matches[2]) { [int]$Matches[2] } else { -1 })) }
  return @(-1, -1)
}

# ---- P2 / P3 parity -----------------------------------------------------------
$r = Run-Harness $Roots
Write-Host "  INFO  $($r.Summary)"
$r.Lines | Where-Object { $_ -like 'FATAL *' } | ForEach-Object { Write-Host "        $_" -ForegroundColor Red }
$mm = Summary-Field $r.Summary 'mismatches'
Check 'P2 parity: no tuple on one side only' (($r.Rc -eq 0) -and ($mm[0] -eq 0)) "(rc $($r.Rc), mismatches $($mm[0]))"
if ($mm[0] -gt 0) { $r.Lines | Where-Object { $_ -like 'MISMATCH *' } | Select-Object -First 15 | ForEach-Object { $s = "$_"; if ($s.Length -gt 220) { $s = $s.Substring(0, 220) + ' ...' }; Write-Host "        $s" } }
$doc = Summary-Field $r.Summary 'doc'
$ok  = Summary-Field $r.Summary 'ok'
$bk  = Summary-Field $r.Summary 'bk'
Check 'P3 non-vacuous (doc >= 1000, ok >= 50, bk >= 1 on both sides)' (
  ($doc[0] -ge 1000) -and ($doc[1] -ge 1000) -and ($ok[0] -ge 50) -and ($ok[1] -ge 50) -and ($bk[0] -ge 1) -and ($bk[1] -ge 1)) "(doc $($doc -join '/'), ok $($ok -join '/'), bk $($bk -join '/'))"

# ---- positive controls ----------------------------------------------------------
$c1 = Run-Harness (@('--drop-kind', '//') + $Roots)
Check "PC1 dropping '//' rows makes OK parity FAIL" (($c1.Rc -eq 1) -and (@($c1.Lines | Where-Object { $_ -like 'MISMATCH OK only-today *' }).Count -gt 0)) "(rc $($c1.Rc))"
$c2 = Run-Harness (@('--drop-kind', '///') + $Roots)
Check "PC2 dropping '///' rows makes DOC parity FAIL" (($c2.Rc -eq 1) -and (@($c2.Lines | Where-Object { $_ -like 'MISMATCH DOC only-today *' }).Count -gt 0)) "(rc $($c2.Rc))"

try { [IO.Directory]::Delete($work, $true) } catch { Write-Host "  (scratch $work left: $($_.Exception.Message))" }
Write-Host ("run_comment_facts_parity: {0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
exit $(if ($script:fail) { 1 } else { 0 })
