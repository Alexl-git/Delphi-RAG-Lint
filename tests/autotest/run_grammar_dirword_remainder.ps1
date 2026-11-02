<#
  run_grammar_dirword_remainder.ps1 -- TSITTER-DIRWORD remainder (1.40): directive and
  calling-convention words used as NAMES parse and are indexed in every slot the
  ext-dirword lane left open (docs\INBOX-grammar-directive-word-names.md "Still open
  after D"), measured on grammar tree-sitter-delphi13 v1.4.0 (1.39.2).

  CASES (one unit each; each was RED on the pre-1.39.2 grammar, 16 findings):
    recCallconvLater   a record field named Stdcall/Cdecl/Pascal/Register/Safecall/Winapi/Inline AFTER a prior field
    clsCallconvLater   the same in a class
    varCallconvLater   a unit var named Stdcall / Cdecl after a prior var
    constCallconvLater a const named Stdcall after a prior const
    varLibraryHint     `var C: Integer library;` (pre-`;` hint on a var)
    localVarDirword    routine locals named Platform/Deprecated/Stdcall/Absolute
    outParam / paramDirword / enumDirword / propDirword   params, enum values, properties
  ASSERTS: zero parser-error / syntax-error findings over the set, and every name is a symbol.
  POSITIVE CONTROL: a broken twin (missing ':') raises a finding, so the zero is a real
  zero; the first name of each list (always parsed) is found, so the symbol read works.

  Usage: pwsh -File tests/autotest/run_grammar_dirword_remainder.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\drag-lint-dirword-rest-$PID"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

# name -> @(interface text, implementation text, expected symbol names; the FIRST is the control)
$cases = [ordered]@{
  recCallconvLater   = @("type`n  TR = record`n    A: Integer;`n    Stdcall: Integer;`n    Cdecl, Pascal: Integer;`n    Register: Integer;`n    Safecall: Integer;`n    Winapi: Integer;`n    Inline: Integer;`n  end;", '',
                         @('A', 'Stdcall', 'Cdecl', 'Pascal', 'Register', 'Safecall', 'Winapi', 'Inline'))
  clsCallconvLater   = @("type`n  TC = class`n    FA: Integer;`n    Stdcall: Integer;`n  end;", '', @('FA', 'Stdcall'))
  varCallconvLater   = @("var`n  A: Integer;`n  Stdcall: Integer;`n  Cdecl: Integer;", '', @('A', 'Stdcall', 'Cdecl'))
  constCallconvLater = @("const`n  A = 1;`n  Stdcall = 2;", '', @('A', 'Stdcall'))
  varLibraryHint     = @("var`n  C: Integer library;", '', @('C'))
  localVarDirword    = @("procedure Q;", "procedure Q;`nvar`n  Platform: Integer;`n  Deprecated: Integer;`n  Stdcall: Integer;`n  Absolute: Integer;`nbegin`n  Platform:= 1;`n  Stdcall:= Platform;`nend;",
                         @('Q', 'Platform', 'Deprecated', 'Stdcall', 'Absolute'))
  outParam           = @("procedure P(const Out: Integer);", "procedure P(const Out: Integer);`nbegin`nend;", @('P', 'Out'))
  paramDirword       = @("procedure R(Platform, Message, Name, Index, Read, Write, Default: Integer);",
                         "procedure R(Platform, Message, Name, Index, Read, Write, Default: Integer);`nbegin`nend;",
                         @('R', 'Platform', 'Message', 'Name', 'Index', 'Read', 'Write', 'Default'))
  enumDirword        = @("type`n  TE = (Platform, Deprecated, Library, Message, Stdcall, Register);", '',
                         @('TE', 'Platform', 'Deprecated', 'Library', 'Message', 'Stdcall', 'Register'))
  propDirword        = @("type`n  TP = class`n    function GetX: Integer;`n    property Platform: Integer read GetX;`n    property Stdcall: Integer read GetX;`n  end;",
                         "function TP.GetX: Integer;`nbegin`n  Result:= 0;`nend;", @('GetX', 'Platform', 'Stdcall'))
}

function Write-Unit([string]$Dir, [string]$Name, [string]$Intf, [string]$Impl) {
  $t = "unit $Name;`n`ninterface`n`n$Intf`n`nimplementation`n`n$Impl`n`nend.`n"
  [IO.File]::WriteAllText((Join-Path $Dir "$Name.pas"), ($t -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

function Get-ParseFindings([string]$Dir, [string]$Db) {
  $all = @()
  Push-Location $Dir
  try {
    foreach ($r in 'parser-error', 'syntax-error') {
      $raw = & $Exe lint $Dir --db $Db --rule $r --json 2>$null | Out-String
      try { $all += @($raw | ConvertFrom-Json) } catch {}
    }
  } finally { Pop-Location }
  return @($all | Where-Object { $_.rule -in 'parser-error', 'syntax-error' })
}

function Build-Db([string]$Dir, [string]$Db) {
  Push-Location $Dir
  try { $null = & $Exe index $Dir --db $Db --library-db none --rule-cache-warm off 2>&1 } finally { Pop-Location }
  return $LASTEXITCODE
}

try {
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $good = Join-Path $WorkDir 'good'; $bad = Join-Path $WorkDir 'bad'
  [void][IO.Directory]::CreateDirectory($good); [void][IO.Directory]::CreateDirectory($bad)
  foreach ($k in $cases.Keys) { Write-Unit $good $k $cases[$k][0] $cases[$k][1] }
  # POSITIVE CONTROL twin: the record case with a missing ':' -- a real syntax error.
  Write-Unit $bad 'recCallconvLater' ($cases['recCallconvLater'][0] -replace 'A: Integer;', 'A Integer;') ''

  $gdb = Join-Path $good 'g.sqlite'; $bdb = Join-Path $bad 'b.sqlite'
  Check 'index exits 0 (good)' ((Build-Db $good $gdb) -eq 0)
  Check 'index exits 0 (bad)' ((Build-Db $bad $bdb) -eq 0)

  $badHits = Get-ParseFindings $bad $bdb
  Check 'CONTROL broken twin raises parser-error/syntax-error' ($badHits.Count -gt 0) "count=$($badHits.Count)"

  $hits = Get-ParseFindings $good $gdb
  Check 'ASSERT zero parser-error/syntax-error over the directive-word set' ($hits.Count -eq 0) `
    ("count={0} {1}" -f $hits.Count, (($hits | ForEach-Object { '{0}:L{1}' -f [IO.Path]::GetFileNameWithoutExtension($_.file_path), $_.start_line }) -join ','))

  Push-Location $good
  try {
    $j = & $Exe sql --db $gdb --query "SELECT f.path, s.name FROM symbols s JOIN files f ON f.id = s.file_id" --json 2>$null | Out-String
  } finally { Pop-Location }
  $rows = @()
  try { $rows = @(($j | ConvertFrom-Json).rows) } catch {}
  foreach ($k in $cases.Keys) {
    $mine = @($rows | Where-Object { [IO.Path]::GetFileNameWithoutExtension([string]$_[0]) -eq $k } | ForEach-Object { [string]$_[1] })
    $want = @($cases[$k][2])
    Check "CONTROL ${k}: first name $($want[0])" ([bool]($mine | Where-Object { $_ -ceq $want[0] }))
    $missing = @($want | Select-Object -Skip 1 | Where-Object { $n = $_; -not ($mine | Where-Object { $_ -ceq $n }) })
    Check "ASSERT ${k}: every directive-word name is a symbol" ($missing.Count -eq 0) ("missing=" + ($missing -join ','))
  }
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch {} }
}
Write-Host ''
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
