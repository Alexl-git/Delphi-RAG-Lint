<#
  run_doc_exception_rtl_callee.ps1 -- C9, 1.44: a documented exception raised inside an RTL
  callee is not "never raised" when the library index holds the body.

  A tiny fake library (its own index, passed as --library-db) stands in for the RTL, the same
  shape as TIniFile.WriteString raising EIniFileException. The project index is built WITHOUT a
  library, so refs.external_target is empty, as on the YADF DB where this was reported; the
  check has to read receiver_type_text.

  RED on 1.43 (each reports "never raises it"):
    1 local var typed by a library class, member with a body raising the class
    2 the same call one project hop down (delegation)
    3 member inherited from a library ancestor
    4 abstract member reached through the base: an override raises
    5 bare call to a free library routine
    6 raise two hops down inside the library
    7 class-receiver call: TLibIni.Open(..)
  CONTROLS (still report: a positive answer is required, absence never silences)
    C1 the library member is quiet
    C2 the member raises a DIFFERENT library class (exact name, as the own-body test)
    C3 a project-declared class: a library callee cannot raise it
    C4 no call into the library at all
    C5 RED 1's routine with --library-db none: no library, no evidence, the finding stands

  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_doc_rtl_callee_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
foreach ($d in 'lib','proj') { New-Item -ItemType Directory -Path (Join-Path $scratch $d) | Out-Null }
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $scratch 'lib\FakeRtl.pas') @'
unit FakeRtl;

interface

type
  ELibWrite = class(TObject)
  public
    constructor Create(const A: string);
  end;
  ELibOther = class(TObject)
  public
    constructor Create(const A: string);
  end;
  ELibDeep = class(TObject)
  public
    constructor Create(const A: string);
  end;
  ELibAbstract = class(TObject)
  public
    constructor Create(const A: string);
  end;
  ELibOpen = class(TObject)
  public
    constructor Create(const A: string);
  end;
  ELibFree = class(TObject)
  public
    constructor Create(const A: string);
  end;
  ELibInherited = class(TObject)
  public
    constructor Create(const A: string);
  end;

  TLibBase = class(TObject)
  public
    procedure WriteAbs(const A: string); virtual; abstract;
    procedure Inh(const A: string);
  end;

  TLibIni = class(TLibBase)
  public
    class function Open(const A: string): TLibIni;
    procedure WriteAbs(const A: string); override;
    procedure WriteIt(const A: string);
    procedure WriteOther(const A: string);
    procedure Deep(const A: string);
    procedure Quiet(const A: string);
  end;

procedure LibRaiser(const A: string);

implementation

constructor ELibWrite.Create(const A: string); begin end;
constructor ELibOther.Create(const A: string); begin end;
constructor ELibDeep.Create(const A: string); begin end;
constructor ELibAbstract.Create(const A: string); begin end;
constructor ELibOpen.Create(const A: string); begin end;
constructor ELibFree.Create(const A: string); begin end;
constructor ELibInherited.Create(const A: string); begin end;

procedure DeepHelper2(const A: string);
begin
  raise ELibDeep.Create(A);
end;

procedure DeepHelper1(const A: string);
begin
  DeepHelper2(A);
end;

procedure TLibBase.Inh(const A: string);
begin
  raise ELibInherited.Create(A);
end;

class function TLibIni.Open(const A: string): TLibIni;
begin
  raise ELibOpen.Create(A);
end;

procedure TLibIni.WriteAbs(const A: string);
begin
  raise ELibAbstract.Create(A);
end;

procedure TLibIni.WriteIt(const A: string);
begin
  raise ELibWrite.Create(A);
end;

procedure TLibIni.WriteOther(const A: string);
begin
  raise ELibOther.Create(A);
end;

procedure TLibIni.Deep(const A: string);
begin
  DeepHelper1(A);
end;

procedure TLibIni.Quiet(const A: string);
begin
end;

procedure LibRaiser(const A: string);
begin
  raise ELibFree.Create(A);
end;

end.
'@
WriteAscii (Join-Path $scratch 'proj\App.pas') @'
unit App;

interface

uses FakeRtl;

type
  EProjOwn = class(TObject);

