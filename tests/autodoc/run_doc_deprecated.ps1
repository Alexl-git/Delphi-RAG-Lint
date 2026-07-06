<#
  run_doc_deprecated.ps1 -- @deprecated doc-source (`document --unit`).

  Uses fixtures\docdep\dep.pas: a unit with three public procedures --
  OldWay (deprecated 'use NewWay'), OldBare (bare deprecated, no message), and
  Fine (not deprecated, but calls OldWay() so it has a Calls fact and gets a
  managed block too -- otherwise a factless Fine would be skipped by the
  facts-only default and there would be nothing to assert 'no deprecation
  line' against).

  Asserts:
    * OldWay's managed block contains 'Deprecated: use NewWay'.
    * OldBare's managed block contains a bare 'Deprecated.' line (no message).
    * Fine's managed block has NO deprecation line at all.
    * IDEMPOTENCY: a second --apply leaves the file BYTE-IDENTICAL.

  Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docdep\dep.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docdep'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'dep.pas'
$db     = Join-Path $scratch 'docdep.sqlite'
Copy-Item $fixture $target -Force

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # --- first --apply ---
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $ec1 = $LASTEXITCODE
  Check 'apply #1: exit 0' ($ec1 -eq 0)

  $src = [IO.File]::ReadAllText($target)
  Check 'file has a triple-slash comment' ($src -match '///')
  Check 'has managed facts block (AUTO_BEGIN)' ($src -match '<!-- drag-lint:auto BEGIN -->')

  # OldWay: deprecated with a message -> 'Deprecated: use NewWay' above its decl.
  Check 'OldWay has Deprecated: use NewWay' ($src -match '(?s)Deprecated: use NewWay.*?procedure OldWay;')

  # OldBare: bare deprecated, no message -> a bare 'Deprecated.' line above its decl.
  Check 'OldBare has bare Deprecated. line' ($src -match '(?s)Deprecated\.[^\r\n]*\r?\n.*?procedure OldBare;')

  # Fine: NOT deprecated, but has a Calls fact (calls OldWay) -> managed block
  # present, but with NO 'Deprecated' line inside it.
  $lines = [IO.File]::ReadAllLines($target)
  $fineIdx = -1
  for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^procedure Fine;') { $fineIdx = $i; break } }
  Check 'Fine decl found' ($fineIdx -ge 0)
  # walk upward from Fine's decl line to the nearest preceding AUTO_END/start-of-
  # comment to isolate JUST Fine's own doc-comment block (not OldBare's above it).
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $fineIdx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $lines[$i])
  }
  $fineBlock = [string]::Join("`n", $blockLines.ToArray())
  Check 'Fine has a managed facts block' ($fineBlock -match '<!-- drag-lint:auto BEGIN -->')
  Check 'Fine has a Calls fact' ($fineBlock -match 'Calls:.*OldWay')
  Check 'Fine has NO deprecation line' ($fineBlock -notmatch 'Deprecated')

  # --- idempotency: second --apply leaves file byte-identical ---
  $before = [IO.File]::ReadAllBytes($target)
  & $exePath index $scratch --db $db 2>$null | Out-Null
  & $exePath document --unit $target --db $db --apply 2>$null | Out-Null
  $after = [IO.File]::ReadAllBytes($target)
  Check 'idempotent: file byte-identical on 2nd run' ([System.Linq.Enumerable]::SequenceEqual([byte[]]$before,[byte[]]$after))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
