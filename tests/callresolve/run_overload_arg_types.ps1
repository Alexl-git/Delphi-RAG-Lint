<#
  run_overload_arg_types.ps1 -- overloads of one arity that differ only in the
  TYPE of a parameter are told apart by the declared type of a VARIABLE argument.

  THE PROBLEM (backlog #25, 2026-09-30). UImageStore.LoadImage has three
  overloads of two parameters: (FileName: String; Bitmap: TBitmap),
  (FileName: String; aJpeg: TJPEGImage), (aFileName: String; aPng: TPngImage).
  UAuxHash.ComprimirJPEG calls LoadImage(aSource, vBitMap) with vBitMap: TBitmap,
  and find-callees said `LoadImage [ambiguous]`: resolver 1.12.0 reads only
  LITERAL arguments, and neither argument is one.

  THE FIX (resolver 1.18.0-alpha). When arity and literals leave several
  overloads, an argument that is a plain identifier the value rungs place
  (local, parameter, class-chain member, the one visible unit var) is typed
  from its declaration. The overload whose exact-type matches STRICTLY contain
  every other candidate's wins, [certain] -- Delphi prefers an exact match over
  any conversion.

  CONTROLS -- conservative, never a guess:
    * an argument of a type no overload declares (TObject) stays ambiguous;
    * a SPLIT -- one overload exact at argument 1, another at argument 2 --
      stays ambiguous;
    * a name a `with` target can claim is not typed from the local of the same
      name (the member would be passed), so that call stays ambiguous.

  The picked overload is read back from the DB by its declaration line, because
  every overload prints the same qualified name.
  Needs python on PATH for the sqlite read-back.

  Usage: pwsh -File tests/callresolve/run_overload_arg_types.ps1 [-Exe <path>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_overload_types_$PID"
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

Write-Ascii (Join-Path $src 'uImg.pas') @'
unit uImg;

interface

type
  TBitmap = class(TObject)
  end;
  TJPEGImage = class(TObject)
  end;
  TPngImage = class(TObject)
  end;
  THolder = class(TObject)
  public
    Img: TJPEGImage;
  end;

function LoadImage(FileName: String; Bitmap: TBitmap): Boolean; overload;
function LoadImage(FileName: String; aJpeg: TJPEGImage): Boolean; overload;
function LoadImage(const aFileName: String; aPng: TPngImage): Boolean; overload;

procedure Pair(A: TBitmap; B: TJPEGImage); overload;
procedure Pair(A: TJPEGImage; B: TBitmap); overload;

implementation

function LoadImage(FileName: String; Bitmap: TBitmap): Boolean;
begin
  Result := True;
end;

function LoadImage(FileName: String; aJpeg: TJPEGImage): Boolean;
begin
  Result := True;
end;

function LoadImage(const aFileName: String; aPng: TPngImage): Boolean;
begin
  Result := True;
end;

procedure Pair(A: TBitmap; B: TJPEGImage);
begin
end;

procedure Pair(A: TJPEGImage; B: TBitmap);
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'uUser.pas') @'
unit uUser;

interface

uses
  uImg;

procedure UseBitmap(const aSource: string);
procedure UseJpeg;
procedure UseUntyped(X: TObject);
procedure UseSplit;
procedure UseWith(AHolder: THolder);

implementation

procedure UseBitmap(const aSource: string);
var
  vBitMap: TBitmap;
begin
  LoadImage(aSource, vBitMap);
end;

procedure UseJpeg;
var
  vNome: string;
  vJ: TJPEGImage;
begin
  LoadImage(vNome, vJ);
end;

procedure UseUntyped(X: TObject);
begin
  LoadImage('a.bmp', X);
end;

procedure UseSplit;
var
  vB: TBitmap;
begin
  Pair(vB, vB);
end;

procedure UseWith(AHolder: THolder);
var
  Img: TBitmap;
begin
  with AHolder do
    LoadImage('x', Img);
end;

end.
'@

$db = Join-Path $WorkDir 'types.sqlite'
& $exePath index $src --db $db --quiet 2>&1 | Out-Null
Check 'precondition: index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$py = Join-Path $WorkDir 'edge.py'
@'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
row = c.execute("""SELECT t.start_line, e.confidence FROM call_edges e
                   JOIN refs r ON r.id = e.ref_id JOIN symbols s ON s.id = r.enclosing_symbol_id
                   JOIN symbols t ON t.id = e.target_symbol_id
                   WHERE s.qualified_name = ? AND r.name_text = ?""", (sys.argv[2], sys.argv[3])).fetchone()
print('%s %s' % row if row else 'none')
'@ | Set-Content -Encoding ascii $py
function Edge([string]$Caller, [string]$Name) { return ((python $py $db $Caller $Name) -join '').Trim() }

# Declaration lines in uImg.pas: LoadImage overloads 17/18/19, Pair 21/22.
$a = Edge 'uUser.UseBitmap' 'LoadImage'
Check 'ASSERT: a TBitmap variable picks the TBitmap overload, certain' ($a -eq '17 certain') "edge: $a"
$b = Edge 'uUser.UseJpeg' 'LoadImage'
Check 'ASSERT: a TJPEGImage variable picks the TJPEGImage overload, certain' ($b -eq '18 certain') "edge: $b"
$c = Edge 'uUser.UseUntyped' 'LoadImage'
Check 'CONTROL: a type no overload declares (TObject) stays ambiguous' ($c -match 'ambiguous$') "edge: $c"
$d = Edge 'uUser.UseSplit' 'Pair'
Check 'CONTROL: a split (exact at argument 1 in one, at 2 in the other) stays ambiguous' ($d -match 'ambiguous$') "edge: $d"
$e = Edge 'uUser.UseWith' 'LoadImage'
Check 'CONTROL: a name a with target can claim is not typed from the local' ($e -notmatch '^17 certain$') "edge: $e"

Write-Host ''
if ($script:fail) { Write-Host 'RESULT: FAIL'; exit 1 }
Write-Host 'RESULT: PASS'; exit 0
} finally {
  foreach ($d in @("$env:TEMP\draglint_overload_types_$PID")) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue } }
}
