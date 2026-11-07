<#
  run_parser_norefs.ps1 -- E-PARSER-NOREFS (wave 146): every name the parse used to drop now has a ref row, bound.

  Before this: `inherited X`, a property specifier (`read GetVal`, `implements IDoer`), the iterator of `for X in`, and a
  record-constant field name (`(Alpha: 1)`) held NO row, so find-callers answered short, unused-public-symbol could fire on
  live code, and rename refused [no-ref-occurrence] on the last two. `MakeA().Count` was the fifth shape: G6 (1.45) closed
  it, and it stays here as a pinned control.

  Each row is asserted bound to the RIGHT symbol, because the wrong binding is what makes a "ref exists" check vacuous:
    * `inherited Run` inside TKid.Run, which has a nested Run: TBase.Run, neither of the near ones;
    * `(Alpha: 22)` in a TOtherPt const: TOtherPt.Alpha, never TPoint2.Alpha;
    * `(X: 24)` in a library TPoint: another index's, not the project's TOtherPt.X.

  POSITIVE CONTROL: the rename half. p1 and p2 apply through the compile gate and the program's stdout must not move; a
  rename that missed a site would not compile, one that took a wrong site would change stdout or the assertions on the text.
  RED on 1.45.0-alpha (lane/145-int): every inherited/spec/for-in/record-field check; `pin` checks are green there on purpose.
  Needs RAD Studio for the gate half; SKIPs that half without it. Works under %TEMP%.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-parser-norefs-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
$ErrorActionPreference = 'Stop'
$script:Failed = 0; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:Failed++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray } }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Fx   = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\parser_norefs')).Path
$Ascii = [Text.Encoding]::ASCII
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$script:N = 0

$libDir = Join-Path $WorkDir 'lib'; New-Item -ItemType Directory -Force $libDir | Out-Null
Copy-Item "$Fx\libstub\*.pas" $libDir
$script:Lib = Join-Path $WorkDir 'lib.sqlite'
Push-Location $WorkDir; try { $null | & $Exe index $libDir --db $script:Lib --library-db none *> "$script:Lib.log" } finally { Pop-Location }

function New-Lab([string]$Lib = $script:Lib) {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  Copy-Item "$Fx\*.pas", "$Fx\*.dpr", "$Fx\*.dproj" $root
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'NrProg.dproj') --db $db --library-db $Lib *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'NrProg.dproj'); Db = $db; Types = (Join-Path $root 'NrTypes.pas') }
}
# sql --json rows are POSITIONAL: map them onto columns[].name.
function Rows($P) {
  $q = 'select r.start_line l, r.start_col c, r.kind k, r.name_text n, coalesce(r.receiver_text,'''') rcv, coalesce(s.qualified_name,'''') bound, coalesce(r.external_target,'''') ext from refs r left join symbols s on s.id = r.symbol_id join files f on f.id = r.file_id where f.path like ''%NrTypes.pas'''
  $j = (& $Exe sql --db $P.Db --query $q --json 2>$null | Out-String | ConvertFrom-Json)
  $names = @($j.columns | ForEach-Object { $_.name })
  $out = foreach ($row in $j.rows) {
    $o = @{}; for ($i = 0; $i -lt $names.Count; $i++) { $o[$names[$i]] = $row[$i] }; [pscustomobject]$o
  }
  return ,@($out)
}
$script:Lab = New-Lab
$script:Refs = Rows $script:Lab
$script:Lines = [IO.File]::ReadAllText($script:Lab.Types, $Ascii) -split "`r`n"
Check 'the raw shape holds rows' ($script:Refs.Count -gt 50 -and $null -ne $script:Refs[0].k) "rows=$($script:Refs.Count)"
function LineOf([string]$Pat, [int]$Nth = 1) {
  $seen = 0
  for ($i = 0; $i -lt $script:Lines.Count; $i++) { if ($script:Lines[$i] -match $Pat) { $seen++; if ($seen -eq $Nth) { return $i + 1 } } }
  throw "no line /$Pat/ #$Nth"
}
# The rows named $Name on the line, as "kind>bound|ext" strings.
function At([int]$Line, [string]$Name) {
  return @($script:Refs | Where-Object { [int]$_.l -eq $Line -and $_.n -eq $Name } | ForEach-Object { "$($_.k)>$($_.bound)$(if ($_.ext) { "|$($_.ext)" })" })
}
function Bound($Label, [int]$Line, [string]$Name, [string]$Kind, [string]$QName) {
  $a = At $Line $Name
  Check $Label ($a -contains "$Kind>$QName") "line $Line $Name : [$($a -join '; ')]"
}

