<#
  run_msp_split_arglist.ps1 -- multiple-statements-per-line must not fire inside
  a CALL whose argument list is split across lines.

  THE DEFECT
    DataCopy, 2026-09-01 (stats\draglint-gaps.log, class `wrong`):
    Test.UsageWiring.pas reported the rule at a column INSIDE the second
    argument of a wrapped CreateProcess call. The line is one statement.

    Cause: IsStatementNodeType accepts 'exprCall', and a typecast such as
    PChar(X) is an exprCall too. When a call's argument list is split across
    lines the parse can hand arguments back as DIRECT NAMED CHILDREN of the
    enclosing block, where they look exactly like siblings sharing a row. The
    "second statement" was `PChar(LCmd)`.

    The fix discriminates on what SEPARATES the two nodes in the source: real
    packing is separated by a semicolon, an argument list by a comma.

  HOW THIS FIXTURE WAS OBTAINED, AND WHY THAT MATTERS
    Two hypotheses were tested and REFUTED by the previous session -- argument
    commas counted as separators, and angle brackets confusing the scan -- and
    a synthetic fixture written from the description stayed silent while the
    real file fired. Eight further hand-written variants (with/without `not`, a
    comparison argument, nils, try/finally, try/except, a preceding
    if..begin..end) were ALSO all silent.

    What worked was delta-debugging the REAL routine down while requiring that
    it still reproduce, which is why the fixture below is close to verbatim
    rather than tidy. Do not "clean it up": every element here was kept because
    removing it made the finding disappear.

  POSITIVE CONTROL
    Genuine packing -- `A := 1; B := 2;` and two calls on one line -- must still
    fire, or the fix bought silence by disabling the rule.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-msp-arglist"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

function Fire($name, $lines) {
  $f = Join-Path $WorkDir $name
  [IO.File]::WriteAllLines($f, [string[]]$lines, (New-Object Text.ASCIIEncoding))
  $out = & $Exe lint $f --enable multiple-statements-per-line 2>&1 | Out-String
  ,@($out -split "`r?`n" | Select-String 'multiple-statements-per-line' | ForEach-Object { $_.ToString().Trim() })
}

# ---------------------------------------------------------------------------
Write-Host 'THE DEFECT -- a split argument list is not two statements' -ForegroundColor Cyan
$hits = Fire 'ArgList.pas' @(
  'unit ArgList;'
  ''
  'interface'
  ''
  'implementation'
  ''
  'uses'
  '  Winapi.Windows, System.SysUtils;'
  ''
  'function RunTool(const AExeName, AArgs: string): Integer;'
  'var'
  '  LStart: TStartupInfo       ;'
  '  LProc : TProcessInformation;'
  '  LExe  : string             ;'
  '  LCmd  : string             ;'
  '  LNul  : THandle            ;'
  'begin'
  '  Result := -1;'
  '  LNul := INVALID_HANDLE_VALUE;'
  '  try'
  '    LStart.wShowWindow:= SW_HIDE;'
  '    if LNul <> INVALID_HANDLE_VALUE then'
  '    begin'
  '      LStart.dwFlags     := LStart.dwFlags or STARTF_USESTDHANDLES;'
  '      LStart.hStdInput   := LNul;'
  '    end; // if'
  '    if not CreateProcess(PChar(LExe), PChar(LCmd), nil, nil, LNul <> INVALID_HANDLE_VALUE,'
  '                         CREATE_NO_WINDOW, nil, nil, LStart, LProc) then'
  '      exit;'
  '  finally'
  '    if LNul <> INVALID_HANDLE_VALUE then'
  '      CloseHandle(LNul);'
  '  end;'
  'end;'
  ''
  'end.'
)
Check 'no finding inside the wrapped CreateProcess call' ($hits.Count -eq 0) ($hits -join ' | ')

# ---------------------------------------------------------------------------
Write-Host 'POSITIVE CONTROL -- real packing still fires' -ForegroundColor Cyan
$tp = Fire 'TruePos.pas' @(
  'unit TruePos;'
  ''
  'interface'
  ''
  'implementation'
  ''
  'procedure P;'
  'var'
  '  A, B: Integer;'
  'begin'
  '  A := 1; B := 2;'
  '  Writeln(A); Writeln(B);'
  'end;'
  ''
  'end.'
)
Check 'assignment packing on line 11 fires' ([bool]($tp -match ':11:')) ($tp -join ' | ')
Check 'call packing on line 12 fires'       ([bool]($tp -match ':12:')) ($tp -join ' | ')

# ---------------------------------------------------------------------------
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
