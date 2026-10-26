<#
  run_cyclefix_b4d.ps1 -- plan 2026-10-25 B4-d (owner-delegated 2026-10-26, ledger
  docs\superpowers\plans\2026-10-26-xcyc-ledger.md): the F5 base-class recipe of `cycles --plan` accepts an
  INHERITING class `TX = class(TAnc[, I1, ...])` when the direct ancestor is declared OUTSIDE the cycle --
  in a project unit that is no member of the group, or (project index silent) in the platform library.
  The leaf gets `TXBase = class(TAnc)`; the class becomes `TX = class(TXBase[, I1, ...])`.

  Every case is a copy of docs\examples\circular-uses-demo with Customers.pas carrying the B4-b plain
  field (`FLast: TOrder`, `FLast.Id` read -> Id and FId are pulled) and Orders.pas / Base.pas edited by
  text substitution (the run_cyclefix_b4.ps1 pattern); a refused case marks the line the refusal must
  name with `{BAD}`.
  ACCEPTED: inherits (TOrder = class(TEntity), TEntity in Base.pas), inheritsiface (TOrder =
            class(TEntity, IDescribable): the interface stays on TOrder), inheritslib (TOrder =
            class(TPersistent) with --library-db; SKIPPED when no platform library DB is on disk).
  REFUSED:  anccycle (the ancestor TOrderRoot is declared in Orders.pas, a unit of the cycle),
            anclibnone (TPersistent with --library-db none: declared in no index given), dfm (`{$R *.dfm}`
            unit and the pulled property Id is published), classparent (Customers.pas names ClassParent).
  POSITIVE CONTROL: the plain (non-inheriting) field case stays accepted.
  The compile of every accepted tree is run_cyclefix_b4d_dcc.ps1 (needs RAD Studio).
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-b4d-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Demo  = Join-Path $Repo 'docs\examples\circular-uses-demo'
$Ascii = [Text.Encoding]::ASCII

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

function Replace-Once([string]$Text, [string]$Old, [string]$New) {
  $Old = $Old -replace "`r?`n", "`r`n"; $New = $New -replace "`r?`n", "`r`n"
  if (-not $Text.Contains($Old)) { throw "fixture edit: text not found: $Old" }
  return $Text.Replace($Old, $New)
}

# Writes the demo copy for case pTag: pCustomers / pOrders edit those units (text -> text);
# pExtra = @{ 'Name.pas' = text } adds units. Returns the case root.
function New-Case([string]$Tag, [scriptblock]$Customers, [scriptblock]$Orders, [hashtable]$Extra) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem $Demo -Filter *.pas | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) -Force }
  $cu = Join-Path $root 'Customers.pas'
  if ($Customers) { Set-Text $cu (& $Customers ([IO.File]::ReadAllText($cu))) }
  $ou = Join-Path $root 'Orders.pas'
  if ($Orders) { Set-Text $ou (& $Orders ([IO.File]::ReadAllText($ou))) }
  $units = @('Customers', 'Orders')
  if ($Extra) { foreach ($k in $Extra.Keys) { Set-Text (Join-Path $root $k) $Extra[$k]; $u = [IO.Path]::GetFileNameWithoutExtension($k); if ($units -notcontains $u) { $units += $u } } }
  $uses = ($units | ForEach-Object { "  $_ in '$_.pas'" }) -join ",`r`n"
  Set-Text (Join-Path $root 'Demo.dpr') "program Demo;`r`n`r`nuses`r`n$uses;`r`n`r`nbegin`r`nend.`r`n"
  $refs = ($units | ForEach-Object { "    <DCCReference Include=`"$_.pas`"/>" }) -join "`r`n"
  Set-Text (Join-Path $root 'Demo.dproj') ("<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`r`n" +
    "  <PropertyGroup><MainSource>Demo.dpr</MainSource></PropertyGroup>`r`n" +
    "  <ItemGroup>`r`n    <DelphiCompile Include=`"Demo.dpr`"><MainSource>MainSource</MainSource></DelphiCompile>`r`n" +
    "$refs`r`n  </ItemGroup>`r`n</Project>`r`n")
  return $root
}

# The plan text of case root pRoot; pLib = the --library-db value ('none' or a scratch copy).
function Get-Plan([string]$Root, [string]$Tag, [string]$Lib = 'none') {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $Root 'Demo.dproj') --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return @{ Exit = $p.ExitCode; Text = [IO.File]::ReadAllText($o) }
}