Write-Host 'pin: a call receiver (G6, 1.45)' -ForegroundColor Cyan
Bound 'pin MakeA().Count read'  (LineOf 'Result \+ MakeA\(\)\.Count') 'Count' 'member-access' 'NrTypes.TBase.Count'
Bound 'pin MakeA().Count write' (LineOf '^  MakeA\(\)\.Count:= 1') 'Count' 'member-access' 'NrTypes.TBase.Count'

Write-Host 'inherited X' -ForegroundColor Cyan
$l = LineOf 'inherited Twice \+ inherited Val'
Bound 'i1 inherited Twice in an expression' $l 'Twice' 'member-access' 'NrTypes.TBase.Twice'
Bound 'i2 inherited Val: a property'        $l 'Val'   'member-access' 'NrTypes.TBase.Val'
Bound 'i4 inherited Run; a statement call'  (LineOf '^  inherited Run;') 'Run' 'call' 'NrTypes.TBase.Run'
Bound 'i5 inherited Take(4): args'          (LineOf 'inherited Take\(4\)') 'Take' 'call' 'NrTypes.TBase.Take'
Bound 'i6 under a nested Run: the ancestor, not the nested one' (LineOf '^  inherited Run;' 2) 'Run' 'call' 'NrTypes.TBase.Run'
Bound 'i7 inherited in a condition'         (LineOf 'if inherited Twice > 0') 'Twice' 'member-access' 'NrTypes.TBase.Twice'
$l = LineOf 'inherited Make\(N\)\.Count'
Bound 'i8 inherited Make(N)'                $l 'Make'  'call' 'NrTypes.TBase.Make'
Bound 'i9 inherited Make(N).Count'          $l 'Count' 'member-access' 'NrTypes.TBase.Count'
$c = @($script:Refs | Where-Object { [int]$_.l -eq (LineOf '^  inherited;$') }).Count
Check 'i10 a bare inherited names nothing: no row' ($c -eq 0) "rows=$c"
$a = At (LineOf '^  inherited Clear;') 'Clear'
Check 'i11 a library parent: external, not a project symbol' (($a | Where-Object { $_ -match '^call>\|.*TStringList\.Clear' }).Count -eq 1) "[$($a -join '; ')]"

Write-Host 'property specifiers' -ForegroundColor Cyan
$l = LineOf 'property Val: Integer read GetVal'
Bound 's1 read a method'  $l 'GetVal'   'property-spec' 'NrTypes.TBase.GetVal'
Bound 's2 write a method' $l 'SetVal'   'property-spec' 'NrTypes.TBase.SetVal'
Bound 's3 stored'         $l 'IsStored' 'property-spec' 'NrTypes.TBase.IsStored'
Bound 's4 default const'  $l 'CDefault' 'read' 'NrTypes.CDefault'
$l = LineOf 'property Raw: Integer read FVal write FVal'
Check 's5 read + write a field: two rows' (@(At $l 'FVal' | Where-Object { $_ -eq 'property-spec>NrTypes.TBase.FVal' }).Count -eq 2) "[$(At $l 'FVal')]"
$l = LineOf 'property Slot: Integer index CIdx'
Bound 's6 index const'    $l 'CIdx'   'read' 'NrTypes.CIdx'
Bound 's7 read under index' $l 'GetIdx' 'property-spec' 'NrTypes.TBase.GetIdx'
$l = LineOf 'property Doer: IDoer read FDoer implements IDoer'
Bound 's8 read a field'   $l 'FDoer' 'property-spec' 'NrTypes.TBase.FDoer'
Check 's9 implements: a second type_use of IDoer' (@(At $l 'IDoer' | Where-Object { $_ -eq 'type_use>NrTypes.IDoer' }).Count -eq 2) "[$(At $l 'IDoer')]"

Write-Host 'for X in' -ForegroundColor Cyan
Bound 'f1 iterator X'     (LineOf 'for X in A do') 'X' 'write' 'NrTypes.Use.X'
Bound 'f2 iterator Y, never read' (LineOf 'for Y in A do') 'Y' 'write' 'NrTypes.Use.Y'
$a = At (LineOf 'for var Z in A do') 'Z'
Check 'f3 for var Z: a declaration, no row' ($a.Count -eq 0) "[$($a -join '; ')]"

