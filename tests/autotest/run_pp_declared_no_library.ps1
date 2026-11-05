<#
  run_pp_declared_no_library.ps1 -- {$IF DECLARED(X)} when the run has NO library
  to ask (backlog YADF6-DECLARED-BRANCH; YADF false positive #6).

  THE DEFECT. An exe with no drag-lint.json finds no library, so every library name
  misses and DECLARED(X) reads False: the THEN branch is dropped and the same source
  indexes differently from a run that has the library.

  THE RULING (lane d5b, 1.43). "Not found" and "nobody to ask" are different answers.
    * With a library DB a miss is a real False -- unchanged.
    * With NO library DB and the newest target (37), DECLARED(X) reads TRUE: a feature
      test names something the current compiler usually has (measured on the real tree:
      tkMRecord, RTLVersion131, AnsiChar ...), and the two shapes below stay consistent,
      because the value is decided for DECLARED, not for the whole expression.
    * With NO library DB and an OLDER target, DECLARED(X) stays False: the premise above
      does not hold for an old compiler (`not Declared(TBytes)` shims are for it).
    * The assumption is never silent: pp-unresolved-if reports it.
    * A BARE unknown name in an IF is still unresolved and False.

  SHAPES
    A   {$IF DECLARED(N)}     A_THEN {$ELSE} A_ELSE {$IFEND}
    B   {$IF NOT DECLARED(N)} B_THEN {$ELSE} B_ELSE {$IFEND}
    C   {$IF DECLARED(N)}     C_ONLY {$IFEND}
    no library, target 37 : A_THEN, B_ELSE, C_ONLY     (RED on 1.42: A_ELSE, B_THEN)
    library, or target 12 : A_ELSE, B_THEN, no C_ONLY  (controls: the old answer)

  Run from a neutral cwd, pwsh 7. Default -Exe has no drag-lint.json beside it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_pp_declared_$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$app = Join-Path $WorkDir 'app'
$lib = Join-Path $WorkDir 'lib'
$cwd = Join-Path $WorkDir 'cwd'
foreach ($d in @($app, $lib, $cwd)) { [void][IO.Directory]::CreateDirectory($d) }
$ascii = New-Object System.Text.ASCIIEncoding
function WriteLines([string]$Path, [string[]]$Lines) {
  [IO.File]::WriteAllText($Path, ($Lines -join "`r`n") + "`r`n", $ascii)
}

WriteLines (Join-Path $lib 'LibU.pas') @(
  'unit LibU;', '', 'interface', '', 'type', '  TLibThing = class', '  end;', '', 'implementation', '', 'end.')
$unitLines = @(
  'unit UShapes;', '', 'interface', '', 'uses', '  LibU;', '',
  'const', '  LOCAL_K = 1;', '',
  '{$IF DECLARED(DragLintNoSuchName)}', 'const A_THEN = 1;', '{$ELSE}', 'const A_ELSE = 1;', '{$IFEND}', '',
  '{$IF NOT DECLARED(DragLintNoSuchName)}', 'const B_THEN = 1;', '{$ELSE}', 'const B_ELSE = 1;', '{$IFEND}', '',
  '{$IF DECLARED(DragLintNoSuchName)}', 'const C_ONLY = 1;', '{$IFEND}', '',
  '{$IF DECLARED(LOCAL_K)}', 'const D_LOCAL = 1;', '{$IFEND}', '',
  '{$IF DECLARED(TLibThing)}', 'const E_LIBTHING = 1;', '{$IFEND}', '',
  '{$IF DragLintBareUnknown}', 'const F_BARE = 1;', '{$ELSE}', 'const F_BARE_ELSE = 1;', '{$IFEND}', '',
  'implementation', '', 'end.')
WriteLines (Join-Path $app 'UShapes.pas') $unitLines
WriteLines (Join-Path $app 'Shapes.dpr') @('program Shapes;', '', 'uses', "  UShapes in 'UShapes.pas';", '', 'begin', 'end.')
$dpr  = Join-Path $app 'Shapes.dpr'
$pas  = Join-Path $app 'UShapes.pas'
$lineA = [array]::IndexOf($unitLines, '{$IF DECLARED(DragLintNoSuchName)}') + 1
$lineF = [array]::IndexOf($unitLines, '{$IF DragLintBareUnknown}') + 1

function Exec([string[]]$ArgList) {
  Push-Location $cwd
  try { $o = & $Exe @ArgList 2>&1 | ForEach-Object { "$_" } } finally { Pop-Location }
  return @{ Code = $LASTEXITCODE; Out = ($o -join "`n") }
}
# sql --json rows are POSITIONAL arrays.
function Names([string]$Db) {
  $r = Exec @('sql', '--db', $Db, '--query', "SELECT name FROM symbols WHERE kind = 'const'", '--json')
  $set = @((($r.Out | ConvertFrom-Json).rows) | ForEach-Object { [string]$_[0] })
  return ,$set
}
function Picks([string[]]$Set, [string[]]$Want, [string[]]$NotWant) {
  foreach ($w in $Want) { if ($Set -notcontains $w) { return $false } }
  foreach ($w in $NotWant) { if ($Set -contains $w) { return $false } }
  return $true
}
function IndexRun([string]$Tag, [string[]]$Extra) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  $r = Exec (@('index', '--project', $dpr, '--db', $db) + $Extra)
  Check "$Tag index exit 0" ($r.Code -eq 0) "exit=$($r.Code)"
  return $db
}
# lint --json is a bare ARRAY; the fields are rule, message, start_line.
function HintRows([string]$Db, [string[]]$Extra) {
  $r = Exec (@('lint', $pas, '--db', $Db, '--json', '--rule', 'pp-unresolved-if') + $Extra)
  $i = $r.Out.IndexOf('[')
  if ($i -lt 0) { return ,@() }
  return ,@($r.Out.Substring($i) | ConvertFrom-Json)
}

