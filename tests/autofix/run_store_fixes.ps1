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
  Lane A5B (cases 5-14): unused-public-symbol own-unit tier (5 fixed, 6 early caller declined),
  unused-unit-in-uses (7 fixed + init-section unit kept, 8 stale), classname-string-compare
  (9 no --db, 10 metaclass Self / unknown class), empty-procedure-body (11 called / override,
  12 stale, 14 no --db), property-accessor-name (13 shifted index writes nothing).
  Each case also checks the rule FIRES (positive control), so a silent rule
  cannot pass it. Exit 0 = all pass.
#>
param([string]$Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'),
      [string]$WorkDir = (Join-Path $env:TEMP ('draglint-store-fix-negatives-' + $PID)))
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

# ---- lane A5B -------------------------------------------------------------------------------
# A copied multi-unit case: every non-.fixed .pas of store-fixes\<Id> beside each other, indexed.
function CopyCase([string]$Name, [string]$Id) {
  $dir = Join-Path $WorkDir $Name
  if (Test-Path $dir) { [IO.Directory]::Delete($dir, $true) }
  New-Item -ItemType Directory -Force $dir | Out-Null
  $src = Join-Path $PSScriptRoot "store-fixes\$Id"
  foreach ($f in @(Get-ChildItem $src -Filter '*.pas' | Where-Object { $_.Name -notlike '*.fixed.pas' })) {
    [IO.File]::Copy($f.FullName, (Join-Path $dir $f.Name), $true)
  }
  $db = Join-Path $dir '_case.sqlite'
  Push-Location $dir
  try { & $exePath index $dir --db $db *> (Join-Path $dir '_index.log') } finally { Pop-Location }
  return @{ Dir = $dir; Db = $db; Src = $src }
}
function Reindex($C) {
  Push-Location $C.Dir
  try { & $exePath index $C.Dir --db $C.Db *> (Join-Path $C.Dir '_reindex.log') } finally { Pop-Location }
}
# lint-all rows of one rule in one file whose message contains $Needle
function AllRows($C, [string]$Rule, [string]$FileName, [string]$Needle) {
  Push-Location $C.Dir
  try { $raw = & $exePath lint-all --db $C.Db --rule $Rule --json 2>$null | Out-String } finally { Pop-Location }
  try {
    return @(@($raw | ConvertFrom-Json) | Where-Object {
      $_.rule -eq $Rule -and ([IO.Path]::GetFileName($_.file_path) -eq $FileName) -and $_.message.Contains($Needle) }).Count
  } catch { return -1 }
}
function SameAsFixed($C, [string]$Case) {
  return [IO.File]::ReadAllText((Join-Path $C.Dir "$Case.pas")) -eq [IO.File]::ReadAllText((Join-Path $C.Src "$Case.fixed.pas"))
}

# 5. unused-public-symbol, own-unit tier: the interface prototype goes, its doc moves to the body
$c5 = CopyCase 'pub' 'unused-public-symbol'
Check 'pub: the own-unit tier fires for Twice (positive control)' ((AllRows $c5 'unused-public-symbol' 'upub.pas' 'Twice is only referenced within its own unit') -eq 1)
FixAll $c5 'unused-public-symbol' @()
Check 'pub: lint-all --fix --apply matches upub.fixed.pas' (SameAsFixed $c5 'upub')
Reindex $c5
Check 'pub: Twice is no longer reported after a reindex' ((AllRows $c5 'unused-public-symbol' 'upub.pas' 'Twice') -eq 0)
$before = [IO.File]::ReadAllText((Join-Path $c5.Dir 'upub.pas'))
FixAll $c5 'unused-public-symbol' @()
Check 'pub: a second run changes nothing' ([IO.File]::ReadAllText((Join-Path $c5.Dir 'upub.pas')) -eq $before)

# 6. unused-public-symbol: a caller ABOVE the body needs the prototype -> declined
$c6 = NewCase 'pubearly' @(
  'unit upubearly;', '', 'interface', '', 'function Twice(A: Integer): Integer;', 'procedure Run;', '',
  'implementation', '', 'procedure Run;', 'begin', '  Writeln(Twice(2));', 'end;', '',
  'function Twice(A: Integer): Integer;', 'begin', '  Result:= A * 2;', 'end;', '', 'end.')
