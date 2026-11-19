<#
  run_v152_BK-TAILS-LSP.ps1 -- 1.52 lane BK-TAILS-LSP: three tails.

  A  (B42) Inc/Dec, var and out arguments of a property whose READ accessor is a field reach
     its SETTER. The index stores `Inc(C.Count)` as a read of Count through FCount, so the
     setter's 'Used in (via property Count):' line and `usages --rw --name SetCount` missed it.
     A0 control: the plain write `C.Count := 5` (Assign) is echoed to SetCount [w].
     A1 Inc(C.Count) (Bump) is echoed [w].     A2 Take(C.Count) out argument (OutIt) is echoed [w].
     A3 NEGATIVE: the read `L := C.Count` (Look) is NOT on the setter's line.
     A4 usages --rw --name SetCount: writers = Assign, Bump, OutIt (no Look).
     A5 control: the property's own 'Used in:' still lists Bump [w] and Look [r].
  B  (INT8) scope project excludes LIBRARY rows (a database named library-*.sqlite): CLI
     `usages --scope project`, LSP textDocument/references with usagesScope=project and
     draglint/usages scope project. Positive controls: the project's own call is listed on
     every surface; a library database asked ALONE still answers (nothing to exclude it for).
  C  (INT8) menu-tree resolves a dotted call by its RECEIVER: `Root.Remove(Leaf)` (Root is a
     TMenuItem) must not walk the unrelated TBag.Remove, and `K.Fill(Root)` (K: TKid, Fill
     inherited from THelper) must walk THelper.Fill, not the earlier-declared TOther.Fill.
     Control: the plain items Top / Leaf are present.

  Usage: pwsh -File tests\autotest\run_v152_BK-TAILS-LSP.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Continue'
$script:fail = 0; $script:pass = 0
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if ($ok) { $script:pass++ } else { $script:fail++ }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_bk_tails_lsp-{0}" -f $PID)
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
[IO.Directory]::CreateDirectory($scratch) | Out-Null
Push-Location $scratch   # no CWD .drag-lint.json walk into C:\Projects

