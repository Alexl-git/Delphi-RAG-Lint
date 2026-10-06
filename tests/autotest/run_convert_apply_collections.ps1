<#
  run_convert_apply_collections.ps1 -- a COLLECTION-valued property (FieldDefs /
  IndexDefs: `Defs = < item ... end>`) never disappears silently (1.25.1-alpha).

  THE DEFECT (found on DMTEST's DMREADINGS: 14 collections, 709 items gone).
  BDE-to-FireDAC.rules' TTable block links every ITEM member of FieldDefs and
  IndexDefs (`#link FieldDefs.Items.Name <- FieldDefs.Items.Name`, ...) and
  ALSO says `#ignore FieldDefs` / `#ignore IndexDefs`. The re-emit treats a
  collection as ONE leaf: only a whole-collection `#link FieldDefs <- ...`
  carried it, the per-item links were dead, and the #ignore -- checked first --
  dropped the collection with no line in any report surface.

  THE CONTRACT this guard pins:
    (a) a collection whose ITEM members the book links, all identity
        (`#link Defs.Items.X <- Defs.Items.X`), and whose To type has the same
        property with the same collection type, is CARRIED verbatim -- item
        count preserved, a reemit note `collection Defs carried, items
        unchanged (#link Defs.Items.* ...)`. The item links are more specific
        than an `#ignore Defs` on the same block, so they win over it.
    (b) a collection the book does not mention is DROPPED AND SAID SO: the
        per-instance `dropped Defs` note, the `TSrcSet.Defs: no #link carries
        it -- dropped on 1 of 1 converted instance(s)` warning, json unlinked[]
        and unlinked_source_properties.
    (c) item links that cannot be honoured (the To type's property has another
        collection type, or none on the .dfm surface -- TFDTable streams no
        FieldDefs) do not carry it, and do not drop it silently either: a
        reemit note names the collection, why, and its item count, and it is
        COUNTED as dropped (warning + unlinked[]) even under an #ignore.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_collections_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }

Write-Ascii (P 'LibA.pas') @'
unit LibA;

interface

uses
  System.Classes;

type
  TMyItem = class(TCollectionItem)
  private
    FName: string;
    FSize: Integer;
  published
    property Name: string read FName write FName;
    property Size: Integer read FSize write FSize;
  end;

  TMyDefs = class(TCollection)
  private
    function GetItem(Index: Integer): TMyItem;
  public
    property Items[Index: Integer]: TMyItem read GetItem; default;
  end;

  TOtherDefs = class(TCollection)
  private
    function GetItem(Index: Integer): TMyItem;
  public
    property Items[Index: Integer]: TMyItem read GetItem; default;
  end;

  TSrcSet = class(TComponent)
  private
    FDefs: TMyDefs;
    FIdx : TMyDefs;
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
    property Defs: TMyDefs read FDefs write FDefs;
    property Idx: TMyDefs read FIdx write FIdx;
  end;

implementation

function TMyDefs.GetItem(Index: Integer): TMyItem;
begin
  Result := TMyItem(inherited GetItem(Index));
end;

function TOtherDefs.GetItem(Index: Integer): TMyItem;
begin
  Result := TMyItem(inherited GetItem(Index));
end;

end.
'@
Write-Ascii (P 'LibB.pas') @'
unit LibB;

interface

uses
  System.Classes, LibA;

type
  TDstSet = class(TComponent)
  private
    FDefs: TMyDefs;
    FIdx : TOtherDefs;
    FTitle: string;
  published
    property Title: string read FTitle write FTitle;
    property Defs: TMyDefs read FDefs write FDefs;
    property Idx: TOtherDefs read FIdx write FIdx;
  end;

implementation

end.
'@

function New-Unit([string]$Name) {
  Write-Ascii (P "$Name.pas") @"
unit $Name;

interface

uses
  System.Classes, LibA;

type
  T$Name = class(TDataModule)
    ds: TSrcSet;
  end;

implementation

{`$R *.dfm}

end.
"@
  Write-Ascii (P "$Name.dfm") @"
object ${Name}: T$Name
  object ds: TSrcSet
    Caption = 'c'
    Defs = <
      item
        Name = 'ID'
        Size = 4
      end
      item
        Name = 'Title'
        Size = 40
      end
      item
        Name = 'Code'
        Size = 8
      end>
  end
end
"@
}
New-Unit 'CarryDM'
New-Unit 'CarryIgnDM'
New-Unit 'DropDM'
Write-Ascii (P 'IdxDM.pas') @'
unit IdxDM;

interface

uses
  System.Classes, LibA;

type
  TIdxDM = class(TDataModule)
    ds: TSrcSet;
  end;

implementation

{$R *.dfm}

end.
'@
Write-Ascii (P 'IdxDM.dfm') @'
object IdxDM: TIdxDM
  object ds: TSrcSet
    Caption = 'c'
    Idx = <
      item
        Name = 'PK'
        Size = 1
      end>
  end
end
'@

Write-Ascii (P 'carry.rules') @'
#convert LibA.TSrcSet -> LibB.TDstSet, LibB
#link Title <- Caption
#link Defs.Items.Name <- Defs.Items.Name
#link Defs.Items.Size <- Defs.Items.Size
'@
Write-Ascii (P 'carryign.rules') @'
#convert LibA.TSrcSet -> LibB.TDstSet, LibB
#link Title <- Caption
#link Defs.Items.Name <- Defs.Items.Name
#link Defs.Items.Size <- Defs.Items.Size
#ignore Defs
'@
Write-Ascii (P 'drop.rules') @'
#convert LibA.TSrcSet -> LibB.TDstSet, LibB
#link Title <- Caption
'@
Write-Ascii (P 'idx.rules') @'
#convert LibA.TSrcSet -> LibB.TDstSet, LibB
#link Title <- Caption
#link Idx.Items.Name <- Idx.Items.Name
#ignore Idx
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $WorkDir --db $db 2>&1
Check 'V the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

function ApplyTo([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe convert-apply --unit (P $Unit) --rules (P $Rules) --db $db @Extra 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Items([string]$File) { return ([regex]::Matches([IO.File]::ReadAllText((P $File)), '(?m)^\s*item\s*$')).Count }

# ---- (a) item links carry the collection -----------------------------------------
$r = ApplyTo 'CarryDM.pas' 'carry.rules' @('--format', 'json')
$j = Json $r.Out
Check 'A1 dry run: exit 0, a reemit note says Defs is carried with its items' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.reemit_notes | Where-Object { $_ -match 'collection Defs carried, items unchanged' }).Count -eq 1)) $r.Out
Check 'A2 no dropped / unlinked report for Defs' `
  ((@($j.reemit_notes | Where-Object { $_ -match 'dropped Defs' }).Count -eq 0) -and ($j.unlinked_source_properties -eq 0)) ($j.reemit_notes -join ' | ')
$r = ApplyTo 'CarryDM.pas' 'carry.rules' @('--apply', '--no-backup')
$t = [IO.File]::ReadAllText((P 'CarryDM.dfm'))
Check 'A3 --apply: the TDstSet block carries Defs with all 3 items, values intact' `
  (($r.Code -eq 0) -and ($t -match 'object ds: TDstSet') -and ((Items 'CarryDM.dfm') -eq 3) -and ($t -match "Name = 'Code'") -and ($t -match 'Size = 40')) $t
$r = ApplyTo 'CarryIgnDM.pas' 'carryign.rules' @('--apply', '--no-backup')
Check 'A4 the real book''s shape (item links AND #ignore Defs): the item links win -- carried, 3 items' `
  (($r.Code -eq 0) -and ((Items 'CarryIgnDM.dfm') -eq 3)) ([IO.File]::ReadAllText((P 'CarryIgnDM.dfm')))

# ---- (b) an unmentioned collection is dropped LOUDLY -------------------------------
$r = ApplyTo 'DropDM.pas' 'drop.rules' @('--format', 'json')
$j = Json $r.Out
Check 'B1 dropped Defs is a reemit note, a warning with the N of M count, and unlinked[]' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.reemit_notes | Where-Object { $_ -match '^ds: dropped Defs$' }).Count -eq 1) -and `
   (@($j.warnings | Where-Object { $_ -match 'TSrcSet\.Defs: no #link carries it -- dropped on 1 of 1 converted instance' }).Count -eq 1) -and `
   ($j.unlinked_source_properties -eq 1) -and (@($j.unlinked | Where-Object { $_.path -eq 'Defs' }).Count -eq 1)) $r.Out

# ---- (c) item links that cannot be honoured are said so, even under #ignore --------
$r = ApplyTo 'IdxDM.pas' 'idx.rules' @('--format', 'json')
$j = Json $r.Out
Check 'C1 Idx (TMyDefs -> TOtherDefs): not carried, and a reemit note names Idx, the two types and the item count' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.reemit_notes | Where-Object { $_ -match 'collection Idx' -and $_ -match 'TMyDefs' -and $_ -match 'TOtherDefs' -and $_ -match 'NOT carried, 1 item' }).Count -eq 1)) $r.Out
Check 'C2 ... and COUNTED although the block says #ignore Idx: dropped note, N of M warning, unlinked[]' `
  ((@($j.reemit_notes | Where-Object { $_ -match '^ds: dropped Idx$' }).Count -eq 1) -and ($j.unlinked_source_properties -eq 1) -and `
   (@($j.warnings | Where-Object { $_ -match 'TSrcSet\.Idx: no #link carries it -- dropped on 1 of 1' }).Count -eq 1)) $r.Out

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_collections_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