$before = [IO.File]::ReadAllText($c6.File)
Check 'pubearly: the own-unit tier fires (positive control)' ((AllRows $c6 'unused-public-symbol' 'upubearly.pas' 'Twice is only referenced within its own unit') -eq 1)
FixAll $c6 'unused-public-symbol' @()
Check 'pubearly: file unchanged (the call precedes the body)' ([IO.File]::ReadAllText($c6.File) -eq $before)

# 7. unused-unit-in-uses: one-per-line and shared-line entries go; the initialization-section unit stays
$c7 = CopyCase 'uses' 'unused-unit-in-uses'
Check 'uses: ubhelp is reported (positive control)' ((AllRows $c7 'unused-unit-in-uses' 'uuses.pas' "'ubhelp'") -eq 1)
Check 'uses: leading-comma entries reported (positive control: 2 + 2)' (((AllRows $c7 'unused-unit-in-uses' 'uusesl1.pas' "'") -eq 2) -and ((AllRows $c7 'unused-unit-in-uses' 'uusesl2.pas' "'") -eq 2))
Check 'uses: uihelp is reported with its initialization caveat (positive control)' ((AllRows $c7 'unused-unit-in-uses' 'uuses.pas' "'uihelp'") -eq 1)
FixAll $c7 'unused-unit-in-uses' @()
Check 'uses: lint-all --fix --apply matches uuses.fixed.pas' (SameAsFixed $c7 'uuses')
# lane IATOM: the house leading-comma layout -- first entry (next one promoted), last entry holding the ;,
# middle entry, last entry before a ; on its own line
Check 'uses: leading-comma uusesl1 matches uusesl1.fixed.pas (first + last-with-;)' (SameAsFixed $c7 'uusesl1')
Check 'uses: leading-comma uusesl2 matches uusesl2.fixed.pas (middle + last-before-;)' (SameAsFixed $c7 'uusesl2')
Reindex $c7
Check 'uses: only uihelp is still reported after a reindex' (((AllRows $c7 'unused-unit-in-uses' 'uuses.pas' "'") -eq 1) -and ((AllRows $c7 'unused-unit-in-uses' 'uuses.pas' "'uihelp'") -eq 1))

# 8. unused-unit-in-uses, stale index: a second run WITHOUT a reindex must not cut what moved
$c8 = CopyCase 'usesstale' 'unused-unit-in-uses'
FixAll $c8 'unused-unit-in-uses' @()
$after1 = [IO.File]::ReadAllText((Join-Path $c8.Dir 'uuses.pas'))
FixAll $c8 'unused-unit-in-uses' @()
Check 'usesstale: second run on the stale index changed nothing' ([IO.File]::ReadAllText((Join-Path $c8.Dir 'uuses.pas')) -eq $after1)

# 9. classname-string-compare: without --db the literal cannot be resolved -> declined
$c9 = NewCase 'clsnodb' @(
  'unit uclsnodb;', '', 'interface', '', 'type', '  TBox = class', '    function Kind(X: TObject): Integer;', '  end;', '',
  'implementation', '', 'function TBox.Kind(X: TObject): Integer;', 'begin', '  Result:= 0;',
  '  if X.ClassName = ''TBox'' then Result:= 1;', 'end;', '', 'end.')
$before = [IO.File]::ReadAllText($c9.File)
Push-Location $c9.Dir
try { & $exePath lint --file $c9.File --fix --fix-rule classname-string-compare --apply --no-backup *> (Join-Path $c9.Dir '_fixnodb.log') } finally { Pop-Location }
Check 'clsnodb: the rule fires (positive control)' ((Fires $c9 'classname-string-compare' @()) -ge 1)
Check 'clsnodb: file unchanged without --db' ([IO.File]::ReadAllText($c9.File) -eq $before)

# 10. classname-string-compare: Self in a CLASS method is a metaclass (no ClassType); an unknown class -> declined
$c10 = NewCase 'clsmeta' @(
  'unit uclsmeta;', '', 'interface', '', 'type', '  TBox = class', '    class function IsBox: Boolean;', '    function IsForm(X: TObject): Boolean;', '  end;', '',
  'implementation', '', 'class function TBox.IsBox: Boolean;', 'begin', '  Result:= Self.ClassName = ''TBox'';', 'end;', '',
  'function TBox.IsForm(X: TObject): Boolean;', 'begin', '  Result:= X.ClassName = ''TNoSuchForm'';', 'end;', '', 'end.')
