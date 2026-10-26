<#
  run_cyclefix_b4.ps1 -- plan 2026-10-25 (cycles-fix refusal recipes) B4-a / B4-b: the F5 base-class
  gate of `cycles --plan` extended to LOCALS and PLAIN FIELDS of the class type, on top of D1 (a+).

  B4-a: a local `L: TX` (a `var` section, an inline `var L: TX`, or `for var L: TX in F do`) switches to
  TXBase when every use of it is a member read through it, a nil test / Assigned, FreeAndNil, an
  assignment from nil or from another slot that switches (a parameter, a field, a local, an element
  `F[..]` of a switching array field), a store of it into such a slot, or the loop variable over a
  switching array field.
  B4-b: a plain field `F: TX;` switches under the same use rules (plus `F.Free`), when it is not
  published and the index shows no ref to it outside its unit. A parameter stored whole into such a
  field or local (`FLast := AOrder`) switches as well.

  Every case is a copy of docs\examples\circular-uses-demo with Customers.pas edited by text
  substitution (the run_cyclefix_f5_field.ps1 pattern); a refused case marks the line the refusal must
  name with `{BAD}`.
  ACCEPTED: local (var-section local read from an array element), localfor (for var O: TOrder in
            FOrders), plainfield (FLast := AOrder; Assigned(FLast); FLast.Id), plainfieldfree (the
            same plus a destructor with FLast.Free).
  REFUSED:  localcast (TObject(LLast) -- a use other than the whitelist), localtest (LLast is TObject
            -- a type test, not on the whitelist), plainfieldpub (FLast published), plainfieldcast
            (TObject(FLast) = nil).
  POSITIVE CONTROL: the shipped demo stays accepted; each refused case differs from an accepted one by
  one edit.
  B4-c: a TList<TX> / TObjectList<TX> field switches when every use is on the list whitelist (Create on the
  same type, Add, Insert, Remove, IndexOf, Contains, Delete, Clear, Count, Free, an element store / member read,
  `for S in F`): list (accepted), listfirst (FList.First -- refused, naming the line).
  B4-e: a property read through a METHOD accessor pulls the method too (`virtual; abstract;` in the base,
  `override;` in the class): accessor (Orders.pas: property Id read GetId) is accepted; accessorvirtual
  (GetId already `virtual;`) is refused, naming the accessor and its directive.
  The compile of every accepted tree is run_cyclefix_b4_dcc.ps1 (needs RAD Studio).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-b4-$PID"
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
  if (-not $Text.Contains($Old)) { throw "fixture edit: text not found: $Old" }
  return $Text.Replace($Old, $New)
}

# Writes the demo copy for case pTag; pEdit (scriptblock: Customers.pas text -> text) edits it;
# pExtra = @{ 'Name.pas' = text } adds units. Returns the case root.
function New-Case([string]$Tag, [scriptblock]$Edit, [hashtable]$Extra) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem $Demo -Filter *.pas | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) -Force }
  $cu = Join-Path $root 'Customers.pas'
  if ($Edit) { Set-Text $cu (& $Edit ([IO.File]::ReadAllText($cu))) }
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

# The plan text of case root pRoot.
function Get-Plan([string]$Root, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $Root 'Demo.dproj') --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', 'none') `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return @{ Exit = $p.ExitCode; Text = [IO.File]::ReadAllText($o) }
}

# 1-based line of the `{BAD}` marker in pPath (0 when none).
function Get-BadLine([string]$Path) {
  $l = [IO.File]::ReadAllLines($Path)
  for ($k = 0; $k -lt $l.Count; $k++) { if ($l[$k].Contains('{BAD}')) { return $k + 1 } }
  return 0
}

function Test-Accepted([string]$Tag, [scriptblock]$Edit) {
  Write-Host "== $Tag (accepted)" -ForegroundColor Cyan
  $root = New-Case $Tag $Edit $null
  $pl = Get-Plan $root $Tag
  Check "$Tag a0 planned (exit 0)" ($pl.Exit -eq 0) "exit=$($pl.Exit)"
  $refused = [regex]::Match($pl.Text, '(?m)^.*refused: base-class.*$').Value
  Check "$Tag a1 no base-class refusal" ($refused -eq '') $refused
  Check "$Tag a2 TOrder gets the base class TOrderBase" ($pl.Text -match 'TOrder = class\(TOrderBase\)') ''
  Check "$Tag a3 the field switches to TArray<TOrderBase>" ($pl.Text -match 'FOrders\s*:\s*TArray<TOrderBase>;') ''
  Check "$Tag a4 the stored parameter switches to TOrderBase" ($pl.Text -match 'AddOrder\(const AOrder: TOrderBase\)') ''
}

