<#
  run_uses_report_name_no_match.ps1 -- `uses-report --name <x>` that matches ZERO
  source units refuses (exit 2, ERROR on stderr, no output file) instead of
  answering "0 source units, 0 rows written" with exit 0.

  WHY (stats\draglint-gaps.log 2026-09-16T13:00, class `wrong`; converter reply
  docs\INBOX-REPLY-2026-09-17-converter-accepts-R-A1-to-R-A6.md, "One gap")
  --------------------------------------------------------------------------------
    uses-report --output x.csv --name VARINSP --db <Micronite2027.sqlite>
      uses-report: 0 source units, 0 rows written to x.csv        exit 0
    outline --file ...\VARINSP.PAS --db <same>
      ERROR: outline: no index that resolves here contains ...    exit 2
  Same file, same DB, two truths. A confident, complete-looking report computed
  against a corpus that does not contain the subject is the `proptree` shape
  again. `outline` is the honest one; this guard makes `uses-report` match it.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_usesreport_nomatch'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

# Two units: urA uses urB, so `--name urA` has >= 1 row to write.
Write-Ascii (Join-Path $scratch 'urA.pas') @'
unit urA;

interface

uses urB;

type
  TAlpha = class
    FB: TBeta;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $scratch 'urB.pas') @'
unit urB;

interface

type
  TBeta = class
    FCount: Integer;
  end;

implementation

end.
'@

$db = Join-Path $scratch 'ur.sqlite'

# Run the verb with stdout / stderr captured SEPARATELY (the ERROR line must be
# on stderr, where uses-report's other refusals already go).
function Invoke-UsesReport([string[]]$extra) {
  $out = Join-Path $scratch 'stdout.txt'; $err = Join-Path $scratch 'stderr.txt'
  $p = Start-Process -FilePath $exePath -ArgumentList (@('uses-report') + $extra) -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput $out -RedirectStandardError $err
  return [pscustomobject]@{
    Code = $p.ExitCode
    # [string] so an EMPTY stream is '' and `-match` yields a Boolean; $null -match
    # returns an empty array and blows up Check's [int] cast.
    Out  = [string](Get-Content $out -Raw -ErrorAction SilentlyContinue)
    Err  = [string](Get-Content $err -Raw -ErrorAction SilentlyContinue)
  }
}

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db --quiet 2>$null | Out-Null
  Check 'index exits 0' ($LASTEXITCODE -eq 0)

  # --- (1) positive control: --name that MATCHES still works ------------------
  $csv1 = Join-Path $scratch 'match.csv'
  $r1 = Invoke-UsesReport @('--output', $csv1, '--name', 'urA', '--db', $db)
  $rows1 = if (Test-Path $csv1) { @(Get-Content $csv1 | Select-Object -Skip 1 | Where-Object { $_ -ne '' }) } else { @() }
  Check '1a --name urA exits 0' ($r1.Code -eq 0) "exit=$($r1.Code) err=$($r1.Err)"
  Check '1b --name urA writes >= 1 data row (urA -> urB)' ($rows1.Count -ge 1) "rows=$($rows1.Count)"
  # (4) the guard can fail: the summary line format is pinned VERBATIM, so a
  # reworded summary or a changed count goes red here.
  Check '1c summary line is "uses-report: 1 source units, N rows written to <csv>"' ($r1.Out -match ('(?m)^uses-report: 1 source units, \d+ rows written to ' + [regex]::Escape($csv1) + '\s*$')) "out=$($r1.Out)"

  # --- (2) the gap: --name that matches NOTHING must refuse -------------------
  $csv2 = Join-Path $scratch 'nomatch.csv'
  if (Test-Path $csv2) { Remove-Item $csv2 -Force }
  $r2 = Invoke-UsesReport @('--output', $csv2, '--name', 'NoSuchUnit', '--db', $db)
  Check '2a --name NoSuchUnit exits 2' ($r2.Code -eq 2) "exit=$($r2.Code)"
  Check '2b stderr carries "ERROR: uses-report: no index passed contains a source unit named NoSuchUnit"' ($r2.Err -match '(?m)^ERROR: uses-report: no index passed contains a source unit named NoSuchUnit\b') "err=$($r2.Err)"
  Check '2c no output file is written' (-not (Test-Path $csv2))
  Check '2d stdout does NOT carry the "0 source units" summary' ($r2.Out -notmatch '0 source units') "out=$($r2.Out)"
  # A pre-existing output file is left UNTOUCHED (the file is opened only after
  # the source set is known to be non-empty).
  $csv3 = Join-Path $scratch 'preexisting.csv'
  Write-Ascii $csv3 "sentinel,do,not,touch`n"
  $before = [IO.File]::ReadAllText($csv3)
  $r3 = Invoke-UsesReport @('--output', $csv3, '--name', 'NoSuchUnit', '--db', $db)
  Check '2e pre-existing output file is untouched on refusal' (($r3.Code -eq 2) -and ([IO.File]::ReadAllText($csv3) -eq $before)) "exit=$($r3.Code)"

  # --- (3) no --name: unchanged ----------------------------------------------
  $csv4 = Join-Path $scratch 'all.csv'
  $r4 = Invoke-UsesReport @('--output', $csv4, '--db', $db)
  Check '3a no --name exits 0' ($r4.Code -eq 0) "exit=$($r4.Code) err=$($r4.Err)"
  Check '3b no --name reports 2 source units with the normal summary' ($r4.Out -match '(?m)^uses-report: 2 source units, \d+ rows written to ') "out=$($r4.Out)"
  Check '3c no --name writes the output file' (Test-Path $csv4)
} finally { Pop-Location }

if($script:Failed){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
