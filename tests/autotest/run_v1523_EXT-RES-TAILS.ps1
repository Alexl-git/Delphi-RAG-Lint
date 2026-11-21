<#
  run_v1523_EXT-RES-TAILS.ps1 -- lane v1523 EXT-RES-TAILS: the two tails 1.52 TAILS-ENG2 left open.

  A  resolver: `var X:= L[K]` where L's type declares NO default indexed property itself but an
     ANCESTOR does -- a library TList<T> / TObjectList<T> or the project's own (generic) base --
     types X as the element, the descendant's type arguments put in, so `X.Side` binds
       A1  TBranchObjs = class(TObjectList<TBranch>)            (non-generic, library ancestor)
       A2  TOwn<T: class> = class(TObjectList<T>), O: TOwn<TBranch>   (generic pass-through)
       A3  TDerived<T> = class(TBase<T>), TBase<V> declares Items[I]: V default (own generic base)
       A4  TSub = class(TBranchList), TBranchList declares B[I]: TBranch default (own, 2 levels)
       A5  negative: TSwap<A, B> = class(TBase<B>) with TSwap<TBranch, string> -> string, unbound
       A6  negative: TNames = class(TList<string>) -> string, unbound
  S  shared scope: an UNINDEXED .groupproj peer that reaches a unit through a search-path entry
     written as a $(MACRO), or through the IDE library Search Path, makes the verdict undecidable
       S1  App2 DCC_UnitSearchPath `$(DLPEERSHARED)`, the macro an IDE Environment Variable naming
           ..\App1 -> UsedOnlyByApp2 withheld (unused-global)
       S2  stderr names App2 and says it has no index
       S3  the same $(DLPEERSHARED) defined in the process environment only -> withheld
           (a unit on the IDE LIBRARY path needs no peer rule: lint-all treats it as library)
       S4  control: the macro undefined and no library path -> UsedOnlyByApp2 fires

  pwsh -File tests\autotest\run_v1523_EXT-RES-TAILS.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Pass = 0; $script:Fail = 0
