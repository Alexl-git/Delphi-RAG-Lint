<#
  Lane A5 store-backed fixers (DRagLint.Fix.Store): the cases the generic
  harness cannot drive. Cases 1-3 are findings the fixer must DECLINE, so the
  file keeps its bytes after the --fix --apply run. Case 4 is the positive
  discarded-effect-free-result case: that rule runs in lint-all only (a bare
  `lint --file --db` never reports it), so it is driven through lint-all and
  compared to store-fixes\discarded-effect-free-result\upure.fixed.pas.
  Other positive cases: tests\autofix\fixtures\<id>\ (run_fix_fixtures.ps1).
    1. unused-private-member, overloaded private method             -> declined
    2. unused-private-member, stale index (second run, no reindex)  -> declined
    3. discarded-effect-free-result as the lone `then` statement    -> declined
    4. discarded-effect-free-result, a bare call line               -> deleted
  Each case also checks the rule FIRES (positive control), so a silent rule
  cannot pass it. Exit 0 = all pass.
#>
param([string]$Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'),
      [string]$WorkDir = (Join-Path $env:TEMP 'draglint-store-fix-negatives'))
$ErrorActionPreference = 'Continue'
$exePath = (Resolve-Path $Exe).Path
$fail = 0; $pass = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; Write-Host "PASS $Name" } else { $script:fail++; Write-Host "FAIL $Name $Detail" }
}
function NewCase([string]$Name, [string[]]$Lines) {
  $dir = Join-Path $WorkDir $Name
  if (Test-Path $dir) { [IO.Directory]::Delete($dir, $true) }
  New-Item -ItemType Directory -Force $dir | Out-Null
  $file = Join-Path $dir "u$Name.pas"
  [IO.File]::WriteAllText($file, ($Lines -join "`r`n") + "`r`n")
  $db = Join-Path $dir '_case.sqlite'
  Push-Location $dir
  try { & $exePath index $dir --db $db *> (Join-Path $dir '_index.log') } finally { Pop-Location }
  return @{ File = $file; Db = $db; Dir = $dir }
}
function FixOnce($C, [string]$Rule, [string[]]$Extra) {
  Push-Location $C.Dir
  try { & $exePath lint --file $C.File --db $C.Db --fix --fix-rule $Rule --apply --no-backup @Extra *> (Join-Path $C.Dir '_fix.log') } finally { Pop-Location }
}
function FixAll($C, [string]$Rule, [string[]]$Extra) {
  Push-Location $C.Dir
  try { & $exePath lint-all --db $C.Db --fix --fix-rule $Rule --apply --no-backup @Extra *> (Join-Path $C.Dir '_fixall.log') } finally { Pop-Location }
}
function Fires($C,[string]$Rule, [string[]]$Extra) {
  $raw = & $exePath lint --file $C.File --db $C.Db --rule $Rule --json @Extra 2>$null | Out-String
  try { return @(@($raw | ConvertFrom-Json) | Where-Object { $_.rule -eq $Rule }).Count } catch { return -1 }
}

# 1. overloaded private method: the impl header is ambiguous
$c1 = NewCase 'overload' @(
  'unit uoverload;', '', 'interface', '', 'type', '  TBox = class', '  private',
  '    procedure Dead(A: Integer); overload;', '    procedure Dead(const S: string); overload;',
  '  public', '    procedure Run;', '  end;', '', 'implementation', '',
  'procedure TBox.Dead(A: Integer);', 'begin', 'end;', '',
  'procedure TBox.Dead(const S: string);', 'begin', 'end;', '',
  'procedure TBox.Run;', 'begin', 'end;', '', 'end.')
$before = [IO.File]::ReadAllText($c1.File)
Check 'overload: the rule fires (positive control)' ((Fires $c1 'unused-private-member' @()) -ge 1)
FixOnce $c1 'unused-private-member' @()
Check 'overload: file unchanged' ([IO.File]::ReadAllText($c1.File) -eq $before)

# 2. stale index: apply once, then a second run WITHOUT reindex must not delete what moved up
$c2 = NewCase 'stale' @(
  'unit ustale;', '', 'interface', '', 'type', '  TBox = class', '  private',
  '    FDead: Integer;', '    FLive: Integer;', '  public', '    procedure Run;', '  end;', '',
  'implementation', '', 'procedure TBox.Run;', 'begin', '  FLive:= 1;', 'end;', '', 'end.')
FixOnce $c2 'unused-private-member' @()
$after1 = [IO.File]::ReadAllText($c2.File)
Check 'stale: first run deleted FDead (positive control)' ((-not $after1.Contains('FDead')) -and $after1.Contains('FLive: Integer;'))
FixOnce $c2 'unused-private-member' @()
Check 'stale: second run on the stale index kept FLive' ([IO.File]::ReadAllText($c2.File) -eq $after1)

# 3. the call is the lone statement of a `then`: deleting it would re-bind the next statement
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$cfg = Join-Path $WorkDir 'pure.config.json'
[IO.File]::WriteAllText($cfg, '{"enabled":["discarded-effect-free-result"]}')
$c3 = NewCase 'then' @(
  'unit uthen;', '', 'interface', '', 'function Twice(A: Integer): Integer;', 'procedure Run(X: Integer);', '',
  'implementation', '', 'function Twice(A: Integer): Integer;', 'begin', '  Result:= A * 2;', 'end;', '',
  'procedure Run(X: Integer);', 'begin', '  if X > 0 then', '    Twice(5);', '  Writeln(X);', 'end;', '', 'end.')
$before = [IO.File]::ReadAllText($c3.File)
Check 'then: the rule fires (positive control)' ((Fires $c3 'discarded-effect-free-result' @('--config', $cfg)) -ge 1)
FixAll $c3 'discarded-effect-free-result' @('--config', $cfg)
Check 'then: file unchanged' ([IO.File]::ReadAllText($c3.File) -eq $before)

# 4. positive: the bare call line is deleted (lint-all) and matches the hand-written result
$src4 = Join-Path $PSScriptRoot 'store-fixes\discarded-effect-free-result'
$c4 = NewCase 'pure' @('unit upure;')
[IO.File]::Copy((Join-Path $src4 'upure.pas'), $c4.File, $true)
Push-Location $c4.Dir
try { & $exePath index $c4.Dir --db $c4.Db *> (Join-Path $c4.Dir '_index2.log') } finally { Pop-Location }
Check 'pure: the rule fires (positive control)' ((Fires $c4 'discarded-effect-free-result' @('--config', $cfg)) -ge 1)
FixAll $c4 'discarded-effect-free-result' @('--config', $cfg)
Check 'pure: lint-all --fix --apply matches upure.fixed.pas' ([IO.File]::ReadAllText($c4.File) -eq [IO.File]::ReadAllText((Join-Path $src4 'upure.fixed.pas')))
Push-Location $c4.Dir
try { & $exePath index $c4.Dir --db $c4.Db *> (Join-Path $c4.Dir '_reindex.log') } finally { Pop-Location }
Check 'pure: the rule no longer fires after a reindex' ((Fires $c4 'discarded-effect-free-result' @('--config', $cfg)) -eq 0)

Write-Host "store fixes: $pass passed, $fail failed"
exit $(if ($fail -eq 0) { 0 } else { 1 })
