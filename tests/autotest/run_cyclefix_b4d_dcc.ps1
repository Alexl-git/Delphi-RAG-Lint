<#
  run_cyclefix_b4d_dcc.ps1 -- plan 2026-10-25 B4-d (owner-delegated 2026-10-26): the F5 base-class plan for an
  INHERITING class (run_cyclefix_b4d.ps1), followed, COMPILES and the program behaves exactly as before.
  Needs RAD Studio (msbuild via rsvars). The run_cyclefix_b4_dcc.ps1 pattern.

  Trees (docs\examples\circular-uses-demo + Base.pas, Customers.pas with the B4-b plain field):
  'inherits' (TOrder = class(TEntity), TEntity in Base.pas, the program prints O.Tag set by TOrder.Create),
  'inheritsiface' (TOrder = class(TEntity, IDescribable); the program calls (O as IDescribable).Describe),
  'inheritslib' (TOrder = class(TPersistent), ancestry from the platform library copy; SKIPPED without one).
  Each: the untouched copy builds and its stdout is kept; `cycles --plan` on a second copy, follow-cycle-plan
  applies cycle 1, the leaf declares `TOrderBase = class(<ancestor>)`, the cycle is gone after a re-index,
  the followed copy builds and its stdout is byte-identical.

  POSITIVE CONTROL: the followed 'inherits' tree with the leaf's `TOrderBase = class(TEntity)` put back to
  `TOrderBase = class` must NOT compile (TOrder.Create sets FTag, the program reads O.Tag) -- so the build
  check can fail.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-b4d-dcc-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
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

function Edit-Text([string]$Text, [string]$Old, [string]$New) {
  $Old = $Old -replace "`r?`n", "`r`n"; $New = $New -replace "`r?`n", "`r`n"
  if (-not $Text.Contains($Old)) { throw "fixture edit: text not found: $Old" }
  return $Text.Replace($Old, $New)
}

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

# The program: pTail = extra Writeln lines on the order O.
function Get-Dpr([string]$Units, [string]$Tail) {
  return @"
program F5Demo;

{`$APPTYPE CONSOLE}

uses
$Units

var
  C: TCustomer;
  O: TOrder;
begin
  C := TCustomer.Create('Ada');
  O := TOrder.Create(7, C);
  C.AddOrder(O);
  C.AddOrder(TOrder.Create(8, C));
  Writeln(C.Name, ' has ', C.OrderCount, ' orders');
  Writeln(O.Describe);
$Tail
end.
"@
}

# A demo copy in pDir: pUnits (names), pEdits = @{ 'File.pas' = scriptblock text->text }, pExtra = @{ 'File.pas' = text }.
function New-Tree([string]$Dir, [string[]]$Units, [hashtable]$Edits, [hashtable]$Extra, [string]$Tail) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Get-ChildItem $Demo -Filter *.pas | ForEach-Object { Copy-Item $_.FullName (Join-Path $Dir $_.Name) -Force }
  foreach ($k in $Extra.Keys) { Set-Text (Join-Path $Dir $k) $Extra[$k] }
  foreach ($k in $Edits.Keys) { $p = Join-Path $Dir $k; Set-Text $p (& $Edits[$k] ([IO.File]::ReadAllText($p))) }
  $uses = ($Units | ForEach-Object { "  $_ in '$_.pas'" }) -join ",`r`n"
  Set-Text (Join-Path $Dir 'F5Demo.dpr') (Get-Dpr ($uses + ';') $Tail)
  $pj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'F5Demo').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{7C3E9FB6-4D8F-4125-AEBC-9F5D3F2B4CA7}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $refs = ($Units | ForEach-Object { "        <DCCReference Include=`"$_.pas`"/>" }) -join "`r`n"
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n$refs")
  Set-Text (Join-Path $Dir 'F5Demo.dproj') $pj
}

function Invoke-Build([string]$Dproj) {
  $dir = Split-Path $Dproj
  $bat = Join-Path $WorkDir ('build-' + (Split-Path $dir -Leaf) + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $dir),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}

function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) 'Win64\Debug\F5Demo.exe'
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}

function Invoke-Cycles([string]$Dproj, [string]$Tag, [string[]]$Extra, [string]$Lib) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList (@('cycles', '--db', ('"' + $db + '"'), '--library-db', ('"' + $Lib + '"')) + $Extra) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o; Text = [IO.File]::ReadAllText($o) }
}