Write-Host 'record-constant field names' -ForegroundColor Cyan
$RF = 'record-field'
$l = LineOf 'COne: TPoint2 ='
Bound 'r1 typed const'   $l 'Alpha' $RF 'NrTypes.TPoint2.Alpha'
Bound 'r2 second field'  $l 'Beta'  $RF 'NrTypes.TPoint2.Beta'
$l = LineOf 'CBox: TBox ='
Bound 'r3 outer field'   $l 'Corner' $RF 'NrTypes.TBox.Corner'
Bound 'r4 nested record' $l 'Alpha'  $RF 'NrTypes.TPoint2.Alpha'
Bound 'r5 field of an inline array' (LineOf '^    Pts: \(\(Alpha') 'Alpha' $RF 'NrTypes.TPoint2.Alpha'
Bound 'r6 field of a named array'   (LineOf '^    Named: \(\(Alpha') 'Alpha' $RF 'NrTypes.TPoint2.Alpha'
Bound 'r7 const of an inline array' (LineOf 'CArr: array') 'Alpha' $RF 'NrTypes.TPoint2.Alpha'
Bound 'r8 const of a named array'   (LineOf 'CAlias: TPairs') 'Alpha' $RF 'NrTypes.TPoint2.Alpha'
$a = At (LineOf 'COther: TOtherPt') 'Alpha'
Check 'r9 same name, other record: only its own type answers' (($a -join ';') -eq "$RF>NrTypes.TOtherPt.Alpha") "[$($a -join '; ')]"
Bound 'r10 var initializer' (LineOf 'VOne: TPoint2 =') 'Alpha' $RF 'NrTypes.TPoint2.Alpha'
Bound 'r11 routine-local const' (LineOf 'CLocal: TPoint2 =') 'Alpha' $RF 'NrTypes.TPoint2.Alpha'
$a = At (LineOf 'CLib: TPoint =') 'X'
Check 'r12 a library record: external, not TOtherPt.X' ((($a -join ';') -match '^record-field>\|.*TPoint\.X') ) "[$($a -join '; ')]"

Write-Host 'an incremental re-emit writes the same rows' -ForegroundColor Cyan
$p = New-Lab; $b = (Rows $p | Where-Object { $_.bound -ne '' -or $_.ext -ne '' }).Count
[IO.File]::AppendAllText($p.Types, "`r`n", $Ascii)
Push-Location $WorkDir; try { $null | & $Exe index --project $p.Dproj --db $p.Db --library-db $script:Lib *> "$($p.Db).log2" } finally { Pop-Location }
$b2 = (Rows $p | Where-Object { $_.bound -ne '' -or $_.ext -ne '' }).Count
Check 'inc bound rows unchanged' ($b -eq $b2) "before=$b after=$b2"

Write-Host 'rename: the plan decides every site' -ForegroundColor Cyan
function Plan($P, [string]$Q, [string]$To) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $P.Db --library-db $script:Lib --plan --json 2>$null | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
  return @{ Exit = $c; Json = $j; Out = $o }
}
foreach ($t in @(
  @('NrTypes.TPoint2.Alpha', 'Aleph'), @('NrTypes.Use.Y', 'Why'), @('NrTypes.TOtherPt.X', 'Xx'),
  @('NrTypes.TBase.Run', 'Exec'), @('NrTypes.TBase.GetVal', 'Fetch'), @('NrTypes.TBase.Count', 'Tally'))) {
  $pl = Plan $script:Lab $t[0] $t[1]
  Check "plan $($t[0]) -> $($t[1]): every occurrence decided" ($pl.Exit -eq 0 -and $pl.Json -and @($pl.Json.refusals).Count -eq 0) ($pl.Out)
}

# A type named by `implements`: its token is decided. The type itself still refuses [group-name-differs]: the delegating
# property sits in the type's dispatch group, a conservative refusal of its own, filed in REPORT.md of lane 146 b1.
$pl = Plan $script:Lab 'NrTypes.IDoer' 'IWorker'
$kinds = @($pl.Json.refusals | ForEach-Object { $_.kind })
Check 'plan NrTypes.IDoer: the implements token holds a ref' ($pl.Json -and $kinds -notcontains 'no-ref-occurrence') ($pl.Out)

