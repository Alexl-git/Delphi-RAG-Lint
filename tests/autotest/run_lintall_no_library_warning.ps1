<#
  run_lintall_no_library_warning.ps1 -- int2 1.44.1. A lint-all with no platform library drops every finding that needs
  a library type (Loader2025: 3410 against 4210) and used to say nothing. It now says so on one stderr line, unless the
  caller chose it (--library-db none) or asked for quiet/JSON output.

  Positive control: the same run with a library, and with the choice stated, prints no warning, so the check is not
  matching a line that is always there. The engine is a COPY with no manifest beside it, in %TEMP%.
#>
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
$Exe = (Resolve-Path $Exe).Path
$Tmp = Join-Path $env:TEMP ('nolibwarn_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null
try {
  $Eng = Join-Path $Tmp 'eng'
  [IO.Directory]::CreateDirectory($Eng) | Out-Null
  Copy-Item $Exe $Eng
  Copy-Item (Join-Path (Split-Path $Exe) '*.dll') $Eng
  $E = Join-Path $Eng 'drag-lint.exe'
  $Prj = Join-Path $Tmp 'p'
  Copy-Item (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\redcast").Path $Prj -Recurse
  $Db = Join-Path $Prj 'p.sqlite'
  & $E index --project (Join-Path $Prj 'RedCast.dproj') --db $Db --library-db none *> (Join-Path $Tmp 'index.log')
  Check 'S0 the fixture indexes' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $Rule = @('--rule', 'unused-global')
  function Err([string[]]$More) {
    $f = Join-Path $Tmp 'err.txt'
    & $E lint-all --db $Db @Rule @More 1> $null 2> $f
    return [IO.File]::ReadAllText($f)
  }
  $Warn = 'no platform library for this run'
  $none = Err @()
  Check 'W1 no library named anywhere: one warning line' (([regex]::Matches($none, $Warn)).Count -eq 1) $none
  Check 'W2 the line says what is lost and what to do' (($none -match 'are dropped') -and ($none -match '--library-db')) $none
  Check 'C1 control: --library-db none says nothing' ((Err @('--library-db', 'none')) -notmatch $Warn)
  Check 'C2 control: a named library says nothing' ((Err @('--library-db', $Db)) -notmatch $Warn)
  Check 'C3 --quiet says nothing' ((Err @('--quiet')) -notmatch $Warn)
  Check 'C4 --json keeps its stderr clean, as the loaded-defaults banner does' ((Err @('--json')) -notmatch $Warn)
}
finally {
  try { [IO.Directory]::Delete($Tmp, $true) } catch { Write-Host "note: scratch left: $Tmp" }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