$before = [IO.File]::ReadAllText($c10.File)
Check 'clsmeta: the rule fires twice (positive control)' ((Fires $c10 'classname-string-compare' @()) -eq 2)
FixOnce $c10 'classname-string-compare' @()
Check 'clsmeta: file unchanged' ([IO.File]::ReadAllText($c10.File) -eq $before)

# 11. empty-procedure-body: a CALLED empty routine and an override are kept
$c11 = NewCase 'emptylive' @(
  'unit uemptylive;', '', 'interface', '', 'type', '  TBox = class', '  public', '    procedure AfterConstruction; override;', '    procedure Hook;', '    procedure Run;', '  end;', '',
  'implementation', '', 'procedure TBox.AfterConstruction;', 'begin', 'end;', '',
  'procedure TBox.Hook;', 'begin', 'end;', '', 'procedure TBox.Run;', 'begin', '  Hook;', 'end;', '', 'end.')
$before = [IO.File]::ReadAllText($c11.File)
Check 'emptylive: the rule fires twice (positive control)' ((Fires $c11 'empty-procedure-body' @()) -eq 2)
FixOnce $c11 'empty-procedure-body' @()
Check 'emptylive: file unchanged' ([IO.File]::ReadAllText($c11.File) -eq $before)

# 12. empty-procedure-body, stale index: a second run WITHOUT a reindex must not delete what moved up
$c12 = NewCase 'emptystale' @(
  'unit uemptystale;', '', 'interface', '', 'procedure Run;', '', 'implementation', '',
  'procedure Lonely;', 'begin', 'end;', '', 'procedure Other;', 'begin', 'end;', '',
  'procedure Run;', 'begin', '  Other;', 'end;', '', 'end.')
FixOnce $c12 'empty-procedure-body' @()
$after1 = [IO.File]::ReadAllText($c12.File)
Check 'emptystale: first run deleted Lonely only (positive control)' ((-not $after1.Contains('Lonely')) -and $after1.Contains('procedure Other;'))
FixOnce $c12 'empty-procedure-body' @()
Check 'emptystale: second run on the stale index kept Other' ([IO.File]::ReadAllText($c12.File) -eq $after1)
# 13. property-accessor-name on a STALE index (a line inserted above everything after indexing):
#     every recorded position is off by one, so the rename must write nothing at all
$c13 = NewCase 'accstale' @(
  'unit uaccstale;', '', 'interface', '', 'type', '  TBox = class', '  private', '    function Reader: Integer;',
  '  public', '    property Count: Integer read Reader;', '  end;', '', 'implementation', '',
  'function TBox.Reader: Integer;', 'begin', '  Result:= 1;', 'end;', '', 'end.')
$cfg13 = Join-Path $WorkDir 'acc.config.json'
[IO.File]::WriteAllText($cfg13, '{"enabled":["property-accessor-name"],"autofix":["property-accessor-name"]}')
Check 'accstale: the rule fires (positive control)' ((Fires $c13 'property-accessor-name' @('--config', $cfg13)) -ge 1)
[IO.File]::WriteAllText($c13.File, "{ inserted after indexing }`r`n" + [IO.File]::ReadAllText($c13.File))
$before = [IO.File]::ReadAllText($c13.File)
FixOnce $c13 'property-accessor-name' @('--config', $cfg13)
Check 'accstale: file unchanged on the shifted index' ([IO.File]::ReadAllText($c13.File) -eq $before)

# 14. empty-procedure-body without --db: zero references cannot be proved -> declined
$c14 = NewCase 'emptynodb' @('unit uemptynodb;', '', 'interface', '', 'implementation', '', 'procedure Lonely;', 'begin', 'end;', '', 'end.')
$before = [IO.File]::ReadAllText($c14.File)
Push-Location $c14.Dir
try { & $exePath lint --file $c14.File --fix --fix-rule empty-procedure-body --apply --no-backup *> (Join-Path $c14.Dir '_fixnodb.log') } finally { Pop-Location }
Check 'emptynodb: file unchanged without --db' ([IO.File]::ReadAllText($c14.File) -eq $before)

Write-Host "store fixes: $pass passed, $fail failed"
exit $(if ($fail -eq 0) { 0 } else { 1 })
