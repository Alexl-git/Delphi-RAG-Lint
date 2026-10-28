<#
  run_signature_excludes_comments.ps1 -- lane EXT E1 (2026-10-28, item #1 of the
  1.37.0 gaps triage; INBOX-dl-ok-in-routine-header-lands-in-signature).
  A comment inside a routine header (a `// dl:ok ...` after a parameter line, a
  `{ ... }` or `(* ... *)` block between parameters) is NOT part of the routine's
  signature: symbols.signature must not carry it, for a standalone routine and for
  a method, in the interface and the implementation. Positive control: a default
  value (`pB: Integer = 3`) still lands in the signature.

  Fixture tests\autotest\fixtures\sigcomment\uSigComment.pas (indexed to a scratch DB).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-sigcomment-$PID"
)
$ErrorActionPreference = 'Stop'; $script:Passed = 0; $script:FailedN = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailedN++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  $fx = Join-Path $WorkDir 'sigcomment'
  Copy-Item (Resolve-Path "$PSScriptRoot\fixtures\sigcomment").Path $fx -Recurse
  $db = Join-Path $WorkDir 's.sqlite'
  Push-Location $WorkDir
  try {
    $null = & $Exe index $fx --db $db --library-db none 2>&1 | Out-String
    $j = & $Exe sql --db $db --json --query "SELECT name, signature FROM symbols WHERE name IN ('MethodWithComment','MethodWithBlock','LineCommented','BlockCommented','DefaultValued','TProcWithBlock','ArrConst')" 2>$null | Out-String
    $hover = & $Exe hover --qname uSigComment.LineCommented --db $db --format md 2>&1 | Out-String
  } finally { Pop-Location }
  # sql --json rows are POSITIONAL arrays: [0]=name, [1]=signature.
  $rows = @((($j | ConvertFrom-Json).rows) | ForEach-Object { ,@([string]$_[0], [string]$_[1]) })
  Check 'symbols rows found for the 7 fixture symbols' ($rows.Count -ge 7) ("rows=" + $rows.Count)
  foreach ($r in $rows) {
    if ($r[0] -in 'DefaultValued','TProcWithBlock','ArrConst') { continue }
    $clean = ($r[1] -notmatch '//|\{|\(\*|dl:ok') -and ($r[1] -match 'pB')
    Check ("{0}: signature carries no comment" -f $r[0]) $clean ("sig='" + $r[1] + "'")
  }
  $dv = @($rows | Where-Object { $_[0] -eq 'DefaultValued' } | ForEach-Object { $_[1] }) -join '|'
  Check 'positive control: default value kept (pB: Integer = 3)' ($dv -match 'pB: Integer = 3') ("sig='" + $dv + "'")
  $pt = @($rows | Where-Object { $_[0] -eq 'TProcWithBlock' } | ForEach-Object { $_[1] }) -join '|'
  Check 'procedural-type signature carries no inline block comment' (($pt -match 'Info: DWORD') -and ($pt -notmatch '\{|\(\*|//')) ("sig='" + $pt + "'")
  $ac = @($rows | Where-Object { $_[0] -eq 'ArrConst' } | ForEach-Object { $_[1] }) -join '|'
  Check 'array const value carries no trailing line comment' (($ac -match '1,\s*2') -and ($ac -notmatch '//')) ("sig='" + $ac + "'")
  Check 'hover LineCommented shows no dl:ok' (($hover -match '`pB`') -and ($hover -notmatch 'dl:ok')) ''
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("run_signature_excludes_comments: {0} passed, {1} failed" -f $script:Passed, $script:FailedN)
if ($script:FailedN -gt 0) { exit 1 } else { exit 0 }