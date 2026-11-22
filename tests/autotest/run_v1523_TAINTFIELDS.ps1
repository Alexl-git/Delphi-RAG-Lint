# run_v1523_TAINTFIELDS.ps1 -- lane SLZ-TAINTFP (1.52.3): taint-path-traversal no longer
# reports a value that a callee wrote into ONE field of a var parameter when nothing after
# that point reads that field. Shape of the 1.52.2 self-lint false positives:
# RefuseNamedUnits writes dcc text into TGpaUnit.Error; RunGate then deletes / backs up
# through TGpaUnit.PasPath only.
#
# Fixture tests\lint\taint-path-traversal\uFieldOut.pas: ReadLn(S) is written into
# A[..].Note (Annotate) and into B[..].Path (AnnotatePath).
#   NON-hits (pruned): DeleteByPath (line 51, reads .Path), KillOne via DeleteByPathDeep (43),
#   DeleteByPathCommented (98: names 'Note' only in comments and a string literal -- v1523
#   TAINT-TRIAGE, a comment cannot read a field).
#   Hits (kept): DeleteByNote (67, reads .Note), DeleteThroughCall (80, .Note read inside the
#   NoteOf call -- a body no path hop shows, so the tag must not prune), DeleteWritten (88,
#   B's tainted .Path).
# POSITIVE CONTROL: the three kept hits prove the rule still fires on this fixture.
#
# Usage: pwsh -File tests\autotest\run_v1523_TAINTFIELDS.ps1 [-Exe <drag-lint.exe>]
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if ($Exe -eq '') { $Exe = Join-Path $repo 'src\cli\Win64\Debug\drag-lint.exe' }
$exePath = (Resolve-Path $Exe).Path
$fx    = Join-Path $repo 'tests\lint\taint-path-traversal'
$tmp   = Join-Path $env:TEMP "taintfields_$PID"
[void][IO.Directory]::CreateDirectory($tmp)
$empty = Join-Path $tmp 'empty.json'
[IO.File]::WriteAllText($empty, '{}')

$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS  $Name" } else { Write-Host "FAIL  $Name  $Detail"; $script:fail++ }
}

Push-Location $env:TEMP
try {
  $work = Join-Path $tmp 'a'; [void][IO.Directory]::CreateDirectory($work)
  [IO.File]::Copy((Join-Path $fx 'uFieldOut.pas'), (Join-Path $work 'uFieldOut.pas'), $true)
  $db = Join-Path $tmp 'a.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index $work --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --json --quiet --config $empty 2>$null }
  $txt = ($raw -join "`n"); $b = $txt.IndexOf('[')
  $all = @(); if ($b -ge 0) { try { $all = @($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $all = @() } }
  $f = @($all | Where-Object { $_.rule -eq 'taint-path-traversal' })
  $f | ForEach-Object { Write-Host ("  {0}:{1} {2}" -f (Split-Path $_.file_path -Leaf), $_.start_line, $_.message) }
  $lines = @($f | ForEach-Object { [int]$_.start_line })
  foreach ($ln in @(43, 51, 98)) { Check "non-hit: field-only taint not read downstream (line $ln)" ($lines -notcontains $ln) }
  foreach ($ln in @(67, 80, 88)) { Check "hit kept (line $ln)" ($lines -contains $ln) "lines: $($lines -join ',')" }
  Check 'exactly three taint-path-traversal findings' ($f.Count -eq 3) "got $($f.Count)"
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($tmp, $true) } catch { }
}
if ($fail -eq 0) { Write-Host 'run_v1523_TAINTFIELDS: ALL PASS'; exit 0 }
Write-Host "run_v1523_TAINTFIELDS: $fail FAILED"; exit 1
