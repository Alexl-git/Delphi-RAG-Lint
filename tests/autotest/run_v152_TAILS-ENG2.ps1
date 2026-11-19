<#
  run_v152_TAILS-ENG2.ps1 -- lane v152 TAILS-ENG2: three engine tails of 1.52.

  G  resolver: `var B:= M[K]` through the project's OWN class default indexer types B as the
     indexed property's type -- for a generic class, with the class's type arguments put in
     for its parameters -- so `B.Side` binds to TBranch.Side
       G1  M a parameter typed TMyMap<string, TBranch> (property Items[K]: V; default)
       G2  Mp an untyped inline var := TMyMap<string, TBranch>.Create
       G3  L a parameter typed TBranchList (non-generic, property B[I]: TBranch; default)
       G4  positive control: `var W: TBranch:= M['v']` (written type) binds
       G5  negative control: TMyMap<TBranch, string>[K] is a string -- `.Side` stays unbound
       G6  negative control: TKeyMap<K, V> whose default property answers K -- with
           TKeyMap<string, TBranch> that is a string -- `.Side` stays unbound
  P  member-could-be-private: a public member referenced from another unit ONLY inside an
     inactive {$IFDEF} block (the index skips that branch) is treated as used -> silent
       P1  TMsgTool.MsgToString (other unit calls it under {$IFDEF TRACE_CODESITE}) silent
       P2  positive control: TMsgTool.OnlyHere (no other unit names it) fires
       P3  positive control: TMsgTool.InComment (named in another unit only in a comment
           OUTSIDE any conditional block) still fires
  S  shared scope: an UNINDEXED .groupproj peer that reaches a unit only through its search
     path (DCC_UnitSearchPath, not listed in .dproj / .dpr) makes the verdict undecidable
       S1  App2 unindexed, UShared NOT listed, ..\App1 on App2's DCC_UnitSearchPath ->
           UsedOnlyByApp2 withheld (unused-global)
       S2  stderr names App2 and says it has no index
       S3  positive control: the same App2 WITHOUT the search path -> UsedOnlyByApp2 fires

  pwsh -File tests\autotest\run_v152_TAILS-ENG2.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
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

$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v152-tailseng2-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
try {
  # ---------------- G: own class default indexer ----------------
  $G = Join-Path $Work 'g'
  [IO.Directory]::CreateDirectory($G) | Out-Null
  $Own = @'
unit uOwn;

interface

type
  TBranch = class
  public
    Side: string;
  end;

  TMyMap<K, V> = class
  private
    function GetItem(const AKey: K): V;
  public
    property Items[const AKey: K]: V read GetItem; default;
  end;

  TKeyMap<K, V> = class
  private
    function GetKey(const AValue: V): K;
  public
    property Keys[const AValue: V]: K read GetKey; default;
  end;

  TBranchList = class
  private
    function GetB(AIndex: Integer): TBranch;
  public
    property B[AIndex: Integer]: TBranch read GetB; default;
  end;

procedure Go(const M: TMyMap<string, TBranch>; const L: TBranchList; const R: TMyMap<TBranch, string>;
  const Km: TKeyMap<string, TBranch>);

implementation

function TMyMap<K, V>.GetItem(const AKey: K): V;
begin
  Result:= Default(V);
end;

function TKeyMap<K, V>.GetKey(const AValue: V): K;
begin
  Result:= Default(K);
end;

function TBranchList.GetB(AIndex: Integer): TBranch;
begin
  Result:= nil;
end;

procedure Go(const M: TMyMap<string, TBranch>; const L: TBranchList; const R: TMyMap<TBranch, string>;
  const Km: TKeyMap<string, TBranch>);
begin
  var B:= M['x'];
  B.Side:= 'g1';
  var Mp:= TMyMap<string, TBranch>.Create;
  var D:= Mp['z'];
  D.Side:= 'g2';
  var C:= L[0];
  C.Side:= 'g3';
  var W: TBranch:= M['v'];
  W.Side:= 'g4';
  var K:= R[nil];
  K.Side:= 'g5';
  var Q:= Km[nil];
  Q.Side:= 'g6';
end;

end.
'@
  [IO.File]::WriteAllText((Join-Path $G 'uOwn.pas'), (Crlf $Own))
  $GDb = Join-Path $Work 'g.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $Exe index $G --db $GDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
  $q = "SELECT r.receiver_text AS rcv, s.qualified_name AS target FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id WHERE r.name_text = 'Side' AND r.receiver_text IS NOT NULL AND r.receiver_text <> ''"
  $rawG = (& { $ErrorActionPreference = 'Continue'; & $Exe sql --db $GDb --query $q --json 2>$null }) -join "`n"
  $bound = @{}
  try {
    $j = $rawG | ConvertFrom-Json
    $ci = @($j.columns | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.name } })
    foreach ($row in @($j.rows)) {
      $rcv = '' + $row[[array]::IndexOf($ci, 'rcv')]; $tg = '' + $row[[array]::IndexOf($ci, 'target')]
      if ($tg -ne '') { $bound[$rcv] = $tg } elseif (-not $bound.ContainsKey($rcv)) { $bound[$rcv] = '' }
    }
  } catch { Write-Host ('  unparsed sql: ' + $rawG.Substring(0, [Math]::Min(200, $rawG.Length))) }
  Check 'G0 sanity: six Side receivers read back' ($bound.Count -eq 6) ("got=" + (($bound.Keys | Sort-Object) -join ','))
  $is = { param($rcv) ('' + $bound[$rcv]) -eq 'uOwn.TBranch.Side' }
  Check 'G1 var B:= M[K] (TMyMap<string, TBranch> parameter) -> B.Side binds' (& $is 'B') ("got='$($bound['B'])'")
  Check 'G2 var D:= Mp[K] (Mp an inline TMyMap<string, TBranch>) -> D.Side binds' (& $is 'D') ("got='$($bound['D'])'")
  Check 'G3 var C:= L[0] (TBranchList, non-generic own default) -> C.Side binds' (& $is 'C') ("got='$($bound['C'])'")
  Check 'G4 control: written type var W: TBranch:= M[K] binds' (& $is 'W') ("got='$($bound['W'])'")
  Check 'G5 negative: TMyMap<TBranch, string>[K] is a string -- K.Side unbound' (-not (& $is 'K')) ("got='$($bound['K'])'")
  Check 'G6 negative: TKeyMap<string, TBranch> default answers K = string -- Q.Side unbound' (-not (& $is 'Q')) ("got='$($bound['Q'])'")

  # ---------------- P: member-could-be-private, inactive {$IFDEF} caller ----------------
  $P = Join-Path $Work 'p'
  [IO.Directory]::CreateDirectory($P) | Out-Null
  $UMsg = @'