function Test-Tree([string]$Tag, [string[]]$Units, [hashtable]$Edits, [hashtable]$Extra, [string]$Tail, [string]$Ancestor, [string]$Lib) {
  Write-Host "== $Tag" -ForegroundColor Cyan
  $base = Join-Path $WorkDir "$Tag-base"; $work = Join-Path $WorkDir "$Tag-edit"
  New-Tree $base $Units $Edits $Extra $Tail; New-Tree $work $Units $Edits $Extra $Tail
  $b0 = Invoke-Build (Join-Path $base 'F5Demo.dproj')
  Check "$Tag 0 the untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'F5Demo.dproj')
  $plan = Invoke-Cycles (Join-Path $work 'F5Demo.dproj') "$Tag-plan" @('--plan') $Lib
  Check "$Tag 1 planned (exit 0), no refusal" (($plan.Exit -eq 0) -and ($plan.Text -notmatch 'refused: ')) "exit=$($plan.Exit)"
  Check "$Tag 1b the leaf declares TOrderBase = class($Ancestor)" ($plan.Text.Contains("TOrderBase = class($Ancestor)")) ''
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle 1 -Root $work 2>&1 | Out-String
  Check "$Tag 2 the follower applies cycle 1 (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $cu = [IO.File]::ReadAllText((Join-Path $work 'Customers.pas'))
  Check "$Tag 3 Customers.pas no longer names TOrder as a type" ($cu -notmatch ':\s*TOrder\b') ''
  $after = Invoke-Cycles (Join-Path $work 'F5Demo.dproj') "$Tag-after" @() $Lib
  Check "$Tag 4 the cycle is gone after a re-index" ($after.Text -notmatch 'customers <-> orders|orders <-> customers') ($after.Text.Trim() -replace "`r?`n", ' | ')
  $b1 = Invoke-Build (Join-Path $work 'F5Demo.dproj')
  Check "$Tag 5 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $work 'F5Demo.dproj')
  Check "$Tag 6 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  return $work
}

# Customers.pas: the B4-b plain field (FLast := AOrder; Assigned(FLast); FLast.Id)
$addField = {
  param($t)
  $t = Edit-Text $t "    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n" `
    "    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n    FLast  : TOrder;`r`n"
  $t = Edit-Text $t "  FOrders[High(FOrders)] := AOrder;`r`n" "  FOrders[High(FOrders)] := AOrder;`r`n  FLast := AOrder;`r`n"
  return Edit-Text $t "  Result := Length(FOrders);`r`n" "  Result := Length(FOrders);`r`n  if Assigned(FLast) then Result := Result + FLast.Id - FLast.Id;`r`n"
}
$inherits = {
  param($t)
  $t = Edit-Text $t "interface`r`n`r`ntype" "interface`r`n`r`nuses`r`n  Base;`r`n`r`ntype"
  $t = Edit-Text $t "  TOrder = class`r`n" "  TOrder = class(TEntity)`r`n"
  return Edit-Text $t "  FId          := AId;`r`n" "  FId          := AId;`r`n  FTag         := 'order';`r`n"
}
$inheritsIface = {
  param($t)
  return Edit-Text (& $inherits $t) "  TOrder = class(TEntity)`r`n" "  TOrder = class(TEntity, IDescribable)`r`n"
}
$inheritsLib = {
  param($t)
  $t = Edit-Text $t "interface`r`n`r`ntype" "interface`r`n`r`nuses`r`n  System.Classes;`r`n`r`ntype"
  return Edit-Text $t "  TOrder = class`r`n" "  TOrder = class(TPersistent)`r`n"
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $units3 = @('Base', 'Customers', 'Orders')
  $extra = @{ 'Base.pas' = $BaseUnit }
  $treeInh = Test-Tree 'inherits' $units3 @{ 'Customers.pas' = $addField; 'Orders.pas' = $inherits } $extra "  Writeln('tag ', O.Tag);" 'TEntity' 'none'
  $null = Test-Tree 'inheritsiface' $units3 @{ 'Customers.pas' = $addField; 'Orders.pas' = $inheritsIface } $extra "  Writeln('tag ', O.Tag);`r`n  Writeln('via interface: ', (O as IDescribable).Describe);" 'TEntity' 'none'
  if (Test-Path $LibraryDb) {
    $Lib = Join-Path $WorkDir 'library-copy.sqlite'
    Copy-Item $LibraryDb $Lib
    Check 's0 the platform library was copied into the scratch dir' ((Get-Item $Lib).Length -eq (Get-Item $LibraryDb).Length) $Lib
    $null = Test-Tree 'inheritslib' @('Customers', 'Orders') @{ 'Customers.pas' = $addField; 'Orders.pas' = $inheritsLib } @{} "  Writeln('class ', O.ClassName);" 'TPersistent' $Lib
  } else { Write-Host "  SKIP inheritslib: no platform library DB at $LibraryDb" -ForegroundColor Yellow }

  Write-Host '== positive control: the followed inherits tree with the leaf ancestor removed' -ForegroundColor Cyan
  $leaf = Get-ChildItem $treeInh -Filter '*.pas' | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains('TOrderBase = class(TEntity)') } | Select-Object -First 1
  Check 'pc0 a leaf declaring TOrderBase = class(TEntity) exists' ($null -ne $leaf) ''
  if ($leaf) {
    $t = [IO.File]::ReadAllText($leaf.FullName)
    Set-Text $leaf.FullName ($t.Replace('TOrderBase = class(TEntity)', 'TOrderBase = class'))
    $bc = Invoke-Build (Join-Path $treeInh 'F5Demo.dproj')
    Check 'pc1 it does NOT compile (the build check has teeth)' (-not $bc.Ok) $bc.Errors
  }
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
