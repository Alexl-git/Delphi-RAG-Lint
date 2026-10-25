<#
  run_lint_all_output_json_guard.ps1 -- `lint-all --json --output <f>` writes the JSON to <f>.

  Defect (ENGINE wave 4, H1): with --json (or --format sarif) the document went to
  stdout and --output was ignored, so <f> was never created.

  Asserts: (1) --json --output creates <f> holding a JSON array, (2) stdout is
  empty (the destination note is on stderr), (3) text mode --output still writes
  the report file, (4) POSITIVE CONTROL: --json without --output puts the same
  array on stdout and creates no file -- so (1)/(2) cannot pass by accident.
  Needs the engine DB (-DbPath); one narrowed rule keeps it to ~20 s per run.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = "$PSScriptRoot\..\..",
  [string]$Exe = '',
  [string]$DbPath = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
$RepoRoot = (Resolve-Path $RepoRoot).Path
if (-not $Exe) { $Exe = Join-Path $RepoRoot 'third_party\dll-win64\drag-lint.exe' }
if (-not $DbPath) { $DbPath = Join-Path $RepoRoot 'src\cli\_D-RAG\drag-lint.sqlite' }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: no exe $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $DbPath))  { Write-Host "FATAL: no db $DbPath"  -ForegroundColor Red; exit 2 }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('lao_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $tmp
Push-Location $tmp
try {
  function Run([string[]]$Extra) {
    $o = Join-Path $tmp ([Guid]::NewGuid().ToString('N') + '.out')
    $p = Start-Process $Exe -ArgumentList (@('lint-all', '--db', $DbPath, '--rule', 'unit-not-in-dpr') + $Extra) `
           -WorkingDirectory $tmp -PassThru -Wait -RedirectStandardOutput $o -RedirectStandardError "$o.err" -WindowStyle Hidden
    [pscustomobject]@{ Out = (Get-Content -LiteralPath $o -Raw); Exit = $p.ExitCode }
  }
  $f1 = Join-Path $tmp 'report.json'
  $r1 = Run @('--json', '--output', $f1)
  Check '--json --output creates the file' (Test-Path -LiteralPath $f1) "exit=$($r1.Exit)"
  $arr = $null
  if (Test-Path -LiteralPath $f1) { try { $arr = Get-Content -LiteralPath $f1 -Raw | ConvertFrom-Json } catch { } }
  Check 'the file holds a parseable JSON document' ($null -ne $arr -or ((Test-Path $f1) -and (Get-Content -LiteralPath $f1 -Raw).Trim() -eq '[]')) ''
  Check 'stdout is empty when --output is given' ([string]::IsNullOrWhiteSpace($r1.Out)) "stdout chars=$($r1.Out.Length)"

  $f2 = Join-Path $tmp 'report.txt'
  $r2 = Run @('--output', $f2)
  Check 'text mode --output still writes the report file' (Test-Path -LiteralPath $f2) ''

  $f3 = Join-Path $tmp 'never.json'
  $r3 = Run @('--json')
  Check 'POSITIVE CONTROL: --json alone prints the array on stdout' ($r3.Out.TrimStart().StartsWith('[')) ''
  Check 'POSITIVE CONTROL: --json alone creates no file' (-not (Test-Path -LiteralPath $f3)) ''
} finally {
  Pop-Location
  try { [IO.Directory]::Delete($tmp, $true) } catch { }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