# 1-based line of the `{BAD}` marker in pPath (0 when none).
function Get-BadLine([string]$Path) {
  $l = [IO.File]::ReadAllLines($Path)
  for ($k = 0; $k -lt $l.Count; $k++) { if ($l[$k].Contains('{BAD}')) { return $k + 1 } }
  return 0
}

function Test-Accepted([string]$Tag, [scriptblock]$Orders, [hashtable]$Extra, [string[]]$Expect, [string]$Lib = 'none') {
  Write-Host "== $Tag (accepted)" -ForegroundColor Cyan
  $root = New-Case $Tag $addField $Orders $Extra
  $pl = Get-Plan $root $Tag $Lib
  Check "$Tag a0 planned (exit 0)" ($pl.Exit -eq 0) "exit=$($pl.Exit)"
  $refused = [regex]::Match($pl.Text, '(?m)^.*refused: base-class.*$').Value
  Check "$Tag a1 no base-class refusal" ($refused -eq '') $refused
  Check "$Tag a2 the plan is mechanical (no refusal of any kind)" ($pl.Text -notmatch 'refused: ') ''
  Check "$Tag a3 the field switches to TOrderBase" ($pl.Text -match 'FLast\s*:\s*TOrderBase;') ''
  $k = 4
  foreach ($e in $Expect) { Check "$Tag a$k the plan says: $e" $pl.Text.Contains($e) ''; $k++ }
}

function Test-Refused([string]$Tag, [scriptblock]$Customers, [scriptblock]$Orders, [hashtable]$Extra, [string]$SiteFile, [string]$Word, [string]$Lib = 'none') {
  Write-Host "== $Tag (refused)" -ForegroundColor Cyan
  $root = New-Case $Tag $Customers $Orders $Extra
  $line = Get-BadLine (Join-Path $root $SiteFile)
  Check "$Tag ctl the {BAD} marker is in $SiteFile" ($line -gt 0) "line=$line"
  $pl = Get-Plan $root $Tag $Lib
  Check "$Tag r0 planned (exit 0)" ($pl.Exit -eq 0) "exit=$($pl.Exit)"
  $refused = [regex]::Match($pl.Text, '(?m)^.*`TOrder` \(class.*refused: base-class.*$').Value
  Check "$Tag r1 TOrder is refused with base-class" ($refused -ne '') ''
  Check "$Tag r2 the refusal names $SiteFile`:$line" ($refused.Contains("refused: base-class -- ``$SiteFile`:$line``")) $refused
  if ($Word) { Check "$Tag r3 the refusal says '$Word'" ($refused.Contains($Word)) '' }
  Check "$Tag r4 TOrder gets no base class" (-not ($pl.Text -match 'TOrder = class\(TOrderBase')) ''
}

