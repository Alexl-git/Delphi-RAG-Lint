<#
  run_facts_ref_types.ps1 -- B9 F1: the ref_types table, the static type of a
  reference, and typeat's read of it.

  ResolveRefTypes writes one row per read / write / member-access / call ref the
  pass can type from what it already knows: refs.symbol_id's declared type, a
  constructor's receiver, a function's return type, `Result`, a cast. Nothing is
  inferred that the resolver did not already know. A library type has a
  type_qname and a NULL type_symbol_id.

  POSITIVE CONTROLS: every `via` is asserted on a named ref with its value (a
  count alone passes on garbage); a routine with no type must have NO row; and
  dropping the table must return typeat to its old output, then a resolve-only
  run must restore it. On a 1.43 engine the table does not exist, so every check
  below it fails: the RED this guard was written against.

  Usage: pwsh -File tests\autotest\run_facts_ref_types.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-facts-types-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail) -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
[void][IO.Directory]::CreateDirectory($src)
$db = Join-Path $WorkDir 'facts.sqlite'
$pas = Join-Path $src 'TypeFx.pas'
$pasB = Join-Path $src 'TypeFxB.pas'

$unitB = @'
unit TypeFxB;

interface

type
  TOther = class
  end;

implementation

end.
'@

$unitText = @'
unit TypeFx;

interface

uses
  System.Classes, TypeFxB;

type
  TColor = (clRed, clBlue);
  TBase = class
  public
    constructor Create;
  end;
  TThing = class(TBase)
  public
    FName: string;
    procedure Ping;
    function Clone: TThing;
    property Name: string read FName;
  end;

var
  GOther: TOther;

implementation

constructor TBase.Create;
begin
end;

procedure TThing.Ping;
begin
  FName:= Name;
end;

function TThing.Clone: TThing;
begin
  Result:= TThing.Create;
end;

procedure Use(AArg: TThing);
var
  Lib: TStringList;
  Own: TThing;
  C: TColor;
begin
  Lib:= TStringList.Create;
  Own:= AArg.Clone;
  var Fresh:= TThing.Create;
  Own.Ping;
  C:= clBlue;
  TThing(Lib).Ping;
  Fresh.Ping;
  GOther.Free;
end;

end.
'@

function Rows([string]$Sql) {
  $j = (& $Exe sql --query $Sql --db $db --json) | Out-String | ConvertFrom-Json
  return , @($j.rows)
}
function Scalar([string]$Sql) { return (Rows $Sql)[0][0] }
# One ref's fact, as "<qname>|<via>|<has symbol id>"; '' when it has no row.
function Fact([string]$Name, [string]$Kind, [int]$Line) {
  $r = Rows ("SELECT t.type_qname, t.via, t.type_symbol_id IS NOT NULL FROM refs r JOIN ref_types t ON t.ref_id = r.id " +
    "WHERE r.name_text = '$Name' AND r.kind = '$Kind' AND r.start_line = $Line")
  if ($r.Count -eq 0) { return '' }
  return ('{0}|{1}|{2}' -f $r[0][0], $r[0][1], $r[0][2])
}
function LineOf([string]$Text) {
  $n = 0
  foreach ($l in ($unitText -split "`r?`n")) { $n++; if ($l.Contains($Text)) { return $n } }
  throw "fixture line not found: $Text"
}

