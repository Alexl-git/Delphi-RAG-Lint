<#
  run_marker_unused_inactive_line.ps1 -- a `dl:ok` marker on a line the preprocessor
  blanked must not be reported `review-marker-unused`.

  YADF FALSE POSITIVE #6 (docs\INBOX-yadf-false-positives-2026-11-03.md).
  YADFOT.CodeFormatter.inc gates a try..except behind {$IF DECLARED(IOTACodeFormatter)}.
  An exe with no drag-lint.json beside it finds no library, DECLARED is false, the
  region is inactive and no rule sees the code -- so its two markers read "no longer
  matches any finding -- remove it". The run has no evidence about that line: the
  rules never saw it. ApplyLineMarkers now skips the unused verdict on such a line,
  decided by the SAME TAstParseCache.ApplyPreprocess the rules read. Which branch
  DECLARED selects is untouched (that is extraction; backlog NEXT-BUMP).

  FIXTURE uInact.pas: dl:ok self-assignment markers (no finding anywhere) on
    L_IFDEF    inside {$IFDEF <never defined>}
    L_DECLARED inside {$IF NOT DECLARED(<no such symbol>)}: with no library DECLARED reads True (1.43, run_pp_declared_no_library.ps1), so this THEN is the inactive one
    L_ELSE     in that $IF's {$ELSE}, which IS active
    L_PLAIN    an ordinary active line
  and uInact.inc, a bare include holding the {$IFDEF} shape (L_INC, inactive).

  1 FIX      lint: no hint at L_IFDEF / L_DECLARED (RED on 1.42 c2c4b750)
  2 FIX      lint-all: same verdict (the two verbs share the seam)
  3 FIX      lint uInact.inc: no hint at L_INC (the real case was an include)
  CONTROLS
  4 lint: L_ELSE and L_PLAIN STILL report unused (the rule is on)
  5 lint-all: L_ELSE and L_PLAIN STILL report unused
  6 lint --no-preprocess: every branch is parsed, so L_IFDEF IS judged again

  Run from a neutral cwd, pwsh 7. Default -Exe has no drag-lint.json beside it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_marker_inactive_$PID"
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'g8-common.ps1')
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe   # 150 H1: no machine drag-lint.json
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $src | Out-Null

$pasLines = @(
  'unit uInact;', '', 'interface', '', 'procedure P;', '', 'implementation', '',
  'procedure P;', 'var', '  X: Integer;', 'begin', '  X := 1;',
  '{$IFDEF DRAGLINT_NEVER_DEFINED_6}',
  '  X := 2; // dl:ok self-assignment -- inactive ifdef',
  '{$ENDIF}',
  '{$IF NOT DECLARED(DragLintNoSuchSymbol6)}',
  '  X := 3; // dl:ok self-assignment -- inactive declared',
  '{$ELSE}',
  '  X := 4; // dl:ok self-assignment -- active else',
  '{$IFEND}',
  '  X := 5; // dl:ok self-assignment -- active plain',
  '  if X > 0 then Exit;',
  'end;', '', 'end.')
$incLines = @(
  '{$IFDEF DRAGLINT_NEVER_DEFINED_6}',
  'X := 6; // dl:ok self-assignment -- inactive in an include',
  '{$ENDIF}')
$pasPath = Join-Path $src 'uInact.pas'
$incPath = Join-Path $src 'uInact.inc'
$ascii = New-Object System.Text.ASCIIEncoding
[IO.File]::WriteAllText($pasPath, ($pasLines -join "`r`n") + "`r`n", $ascii)
[IO.File]::WriteAllText($incPath, ($incLines -join "`r`n") + "`r`n", $ascii)
function LineOf([string[]]$Lines, [string]$Tail) {
  for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i].EndsWith($Tail)) { return $i + 1 } }
  throw "fixture line not found: $Tail"
}
$lIfdef    = LineOf $pasLines 'inactive ifdef'
$lDeclared = LineOf $pasLines 'inactive declared'
$lElse     = LineOf $pasLines 'active else'
$lPlain    = LineOf $pasLines 'active plain'
$lInc      = LineOf $incLines 'inactive in an include'

$db = Join-Path $WorkDir 'u.sqlite'
$code = Invoke-G8Index $Exe $src $db
Check 'fixture index built' (($code -eq 0) -and (Test-Path $db)) "exit=$code"

# `lint --json` is a bare array and its line field is start_line. The rule id
# field `rule` is pinned by the positive controls: a wrong name fails checks 4 and 5.
function UnusedLines([string[]]$CmdArgs) {
  $raw = (& $Exe @CmdArgs 2>$null | ForEach-Object { "$_" }) -join "`n"
  $start = $raw.IndexOf('[')
  if ($start -lt 0) { return ,@() }
  $rows = @($raw.Substring($start) | ConvertFrom-Json)
  return ,@($rows | Where-Object { $_.rule -eq 'review-marker-unused' } | ForEach-Object { [int]$_.start_line })
}

$cwd = Join-Path $WorkDir 'cwd'
New-Item -ItemType Directory -Force $cwd | Out-Null
Push-Location $cwd
try {
  $u1 = UnusedLines @('lint', $pasPath, '--db', $db, '--json')
  Check '1 lint: no unused hint on the {$IFDEF} inactive line' ($u1 -notcontains $lIfdef) "lines=$($u1 -join ',')"
  Check '1 lint: no unused hint on the DECLARED inactive line' ($u1 -notcontains $lDeclared) "lines=$($u1 -join ',')"
  Check '4 CONTROL lint: the active {$ELSE} line still reports unused' ($u1 -contains $lElse) "lines=$($u1 -join ',')"
  Check '4 CONTROL lint: the plain active line still reports unused' ($u1 -contains $lPlain) "lines=$($u1 -join ',')"

  $u2 = UnusedLines @('lint-all', '--db', $db, '--json')
  Check '2 lint-all: no unused hint on the {$IFDEF} inactive line' ($u2 -notcontains $lIfdef) "lines=$($u2 -join ',')"
  Check '2 lint-all: no unused hint on the DECLARED inactive line' ($u2 -notcontains $lDeclared) "lines=$($u2 -join ',')"
  Check '5 CONTROL lint-all: the active {$ELSE} line still reports unused' ($u2 -contains $lElse) "lines=$($u2 -join ',')"
  Check '5 CONTROL lint-all: the plain active line still reports unused' ($u2 -contains $lPlain) "lines=$($u2 -join ',')"

  $u3 = UnusedLines @('lint', $incPath, '--db', $db, '--json')
  Check '3 lint include: no unused hint on the inactive include line' ($u3 -notcontains $lInc) "lines=$($u3 -join ',')"

  $u6 = UnusedLines @('lint', $pasPath, '--db', $db, '--json', '--no-preprocess')
  Check '6 CONTROL --no-preprocess judges the line again' ($u6 -contains $lIfdef) "lines=$($u6 -join ',')"
} finally { Pop-Location }
[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'run_marker_unused_inactive_line: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_marker_unused_inactive_line: PASS' -ForegroundColor Green
exit 0