# B4-b plain field in Customers.pas (run_cyclefix_b4.ps1): FLast := AOrder; Assigned(FLast); FLast.Id
$addField = {
  param($t)
  $t = Replace-Once $t "    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n" `
    "    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n    FLast  : TOrder;`r`n"
  $t = Replace-Once $t "  FOrders[High(FOrders)] := AOrder;`r`n" "  FOrders[High(FOrders)] := AOrder;`r`n  FLast := AOrder;`r`n"
  return Replace-Once $t "  Result := Length(FOrders);`r`n" "  Result := Length(FOrders);`r`n  if Assigned(FLast) then Result := Result + FLast.Id - FLast.Id;`r`n"
}

# Base.pas: an ancestor OUTSIDE the cycle with the IInterface methods (no reference counting), and an interface.
$BaseUnit = @'
unit Base;

// B4-d fixture: the ancestor of TOrder, declared OUTSIDE the cycle.

interface

type
  /// <summary>Describes an entity.</summary>
  IDescribable = interface
    ['{B4D00001-0000-4000-8000-000000000001}']
    function Describe: string;
  end;

  /// <summary>Ancestor with a tag; carries the IInterface methods without reference
  /// counting so a descendant may list interfaces.</summary>
  TEntity = class(TObject, IInterface)
  protected
    FTag: string;
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  public
    property Tag: string read FTag;
  end;

implementation

function TEntity.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then Result := 0 else Result := E_NOINTERFACE;
end;

function TEntity._AddRef: Integer;
begin
  Result := -1;
end;

function TEntity._Release: Integer;
begin
  Result := -1;
end;

end.
'@

# Orders.pas: uses Base in the interface, inherits TEntity, sets the tag.
$inherits = {
  param($t)
  $t = Replace-Once $t "interface`r`n`r`ntype" "interface`r`n`r`nuses`r`n  Base;`r`n`r`ntype"
  $t = Replace-Once $t "  TOrder = class`r`n" "  TOrder = class(TEntity)`r`n"
  return Replace-Once $t "  FId          := AId;`r`n" "  FId          := AId;`r`n  FTag         := 'order';`r`n"
}
$inheritsIface = {
  param($t)
  $t = & $inherits $t
  $t = Replace-Once $t "  TOrder = class(TEntity)`r`n" "  TOrder = class(TEntity, IDescribable)`r`n"
  return $t
}
$inheritsLib = {
  param($t)
  $t = Replace-Once $t "interface`r`n`r`ntype" "interface`r`n`r`nuses`r`n  System.Classes;`r`n`r`ntype"
  return Replace-Once $t "  TOrder = class`r`n" "  TOrder = class(TPersistent)`r`n"
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== positive control: the plain field case (no ancestor) stays accepted' -ForegroundColor Cyan
  $root = New-Case 'plain' $addField $null $null
  $pl = Get-Plan $root 'plain'
  Check 'plain a0 planned (exit 0), no refusal, TOrder = class(TOrderBase)' (($pl.Exit -eq 0) -and ($pl.Text -notmatch 'refused: ') -and ($pl.Text -match 'TOrder = class\(TOrderBase\)')) ''
  Check 'plain c9 the Fix it line names the base-class recipe, not "move globals"' (($pl.Text -match '(?m)^  cuts    : the INTERFACE coupling of this cycle \(Part A: extract base classes into new leaf units\)\r?$') -and ($pl.Text -notmatch 'Part A: move globals into new leaf units\)')) ''

  Test-Accepted 'inherits' $inherits @{ 'Base.pas' = $BaseUnit } @('TOrder = class(TOrderBase)', 'TOrderBase = class(TEntity)', '`TOrder` stays in `Orders.pas` and becomes `TOrder = class(TOrderBase)`')
  Test-Accepted 'inheritsiface' $inheritsIface @{ 'Base.pas' = $BaseUnit } @('TOrder = class(TOrderBase, IDescribable)', 'TOrderBase = class(TEntity)')
  if (Test-Path $LibraryDb) {
    $Lib = Join-Path $WorkDir 'library-copy.sqlite'
    Copy-Item $LibraryDb $Lib
    Test-Accepted 'inheritslib' $inheritsLib $null @('TOrder = class(TOrderBase)', 'TOrderBase = class(TPersistent)') $Lib
  } else { Write-Host "  SKIP inheritslib: no platform library DB at $LibraryDb" -ForegroundColor Yellow }

  Test-Refused 'anccycle' $addField {
    param($t)
    $t = Replace-Once $t "type`r`n  /// <summary>An order." "type`r`n  TOrderRoot = class`r`n  end;`r`n`r`n  /// <summary>An order."
    return Replace-Once $t "  TOrder = class`r`n" "  TOrder = class(TOrderRoot) {BAD}`r`n"
  } $null 'Orders.pas' 'TOrderRoot'
  Test-Refused 'anclibnone' $addField {
    param($t)
    return Replace-Once (& $inheritsLib $t) "  TOrder = class(TPersistent)`r`n" "  TOrder = class(TPersistent) {BAD}`r`n"
  } $null 'Orders.pas' '--library-db'
  Test-Refused 'dfm' $addField {
    param($t)
    $t = & $inherits $t
    $t = Replace-Once $t "    function Describe: string;`r`n    property Id: Integer read FId;`r`n" "    function Describe: string;`r`n  published`r`n    property Id: Integer read FId; {BAD}`r`n"
    return Replace-Once $t "implementation`r`n`r`nuses" "implementation`r`n`r`n{`$R *.dfm}`r`n`r`nuses"
  } @{ 'Base.pas' = $BaseUnit } 'Orders.pas' 'published'
  # ClassParent named in the class's OWN unit (a consumer site would be judged by the F5 site rules first)
  Test-Refused 'classparent' $addField {
    param($t)
    return Replace-Once (& $inherits $t) "  { reaches back into Customers to read the customer's name }`r`n" "  if ClassParent = nil then Result := ''; {BAD}`r`n  { reaches back into Customers to read the customer's name }`r`n"
  } @{ 'Base.pas' = $BaseUnit } 'Orders.pas' 'ClassParent'
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