try {
  [IO.File]::WriteAllText($pas, ($unitText -replace "`r?`n", "`r`n"))
  [IO.File]::WriteAllText($pasB, ($unitB -replace "`r?`n", "`r`n"))
  & $Exe index $src --db $db *> (Join-Path $WorkDir 'index1.log')
  Check 'fixture indexes' ($LASTEXITCODE -eq 0)

  $count = 0
  try { $count = Scalar 'SELECT COUNT(*) FROM ref_types' } catch { $count = -1 }
  Check 'F1: ref_types has rows' ($count -gt 0) "count=$count"

  $lLib = LineOf 'Lib:= TStringList.Create'
  $lOwn = LineOf 'Own:= AArg.Clone'
  $lFresh = LineOf 'var Fresh:= TThing.Create'
  $lCol = LineOf 'C:= clBlue'
  $lCast = LineOf 'TThing(Lib).Ping'
  $lFreshUse = LineOf 'Fresh.Ping'
  $lResult = LineOf 'Result:= TThing.Create'

  Check 'via decl: a library-typed local has NULL id' ((Fact 'Lib' 'write' $lLib) -eq 'TStringList|decl|0') (Fact 'Lib' 'write' $lLib)
  Check 'via decl: a project-typed param has an id' ((Fact 'AArg' 'read' $lOwn) -eq 'TypeFx.TThing|decl|1') (Fact 'AArg' 'read' $lOwn)
  $lMem = LineOf 'FName:= Name'
  Check 'via member: a field' ((Fact 'FName' 'write' $lMem) -eq 'string|member|0') (Fact 'FName' 'write' $lMem)
  Check 'via member: a property' ((Fact 'Name' 'read' $lMem) -eq 'string|member|0') (Fact 'Name' 'read' $lMem)
  Check 'via result: a method return type' ((Fact 'Clone' 'member-access' $lOwn) -eq 'TypeFx.TThing|result|1') (Fact 'Clone' 'member-access' $lOwn)
  Check 'via result: the implicit Result' ((Fact 'Result' 'write' $lResult) -eq 'TypeFx.TThing|result|1') (Fact 'Result' 'write' $lResult)
  Check 'via ctor: the receiver, NOT the inherited ctor owner' ((Fact 'Create' 'member-access' $lResult) -eq 'TypeFx.TThing|ctor|1') (Fact 'Create' 'member-access' $lResult)
  Check 'CONTROL: no library store -> a library Create has no row' ((Fact 'Create' 'member-access' $lLib) -eq '') (Fact 'Create' 'member-access' $lLib)
  Check 'via inline: an inline var the resolver typed' ((Fact 'Fresh' 'read' $lFreshUse) -eq 'TypeFx.TThing|inline|1') (Fact 'Fresh' 'read' $lFreshUse)
  Check 'via cast: a hard cast' ((Fact 'TThing' 'call' $lCast) -eq 'TypeFx.TThing|cast|1') (Fact 'TThing' 'call' $lCast)
  Check 'via decl: an enum value is its enum' ((Fact 'clBlue' 'read' $lCol) -eq 'TypeFx.TColor|decl|1') (Fact 'clBlue' 'read' $lCol)
  $lGOther = LineOf 'GOther.Free'
  Check 'via decl: a type from another unit' ((Fact 'GOther' 'read' $lGOther) -eq 'TypeFxB.TOther|decl|1') (Fact 'GOther' 'read' $lGOther)
  Check 'POSITIVE: a procedure has no static type, no row' ((Fact 'Ping' 'call' $lFreshUse) -eq '') (Fact 'Ping' 'call' $lFreshUse)
  $via = Scalar "SELECT COUNT(*) FROM ref_types WHERE via NOT IN ('decl','result','member','cast','ctor','literal','inline')"
  Check 'every via is in the documented set' ($via -eq 0) "bad=$via"
  $empty = Scalar "SELECT COUNT(*) FROM ref_types WHERE type_qname = ''"
  Check 'no row has an empty type_qname' ($empty -eq 0) "empty=$empty"

  # typeat answers from the table: the cursor is on `Create`, whose symbol is TBase.Create.
  $col = ($unitText -split "`r?`n")[$lResult - 1].IndexOf('Create') + 1
  $pos = "${pas}:${lResult}:${col}"
  $t = (& $Exe typeat $pos --db $db) | Out-String
  Check 'typeat prints the stored static type' ($t -match 'StaticType:\s+TypeFx\.TThing \(via ctor\)') $t.Trim().Replace("`r`n", ' / ')
  $j = (& $Exe typeat $pos --format json --db $db) | Out-String | ConvertFrom-Json
  Check 'typeat --format json carries it' (($j.static_type -eq 'TypeFx.TThing') -and ($j.static_type_via -eq 'ctor')) "$($j.static_type) $($j.static_type_via)"
  Check 'typeat --format json keeps its old fields' ($j.resolved -eq 'TypeFx.TBase.Create') "$($j.resolved)"

  # Control: without the table typeat is what it was.
  $py = Join-Path $WorkDir 'drop.py'
  [IO.File]::WriteAllText($py, "import sqlite3, sys`nc = sqlite3.connect(sys.argv[1])`nc.execute('DROP TABLE ref_types')`nc.commit()`nc.close()`n")
  python $py $db
  Check 'control: table dropped' ($LASTEXITCODE -eq 0)
  $t2 = (& $Exe typeat $pos --db $db) | Out-String
  Check 'POSITIVE: no table -> the old path, no static type line' (($t2 -notmatch 'StaticType') -and ($t2 -match 'TBase\.Create')) $t2.Trim().Replace("`r`n", ' / ')

  & $Exe index $src --db $db --resolve-only *> (Join-Path $WorkDir 'resolve.log')
  Check 'resolve-only runs' ($LASTEXITCODE -eq 0)
  $back = Scalar 'SELECT COUNT(*) FROM ref_types'
  Check 'resolve-only recreates and refills the table' ($back -eq $count) "count=$back of $count"

  # Scoped incremental: the edited ref changes type; deleting a type leaves no dangling id.
  $edited = ($unitText -replace "`r?`n", "`r`n") -replace 'Lib: TStringList;', 'Lib: TStrings;  '
  [IO.File]::WriteAllText($pas, $edited)
  $editedB = ($unitB -replace "`r?`n", "`r`n") -replace 'TOther = class', 'TOtherGone = class'
  [IO.File]::WriteAllText($pasB, $editedB)
  & $Exe index $src --db $db *> (Join-Path $WorkDir 'index2.log')
  Check 'incremental reindex runs' ($LASTEXITCODE -eq 0)
  Check 'an edited declaration re-types its refs' ((Fact 'Lib' 'write' $lLib) -eq 'TStrings|decl|0') (Fact 'Lib' 'write' $lLib)
  Check 'a removed type leaves no id in the row' ((Fact 'GOther' 'read' $lGOther) -eq 'TOther|decl|0') (Fact 'GOther' 'read' $lGOther)
  $orphans = Scalar 'SELECT COUNT(*) FROM ref_types WHERE ref_id NOT IN (SELECT id FROM refs)'
  Check 'no row outlives its ref' ($orphans -eq 0) "orphans=$orphans"
  $dangling = Scalar 'SELECT COUNT(*) FROM ref_types WHERE type_symbol_id IS NOT NULL AND type_symbol_id NOT IN (SELECT id FROM symbols)'
  Check 'no row names a dead symbol' ($dangling -eq 0) "dangling=$dangling"

  # A library class's constructor: type by name, NULL id, only with the library store open.
  $libDir = Join-Path $WorkDir 'lib'; $appDir = Join-Path $WorkDir 'app'
  [void][IO.Directory]::CreateDirectory($libDir); [void][IO.Directory]::CreateDirectory($appDir)
  [IO.File]::WriteAllText((Join-Path $libDir 'LibFx.pas'), "unit LibFx;`r`n`r`ninterface`r`n`r`ntype`r`n  TLibList = class`r`n  public`r`n    constructor Create;`r`n  end;`r`n`r`nimplementation`r`n`r`nconstructor TLibList.Create;`r`nbegin`r`nend;`r`n`r`nend.`r`n")
  [IO.File]::WriteAllText((Join-Path $appDir 'AppFx.pas'), "unit AppFx;`r`n`r`ninterface`r`n`r`nuses`r`n  LibFx;`r`n`r`nprocedure Go;`r`n`r`nimplementation`r`n`r`nprocedure Go;`r`nvar`r`n  L: TLibList;`r`nbegin`r`n  L:= TLibList.Create;`r`nend;`r`n`r`nend.`r`n")
  $libDb = Join-Path $WorkDir 'lib.sqlite'
  & $Exe index $libDir --db $libDb *> (Join-Path $WorkDir 'lib.log')
  $db = Join-Path $WorkDir 'app.sqlite'
  & $Exe index $appDir --db $db --library-db $libDb *> (Join-Path $WorkDir 'app.log')
  Check 'app with a library store indexes' ($LASTEXITCODE -eq 0)
  Check 'via ctor: a library class by name, NULL id' ((Fact 'Create' 'member-access' 16) -eq 'TLibList|ctor|0') (Fact 'Create' 'member-access' 16)

  # Acceptance on the repository's own demo project.
  $demo = (Resolve-Path "$PSScriptRoot\..\..\circular-demo\CircularDemo.dproj").Path
  $db = Join-Path $WorkDir 'demo.sqlite'
  & $Exe index --project $demo --db $db *> (Join-Path $WorkDir 'demo.log')
  Check 'circular-demo indexes' ($LASTEXITCODE -eq 0)
  $demoRows = Scalar 'SELECT COUNT(*) FROM ref_types'
  Check 'circular-demo: ref_types has rows' ($demoRows -gt 0) "count=$demoRows"
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: could not delete $WorkDir" } }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
