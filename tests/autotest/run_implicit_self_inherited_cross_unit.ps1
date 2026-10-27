<#
  run_implicit_self_inherited_cross_unit.ps1 -- E4 (PLAN-2026-10-26 2c; CONVERTER
  ask 2 of docs\INBOX-2026-10-05-converter-to-engine-local-read-unresolved.md):
  an implicit-Self read or write of a field inherited from an ancestor declared
  in ANOTHER unit binds to that field.

  The converter's C8 editor filters code refs on rs.kind = 'field' and keeps a
  name-drop workaround for unresolved refs only until this holds cross-unit.
  Measured 2026-10-26 on the deployed 1.35.1-alpha: it already holds for every
  shape below; this guard pins it so the workaround can go.

  Shapes: form inheritance with a published component field (the converter's
  own Desc1/Desc2 repro, with .dfm), a two-unit-deep chain with a unit-qualified
  heritage, an ancestor reached through the IMPLEMENTATION uses, a nested
  routine, a generic descendant, and a property read. No-wrong-edge controls: a
  local spelled like the inherited field binds to the LOCAL, and an unrelated
  class's own same-named field binds to ITS field. Run from a NEUTRAL CWD.
#>
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-e4inh-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$WorkDir = Join-Path $WorkDir ([guid]::NewGuid().ToString('N'))
$srcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $srcDir -Force | Out-Null

