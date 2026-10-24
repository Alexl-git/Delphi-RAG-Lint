<#
  run_lintall_json_stdout_clean.ps1 -- `lint-all --json` (and lint-project / lint --json): STDOUT
  is exactly one JSON array, no prefix or suffix; every progress / status line ("lint-all:
  scanning N", "[i/N] P%", "100% done") goes to STDERR (W6-cli item b).

  STDOUT IS CAPTURED ALONE, to a file. Controls, so the checks cannot pass vacuously:
    - stderr DOES carry the progress lines (else nothing was proved about where they go);
    - stdout is non-empty and the array has findings;
    - NEGATIVE control: the two streams merged do NOT parse as JSON (the check can fail).
  Run with pwsh 7 from a neutral cwd.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lintall-json-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, (($Body -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$fx = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory -Force (Join-Path $fx '_D-RAG') | Out-Null
Write-Ascii (Join-Path $fx 'App.dpr') @'
program App;

uses
  U1 in 'U1.pas';

begin
  Foo;
end.
'@
Write-Ascii (Join-Path $fx 'U1.pas') @'
unit U1;

interface

procedure Foo;

implementation

procedure Foo;
var
  Unused: Integer;
begin
end;

end.
'@
$db = Join-Path $fx '_D-RAG\App.sqlite'
& $Exe index --project (Join-Path $fx 'App.dpr') --db $db 2>&1 | Out-Null
if (-not (Test-Path $db)) { Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2 }

function Run([string[]]$ArgList) {
  $o = Join-Path $WorkDir 'out.txt'; $e = Join-Path $WorkDir 'err.txt'
  $q = $ArgList | ForEach-Object { if ($_ -match '[\s"]') { '"' + $_ + '"' } else { $_ } }
  Start-Process -FilePath $Exe -ArgumentList $q -WorkingDirectory $WorkDir -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError $e | Out-Null
  return @{ Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}
function Parses([string]$T) { try { $null = ConvertFrom-Json $T -Depth 100; $true } catch { $false } }

$runs = @(
  @{ n = 'lint-all --db --json';        a = @('lint-all', '--db', $db, '--json');                                 progress = $true },
  @{ n = 'lint-all --project --json';   a = @('lint-all', '--project', (Join-Path $fx 'App.dpr'), '--db', $db, '--json'); progress = $true },
  @{ n = 'lint-all --format json';      a = @('lint-all', '--db', $db, '--format', 'json');                       progress = $true },
  @{ n = 'lint-project --json';         a = @('lint-project', '--project', (Join-Path $fx 'App.dpr'), '--db', $db, '--json'); progress = $false }
)
foreach ($r in $runs) {
  $x = Run $r.a
  $t = $x.Out.Trim()
  Check "$($r.n): stdout non-empty" ($t.Length -gt 0)
  Check "$($r.n): stdout starts with [ and ends with ]" ($t.StartsWith('[') -and $t.EndsWith(']'))
  Check "$($r.n): stdout parses as JSON" (Parses $t)
  if ($r.progress) { Check "$($r.n): stdout has findings (control)" ((ConvertFrom-Json $t -Depth 100).Count -gt 0) }
  Check "$($r.n): no 'lint-all:' text on stdout" ($x.Out -notmatch 'lint-all:')
  if ($r.progress) {
    Check "$($r.n): progress is on stderr (control)" (($x.Err -match 'lint-all: scanning') -and ($x.Err -match '\d+%'))
    Check "$($r.n): merged streams do NOT parse (negative control)" (-not (Parses ($x.Err + $x.Out)))
  }
}
$x = Run @('lint', (Join-Path $fx 'U1.pas'), '--json')
Check 'lint <file> --json: stdout parses' ((Parses $x.Out.Trim()) -and ($x.Out.Trim().StartsWith('[')))
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