if (-not (Test-Path $RsVars)) { Write-Host "SKIP: the gate half needs rsvars.bat ($RsVars)" -ForegroundColor Yellow }
else {
  function Build-Lab([string]$Root) {
    $bat = "$Root.bld.bat"
    [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$RsVars`"`r`ncd /D `"$Root`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal NrProg.dproj`r`nexit /b %ERRORLEVEL%`r`n", $Ascii)
    $x = Start-Process cmd.exe -ArgumentList "/c `"$bat`"" -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$Root.bld.log" -RedirectStandardError "$Root.bld.err"
    return ($x.ExitCode -eq 0)
  }
  function Stdout-Of([string]$Root) {
    $x = Get-ChildItem $Root -Recurse -Filter NrProg.exe | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $x) { return '<no exe>' }
    return (& $x.FullName 2>&1 | Out-String)
  }
  function Apply($P, [string]$Q, [string]$To) {
    Push-Location $WorkDir
    try { $o = ($null | & $Exe rename --kind symbol --name $Q --to $To --db $P.Db --library-db $script:Lib --project $P.Dproj --build-timeout 600 --apply --no-backup 2>&1 | Out-String); $c = $LASTEXITCODE } finally { Pop-Location }
    return @{ Exit = $c; Out = $o }
  }
  $base = New-Lab
  if (-not (Build-Lab $base.Root)) { Write-Host "FATAL: the untouched fixture does not build ($($base.Root).bld.log)" -ForegroundColor Red; exit 2 }
  $want = Stdout-Of $base.Root
  Check 'the fixture runs and prints' ($want -match '\d') $want

  Write-Host 'p1: a record field, through the gate' -ForegroundColor Cyan
  $p = New-Lab; $a = Apply $p 'NrTypes.TPoint2.Alpha' 'Aleph'
  $x = [IO.File]::ReadAllText($p.Types, $Ascii)
  Check 'p1 apply exit 0' ($a.Exit -eq 0 -and $a.Out -match 'compile gate') $a.Out
  Check 'p1 stdout unchanged' ((Stdout-Of $p.Root) -ceq $want) (Stdout-Of $p.Root)
  Check 'p1 COne and the nested sites follow' ($x -match 'COne: TPoint2 = \(Aleph: 1' -and $x -match 'Corner: \(Aleph: 3' -and $x -match 'CArr: array\[0\.\.1\] of TPoint2 = \(\(Aleph: 6' -and $x -match 'CAlias: TPairs = \(\(Aleph: 18') $x
  Check 'p1 the other record stays' ($x -match 'COther: TOtherPt = \(Alpha: 22') $x

  Write-Host 'p2: a local under for-in, through the gate' -ForegroundColor Cyan
  $p = New-Lab; $a = Apply $p 'NrTypes.Use.X' 'Elem'
  $x = [IO.File]::ReadAllText($p.Types, $Ascii)
  Check 'p2 apply exit 0' ($a.Exit -eq 0 -and $a.Out -match 'compile gate') $a.Out
  Check 'p2 the iterator and its read follow' ($x -match 'for Elem in A do' -and $x -match 'Result \+ Elem;') $x
  Check 'p2 stdout unchanged' ((Stdout-Of $p.Root) -ceq $want) (Stdout-Of $p.Root)

  Write-Host 'p3: a library record''s same-named field stays' -ForegroundColor Cyan
  $p = New-Lab; $a = Apply $p 'NrTypes.TOtherPt.X' 'Xx'
  $x = [IO.File]::ReadAllText($p.Types, $Ascii)
  Check 'p3 apply exit 0' ($a.Exit -eq 0 -and $a.Out -match 'compile gate') $a.Out
  Check 'p3 own site follows, TPoint''s does not' ($x -match 'Lat: 23; Xx: 30' -and $x -match 'CLib: TPoint = \(X: 24') $x

  Write-Host 'p4: inherited and a specifier, through the gate (decided from refs now)' -ForegroundColor Cyan
  $p = New-Lab; $a = Apply $p 'NrTypes.TBase.Run' 'Exec'
  $x = [IO.File]::ReadAllText($p.Types, $Ascii)
  Check 'p4 apply exit 0' ($a.Exit -eq 0 -and $a.Out -match 'compile gate') $a.Out
  Check 'p4 inherited follows' ($x -match 'inherited Exec;' -and $x -notmatch 'inherited Run;') $x
  $p = New-Lab; $a = Apply $p 'NrTypes.TBase.GetVal' 'Fetch'
  $x = [IO.File]::ReadAllText($p.Types, $Ascii)
  Check 'p5 apply exit 0' ($a.Exit -eq 0 -and $a.Out -match 'compile gate') $a.Out
  Check 'p5 the read specifier follows' ($x -match 'read Fetch write SetVal') $x
}

Write-Host ("{0} passed, {1} failed" -f $script:Passed, $script:Failed)
try { [IO.Directory]::Delete($WorkDir, $true) } catch { }
if ($script:Failed -gt 0) { exit 1 }
exit 0
