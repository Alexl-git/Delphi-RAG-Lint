#Requires -Version 7
<#
  run_lsp_type_definition_guard.ps1 -- `textDocument/typeDefinition` (lane 145 lsp).

  Fixture: TFoo, TBar and a decoy TFoo2 in one unit; TBar has a field FFoo: TFoo and a function Make: TFoo;
  Demo declares a local `Obj: TBar`, `Foo: TFoo`.
  Positive controls (a handler answering [] or one fixed location fails them):
    initialize advertises typeDefinitionProvider.
    on the field FFoo -> the line of `TFoo = class` (not TFoo2, not TBar).
    on the function Make -> the same TFoo line (the result type).
    on `Obj` in the body of Demo -> the `TBar = class` line (a different answer from FFoo's).
    on the type name TFoo itself -> its own declaration line.
  Honest misses -> [] (never an error, never a wrong place): a variable of an RTL type (Integer, not in the
  index), whitespace, and a file the index does not hold.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-typedef-$PID"
)
if (-not $Exe) { $Exe = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\src\cli\Win64\Debug\drag-lint.exe' }
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lsp_stdio_helpers.ps1')
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uTD.pas'
WriteAnsi $file @'
unit uTD;

interface

type
  TFoo = class
  public
    procedure Run;
  end;

  TFoo2 = class
  public
    procedure Other;
  end;

  TBar = class
  public
    FFoo: TFoo;
    Count: Integer;
    function Make: TFoo;
  end;

procedure Demo;

implementation

procedure TFoo.Run;
begin
end;

procedure TFoo2.Other;
begin
end;

function TBar.Make: TFoo;
begin
  Result:= FFoo;
end;

procedure Demo;
var
  Obj: TBar;
  Foo: TFoo;
begin
  Obj:= TBar.Create;
  Foo:= Obj.Make;
  Foo.Run;
  Obj.Count:= 1;
end;

end.
'@
$loose = Join-Path $WorkDir 'loose.pas'
WriteAnsi $loose "unit loose;`ninterface`nprocedure Z;`nimplementation`nprocedure Z;`nbegin`nend;`nend.`n"

$db = Join-Path $WorkDir 'td.sqlite'
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $Exe index $src --db $db 2>&1 | Out-Null
$ErrorActionPreference = $ea
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern, [int]$from = 0) { for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } } return -1 }
$uri = 'file:///' + ($file -replace '\\', '/')
$looseUri = 'file:///' + ($loose -replace '\\', '/')
$lFooType = LineOf '^  TFoo = class'; $lBarType = LineOf '^  TBar = class'
$lField = LineOf '^    FFoo: TFoo;'; $lMake = LineOf '^    function Make: TFoo;'; $lCount = LineOf '^    Count: Integer;'
$demo = LineOf '^procedure Demo;$' ((LineOf '^implementation') + 1)
$lObjUse = LineOf '^  Foo:= Obj\.Make;' $demo
$lFooRun = LineOf '^  Foo\.Run;' $demo
$lCountUse = LineOf '^  Obj\.Count:= 1;' $demo
function TD([int]$line, [int]$col, [string]$u = $uri) { @{ method='textDocument/typeDefinition'; params=(PosParams $u $line $col) } }
$r = LspSession $Exe $WorkDir $db @(
  (TD $lField 6),            # 11 FFoo
  (TD $lMake 14),            # 12 Make
  (TD $lObjUse 10),          # 13 Obj in Foo:= Obj.Make
  (TD $lFooType 4),          # 14 TFoo type name
  (TD $lCount 6),            # 15 Count: Integer
  (TD 1 0),                  # 16 whitespace
  (TD 2 5 $looseUri),        # 17 unindexed file
  (TD $lFooRun 3)            # 18 Foo in Foo.Run
)
Check 'initialize advertises typeDefinitionProvider' ($r.init.capabilities.typeDefinitionProvider -eq $true)
Check 'typeDefinition answered (not -32601)' ($r.res.ContainsKey(11)) $(if ($r.err.Count) { 'error=' + (($r.err.Values | % { $_.code }) -join ',') })
if (-not $r.res.ContainsKey(11)) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }
function Locs([int]$id) { if ($r.res.ContainsKey($id)) { return @($r.res[$id][0]) } else { return @() } }
$a = @(Locs 11)
Check 'field FFoo: TFoo -> the TFoo class line' ($a.Count -eq 1 -and $a[0].range.start.line -eq $lFooType) "got=$($a.Count)/$($a[0].range.start.line) want=$lFooType"
$b = @(Locs 12)
Check 'function Make: TFoo -> the TFoo class line' ($b.Count -eq 1 -and $b[0].range.start.line -eq $lFooType) "got=$($b.Count)/$($b[0].range.start.line) want=$lFooType"
$c = @(Locs 13)
Check 'local Obj: TBar -> the TBar class line (differs from the TFoo answers)' ($c.Count -eq 1 -and $c[0].range.start.line -eq $lBarType) "got=$($c.Count)/$($c[0].range.start.line) want=$lBarType"
$d = @(Locs 14)
Check 'on the type name TFoo -> its own declaration' ($d.Count -eq 1 -and $d[0].range.start.line -eq $lFooType) "got=$($d.Count)/$($d[0].range.start.line) want=$lFooType"
$e = @(Locs 18)
Check 'local Foo: TFoo at a use site -> the TFoo class line' ($e.Count -eq 1 -and $e[0].range.start.line -eq $lFooType) "got=$($e.Count)/$($e[0].range.start.line) want=$lFooType"
Check 'Count: Integer (RTL type, not in the index) -> []' ($r.res.ContainsKey(15) -and @(Locs 15).Count -eq 0 -and -not $r.err.ContainsKey(15))
Check 'whitespace -> []' ($r.res.ContainsKey(16) -and @(Locs 16).Count -eq 0 -and -not $r.err.ContainsKey(16))
Check 'unindexed file -> []' ($r.res.ContainsKey(17) -and @(Locs 17).Count -eq 0 -and -not $r.err.ContainsKey(17))

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