$libDb = Join-Path $WorkDir 'lib.sqlite'
$r = Exec @('index', $lib, '--db', $libDb, '--library-db', 'none')
Check 'library DB built' (($r.Code -eq 0) -and (Test-Path $libDb)) "exit=$($r.Code)"

# 1 no library at all (the exe has no drag-lint.json; the real report)
$n = Names (IndexRun 'nolib' @())
Write-Host ("  consts: {0}" -f ($n -join ','))
Check '1 no library, shape A takes THEN'        (Picks $n @('A_THEN') @('A_ELSE')) ($n -join ',')
Check '1 no library, shape B takes ELSE (consistent with A)' (Picks $n @('B_ELSE') @('B_THEN')) ($n -join ',')
Check '1 no library, shape C keeps its only branch' (Picks $n @('C_ONLY') @()) ($n -join ',')
Check '1 same-file constant still answered'     (Picks $n @('D_LOCAL') @()) ($n -join ',')
Check '1 a BARE unknown name stays False'       (Picks $n @('F_BARE_ELSE') @('F_BARE')) ($n -join ',')

# 2 an explicit "--library-db none" is the same state
$n2 = Names (IndexRun 'none' @('--library-db', 'none'))
Check '2 --library-db none: same branches as no library' (Picks $n2 @('A_THEN', 'B_ELSE', 'C_ONLY') @('A_ELSE', 'B_THEN')) ($n2 -join ',')

# 3 CONTROL with a library: a miss is a real False
$dbLib = IndexRun 'withlib' @('--library-db', $libDb)
$n3 = Names $dbLib
Check '3 CONTROL library: shape A takes ELSE'   (Picks $n3 @('A_ELSE') @('A_THEN')) ($n3 -join ',')
Check '3 CONTROL library: shape B takes THEN'   (Picks $n3 @('B_THEN') @('B_ELSE')) ($n3 -join ',')
Check '3 CONTROL library: shape C is dropped'   (Picks $n3 @() @('C_ONLY')) ($n3 -join ',')
Check '3 CONTROL library: a library symbol is declared' (Picks $n3 @('E_LIBTHING') @()) ($n3 -join ',')

# 4 CONTROL no library, older target: no feature-test premise, the old False
$n4 = Names (IndexRun 'old' @('--target-compiler', '12'))
Check '4 CONTROL target 12, no library: shape A takes ELSE' (Picks $n4 @('A_ELSE') @('A_THEN')) ($n4 -join ',')
Check '4 CONTROL target 12, no library: shape B takes THEN' (Picks $n4 @('B_THEN') @('B_ELSE')) ($n4 -join ',')

# 5 the assumption is reported, and only where it was made
$h = HintRows (Join-Path $WorkDir 'none.sqlite') @('--library-db', 'none')
$assumed = @($h | Where-Object { $_.rule -eq 'pp-unresolved-if' -and $_.start_line -eq $lineA })
Check '5 no library: pp-unresolved-if names the assumption' (($assumed.Count -eq 1) -and ($assumed[0].message -match 'assumed') -and ($assumed[0].message -match 'DragLintNoSuchName')) (($h | ForEach-Object { "$($_.start_line): $($_.message)" }) -join ' | ')
$bare = @($h | Where-Object { $_.rule -eq 'pp-unresolved-if' -and $_.start_line -eq $lineF })
Check '5 CONTROL the bare unknown keeps its "cannot resolve" hint' (($bare.Count -eq 1) -and ($bare[0].message -match 'cannot resolve')) ''
$h2 = HintRows $dbLib @('--library-db', $libDb)
$assumed2 = @($h2 | Where-Object { $_.message -match 'assumed' })
$bare2 = @($h2 | Where-Object { $_.start_line -eq $lineF })
Check '5 CONTROL library: no assumption reported' ($assumed2.Count -eq 0) (($h2 | ForEach-Object { "$($_.start_line): $($_.message)" }) -join ' | ')
Check '5 CONTROL library: the rule is on (bare hint fires)' ($bare2.Count -eq 1) ''

[IO.Directory]::Delete($WorkDir, $true)
if ($script:Failed) { Write-Host 'run_pp_declared_no_library: FAIL' -ForegroundColor Red; exit 1 }
Write-Host "run_pp_declared_no_library: PASS ($script:Passed)" -ForegroundColor Green
exit 0
