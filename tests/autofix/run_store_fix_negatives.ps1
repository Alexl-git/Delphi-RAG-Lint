<#
  Lane A5 negative controls for the store-backed fixers (DRagLint.Fix.Store):
  every case below is a finding the fixer must DECLINE, so the file keeps its
  bytes after `lint --fix --apply --db <scratch>`. Positive cases live in
  tests\autofix\fixtures\<id>\ (run_fix_fixtures.ps1).
    1. unused-private-member, overloaded private method             -> declined
    2. unused-private-member, stale index (second run, no reindex)  -> declined
    3. discarded-effect-free-result as the lone `then` statement    -> declined
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
function Fires($C, [string]$Rule, [string[]]$Extra) {
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
FixOnce $c3 'discarded-effect-free-result' @('--config', $cfg)
Check 'then: file unchanged' ([IO.File]::ReadAllText($c3.File) -eq $before)

Write-Host "store-fix negatives: $pass passed, $fail failed"
exit $(if ($fail -eq 0) { 0 } else { 1 })
