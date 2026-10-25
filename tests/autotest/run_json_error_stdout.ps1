<#
  run_json_error_stdout.ps1 -- X-26: under --json, a "symbol not found" / "no doc-comment on"
  diagnostic goes to STDERR; stdout stays empty or parseable JSON. Before the fix these verbs
  printed the plain-text line on stdout, so `drag-lint doc-drift --qname X --json | ConvertFrom-Json`
  died on a valid "not found" answer.

  Verbs: doc-drift, find-callees, call-path, callgraph (reverse-calltree is fixed in code but its --db handling needs its own repro).
  Controls: (1) the JSON test rejects a planted plain-text line; (2) without --json the same
  diagnostic still reaches stdout (the stream split is keyed on --json, not removed).
  Needs a DB: -DbPath (default: the main engine DB beside the repo; read-only verbs only).
  Run with pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$DbPath = 'C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite')
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
function Test-StdoutJsonOrEmpty([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return $true }
  try { $null = $text | ConvertFrom-Json -ErrorAction Stop; return $true } catch { return $false }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $DbPath)) { Write-Host "FATAL: db not found: $DbPath" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$bogus = 'ZzNoSuchSymbolX26'
$cases = [ordered]@{
  'doc-drift'        = @('doc-drift', '--qname', $bogus, '--db', $DbPath)
  'find-callees'     = @('find-callees', '--qname', $bogus, '--db', $DbPath)
  'call-path'        = @('call-path', '--from', $bogus, '--to', $bogus, '--db', $DbPath)
  'callgraph'        = @('callgraph', '--qname', $bogus, '--db', $DbPath)
}
foreach ($k in $cases.Keys) {
  $a = $cases[$k]
  $out = (& $Exe @a '--json' 2>$null) -join "`n"
  Check "$k --json: stdout empty or JSON" (Test-StdoutJsonOrEmpty $out) "stdout=[$out]"
  $plain = (& $Exe @a 2>$null) -join "`n"
  Check "control: $k without --json still prints the diagnostic on stdout" ($plain -match 'not found|no doc-comment') "stdout=[$plain]"
}
Check 'control: the JSON test rejects a planted plain-text line' (-not (Test-StdoutJsonOrEmpty 'symbol not found: Foo'))
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