/// <summary>Direct.</summary>
/// <exception cref="ELibWrite">Member with a body.</exception>
procedure R1Direct;
/// <summary>Delegates.</summary>
/// <exception cref="ELibWrite">One project hop down.</exception>
procedure R2Delegate;
/// <summary>Inherited.</summary>
/// <exception cref="ELibInherited">Declared on the ancestor.</exception>
procedure R3Inherited;
/// <summary>Abstract.</summary>
/// <exception cref="ELibAbstract">An override raises it.</exception>
procedure R4Abstract(const B: TLibBase);
/// <summary>Bare.</summary>
/// <exception cref="ELibFree">Free routine.</exception>
procedure R5Bare;
/// <summary>Deep.</summary>
/// <exception cref="ELibDeep">Two hops inside the library.</exception>
procedure R6Deep;
/// <summary>Class receiver.</summary>
/// <exception cref="ELibOpen">Class function.</exception>
procedure R7ClassCall;
/// <summary>Quiet.</summary>
/// <exception cref="ELibWrite">Control, the member raises nothing.</exception>
procedure C1Quiet;
/// <summary>Other.</summary>
/// <exception cref="ELibWrite">Control, the member raises another class.</exception>
procedure C2Other;
/// <summary>Own.</summary>
/// <exception cref="EProjOwn">Control, a project class.</exception>
procedure C3Own;
/// <summary>None.</summary>
/// <exception cref="ELibWrite">Control, no call at all.</exception>
procedure C4None;

implementation

procedure R1Direct;
var
  Ini: TLibIni;
begin
  Ini.WriteIt('x');
end;

procedure R2Delegate;
begin
  R1Direct;
end;

procedure R3Inherited;
var
  Ini: TLibIni;
begin
  Ini.Inh('x');
end;

procedure R4Abstract(const B: TLibBase);
begin
  B.WriteAbs('x');
end;

procedure R5Bare;
begin
  LibRaiser('x');
end;

procedure R6Deep;
var
  Ini: TLibIni;
begin
  Ini.Deep('x');
end;

procedure R7ClassCall;
begin
  TLibIni.Open('x');
end;

procedure C1Quiet;
var
  Ini: TLibIni;
begin
  Ini.Quiet('x');
end;

procedure C2Other;
var
  Ini: TLibIni;
begin
  Ini.WriteOther('x');
end;

procedure C3Own;
var
  Ini: TLibIni;
begin
  Ini.WriteIt('x');
end;

procedure C4None;
begin
end;

end.
'@

$libDb = Join-Path $scratch 'lib.sqlite'
$projDb = Join-Path $scratch 'proj.sqlite'
Push-Location $scratch
try {
  $null = & $exePath index (Join-Path $scratch 'lib') --db $libDb --library-db none 2>&1 | Out-String
  $null = & $exePath index (Join-Path $scratch 'proj') --db $projDb --library-db none 2>&1 | Out-String

  function NeverRaisedIn([string]$LibArg) {
    $raw = (& $exePath lint-all --db $projDb --rule doc-drift --library-db $LibArg --json 2>$null | Out-String)
    $rows = @($raw | ConvertFrom-Json)
    $src = [IO.File]::ReadAllLines((Join-Path $scratch 'proj\App.pas'))
    $names = @{}
    foreach ($r in $rows) {
      if ($r.message -notmatch 'never raises') { continue }
      for ($i = $r.start_line - 1; $i -lt $src.Length; $i++) {
        if ($src[$i] -match '^procedure (\w+)') { $names[$Matches[1]] = $true; break }
      }
    }
    return ,$names
  }

  $with = NeverRaisedIn $libDb
  Check '0. sanity: the fixture produced the control findings at all' ($with.Count -gt 0) ("reported: " + (($with.Keys | Sort-Object) -join ','))
  foreach ($n in 'R1Direct','R2Delegate','R3Inherited','R4Abstract','R5Bare','R6Deep','R7ClassCall') {
    Check "$n silent with the library" (-not $with.ContainsKey($n))
  }
  foreach ($n in 'C1Quiet','C2Other','C3Own','C4None') {
    Check "CONTROL $n still reports" ($with.ContainsKey($n))
  }
  $none = NeverRaisedIn 'none'
  Check 'CONTROL C5 R1Direct reports with --library-db none' ($none.ContainsKey('R1Direct'))
} finally { Pop-Location }

[IO.Directory]::Delete($scratch, $true)
if ($fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
} catch { Write-Host "FAIL (exception): $_"; exit 1 }