unit UMsg;

interface

type
  TMsgTool = class
  public
    class function MsgToString(AMsg: Integer): string;
    class function OnlyHere(AMsg: Integer): string;
    class function InComment(AMsg: Integer): string;
  end;

procedure RunMsg;

implementation

class function TMsgTool.MsgToString(AMsg: Integer): string;
begin
  Result:= IntToStr(AMsg);
end;

class function TMsgTool.OnlyHere(AMsg: Integer): string;
begin
  Result:= MsgToString(AMsg);
end;

class function TMsgTool.InComment(AMsg: Integer): string;
begin
  Result:= OnlyHere(AMsg);
end;

procedure RunMsg;
begin
  TMsgTool.InComment(1);
end;

end.
'@
  $UCaller = @'
unit UCaller;

interface

procedure RunCaller;

implementation

uses
  UMsg;

{ InComment is only named in this comment, outside any conditional block. }

procedure RunCaller;
begin
  RunMsg;
{$IFDEF TRACE_CODESITE}
  Writeln(TMsgTool.MsgToString(42));
{$ENDIF}
end;

end.
'@
  $PDpr = @'
program PApp;

uses
  UMsg in 'UMsg.pas',
  UCaller in 'UCaller.pas';

begin
  RunCaller;
end.
'@
  $PDproj = @'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>PApp.dpr</MainSource><Config Condition="'$(Config)'==''">Debug</Config><Base>true</Base></PropertyGroup>
  <ItemGroup>
    <DelphiCompile Include="PApp.dpr"><MainSource>MainSource</MainSource></DelphiCompile>
    <DCCReference Include="UMsg.pas"/>
    <DCCReference Include="UCaller.pas"/>
  </ItemGroup>