function Test-Refused([string]$Tag, [scriptblock]$Edit, [hashtable]$Extra, [string]$SiteFile, [string]$Word) {
  Write-Host "== $Tag (refused)" -ForegroundColor Cyan
  $root = New-Case $Tag $Edit $Extra
  $line = Get-BadLine (Join-Path $root $SiteFile)
  Check "$Tag ctl the {BAD} marker is in $SiteFile" ($line -gt 0) "line=$line"
  $pl = Get-Plan $root $Tag
  Check "$Tag r0 planned (exit 0)" ($pl.Exit -eq 0) "exit=$($pl.Exit)"
  $refused = [regex]::Match($pl.Text, '(?m)^.*`TOrder` \(class.*refused: base-class.*$').Value
  Check "$Tag r1 TOrder is refused with base-class" ($refused -ne '') ''
  Check "$Tag r2 the refusal names $SiteFile`:$line" ($refused.Contains("refused: base-class -- ``$SiteFile`:$line``")) $refused
  if ($Word) { Check "$Tag r3 the refusal says '$Word'" ($refused.Contains($Word)) '' }
}


function Test-AcceptedB4([string]$Tag, [scriptblock]$Edit, [hashtable]$Extra, [string[]]$Expect) {
  Write-Host "== $Tag (accepted)" -ForegroundColor Cyan
  $root = New-Case $Tag $Edit $Extra
  $pl = Get-Plan $root $Tag
  Check "$Tag a0 planned (exit 0)" ($pl.Exit -eq 0) "exit=$($pl.Exit)"
  $refused = [regex]::Match($pl.Text, '(?m)^.*refused: base-class.*$').Value
  Check "$Tag a1 no base-class refusal" ($refused -eq '') $refused
  Check "$Tag a2 TOrder gets the base class TOrderBase" ($pl.Text -match 'TOrder = class\(TOrderBase\)') ''
  $k = 3
  foreach ($e in $Expect) { Check "$Tag a$k the plan switches: $e" $pl.Text.Contains($e) ''; $k++ }
}

