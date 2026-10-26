<#
  run_json_error_stdout.ps1 -- X-26: under --json, a "symbol not found" / "no doc-comment on"
  diagnostic goes to STDERR; stdout stays empty or parseable JSON. Before the fix these verbs
  printed the plain-text line on stdout, so `drag-lint doc-drift --qname X --json | ConvertFrom-Json`
  died on a valid "not found" answer.

  Verbs: doc-drift, find-callees, call-path, callgraph; CLI lane (2026-10-26): + query unit-usage, impact,
  wiring, reverse-calltree (incl. its not-found exit code), outline (incl. --json), find-unit (incl. the
  already-used [] answer), lint, shared-unit, query type-usage.
  FLAG lane (2026-10-26): + proptree; and under --format json butterfly, context, surface, slice, hover, proptree.
  Each verb tests only the output flags it documents (ReportNotFoundFor), so run_flag_verb_map stays honest.
  Controls: (1) the JSON test rejects a planted plain-text line; (2) without --json the same
  diagnostic still reaches stdout (the stream split is keyed on --json, not removed).
  Needs a DB: -DbPath (default: the main engine DB beside the repo; read-only verbs only).
  Run with pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
      [string]$DbPath = 'C:\Projects\Delphi-RAG-lint\src\cli\_D-RAG\drag-lint.sqlite',
      [string]$SrcDir = 'C:\Projects\Delphi-RAG-lint\src\cli')
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
  # FLAG lane audit (2026-10-26): the same leak on proptree (it takes --json and --format json).
  'proptree'         = @('proptree', '--qname', $bogus, '--db', $DbPath)
}
foreach ($k in $cases.Keys) {
  $a = $cases[$k]
  $out = (& $Exe @a '--json' 2>$null) -join "`n"
  Check "$k --json: stdout empty or JSON" (Test-StdoutJsonOrEmpty $out) "stdout=[$out]"
  $plain = (& $Exe @a 2>$null) -join "`n"
  Check "control: $k without --json still prints the diagnostic on stdout" ($plain -match 'not found|no doc-comment|No symbol matched|No slice returned') "stdout=[$plain]"
}
# --format json asks for the same machine-readable stdout as --json (FLAG lane audit).
$fmtCases = [ordered]@{
  'butterfly --format json' = @('butterfly', '--qname', $bogus, '--format', 'json', '--db', $DbPath)
  'context --format json'   = @('context', '--task', "modify $bogus", '--format', 'json', '--db', $DbPath)
  'surface --format json'   = @('surface', '--qname', $bogus, '--format', 'json', '--db', $DbPath)
  'slice --format json'     = @('slice', '--qname', $bogus, '--format', 'json', '--db', $DbPath)
  'hover --format json'     = @('hover', '--qname', $bogus, '--format', 'json', '--db', $DbPath)
  'proptree --format json'  = @('proptree', '--qname', $bogus, '--format', 'json', '--db', $DbPath)
}
foreach ($k in $fmtCases.Keys) {
  $a = $fmtCases[$k]
  $out = (& $Exe @a 2>$null) -join "`n"
  Check "${k}: stdout empty or JSON" (Test-StdoutJsonOrEmpty $out) "stdout=[$out]"
  $errFile = [IO.Path]::GetTempFileName()
  $null = & $Exe @a 2> $errFile
  $err = (Get-Content -LiteralPath $errFile) -join "`n"
  [IO.File]::Delete($errFile)
  Check "control: ${k} still SAYS it on stderr" ($err -match 'not found|No symbol matched|No slice returned') "stderr=[$err]"
}
# CLI lane (2026-10-26), X-26 remainder: usage / error / "nothing to do" lines of query unit-usage,
# impact, wiring, reverse-calltree, outline, find-unit, lint and shared-unit. Each case: the verb's
# OWN documented JSON flag, the args that reach the diagnostic, and the text that must still reach
# stdout without it (control: the split is keyed on the JSON flag, the message was not deleted).
# -SrcDir: the folder whose units -DbPath indexes (the DB stores absolute paths).
$realUnit = Join-Path $srcDir 'DRagLint.Hover.Renderer.pas'
$cliUnit  = Join-Path $srcDir 'DRagLint.CLI.pas'
$noFile   = 'C:\ZzNoSuchDirX26\ZzNoSuchUnitX26.pas'
$rem = @(
  @{ n = 'query unit-usage, unit in no index';  a = @('query', 'unit-usage', '--unit', $bogus, '--db', $DbPath); j = @('--json'); m = 'no interface-section symbols' }
  @{ n = 'query unit-usage, --in missing';      a = @('query', 'unit-usage', '--unit', $bogus, '--in', $noFile, '--db', $DbPath); j = @('--json'); m = 'file not found' }
  @{ n = 'query unit-usage, no --unit';         a = @('query', 'unit-usage', '--db', $DbPath); j = @('--json'); m = 'requires --unit' }
  @{ n = 'impact, no --qname';                  a = @('impact', '--db', $DbPath); j = @('--format', 'json'); m = 'Usage: drag-lint impact' }
  @{ n = 'wiring, no --qname';                  a = @('wiring', '--db', $DbPath); j = @('--format', 'json'); m = 'Usage: drag-lint wiring' }
  @{ n = 'reverse-calltree, no --qname';        a = @('reverse-calltree', '--db', $DbPath); j = @('--json'); m = 'Usage: drag-lint reverse-calltree' }
  @{ n = 'reverse-calltree --json, not found';  a = @('reverse-calltree', '--qname', $bogus, '--db', $DbPath); j = @('--json'); m = 'symbol not found' }
  @{ n = 'reverse-calltree --format json, not found'; a = @('reverse-calltree', '--qname', $bogus, '--db', $DbPath); j = @('--format', 'json'); m = 'symbol not found' }
  @{ n = 'outline, file in no index';           a = @('outline', '--in', $noFile, '--db', $DbPath); j = @('--format', 'json'); m = 'no index that resolves' }
  @{ n = 'outline, no --in';                    a = @('outline', '--db', $DbPath); j = @('--format', 'json'); m = 'Usage: drag-lint outline' }
  @{ n = 'outline --json, file in no index';    a = @('outline', '--in', $noFile, '--db', $DbPath); j = @('--json'); m = 'no index that resolves' }
  @{ n = 'query type-usage, no --in';           a = @('query', 'type-usage', '--names', 'TFoo', '--db', $DbPath); j = @('--json'); m = 'requires --in' }
  @{ n = 'query type-usage, no --names';        a = @('query', 'type-usage', '--in', $realUnit, '--db', $DbPath); j = @('--json'); m = 'requires --names' }
  @{ n = 'query type-usage, --in missing';      a = @('query', 'type-usage', '--in', $noFile, '--names', 'TFoo', '--db', $DbPath); j = @('--json'); m = 'file not found' }
  @{ n = 'query type-usage, --names-file missing'; a = @('query', 'type-usage', '--in', $realUnit, '--names-file', $noFile, '--db', $DbPath); j = @('--json'); m = '--names-file not found' }
  @{ n = 'find-unit, unresolvable name';        a = @('find-unit', '--name', $bogus, '--in', $realUnit, '--db', $DbPath); j = @('--json'); m = 'Could not resolve a unit' }
  @{ n = 'find-unit, no --name';                a = @('find-unit', '--in', $realUnit, '--db', $DbPath); j = @('--json'); m = 'needs --name' }
  @{ n = 'find-unit, already in uses';          a = @('find-unit', '--name', 'BuildHoverModel', '--in', $cliUnit, '--db', $DbPath); j = @('--json'); m = 'already in the uses clause' }
  @{ n = 'lint, path missing';                  a = @('lint', $noFile, '--db', $DbPath); j = @('--json'); m = 'path does not exist' }
  @{ n = 'lint, no path';                       a = @('lint', '--db', $DbPath); j = @('--json'); m = 'lint requires' }
  @{ n = 'shared-unit, file missing';           a = @('shared-unit', '--in', $noFile); j = @('--json'); m = 'file not found' }
  @{ n = 'shared-unit, no --in';                a = @('shared-unit'); j = @('--json'); m = 'Usage: drag-lint shared-unit' }
)
foreach ($c in $rem) {
  $all = @($c.a) + @($c.j)
  $out = (& $Exe @all 2>$null) -join "`n"
  Check "$($c.n) $($c.j -join ' '): stdout empty or JSON" (Test-StdoutJsonOrEmpty $out) "stdout=[$out]"
  $errFile = [IO.Path]::GetTempFileName()
  $null = & $Exe @all 2> $errFile
  $err = (Get-Content -LiteralPath $errFile) -join "`n"
  [IO.File]::Delete($errFile)
  Check "$($c.n): the diagnostic is still SAID, on stderr" ($err -match [regex]::Escape($c.m)) "stderr=[$err]"
  $plain = (& $Exe @($c.a) 2>$null) -join "`n"
  Check "control: $($c.n) without the JSON flag still prints it on stdout" ($plain -match [regex]::Escape($c.m)) "stdout=[$plain]"
}
# reverse-calltree: an unresolved qname over a READABLE index is "not found" (exit 1), not "no readable index" (exit 2).
$null = & $Exe reverse-calltree --qname $bogus --db $DbPath --json 2>$null
Check 'reverse-calltree: unresolved qname exits 1 (not found), not 2' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"
# find-unit --json when the unit is already used: a valid JSON answer on stdout (the edits array, empty), exit 0.
$fu = (& $Exe find-unit --name 'BuildHoverModel' --in $cliUnit --db $DbPath --json 2>$null) -join "`n"
$fuExit = $LASTEXITCODE
Check 'find-unit --json, already in uses: stdout is exactly [] and exit 0' (($fu.Trim() -eq '[]') -and ($fuExit -eq 0)) "stdout=[$fu] exit=$fuExit"
# outline --json is the same request as --format json: identical stdout on an indexed unit.
$oj = (& $Exe outline --in $realUnit --db $DbPath --json 2>$null) -join "`n"
$of = (& $Exe outline --in $realUnit --db $DbPath --format json 2>$null) -join "`n"
Check 'outline --json prints what --format json prints (non-empty JSON)' ((-not [string]::IsNullOrWhiteSpace($oj)) -and ($oj -ceq $of) -and (Test-StdoutJsonOrEmpty $oj))
# Positive control: success paths of the same verbs were already JSON and stay JSON (non-empty, parses).
$ok = (& $Exe outline --in $realUnit --db $DbPath --format json 2>$null) -join "`n"
Check 'control: outline --format json on an indexed unit is non-empty JSON' ((-not [string]::IsNullOrWhiteSpace($ok)) -and (Test-StdoutJsonOrEmpty $ok))
$ok = (& $Exe query unit-usage --unit 'DRagLint.Hover.Renderer' --db $DbPath --json 2>$null) -join "`n"
Check 'control: query unit-usage --json on an indexed unit is non-empty JSON' ((-not [string]::IsNullOrWhiteSpace($ok)) -and (Test-StdoutJsonOrEmpty $ok))Check 'control: the JSON test rejects a planted plain-text line' (-not (Test-StdoutJsonOrEmpty 'symbol not found: Foo'))
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
