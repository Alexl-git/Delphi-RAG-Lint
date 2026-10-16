<#
  run_nested_routine_reaches_class.ps1 -- a bare (or Self.) call inside a NESTED
  routine of a method binds to the method's CLASS, as the compiler binds it.

  THE PROBLEM (reference benchmark on D:\TEST_REPO_2 ProjectB, 2026-09-30).
  TypeReceiver typed a bare call's implicit receiver as the enclosing symbol's
  ParentId -- one hop. For a method that is the class; for a routine NESTED in a
  method it is the outer ROUTINE, and no class method is its child, so the call
  bound to nothing. UWSPartner.TWSPartner.ExportResults._Read calls
  GetValorTag(vRoot, ...) -- a TWSPartner method -- and the edge was empty, while
  the same call written directly in a TWSPartner method came out [certain].
  22 of the 219 misses in that benchmark are this shape.
  EnclosingClassChainDeclares already climbed to the OUTERMOST routine and named
  this very defect in its header; TypeReceiver now uses it.

  CONTROLS -- the lexical chain still comes first, and nothing new is invented:
    * a nested routine NAMED like the method is nearer and still wins;
    * a routine nested in a FREE routine still reaches the unit-level routine.

  Usage: pwsh -File tests/callresolve/run_nested_routine_reaches_class.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_nested_class_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $src 'uShift.pas') @'
unit uShift;

interface

type
  TBase = class(TObject)
  public
    function Herdado: string;
  end;

  TWS = class(TBase)
  public
    function GetValorTag(const ANome: string): string;
    function Export: string;
    function ExportSelf: string;
    function ExportInherited: string;
    function ExportShadow: string;
    function ExportBase: string;
  end;

function UnitLevel: string;
function Livre: string;

implementation

function TBase.Herdado: string;
begin
  Result := '';
end;

function TWS.GetValorTag(const ANome: string): string;
begin
  Result := ANome;
end;

function TWS.Export: string;
  function _Read(const ANome: string): string;
  begin
    Result := GetValorTag(ANome);
  end;
begin
  Result := _Read('x');
end;

function TWS.ExportSelf: string;
  function _Read: string;
  begin
    Result := Self.GetValorTag('y');
  end;
begin
  Result := _Read;
end;

function TWS.ExportInherited: string;
  function _Read: string;
  begin
    Result := Herdado();
  end;
begin
  Result := _Read;
end;

function TWS.ExportShadow: string;
  function GetValorTag(const ANome: string): string;
  begin
    Result := ANome + '!';
  end;
  function _Read: string;
  begin
    Result := GetValorTag('z');
  end;
begin
  Result := _Read;
end;

function TWS.ExportBase: string;
  function _Nivel1: string;
    function _Nivel2: string;
    begin
      Result := GetValorTag('w');
    end;
  begin
    Result := _Nivel2;
  end;
begin
  Result := _Nivel1;
end;

function UnitLevel: string;
begin
  Result := '';
end;

function Livre: string;
  function _Read: string;
  begin
    Result := UnitLevel();
  end;
begin
  Result := _Read;
end;

end.
'@

$db = Join-Path $WorkDir 'nested.sqlite'
& $exePath index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

function Callees([string]$QName) { return ((& $exePath find-callees --qname $QName --db $db 2>$null) -join "`n") }

$a = Callees 'uShift.TWS.Export._Read'
Check 'ASSERT: a bare call in a nested routine binds to the class method' ($a -match 'uShift\.TWS\.GetValorTag\s+\[certain\]') "callees: $a"
$b = Callees 'uShift.TWS.ExportSelf._Read'
Check 'ASSERT: Self. in a nested routine binds to the class method' ($b -match 'uShift\.TWS\.GetValorTag\s+\[certain\]') "callees: $b"
$c = Callees 'uShift.TWS.ExportInherited._Read'
Check 'ASSERT: an INHERITED method is reached from a nested routine' ($c -match 'uShift\.TBase\.Herdado\s+\[certain\]') "callees: $c"
$d = Callees 'uShift.TWS.ExportBase._Nivel1._Nivel2'
Check 'ASSERT: a doubly nested routine reaches the class' ($d -match 'uShift\.TWS\.GetValorTag\s+\[certain\]') "callees: $d"
$e = Callees 'uShift.TWS.ExportShadow._Read'
Check 'CONTROL: a nested routine of the same name is nearer and still wins' `
  (($e -match 'ExportShadow\.GetValorTag') -and ($e -notmatch 'uShift\.TWS\.GetValorTag\s')) "callees: $e"
$f = Callees 'uShift.Livre._Read'
Check 'CONTROL: nested in a FREE routine still reaches the unit-level routine' ($f -match 'uShift\.UnitLevel\s+\[certain\]') "callees: $f"

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_nested_class_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