function Put([string]$rel, [string]$text) {
  $p = Join-Path $scratch $rel
  [IO.Directory]::CreateDirectory((Split-Path $p)) | Out-Null
  [IO.File]::WriteAllText($p, ($text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
  return $p
}
function Json([string]$text) {
  $s0 = $text.IndexOf('{'); $e0 = $text.LastIndexOf('}')
  if ($s0 -lt 0 -or $e0 -le $s0) { return $null }
  try { return $text.Substring($s0, $e0 - $s0 + 1) | ConvertFrom-Json | ForEach-Object { $_ } } catch { return $null }
}
function Frame($obj) {
  $j = ($obj | ConvertTo-Json -Depth 12 -Compress)
  return "Content-Length: $([Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}

try {
  # ------------------------------------------------------------------ A (B42)
  Write-Host '== A: B42 Inc/Dec / out argument of a field-read property reaches its setter ==' -ForegroundColor Cyan
  Put 'a\uP.pas' @'
unit uP;

interface

type
  TCounter = class
  private
    FCount: Integer;
    procedure SetCount(pValue: Integer);
  public
    property Count: Integer read FCount write SetCount;
  end;

procedure Take(out pV: Integer);

implementation

procedure TCounter.SetCount(pValue: Integer);
begin
  FCount := pValue;
end;

procedure Take(out pV: Integer);
begin
  pV := 0;
end;

end.
'@ | Out-Null
  Put 'a\uC.pas' @'
unit uC;

interface

uses uP;

procedure Assign(C: TCounter);
procedure Bump(C: TCounter);
procedure OutIt(C: TCounter);
procedure Look(C: TCounter);

implementation

procedure Assign(C: TCounter);
begin
  C.Count := 5;
end;

procedure Bump(C: TCounter);
begin
  Inc(C.Count);
end;

procedure OutIt(C: TCounter);
begin
  Take(C.Count);
end;

procedure Look(C: TCounter);
var
  L: Integer;
begin
  L := C.Count;
end;

end.
'@ | Out-Null
  $dbA = Join-Path $scratch 'a.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index (Join-Path $scratch 'a') --db $dbA *> (Join-Path $scratch 'a-index.log') }
  if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index A exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }
  $mdSet = (& { $ErrorActionPreference = 'Continue'; & $exePath hover --qname uP.TCounter.SetCount --db $dbA --format md 2>$null }) -join "`n"
  $echo = [regex]::Match($mdSet, '(?m)^.*Used in \(via property Count\):.*$').Value
  function EchoMode([string]$routine) { $m = [regex]::Match($echo, [regex]::Escape("uC.$routine (uC.pas) [") + '(r|w|rw)\]'); if ($m.Success) { $m.Groups[1].Value } else { '' } }
  Check 'A0 control: Assign (C.Count := 5) on the setter line [w]' ((EchoMode 'Assign') -eq 'w') "echo='$echo'"
  Check 'A1 Inc(C.Count): Bump on the setter line [w]' ((EchoMode 'Bump') -eq 'w') "echo='$echo'"
  Check 'A2 Take(C.Count) out argument: OutIt on the setter line [w]' ((EchoMode 'OutIt') -eq 'w') "echo='$echo'"
  Check 'A3 NEGATIVE: the read in Look is not on the setter line' (($echo -ne '') -and ((EchoMode 'Look') -eq '')) "echo='$echo'"
  $rw = Json ((& { $ErrorActionPreference = 'Continue'; & $exePath usages --name SetCount --rw --db $dbA --json 2>$null }) -join "`n")
  $writers = @(@($rw.targets) | ForEach-Object { @($_.writers) } | ForEach-Object { ([string]$_.caller -split '\.')[-1] } | Sort-Object -Unique) -join ','
  $readers = @(@($rw.targets) | ForEach-Object { @($_.readers) }).Count
  Check 'A4 usages --rw --name SetCount: writers Assign,Bump,OutIt; no reader' (($writers -eq 'Assign,Bump,OutIt') -and ($readers -eq 0)) "writers=[$writers] readers=$readers"
  $mdProp = (& { $ErrorActionPreference = 'Continue'; & $exePath hover --qname uP.TCounter.Count --db $dbA --format md 2>$null }) -join "`n"
  $used = [regex]::Match($mdProp, '(?m)^.*Used in: .*$').Value
  Check 'A5 control: property Count Used in: Bump [w], Look [r]' ($used.Contains('uC.Bump (uC.pas) [w]') -and $used.Contains('uC.Look (uC.pas) [r]')) "used='$used'"

  # ------------------------------------------------------------------ B (scope project vs library)
  Write-Host '== B: scope project excludes library-*.sqlite rows ==' -ForegroundColor Cyan
  Put 'one\uAlpha.pas' "unit uAlpha;`ninterface`ntype`n  TAlpha = class`n  public`n    procedure Run;`n  end;`nimplementation`nprocedure TAlpha.Run;`nbegin`nend;`nend.`n" | Out-Null
  $mainText = "unit uMain;`ninterface`nuses uAlpha;`nprocedure Go;`nimplementation`nprocedure Go;`nvar`n  A: TAlpha;`nbegin`n  A := TAlpha.Create;`n  A.Run;`nend;`nend.`n"
  $uMain = Put 'one\uMain.pas' $mainText
  $lineA = [Array]::IndexOf(($mainText -split "`n"), '  A.Run;') + 1
  $pOne = Put 'one\AppOne.dpr' "program AppOne;`nuses uAlpha in 'uAlpha.pas', uMain in 'uMain.pas';`nbegin`nend.`n"
  Put 'lib\uLibThing.pas' "unit uLibThing;`ninterface`ntype`n  TLibThing = class`n  public`n    procedure Run;`n  end;`nprocedure LibGo;`nimplementation`nprocedure TLibThing.Run;`nbegin`nend;`nprocedure LibGo;`nvar`n  T: TLibThing;`nbegin`n  T := TLibThing.Create;`n  T.Run;`nend;`nend.`n" | Out-Null
  $dbOne = Join-Path $scratch 'one\_D-RAG\AppOne.sqlite'
  $dbLib = Join-Path $scratch 'library-Win64.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index --project $pOne --db $dbOne *> (Join-Path $scratch 'one-index.log') }
  $e1 = $LASTEXITCODE
  & { $ErrorActionPreference = 'Continue'; & $exePath index (Join-Path $scratch 'lib') --db $dbLib *> (Join-Path $scratch 'lib-index.log') }
  if ($e1 -ne 0 -or $LASTEXITCODE -ne 0) { Write-Host "FATAL: index B exit $e1/$LASTEXITCODE" -ForegroundColor Red; exit 2 }
  function RowFiles($doc) { return @(@($doc.reads) + @($doc.writes) + @($doc.calls) + @($doc.declarations) | Where-Object { $_ } | ForEach-Object { [string]$_.file }) }
  $cli = Json ((& { $ErrorActionPreference = 'Continue'; & $exePath usages --name Run --scope project --db $dbOne --db $dbLib --json 2>$null }) -join "`n")
  $files = RowFiles $cli
  Check 'B0 control: CLI scope project lists the project call (uMain)' (@($files | Where-Object { $_ -like '*\one\uMain.pas' }).Count -ge 1) "files=$($files -join ';')"
  Check 'B1 CLI scope project: no library row, library db not read' ((@($files | Where-Object { $_ -like '*\lib\*' }).Count -eq 0) -and (@(@($cli.databases) | Where-Object { ([string]$_) -like '*library-*' }).Count -eq 0)) "files=$($files -join ';') dbs=$(@($cli.databases) -join ';')"
  $cliLib = Json ((& { $ErrorActionPreference = 'Continue'; & $exePath usages --name Run --scope project --db $dbLib --json 2>$null }) -join "`n")
  Check 'B2 control: a library db asked alone still answers' (@(RowFiles $cliLib | Where-Object { $_ -like '*\lib\*' }).Count -ge 1) "doc=$($cliLib | ConvertTo-Json -Depth 3 -Compress)"

  $uri = 'file:///' + ($uMain -replace '\\', '/')
  $pos = @{ line = $lineA - 1; character = 4 }
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; method='workspace/didChangeConfiguration'; params=@{ settings=@{ dragLint=@{ usagesScope='project' } } } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/references'; params=@{ textDocument=@{ uri=$uri }; position=$pos; context=@{ includeDeclaration=$true } } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='draglint/usages'; params=@{ name='Run'; scope='project' } }
  $m += Frame @{ jsonrpc='2.0'; id=4; method='shutdown'; params=@{} }
  $inF = Join-Path $scratch 'in.txt'; $outF = Join-Path $scratch 'out.txt'
  [IO.File]::WriteAllText($inF, $m, (New-Object Text.UTF8Encoding $false))
  Start-Process $exePath -ArgumentList @('lsp', '--db', $dbOne, '--db', $dbLib) -WorkingDirectory $scratch -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError (Join-Path $scratch 'lsp.err') -NoNewWindow -Wait | Out-Null
  $res = @{}
  foreach ($mm in [regex]::Matches([IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $r = $mm.Value.Trim() | ConvertFrom-Json | ForEach-Object { $_ } } catch { continue }
    if ($null -ne $r.id) { $res[[int]$r.id] = $r }
  }
  $refUris = @(@($res[2].result) | ForEach-Object { [string]$_.uri })
  Check 'B3 control: LSP references (usagesScope=project) list the project call' (@($refUris | Where-Object { $_ -like '*/one/uMain.pas' }).Count -ge 1) "uris=$($refUris -join ';')"
  Check 'B4 LSP references (usagesScope=project): no library location' (@($refUris | Where-Object { $_ -like '*/lib/*' }).Count -eq 0) "uris=$($refUris -join ';')"
  $u3 = $res[3].result
  $u3Files = RowFiles $u3
  Check 'B5 control: draglint/usages scope project lists the project call' (@($u3Files | Where-Object { $_ -like '*\one\uMain.pas' }).Count -ge 1) "result=$($u3 | ConvertTo-Json -Depth 3 -Compress)"
  Check 'B6 draglint/usages scope project: no library row' (@($u3Files | Where-Object { $_ -like '*\lib\*' }).Count -eq 0) "files=$($u3Files -join ';')"

  # ------------------------------------------------------------------ C (menu-tree receiver)
  Write-Host '== C: menu-tree resolves a dotted call by its receiver ==' -ForegroundColor Cyan
  Put 'mt\uBag.pas' @'
unit uBag;

interface

uses Vcl.Menus;

type
  TBag = class
  public
    procedure Remove(pItem: TMenuItem);
  end;

  TOther = class
  public
    procedure Fill(pParent: TMenuItem);
  end;

implementation

procedure TBag.Remove(pItem: TMenuItem);
var
  X: TMenuItem;
begin
  X := TMenuItem.Create(pItem);
  X.Caption := 'Bogus';
  pItem.Add(X);
end;

procedure TOther.Fill(pParent: TMenuItem);
var
  X: TMenuItem;
begin
  X := TMenuItem.Create(pParent);
  X.Caption := 'Wrong';
  pParent.Add(X);
end;

end.
'@ | Out-Null
  Put 'mt\uKid.pas' @'
unit uKid;

interface

uses Vcl.Menus;

type
  THelper = class
  public
    procedure Fill(pParent: TMenuItem);
  end;

  TKid = class(THelper)
  end;

implementation

procedure THelper.Fill(pParent: TMenuItem);
var
  X: TMenuItem;
begin
  X := TMenuItem.Create(pParent);
  X.Caption := 'Good';
  pParent.Add(X);
end;

end.
'@ | Out-Null
  Put 'mt\uMenu.pas' @'
unit uMenu;

interface

uses Vcl.Menus;

procedure BuildIt(pMain: TMainMenu);

implementation

uses uBag, uKid;

procedure BuildIt(pMain: TMainMenu);
var
  Root, Leaf: TMenuItem;
  K: TKid;
begin
  Root := TMenuItem.Create(nil);
  Root.Caption := 'Top';
  pMain.Items.Add(Root);
  Leaf := TMenuItem.Create(Root);
  Leaf.Caption := 'Leaf';
  Root.Add(Leaf);
  Root.Remove(Leaf);
  K := TKid.Create;
  K.Fill(Root);
end;

end.
'@ | Out-Null
  Put 'mt\MtRecv.dpr' "program MtRecv;`n`nuses`n  Vcl.Menus,`n  uBag in 'uBag.pas',`n  uKid in 'uKid.pas',`n  uMenu in 'uMenu.pas';`n`nbegin`n  BuildIt(nil);`nend.`n" | Out-Null
  $pMt = Put 'mt\MtRecv.dproj' "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <MainSource>MtRecv.dpr</MainSource>`n  </PropertyGroup>`n  <ItemGroup>`n    <DCCReference Include=`"uBag.pas`"/>`n    <DCCReference Include=`"uKid.pas`"/>`n    <DCCReference Include=`"uMenu.pas`"/>`n  </ItemGroup>`n</Project>`n"
  $dbMt = Join-Path $scratch 'mt.sqlite'
  & { $ErrorActionPreference = 'Continue'; & $exePath index --project $pMt --db $dbMt *> (Join-Path $scratch 'mt-index.log') }
  if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index C exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }
  $paths = (& { $ErrorActionPreference = 'Continue'; & $exePath menu-tree --project $pMt --db $dbMt 2>$null }) -join "`n"   # tree text: an external root (pMain) has no --format paths row
  Check 'C0 control: Top and Leaf present' (($paths -match '\] Top ') -and ($paths -match '\] Leaf ')) "paths=$paths"
  Check 'C1 Root.Remove(Leaf) does not walk TBag.Remove (no Bogus)' (($paths -match 'Top') -and ($paths -notmatch 'Bogus')) "paths=$paths"
  Check 'C2 K.Fill(Root) walks the inherited THelper.Fill (Good)' ($paths -match '\] Good ') "paths=$paths"
  Check 'C3 K.Fill(Root) does not walk the unrelated TOther.Fill (no Wrong)' (($paths -match 'Top') -and ($paths -notmatch 'Wrong')) "paths=$paths"
}
finally {
  Pop-Location
  if (Test-Path $scratch) { try { [IO.Directory]::Delete($scratch, $true) } catch { Write-Host "note: scratch left at $scratch" } }
}
Write-Host ("run_v152_BK-TAILS-LSP: {0} pass, {1} fail" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
