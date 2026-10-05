<#
  run_lint_dpr_parity.ps1 -- engine 1.20.6 Task 3.

  `lint <file>` gated its no-DB AST checks (try-except-swallowed, write-only-local,
  ...) to .pas/.inc, while `lint-all` was fixed for .dpr on 2026-08-16. So the
  editor's per-file view of a .dpr showed only the .scm findings (bare-except,
  empty-on-handler) and hid the AST ones.

  A1  per-file `lint X.dpr --json` finding set (rule@line) == lint-all's for that file
  A2  CONTROL: the AST rules (try-except-swallowed, write-only-local) are in the set
  A3  a live dl:ok on the write-only local -> 0 review-marker-unused, rule suppressed
  A4  .dpk: lint-all does not scan .dpk, so none is claimed; per-file .dpk is unchanged
      (still no AST checks) -- pinned so a later change is deliberate.

  Fixtures are indexed into a SCRATCH db; never a real one. Run from a neutral CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_dpr_parity_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }
$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path

$template = @'
program PDprParity;

{$APPTYPE CONSOLE}

uses
  System.SysUtils;

procedure BareOne;
begin
  try
    Writeln('a');
  except
    Writeln('b');
  end;
end;

procedure Swallow;
begin
  try
    Writeln('a');
  except
    on E: Exception do
  end;
end;

procedure WriteOnly;
var
  X: Integer;@@MARK@@
begin
  X := 1;
end;

begin
  BareOne;
  Swallow;
  WriteOnly;
end.
'@

function Sets($json) {
  $a = @($json | ConvertFrom-Json)
  @($a | ForEach-Object { '{0}@{1}' -f $_.rule, $_.start_line } | Sort-Object)
}
function Run($name, $mark) {
  $d = Join-Path $WorkDir $name
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  $f = Join-Path $d 'PDprParity.dpr'
  Write-Ascii $f ($template -replace '@@MARK@@', $mark)
  $db = Join-Path $d 'x.sqlite'
  $null = & $exePath index $d --db $db 2>&1
  $en = 'review-marker-unused,review-marker-stale'
  $pf  = (& $exePath lint $f --db $db --rules-dir $rules --enable $en --json 2>$null | Out-String)
  $all = (& $exePath lint-all --db $db --rules-dir $rules --enable $en --json 2>$null | Out-String)
  [pscustomobject]@{ PerFile = (Sets $pf); All = (Sets $all) }
}

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

$plain = Run 'plain' ''
Check 'A1  per-file .dpr finding set equals lint-all' `
      (($plain.PerFile -join ',') -eq ($plain.All -join ',')) `
      "per-file: $($plain.PerFile -join ', ') | lint-all: $($plain.All -join ', ')"
Check 'A2  CONTROL: AST rules present (try-except-swallowed, write-only-local)' `
      (($plain.All -match '^try-except-swallowed@').Count -ge 1 -and ($plain.All -match '^write-only-local@').Count -ge 1 -and ($plain.PerFile -match '^try-except-swallowed@').Count -ge 1) `
      "lint-all: $($plain.All -join ', ')"

$marked = Run 'marked' ' // dl:ok write-only-local -- fixture: deliberate'
Check 'A3  live dl:ok -> write-only-local suppressed, 0 review-marker-unused (per-file)' `
      (($marked.PerFile -match '^write-only-local@').Count -eq 0 -and ($marked.PerFile -match '^review-marker-unused@').Count -eq 0) `
      "per-file: $($marked.PerFile -join ', ')"
Check 'A3b PARITY with the marker present' `
      (($marked.PerFile -join ',') -eq ($marked.All -join ',')) `
      "per-file: $($marked.PerFile -join ', ') | lint-all: $($marked.All -join ', ')"

# A4: .dpk per-file stays as it was (no AST checks); lint-all never scans .dpk.
$dk = Join-Path $WorkDir 'dpk'; New-Item -ItemType Directory -Path $dk -Force | Out-Null
Write-Ascii (Join-Path $dk 'PDpk.dpk') (($template -replace '@@MARK@@','') -replace '^program PDprParity;','package PDpk;')
$o = (& $exePath lint (Join-Path $dk 'PDpk.dpk') --rules-dir $rules --json 2>$null | Out-String)
$ids = if ($o.Trim()) { Sets $o } else { @() }
Check 'A4  .dpk per-file: no AST findings (unchanged; lint-all does not scan .dpk)' `
      (($ids -match '^(try-except-swallowed|write-only-local)@').Count -eq 0) ($ids -join ', ')

Write-Host ''
if ($fail) { Write-Host 'run_lint_dpr_parity: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_dpr_parity: PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d in @("C:\TEMP\draglint_dpr_parity_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