</Project>
'@
  [IO.File]::WriteAllText((Join-Path $P 'UMsg.pas'), (Crlf $UMsg))
  [IO.File]::WriteAllText((Join-Path $P 'UCaller.pas'), (Crlf $UCaller))
  [IO.File]::WriteAllText((Join-Path $P 'PApp.dpr'), (Crlf $PDpr))
  [IO.File]::WriteAllText((Join-Path $P 'PApp.dproj'), (Crlf $PDproj))
  $PProj = Join-Path $P 'PApp.dproj'
  $PDb = Join-Path $P '_D-RAG\PApp.sqlite'
  [IO.Directory]::CreateDirectory((Split-Path $PDb)) | Out-Null
  $o = (& { $ErrorActionPreference = 'Continue'; & $Exe index --project $PProj --db $PDb 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  if ($LASTEXITCODE -ne 0) { Write-Host $o; throw 'index PApp failed' }
  $rawP = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $PDb --project $PProj --json --no-stand-down --rule member-could-be-private 2>$null }) -join "`n"
  $pf = @(); try { $pf = @($rawP | ConvertFrom-Json) } catch { Write-Host ('  unparsed: ' + $rawP.Substring(0, [Math]::Min(200, $rawP.Length))) }
  $mp = { param($w) @($pf | Where-Object { $_.rule -eq 'member-could-be-private' -and ('' + $_.message) -match "\.$w\b" }).Count }
  Check 'P1 MsgToString called only under an inactive {$IFDEF} in UCaller -> silent' ((& $mp 'MsgToString') -eq 0) ("hits=$(& $mp 'MsgToString')")
  Check 'P2 control: OnlyHere (own unit only) fires' ((& $mp 'OnlyHere') -eq 1) ("hits=$(& $mp 'OnlyHere')")
  Check 'P3 control: InComment (other unit names it only in a plain comment) fires' ((& $mp 'InComment') -eq 1) ("hits=$(& $mp 'InComment')")

  # ---------------- S: unindexed peer reaching a unit via its search path ----------------
  $X = Join-Path $Work 'x'
  [IO.Directory]::CreateDirectory($X) | Out-Null
  Copy-Item -Path (Join-Path $PSScriptRoot '..\lint\xproj\*') -Destination $X -Recurse
  $P1 = Join-Path $X 'App1\App1.dproj'
  $Real1 = Join-Path $X 'App1\_D-RAG\App1.sqlite'
  [IO.Directory]::CreateDirectory((Split-Path $Real1)) | Out-Null
  $o = (& { $ErrorActionPreference = 'Continue'; & $Exe index --project $P1 --db $Real1 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  if ($LASTEXITCODE -ne 0) { Write-Host $o; throw 'index App1 failed' }
  # App2 stays unindexed; it no longer LISTS UShared (dproj + dpr), it reaches it via its search path.
  $d2 = Join-Path $X 'App2\App2.dproj'; $p2 = Join-Path $X 'App2\App2.dpr'
  $sd = [IO.File]::ReadAllText($d2) -replace '(?m)^\s*<DCCReference Include="\.\.\\App1\\UShared\.pas"/>\r?\n', ''
  $sp = [IO.File]::ReadAllText($p2) -replace "UShared in '\.\.\\App1\\UShared\.pas',", 'UShared,'
  $withPath = $sd -replace '<Base>true</Base></PropertyGroup>', '<Base>true</Base></PropertyGroup><PropertyGroup><DCC_UnitSearchPath>..\App1;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>'
  [IO.File]::WriteAllText($d2, $withPath); [IO.File]::WriteAllText($p2, $sp)
  function LintS {
    $errFile = Join-Path $Work ('err-' + [guid]::NewGuid().ToString('N') + '.txt')
    $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $Real1 --project $P1 --json --no-stand-down --rule unused-global 2>$errFile }) -join "`n"
    $arr = @(); try { $arr = @($raw | ConvertFrom-Json) } catch { Write-Host ('  unparsed: ' + $raw.Substring(0, [Math]::Min(200, $raw.Length))) }
    $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
    return [pscustomobject]@{ F = $arr; Err = $err }
  }
  $ug = { param($f) @($f | Where-Object { $_.rule -eq 'unused-global' -and ('' + $_.message) -match '\bUsedOnlyByApp2\b' }).Count }
  $peerLine = { param($e) @(($e -split "`r?`n") | Where-Object { $_ -match 'App2' -and $_ -match 'no index' }) }
  $s1 = LintS
  Check 'S1 App2 reaches UShared via DCC_UnitSearchPath only -> UsedOnlyByApp2 withheld' ((& $ug $s1.F) -eq 0) ("hits=$(& $ug $s1.F)")
  Check 'S2 stderr names the unindexed peer App2' ((& $peerLine $s1.Err).Count -eq 1) ("lines=$((& $peerLine $s1.Err).Count)")
  [IO.File]::WriteAllText($d2, $sd)
  $s3 = LintS
  Check 'S3 control: no search path to App1 -> UsedOnlyByApp2 fires, no peer line' ((& $ug $s3.F) -eq 1 -and (& $peerLine $s3.Err).Count -eq 0) ("hits=$(& $ug $s3.F) lines=$((& $peerLine $s3.Err).Count)")
} finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
Write-Host ("RESULT: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
