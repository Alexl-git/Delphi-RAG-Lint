# dl:serial: re-stages the SHARED engine rules directory. It copies rules\*.scm /
#   *.json into <exeDir>\rules -- the same directory every other runner READS
#   its rule catalogue from -- so while this copy is in flight a concurrent
#   sibling can load a half-written or briefly-locked rule file. FOUND BY THE
#   SECOND -Jobs 8 A/B: run_store_tests failed its circular-uses case while
#   passing serially and in the first parallel run. The staging is redundant
#   under the battery (the driver stages the same files before the first
#   runner starts) but is needed when the runner is invoked standalone, so it
#   is quarantined rather than deleted.
<#
  run_report_encoding.ps1 -- the lint-all REPORT FILE is plain 7-bit ASCII with
  no BOM.

  THE DEFECT (PLAN-autodoc-and-backlog-2026-08-06, PHASE B item B8)
  ---------------------------------------------------------------------------
  Two independent things made the report non-ASCII:

    * it was written with TEncoding.UTF8, whose preamble puts EF BB BF at the
      head of the file, and
    * `writeln-in-source`'s message carried a real EM DASH (U+2014) while every
      other rule message in the catalogue spells the same punctuation `--`.
      One character in one rule file was enough to make any report that fires
      that rule non-ASCII.

  Both matter for the same reason: the report is read by `type`, by grep, and by
  editors that guess an encoding from the first bytes. The repo's own rule for
  source is 7-bit ASCII with no BOM (tests\autotest\run_encoding_guard.ps1) and
  the artefact the tool WRITES should not be held to a lower standard than the
  source it reads.

  This drives the report end to end -- index a fixture that fires the rule, run
  lint-all, and read the bytes it produced -- rather than only scanning the rule
  files, so a future writer that reintroduces a preamble fails here too.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-report-encoding"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$repo = (Resolve-Path "$PSScriptRoot\..\..").Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- the rule messages the report is built from -----------------------------
Write-Host 'Rule catalogue messages' -ForegroundColor Cyan
$badMsg = New-Object System.Collections.Generic.List[string]
Get-ChildItem -LiteralPath (Join-Path $repo 'rules') -Filter '*.json' -File | ForEach-Object {
  $txt = [System.IO.File]::ReadAllText($_.FullName)
  foreach ($ch in $txt.ToCharArray()) {
    if ([int]$ch -gt 127) { $badMsg.Add(("{0}  (U+{1:X4})" -f $_.Name, [int]$ch)); break }
  }
}
Check 'no rule file carries a non-ASCII character' ($badMsg.Count -eq 0) `
  $(if ($badMsg.Count) { "`n        " + ($badMsg -join "`n        ") } else { '' })

# --- and the report as actually written -------------------------------------
$src = @'
unit reportenc;

interface

procedure Noisy;

implementation

procedure Noisy;
begin
  { fires writeln-in-source, the one rule whose message was not ASCII.
    Spelled WriteLn exactly: the rule's #eq? predicate is case-SENSITIVE. }
  WriteLn('hello');
end;

end.
'@ -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path $WorkDir 'reportenc.pas'), $src, [System.Text.Encoding]::ASCII)

# The exe resolves rules from <exe-dir>\rules; keep them in step with the repo.
$rulesDst = Join-Path (Split-Path $Exe -Parent) 'rules'
if (-not (Test-Path $rulesDst)) { New-Item -ItemType Directory $rulesDst | Out-Null }
Copy-Item (Join-Path $repo 'rules\*.scm')  $rulesDst -Force
Copy-Item (Join-Path $repo 'rules\*.json') $rulesDst -Force

$db     = Join-Path $WorkDir 'reportenc.sqlite'
$report = Join-Path $WorkDir 'report.txt'
& $Exe index $WorkDir --db $db --quiet 2>&1 | Out-Null
& $Exe lint-all --db $db --output $report 2>&1 | Out-Null

Write-Host ''
Write-Host 'The report file' -ForegroundColor Cyan
Check 'lint-all wrote the report' (Test-Path $report)
if (-not (Test-Path $report)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$bytes = [System.IO.File]::ReadAllBytes($report)
$bom   = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$hi    = @($bytes | Where-Object { $_ -gt 127 }).Count
$text  = [System.Text.Encoding]::UTF8.GetString($bytes)

Check 'the report has no BOM' (-not $bom)
Check 'the report is 7-bit ASCII' ($hi -eq 0) "($hi byte(s) >127)"
Check 'the fixture really did fire writeln-in-source' ($text -match 'writeln-in-source') `
  'else this asserts nothing about that message'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