function Emit([string]$name, [string]$text) {
  [System.IO.File]::WriteAllText((Join-Path $srcDir $name),
    (($text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Emit 'uE4Base.pas' @'
unit uE4Base;
interface
type
  TE4Label = class
  public
    Caption: string;
  end;
  TE4Base = class
  protected
    FCount: Integer;
    Label1: TE4Label;
  public
    Tag: Integer;
  end;
  TE4Other = class
  public
    FCount: Integer;
    procedure Own;
  end;
implementation
procedure TE4Other.Own;
begin
  FCount := 1;
end;
end.
'@

Emit 'uE4Mid.pas' @'
unit uE4Mid;
interface
uses uE4Base;
type
  TE4Mid = class(uE4Base.TE4Base)
    Label2: TE4Label;
  private
    FMid: Integer;
  public
    property Mid: Integer read FMid;
  end;
implementation
end.
'@

# Line numbers matter: the assertions match on them.
Emit 'uE4Leaf.pas' @'
unit uE4Leaf;
interface
procedure Free1;
implementation
uses uE4Base, uE4Mid;
type
  TE4Leaf = class(TE4Mid)
  public
    procedure Run;
    procedure Shadow;
  end;
  TE4Gen<T> = class(TE4Base)
    procedure G;
  end;
procedure TE4Leaf.Run;
  procedure Inner;
  begin
    Tag := FCount;
  end;
var
  N: Integer;
begin
  N := FCount;
  Label2.Caption := 'y';
  N := Mid;
  Label1.Caption := 'z';
  FCount := N;
  Inner;
end;
procedure TE4Leaf.Shadow;
var
  FCount: Integer;
begin
  FCount := 0;
  Tag := FCount;
end;
procedure TE4Gen<T>.G;
begin
  Tag := FCount;
end;
procedure Free1;
begin
end;
end.
'@
#  18 Tag write / FCount read inside a NESTED routine
#  23 FCount read (two units up, ancestor via implementation uses)
#  24 Label2 read (one unit up, published field, no visibility keyword)
#  25 Mid read (inherited property)
#  26 Label1 read (two units up)
#  27 FCount write
#  34 NEG: local FCount write -> the local
#  35 NEG: local FCount read  -> the local; Tag still the inherited field
#  39 generic descendant: FCount read

Emit 'Desc1.pas' @'
unit Desc1;
interface
uses Vcl.Forms, Vcl.StdCtrls, System.Classes;
type
  TDesc1Form = class(TForm)
    Label1: TLabel;
  private
  public
  end;
implementation
{$R *.dfm}
end.
'@
Emit 'Desc1.dfm' @'
object Desc1Form: TDesc1Form
  Caption = 'One'
  object Label1: TLabel
    Caption = 'L'
  end
end
'@
Emit 'Desc2.pas' @'
unit Desc2;
interface
uses Vcl.Forms, Desc1;
type
  TDesc2Form = class(TDesc1Form)
    procedure FormCreate(Sender: TObject);
  end;
implementation
{$R *.dfm}
procedure TDesc2Form.FormCreate(Sender: TObject);
var
  S: string;
begin
  Label1.Caption:= 'Two';
  S:= Label1.Caption;
  if Label1 = nil then Exit;
end;
end.
'@
Emit 'Desc2.dfm' @'
inherited Desc2Form: TDesc2Form
  inherited Label1: TLabel
    Caption = 'Two'
  end
end
'@

$manifest = Join-Path $WorkDir 'manifest.drag-lint.json'
$mtext = '{' + [char]10 +
  '  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },' + [char]10 +
  '  "indexes": { "outDir": "out", "sections": [ { "name": "SecE4", "db": "e4.sqlite", "include": ["src"] } ] }' + [char]10 +
  '}'
[System.IO.File]::WriteAllText($manifest, $mtext, [System.Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'out\e4.sqlite'

Push-Location C:\TEMP
try {
  & $Exe index --all --config $manifest --only SecE4 --jobs 1 2>&1 | Out-Null
  if (-not (Test-Path $db)) {
    Write-Host "FATAL: index did not produce $db" -ForegroundColor Red; exit 2
  }
  $rows = & $Exe sql --db $db --query ("select substr(f.path, length(rtrim(f.path, replace(f.path, '\', ''))) + 1) " +
                                       "|| '|' || r.start_line || '|' || r.kind || '|' || r.name_text || '|' || " +
                                       "coalesce(s.kind || ':' || s.qualified_name, 'NULL') " +
                                       "from refs r join files f on f.id = r.file_id " +
                                       "left join symbols s on s.id = r.symbol_id " +
                                       "where r.kind in ('read', 'write') and coalesce(r.receiver_text, '') = ''") 2>&1 | Out-String
} finally { Pop-Location }

function Has([string]$file, [int]$line, [string]$kind, [string]$name, [string]$target) {
  $pat = '(?m)^\s*' + [regex]::Escape("$file|$line|$kind|$name|$target") + '\s*$'
  [regex]::IsMatch($rows, $pat)
}
function Show([string]$file, [int]$line, [string]$name) {
  (@($rows -split "`r?`n" | Where-Object { $_ -match ('^\s*' + [regex]::Escape("$file|$line|")) -and $_ -match ('\|' + $name + '\|') }) -join ' ; ').Trim()
}

Write-Host ''
Write-Host 'CONVERTER REPRO -- form inheritance across units' -ForegroundColor Cyan
foreach ($ln in 14, 15, 16) {
  Check "Desc2.pas:$ln Label1 -> field Desc1.TDesc1Form.Label1" (Has 'Desc2.pas' $ln 'read' 'Label1' 'field:Desc1.TDesc1Form.Label1') (Show 'Desc2.pas' $ln 'Label1')
}

Write-Host ''
Write-Host 'DEEPER SHAPES' -ForegroundColor Cyan
Check 'nested routine: Tag write (18)' (Has 'uE4Leaf.pas' 18 'write' 'Tag' 'field:uE4Base.TE4Base.Tag') (Show 'uE4Leaf.pas' 18 'Tag')
Check 'nested routine: FCount read (18)' (Has 'uE4Leaf.pas' 18 'read' 'FCount' 'field:uE4Base.TE4Base.FCount') (Show 'uE4Leaf.pas' 18 'FCount')
Check 'two units up via implementation uses: FCount read (23)' (Has 'uE4Leaf.pas' 23 'read' 'FCount' 'field:uE4Base.TE4Base.FCount') (Show 'uE4Leaf.pas' 23 'FCount')
Check 'published field, unit-qualified heritage: Label2 read (24)' (Has 'uE4Leaf.pas' 24 'read' 'Label2' 'field:uE4Mid.TE4Mid.Label2') (Show 'uE4Leaf.pas' 24 'Label2')
Check 'inherited property: Mid read (25)' (Has 'uE4Leaf.pas' 25 'read' 'Mid' 'property:uE4Mid.TE4Mid.Mid') (Show 'uE4Leaf.pas' 25 'Mid')
Check 'two units up: Label1 read (26)' (Has 'uE4Leaf.pas' 26 'read' 'Label1' 'field:uE4Base.TE4Base.Label1') (Show 'uE4Leaf.pas' 26 'Label1')
Check 'FCount write (27)' (Has 'uE4Leaf.pas' 27 'write' 'FCount' 'field:uE4Base.TE4Base.FCount') (Show 'uE4Leaf.pas' 27 'FCount')
Check 'generic descendant: FCount read (39)' (Has 'uE4Leaf.pas' 39 'read' 'FCount' 'field:uE4Base.TE4Base.FCount') (Show 'uE4Leaf.pas' 39 'FCount')

Write-Host ''
Write-Host 'NO WRONG EDGE' -ForegroundColor Cyan
Check 'local shadow: FCount write (34) -> the LOCAL' (Has 'uE4Leaf.pas' 34 'write' 'FCount' 'local_var:uE4Leaf.TE4Leaf.Shadow.FCount') (Show 'uE4Leaf.pas' 34 'FCount')
Check 'local shadow: FCount read (35) -> the LOCAL' (Has 'uE4Leaf.pas' 35 'read' 'FCount' 'local_var:uE4Leaf.TE4Leaf.Shadow.FCount') (Show 'uE4Leaf.pas' 35 'FCount')
Check 'beside it, Tag write (35) is still the inherited field' (Has 'uE4Leaf.pas' 35 'write' 'Tag' 'field:uE4Base.TE4Base.Tag') (Show 'uE4Leaf.pas' 35 'Tag')
Check 'unrelated class: TE4Other.FCount write (23 of uE4Base) -> its OWN field' (Has 'uE4Base.pas' 23 'write' 'FCount' 'field:uE4Base.TE4Other.FCount') (Show 'uE4Base.pas' 23 'FCount')
$leak = @($rows -split "`r?`n" | Where-Object { $_ -match '^\s*uE4Leaf\.pas\|' -and $_ -match 'TE4Other' })
Check 'no uE4Leaf ref binds to the unrelated TE4Other' ($leak.Count -eq 0) ($leak -join ' ; ')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-e4inh-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
