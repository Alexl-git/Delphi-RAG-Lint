<#
  run_cyclefix_b4_dcc.ps1 -- plan 2026-10-25 B4-a / B4-b: the F5 base-class plan for a LOCAL or a PLAIN
  FIELD of the class type (run_cyclefix_b4.ps1), followed, COMPILES and the program behaves exactly as
  before. Needs RAD Studio (msbuild via rsvars). The run_cyclefix_f5_field_dcc.ps1 pattern.

  Trees (docs\examples\circular-uses-demo, Customers.pas edited as run_cyclefix_b4.ps1 does):
  'local' (LLast: TOrder in OrderCount, read from FOrders[High(FOrders)]), 'localfor' (for var O: TOrder
  in FOrders), 'plainfield' (FLast: TOrder, FLast := AOrder, Assigned(FLast), FLast.Id) and
  'plainfieldfree' (the same plus a destructor calling FLast.Free), 'list' (FList: TList<TOrder> -- B4-c), 'accessor' (plainfield with Orders.pas
  reading Id through a method GetId -- B4-e). Each: the untouched copy builds and
  its stdout is kept; `cycles --plan` on a second copy, follow-cycle-plan applies cycle 1, the cycle is
  gone after a re-index, the followed copy builds and its stdout is byte-identical.

  POSITIVE CONTROL: the followed 'plainfield' tree with `FLast  : TOrderBase;` put back to `TOrder` must
  NOT compile (Customers no longer uses Orders) -- so the build check can fail.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-b4-dcc-$PID",
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

$Dpr = @'
program F5Demo;

{$APPTYPE CONSOLE}

uses
  Customers in 'Customers.pas',
  Orders in 'Orders.pas';

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
end.
'@

function New-Tree([string]$Dir, [scriptblock]$Edit, [scriptblock]$OrdersEdit) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  Get-ChildItem $Demo -Filter *.pas | ForEach-Object { Copy-Item $_.FullName (Join-Path $Dir $_.Name) -Force }
  if ($Edit) { $cu = Join-Path $Dir 'Customers.pas'; Set-Text $cu (& $Edit ([IO.File]::ReadAllText($cu))) }
  if ($OrdersEdit) { $ou = Join-Path $Dir 'Orders.pas'; Set-Text $ou (& $OrdersEdit ([IO.File]::ReadAllText($ou))) }
  Set-Text (Join-Path $Dir 'F5Demo.dpr') $Dpr
  $pj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'F5Demo').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{6B2D8FA5-3C7E-4014-9DAB-8F4C2E1A3B96}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n        <DCCReference Include=`"Customers.pas`"/>`r`n        <DCCReference Include=`"Orders.pas`"/>")
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

function Invoke-Cycles([string]$Dproj, [string]$Tag, [string[]]$Extra) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "cycles-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList (@('cycles', '--db', ('"' + $db + '"'), '--library-db', 'none') + $Extra) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "cycles-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o; Text = [IO.File]::ReadAllText($o) }
}

function Test-Tree([string]$Tag, [scriptblock]$Edit, [scriptblock]$OrdersEdit) {
  Write-Host "== $Tag" -ForegroundColor Cyan
  $base = Join-Path $WorkDir "$Tag-base"; $work = Join-Path $WorkDir "$Tag-edit"
  New-Tree $base $Edit $OrdersEdit; New-Tree $work $Edit $OrdersEdit
  $b0 = Invoke-Build (Join-Path $base 'F5Demo.dproj')
  Check "$Tag 0 the untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'F5Demo.dproj')
  $plan = Invoke-Cycles (Join-Path $work 'F5Demo.dproj') "$Tag-plan" @('--plan')
  Check "$Tag 1 planned (exit 0), no base-class refusal" (($plan.Exit -eq 0) -and ($plan.Text -notmatch 'refused: base-class')) "exit=$($plan.Exit)"
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle 1 -Root $work 2>&1 | Out-String
  Check "$Tag 2 the follower applies cycle 1 (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $cu = [IO.File]::ReadAllText((Join-Path $work 'Customers.pas'))
  Check "$Tag 3 Customers.pas no longer names TOrder as a type" ($cu -notmatch ':\s*TOrder\b') ''
  $after = Invoke-Cycles (Join-Path $work 'F5Demo.dproj') "$Tag-after" @()
  Check "$Tag 4 the cycle is gone after a re-index" ($after.Text -notmatch 'customers <-> orders|orders <-> customers') ($after.Text.Trim() -replace "`r?`n", ' | ')
  $b1 = Invoke-Build (Join-Path $work 'F5Demo.dproj')
  Check "$Tag 5 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $work 'F5Demo.dproj')
  Check "$Tag 6 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  return $work
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $addField = {
    param($t)
    $t = $t.Replace("    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n",
      "    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }`r`n    FLast  : TOrder;`r`n")
    $t = $t.Replace("  FOrders[High(FOrders)] := AOrder;`r`n", "  FOrders[High(FOrders)] := AOrder;`r`n  FLast := AOrder;`r`n")
    return $t.Replace("  Result := Length(FOrders);`r`n", "  Result := Length(FOrders);`r`n  if Assigned(FLast) then Result := Result + FLast.Id - FLast.Id;`r`n")
  }
  $null = Test-Tree 'local' {
    param($t)
    return $t.Replace("function TCustomer.OrderCount: Integer;`r`nbegin`r`n  Result := Length(FOrders);`r`nend;", (
      "function TCustomer.OrderCount: Integer;`r`nvar`r`n  LLast: TOrder;`r`nbegin`r`n  Result := Length(FOrders);`r`n" +
      "  if Result > 0 then`r`n  begin`r`n    LLast := FOrders[High(FOrders)];`r`n    if LLast <> nil then Result := Result + LLast.Id - LLast.Id;`r`n  end;`r`nend;"))
  }
  $null = Test-Tree 'localfor' {
    param($t)
    return $t.Replace("  Result := Length(FOrders);`r`n", ("  Result := Length(FOrders);`r`n  for var O: TOrder in FOrders do`r`n" +
      "    if O <> nil then Result := Result + O.Id - O.Id;`r`n"))
  }
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
  $null = Test-Tree 'list' $addList
  $fieldTree = Test-Tree 'plainfield' $addField
  $null = Test-Tree 'plainfieldfree' {
    param($t)
    $t = (& $addField $t).Replace("    function OrderCount: Integer;`r`n", "    function OrderCount: Integer;`r`n    destructor Destroy; override;`r`n")
    return $t -replace 'end\.\s*$', "destructor TCustomer.Destroy;`r`nbegin`r`n  FLast.Free;`r`n  inherited Destroy;`r`nend;`r`n`r`nend.`r`n"
  }

  $null = Test-Tree 'accessor' $addField {
    param($t)
    $t = $t.Replace('    property Id: Integer read FId;', '    property Id: Integer read GetId;').Replace("  public`r`n    constructor Create(", "    function GetId: Integer;`r`n  public`r`n    constructor Create(")
    return $t -replace 'end\.\s*$', "function TOrder.GetId: Integer;`r`nbegin`r`n  Result := FId;`r`nend;`r`n`r`nend.`r`n"
  }

  Write-Host '== positive control: the followed plainfield tree with the field line put back' -ForegroundColor Cyan
  $cuP = Join-Path $fieldTree 'Customers.pas'
  $t = [IO.File]::ReadAllText($cuP)
  $t2 = $t.Replace('FLast  : TOrderBase;', 'FLast  : TOrder;')
  Set-Text $cuP $t2
  Check 'pc0 the field line was changed back' ($t2 -ne $t) ''
  $bc = Invoke-Build (Join-Path $fieldTree 'F5Demo.dproj')
  Check 'pc1 it does NOT compile (the build check has teeth)' (-not $bc.Ok) $bc.Errors
} finally {
  if (-not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