function Check([string]$n, [bool]$ok, [string]$d = '') {
  if ($ok) { $script:Pass++; Write-Host "[PASS] $n" -ForegroundColor Green }
  else     { $script:Fail++; Write-Host "[FAIL] $n  $d" -ForegroundColor Red }
}
function Crlf([string]$s) { return ($s -replace "`r?`n", "`r`n") }

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v1523-extres-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
$SavedFixture = $env:DRAGLINT_TEST_BDS_REGISTRY
try {
  # ---------------- A: default indexer declared on an ancestor ----------------
  $G = Join-Path $Work 'a'
  [IO.Directory]::CreateDirectory($G) | Out-Null
  $Own = @'
unit uAnc;

interface

uses
  System.Generics.Collections;

type
  TBranch = class
  public
    Side: string;
  end;

  TBase<V> = class
  private
    function GetItem(AIndex: Integer): V;
  public
    property Items[AIndex: Integer]: V read GetItem; default;
  end;

  TDerived<T> = class(TBase<T>)
  end;

  TSwap<A, B> = class(TBase<B>)
  end;

  TBranchList = class
  private
    function GetB(AIndex: Integer): TBranch;
  public
    property B[AIndex: Integer]: TBranch read GetB; default;
  end;

  TMid = class(TBranchList)
  end;

  TSub = class(TMid)
  end;

  TBranchObjs = class(TObjectList<TBranch>)
  end;

  TOwn<T: class> = class(TObjectList<T>)
  end;

  TNames = class(TList<string>)
  end;

procedure Go(const L: TBranchObjs; const O: TOwn<TBranch>; const Dv: TDerived<TBranch>; const Sb: TSub;
  const Sw: TSwap<TBranch, string>; const Nm: TNames);

implementation

function TBase<V>.GetItem(AIndex: Integer): V;
begin
  Result:= Default(V);
end;

function TBranchList.GetB(AIndex: Integer): TBranch;
begin
  Result:= nil;
end;

procedure Go(const L: TBranchObjs; const O: TOwn<TBranch>; const Dv: TDerived<TBranch>; const Sb: TSub;
  const Sw: TSwap<TBranch, string>; const Nm: TNames);
begin
  var X:= L[0];
  X.Side:= 'a1';
  var Y:= O[0];
  Y.Side:= 'a2';
  var Z:= Dv[0];
  Z.Side:= 'a3';
  var U:= Sb[0];
  U.Side:= 'a4';
  var K:= Sw[0];
  K.Side:= 'a5';
  var N:= Nm[0];
  N.Side:= 'a6';
end;

end.
'@
  [IO.File]::WriteAllText((Join-Path $G 'uAnc.pas'), (Crlf $Own))
  $GDb = Join-Path $Work 'a.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $G --db $GDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $q = "SELECT r.receiver_text AS rcv, s.qualified_name AS target FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id WHERE r.name_text = 'Side' AND r.receiver_text IS NOT NULL AND r.receiver_text <> ''"
  $rawG = (& { $ErrorActionPreference = 'Continue'; & $Exe sql --db $GDb --query $q --json 2>$null }) -join "`n"
  $bound = @{}
  try {
    $j = $rawG | ConvertFrom-Json | ForEach-Object { $_ }
    $ci = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
    foreach ($row in @($j.rows)) {
      $rcv = '' + $row[[array]::IndexOf($ci, 'rcv')]; $tg = '' + $row[[array]::IndexOf($ci, 'target')]
      if ($tg -ne '') { $bound[$rcv] = $tg } elseif (-not $bound.ContainsKey($rcv)) { $bound[$rcv] = '' }
    }
  } catch { Write-Host ('  unparsed sql: ' + $rawG.Substring(0, [Math]::Min(200, $rawG.Length))) }
  Check 'A0 sanity: six Side receivers read back' ($bound.Count -eq 6) ("got=" + (($bound.Keys | Sort-Object) -join ','))
  $is = { param($rcv) ('' + $bound[$rcv]) -eq 'uAnc.TBranch.Side' }
  Check 'A1 TBranchObjs = class(TObjectList<TBranch>): var X:= L[0] -> X.Side binds' (& $is 'X') ("got='$($bound['X'])'")
  Check 'A2 TOwn<T> = class(TObjectList<T>), TOwn<TBranch>: var Y:= O[0] -> Y.Side binds' (& $is 'Y') ("got='$($bound['Y'])'")
  Check 'A3 TDerived<T> = class(TBase<T>) (own generic base default): Z.Side binds' (& $is 'Z') ("got='$($bound['Z'])'")
  Check 'A4 TSub -> TMid -> TBranchList (own default two levels up): U.Side binds' (& $is 'U') ("got='$($bound['U'])'")
  Check 'A5 negative: TSwap<TBranch, string> = class(TBase<B>) answers string -- K.Side unbound' (-not (& $is 'K')) ("got='$($bound['K'])'")
  Check 'A6 negative: TNames = class(TList<string>) answers string -- N.Side unbound' (-not (& $is 'N')) ("got='$($bound['N'])'")

  # ---------------- S: unindexed peer reaching a unit via a macro / library search path ----------------
  $X = Join-Path $Work 'x'
  [IO.Directory]::CreateDirectory($X) | Out-Null
  Copy-Item -Path (Join-Path $PSScriptRoot '..\lint\xproj\*') -Destination $X -Recurse
  $P1 = Join-Path $X 'App1\App1.dproj'
  $Real1 = Join-Path $X 'App1\_D-RAG\App1.sqlite'
  [IO.Directory]::CreateDirectory((Split-Path $Real1)) | Out-Null
  $o = (& { $ErrorActionPreference = 'Continue'; & $Exe index --project $P1 --db $Real1 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  if ($LASTEXITCODE -ne 0) { Write-Host $o; throw 'index App1 failed' }
  # App2 stays unindexed; it no longer LISTS UShared (dproj + dpr).
  $d2 = Join-Path $X 'App2\App2.dproj'; $p2 = Join-Path $X 'App2\App2.dpr'
  $sd = [IO.File]::ReadAllText($d2) -replace '(?m)^\s*<DCCReference Include="\.\.\\App1\\UShared\.pas"/>\r?\n', ''
  $sp = [IO.File]::ReadAllText($p2) -replace "UShared in '\.\.\\App1\\UShared\.pas',", 'UShared,'
  $withMacro = $sd -replace '<Base>true</Base></PropertyGroup>', '<Base>true</Base></PropertyGroup><PropertyGroup><DCC_UnitSearchPath>$(DLPEERSHARED);$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>'
  [IO.File]::WriteAllText($p2, $sp)
  $App1Dir = Join-Path $X 'App1'
  $Fixture = Join-Path $Work 'bds.json'
  function Set-Bds([hashtable]$EnvVars, [string]$SearchPath) {
    $studio = [ordered]@{ RootDir = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'; 'Environment Variables' = $EnvVars;
      Library = [ordered]@{ Win32 = [ordered]@{ 'Search Path' = $SearchPath }; Win64 = [ordered]@{ 'Search Path' = '' } } }
    [IO.File]::WriteAllText($Fixture, (@{ '37.0' = $studio } | ConvertTo-Json -Depth 6))
    $env:DRAGLINT_TEST_BDS_REGISTRY = $Fixture
  }
  function LintS {
    $errFile = Join-Path $Work ('err-' + [guid]::NewGuid().ToString('N') + '.txt')
    $raw = (& { $ErrorActionPreference = 'Continue'; $dlErrFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($errFile); [IO.File]::WriteAllText($dlErrFile, ''); & $Exe lint-all --db $Real1 --project $P1 --json --no-stand-down --rule unused-global 2>&1 | ForEach-Object { if ($_ -is [Management.Automation.ErrorRecord]) { [IO.File]::AppendAllText($dlErrFile, "$_" + [Environment]::NewLine) } else { $_ } } }) -join "`n"
    $arr = @(); try { $arr = @(($raw | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { Write-Host ('  unparsed: ' + $raw.Substring(0, [Math]::Min(200, $raw.Length))) }
    $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
    return [pscustomobject]@{ F = $arr; Err = $err }
  }
  $ug = { param($f) @($f | Where-Object { $_.rule -eq 'unused-global' -and ('' + $_.message) -match '\bUsedOnlyByApp2\b' }).Count }
  $peerLine = { param($e) @(($e -split "`r?`n") | Where-Object { $_ -match 'App2' -and $_ -match 'no index' }) }
  [IO.File]::WriteAllText($d2, $withMacro)
  Set-Bds @{ DLPEERSHARED = $App1Dir } ''
  $s1 = LintS
  Check 'S1 App2 reaches UShared via $(DLPEERSHARED) on DCC_UnitSearchPath -> UsedOnlyByApp2 withheld' ((& $ug $s1.F) -eq 0) ("hits=$(& $ug $s1.F)")
  Check 'S2 stderr names the unindexed peer App2' ((& $peerLine $s1.Err).Count -eq 1) ("lines=$((& $peerLine $s1.Err).Count)")
  Set-Bds @{} ''
  $env:DLPEERSHARED = $App1Dir
  $s3 = LintS
  $env:DLPEERSHARED = $null
  Check 'S3 $(DLPEERSHARED) from the process environment -> UsedOnlyByApp2 withheld' ((& $ug $s3.F) -eq 0) ("hits=$(& $ug $s3.F) total=$($s3.F.Count)")
  $s4 = LintS
  Check 'S4 control: $(DLPEERSHARED) undefined, no library path -> UsedOnlyByApp2 fires, no peer line' ((& $ug $s4.F) -eq 1 -and (& $peerLine $s4.Err).Count -eq 0) ("hits=$(& $ug $s4.F) lines=$((& $peerLine $s4.Err).Count)")
} finally {
  $env:DRAGLINT_TEST_BDS_REGISTRY = $SavedFixture
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
Write-Host ("RESULT: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
