<#
  run_cyclefix_f5_field.ps1 -- owner ruling D1 (a+), 2026-10-25: `cycles --plan` step F5 may switch a
  FIELD of type TArray<TX> / array of TX to the base class TXBase when EVERY ref to the field is
  SetLength / Length / High / Low, a store `F[..] := x`, or a read `F[..].M` of a pulled member;
  the field is not published; and the index shows no ref to it outside its unit. A parameter of
  type TX whose body only stores it into such a field (`F[..] := p`) switches as well.

  Every case is a copy of docs\examples\circular-uses-demo (plus a Demo.dpr / Demo.dproj this
  runner writes), with Customers.pas edited by text substitution. A refused case marks the line
  the refusal must name with a `{BAD}` comment; the expected line is read from the SOURCE.

  ACCEPTED (TOrder gets a base class; no `refused: base-class`; the field line switches):
    demo        -- the shipped demo, unchanged
    memberread  -- adds `Result := FOrders[0].Id` (a read of a pulled member)
  REFUSED (the plan names the offending site):
    bare        -- `var LAll := FOrders;`              (a bare read)
    elemvalue   -- `var LFirst := FOrders[0];`         (an element used as a value)
    passed      -- `Length(Copy(FOrders))`             (passed as an argument)
    returned    -- `Result := FOrders` in a function   (returned)
    published   -- the field sits in a `published` section (named at the field line)
    crossunit   -- protected field, read by a descendant in Vip.pas (named at the Vip.pas line)
  POSITIVE CONTROL: every refused case differs from `demo` by one edit, and `demo` must be accepted
  -- so a rule that refuses everything fails the accepted cases, and one that accepts everything
  fails the refused ones.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-f5field-$PID"
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
  if ($Extra) { foreach ($k in $Extra.Keys) { Set-Text (Join-Path $root $k) $Extra[$k]; $units += [IO.Path]::GetFileNameWithoutExtension($k) } }
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

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Test-Accepted 'demo' $null
  Test-Accepted 'memberread' {
    param($t)
    $t = Replace-Once $t "    function OrderCount: Integer;`r`n" "    function OrderCount: Integer;`r`n    function FirstId: Integer;`r`n"
    return $t -replace 'end\.\s*$', "function TCustomer.FirstId: Integer;`r`nbegin`r`n  Result := FOrders[0].Id;`r`nend;`r`n`r`nend.`r`n"
  }
  Test-Refused 'bare' { param($t) Replace-Once $t '  Result := Length(FOrders);' "  var LAll := FOrders; {BAD}`r`n  Result := Length(LAll);" } $null 'Customers.pas' ''
  Test-Refused 'elemvalue' { param($t) Replace-Once $t '  Result := Length(FOrders);' "  var LFirst := FOrders[0]; {BAD}`r`n  Result := Length(FOrders) + Ord(LFirst = nil);" } $null 'Customers.pas' ''
  Test-Refused 'passed' { param($t) Replace-Once $t '  Result := Length(FOrders);' '  Result := Length(Copy(FOrders)); {BAD}' } $null 'Customers.pas' ''
  Test-Refused 'returned' {
    param($t)
    $t = Replace-Once $t "    function OrderCount: Integer;`r`n" "    function OrderCount: Integer;`r`n    function AllOrders: TArray<TOrder>;`r`n"
    return $t -replace 'end\.\s*$', "function TCustomer.AllOrders: TArray<TOrder>;`r`nbegin`r`n  Result := FOrders; {BAD}`r`nend;`r`n`r`nend.`r`n"
  } $null 'Customers.pas' ''
  Test-Refused 'published' {
    param($t)
    $t = Replace-Once $t "  private`r`n    FName  : string;`r`n" "  private`r`n    FName  : string;`r`n  published`r`n"
    return Replace-Once $t '    FOrders: TArray<TOrder>;' '    FOrders: TArray<TOrder>; {BAD}'
  } $null 'Customers.pas' 'published'
  $vip = "unit Vip;`r`n`r`ninterface`r`n`r`nuses`r`n  Customers;`r`n`r`ntype`r`n  TVipCustomer = class(TCustomer)`r`n" +
    "  public`r`n    function Doubled: Integer;`r`n  end;`r`n`r`nimplementation`r`n`r`nfunction TVipCustomer.Doubled: Integer;`r`n" +
    "begin`r`n  Result := 2 * Length(FOrders); {BAD}`r`nend;`r`n`r`nend.`r`n"
  Test-Refused 'crossunit' { param($t) Replace-Once $t "  private`r`n    FName  : string;`r`n" "  private`r`n    FName  : string;`r`n  protected`r`n" } @{ 'Vip.pas' = $vip } 'Vip.pas' 'outside'
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