# B4 edits of Customers.pas
$addLocal = {
  param($t)
  return Replace-Once $t "function TCustomer.OrderCount: Integer;`r`nbegin`r`n  Result := Length(FOrders);`r`nend;" (
    "function TCustomer.OrderCount: Integer;`r`nvar`r`n  LLast: TOrder;`r`nbegin`r`n  Result := Length(FOrders);`r`n" +
    "  if Result > 0 then`r`n  begin`r`n    LLast := FOrders[High(FOrders)];`r`n    if LLast <> nil then Result := Result + LLast.Id - LLast.Id;`r`n  end;`r`nend;")
}
$addField = {
  param($t)
  $t = Replace-Once $t "    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n" (
    "    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n    FLast  : TOrder;`r`n")
  $t = Replace-Once $t "  FOrders[High(FOrders)] := AOrder;`r`n" "  FOrders[High(FOrders)] := AOrder;`r`n  FLast := AOrder;`r`n"
  return Replace-Once $t "  Result := Length(FOrders);`r`n" "  Result := Length(FOrders);`r`n  if Assigned(FLast) then Result := Result + FLast.Id - FLast.Id;`r`n"
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Test-AcceptedB4 'demo' $null $null @('FOrders: TArray<TOrderBase>;')
  # --- B4-a locals ------------------------------------------------------------------------------
  Test-AcceptedB4 'local' $addLocal $null @('  LLast: TOrderBase;')
  Test-AcceptedB4 'localfor' {
    param($t)
    return Replace-Once $t "  Result := Length(FOrders);`r`n" ("  Result := Length(FOrders);`r`n  for var O: TOrder in FOrders do`r`n" +
      "    if O <> nil then Result := Result + O.Id - O.Id;`r`n")
  } $null @('  for var O: TOrderBase in FOrders do')
  Test-Refused 'localcast' {
    param($t)
    return Replace-Once (& $addLocal $t) "    if LLast <> nil then Result := Result + LLast.Id - LLast.Id;`r`n" (
      "    if LLast <> nil then Result := Result + LLast.Id - LLast.Id;`r`n    if TObject(LLast) = nil then Result := 0; {BAD}`r`n")
  } $null 'Customers.pas' 'local `LLast`'
  Test-Refused 'localtest' {
    param($t)
    return Replace-Once (& $addLocal $t) "    if LLast <> nil then Result := Result + LLast.Id - LLast.Id;`r`n" (
      "    if LLast <> nil then Result := Result + LLast.Id - LLast.Id;`r`n    if LLast is TObject then Inc(Result, 0); {BAD}`r`n")
  } $null 'Customers.pas' 'local `LLast`'  # --- B4-b plain fields ------------------------------------------------------------------------
  Test-AcceptedB4 'plainfield' $addField $null @('    FLast  : TOrderBase;', 'AddOrder(const AOrder: TOrderBase)')
  Test-AcceptedB4 'plainfieldfree' {
    param($t)
    $t = Replace-Once (& $addField $t) "    function OrderCount: Integer;`r`n" "    function OrderCount: Integer;`r`n    destructor Destroy; override;`r`n"
    return $t -replace 'end\.\s*$', "destructor TCustomer.Destroy;`r`nbegin`r`n  FLast.Free;`r`n  inherited Destroy;`r`nend;`r`n`r`nend.`r`n"
  } $null @('    FLast  : TOrderBase;')
  Test-Refused 'plainfieldpub' {
    param($t)
    $t = Replace-Once (& $addField $t) "    FLast  : TOrder;`r`n" "  published`r`n    FLast  : TOrder; {BAD}`r`n"
    return $t
  } $null 'Customers.pas' 'published'
  Test-Refused 'plainfieldcast' {
    param($t)
    return Replace-Once (& $addField $t) "  FLast := AOrder;`r`n" "  FLast := AOrder;`r`n  if TObject(FLast) = nil then Exit; {BAD}`r`n"
  } $null 'Customers.pas' 'field `FLast`'
  $addList = {
    param($t)
    $t = $t.Replace("  Orders;   { <-- interface-section use", "  System.Generics.Collections,`r`n  Orders;   { <-- interface-section use")
    $t = $t.Replace("    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n",
      "    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n    FList  : TList<TOrder>;`r`n")
    $t = $t.Replace("  SetLength(FOrders, 0);`r`n", "  SetLength(FOrders, 0);`r`n  FList := TList<TOrder>.Create;`r`n")
    $t = $t.Replace("  FOrders[High(FOrders)] := AOrder;`r`n", "  FOrders[High(FOrders)] := AOrder;`r`n  FList.Add(AOrder);`r`n")
    return $t.Replace("  Result := Length(FOrders);`r`n", ("  Result := Length(FOrders) + FList.Count - FList.Count;`r`n" +
      "  for var O: TOrder in FList do`r`n    if O <> nil then Result := Result + O.Id - O.Id;`r`n"))
  }
  # --- B4-c RTL object lists ---------------------------------------------------------------------
  Test-AcceptedB4 'list' $addList $null @('    FList  : TList<TOrderBase>;', '  FList := TList<TOrderBase>.Create;', '  for var O: TOrderBase in FList do')
  Test-Refused 'listfirst' { param($t) return Replace-Once (& $addList $t) "  FList.Add(AOrder);`r`n" "  FList.Add(AOrder);`r`n  if FList.First = nil then Exit; {BAD}`r`n" } $null 'Customers.pas' 'field `FList`'
  # --- B4-e accessor closure: a property read through a method -------------------------------------
  $ordersText = [IO.File]::ReadAllText((Join-Path $Demo 'Orders.pas'))
  $ordersAcc = Replace-Once (Replace-Once $ordersText '    property Id: Integer read FId;' '    property Id: Integer read GetId;') `
    "  public`r`n    constructor Create(" "    function GetId: Integer;`r`n  public`r`n    constructor Create("
  $ordersAcc = $ordersAcc -replace 'end\.\s*$', "function TOrder.GetId: Integer;`r`nbegin`r`n  Result := FId;`r`nend;`r`n`r`nend.`r`n"
  Test-AcceptedB4 'accessor' $addField @{ 'Orders.pas' = $ordersAcc } @('function GetId: Integer; virtual; abstract;', 'function GetId: Integer; override;')
  Write-Host '== accessorvirtual (refused: the accessor already carries a directive)' -ForegroundColor Cyan
  $rv = New-Case 'accessorvirtual' $addField @{ 'Orders.pas' = (Replace-Once $ordersAcc '    function GetId: Integer;' '    function GetId: Integer; virtual;') }
  $pv = Get-Plan $rv 'accessorvirtual'
  Check 'accessorvirtual r1 TOrder gets no base class' (-not ($pv.Text -match 'TOrder = class\(TOrderBase\)')) ''
  Check 'accessorvirtual r2 the plan names the accessor and its directive' `
    $pv.Text.Contains('property `Id` is read or written through method `GetId`, which already carries directives') ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }