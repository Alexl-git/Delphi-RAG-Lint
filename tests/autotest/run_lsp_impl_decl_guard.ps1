#Requires -Version 7
<#
  run_lsp_impl_decl_guard.ps1 -- `textDocument/implementation` and
  `textDocument/declaration` (B2).

  WHAT THIS PINS (each part is a positive control: a handler answering [] or a
  constant fails it):

    BOTH METHODS ARE ANSWERED (RED before B2: -32601) and `initialize`
    advertises implementationProvider and declarationProvider = true.

    IMPLEMENTATION of a virtual method = its own body PLUS every descendant's
    same-named method: cursor on `Foo` in TBase's declaration -> exactly 2
    Locations (TBase.Foo body, TDerived.Foo body), ordered by file:line. A
    routine with one body (`Solo`) -> 1. Lines are 0-based, computed here FROM
    THE FIXTURE TEXT.

    DECLARATION: cursor on the NAME in the BODY header `procedure TDerived.Foo`
    -> the line of `procedure Foo; override;` inside TDerived's declaration.

    WHITESPACE / no symbol -> [] for both (never an error).
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-impldecl-$PID"
)
# $PSScriptRoot is empty inside a param() default under Windows PowerShell 5 (the battery runs pwsh,
# a developer may not): resolve the default exe after the param block, which works under both.
if (-not $Exe) { $Exe = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\src\cli\Win64\Debug\drag-lint.exe' }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($o) {
  $j = $o | ConvertTo-Json -Compress -Depth 10
  $n = [Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uImpl.pas'
WriteAnsi $file @'
unit uImpl;

interface

type
  TBase = class
  public
    procedure Foo; virtual;
  end;

  TDerived = class(TBase)
  public
    procedure Foo; override;
  end;

procedure Solo;

implementation

procedure TBase.Foo;
begin
end;

procedure TDerived.Foo;
begin
  inherited;
end;

procedure Solo;
begin
end;

end.
'@

$file2 = Join-Path $src 'uImpl2.pas'
WriteAnsi $file2 @'
unit uImpl2;

interface

type
  TFwdCls = class;

  IShape = interface
    procedure Draw;
  end;

  TShapeBase = class(TObject, IShape)
  public
    procedure Draw; virtual; abstract;
  end;

  TCircle = class(TShapeBase)
  public
    procedure Draw; override;
  end;

  TAbs = class
  public
    procedure Foo; virtual; abstract;
  end;

  TAbsDer = class(TAbs)
  public
    procedure Foo; override; abstract;
  end;

  TFwdCls = class
  public
    procedure Zed;
  end;

procedure Other;

implementation

procedure Fwd; forward;

procedure TCircle.Draw;
begin
end;

procedure Other;
begin
  Fwd;
end;

procedure Fwd;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'impl.sqlite'
# PS5 turns native stderr under 2>&1 into a terminating error when ErrorActionPreference is Stop.
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $Exe index $src --db $db 2>&1 | Out-Null
$ErrorActionPreference = $ea
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern, [int]$from = 0) {
  for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } }
  return -1
}
function ColOf([int]$ln, [string]$word) { return $lines[$ln].IndexOf($word) + 1 }

$uri = 'file:///' + ($file -replace '\\', '/')
function Session([array]$reqs) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $id = 10
  foreach ($q in $reqs) {
    $id++
    $m += Frame @{ jsonrpc='2.0'; id=$id; method=$q.method; params=@{ textDocument=@{ uri=$uri }; position=@{ line=$q.line; character=$q.col } } }
  }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $r = @{ init = $null; res = @{}; err = @{} }
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 1) { $r.init = $o.result }
    if ($o.id -gt 10) {
      if ($null -ne $o.error) { $r.err[[int]$o.id] = $o.error }
      else { $r.res[[int]$o.id] = ,@($o.result) }   # ,@() keeps an empty [] distinct from "no answer"
    }
  }
  return $r
}

$lFooBase    = LineOf '^\s*procedure Foo; virtual;'
$lFooDer     = LineOf '^\s*procedure Foo; override;'
$lSoloDecl   = LineOf '^procedure Solo;'
$bBase       = LineOf '^procedure TBase\.Foo;'
$bDer        = LineOf '^procedure TDerived\.Foo;'
$bSolo       = LineOf '^procedure Solo;' ($lSoloDecl + 1)
$lBlank      = LineOf '^$' 1

$reqs = @(
  @{ method='textDocument/implementation'; line=$lFooBase;  col=(ColOf $lFooBase 'Foo') },   # 11
  @{ method='textDocument/implementation'; line=$lSoloDecl; col=(ColOf $lSoloDecl 'Solo') }, # 12
  @{ method='textDocument/declaration';    line=$bDer;      col=(ColOf $bDer 'Foo') },       # 13
  @{ method='textDocument/implementation'; line=$lBlank;    col=0 },                         # 14
  @{ method='textDocument/declaration';    line=$lBlank;    col=0 }                          # 15
)
$r = Session $reqs
$caps = $r.init.capabilities
Check 'initialize advertises implementationProvider' ($caps.implementationProvider -eq $true)
Check 'initialize advertises declarationProvider' ($caps.declarationProvider -eq $true)
Check 'the methods answered (not -32601)' ($r.res.ContainsKey(11) -and $r.res.ContainsKey(13)) $(if ($r.err.Count) { "error=" + (($r.err.Values | ForEach-Object { $_.code }) -join ',') } else { '' })
if (-not $r.res.ContainsKey(11)) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }

$imp = @($r.res[11][0])
Check 'implementation of TBase.Foo: exactly 2 Locations' ($imp.Count -eq 2) "got=$($imp.Count)"
if ($imp.Count -eq 2) {
  Check 'first is the TBase.Foo body line, character 0' ($imp[0].range.start.line -eq $bBase -and $imp[0].range.start.character -eq 0) "got=$($imp[0].range.start.line) want=$bBase"
  Check 'second is the TDerived.Foo body line (ordered by line)' ($imp[1].range.start.line -eq $bDer) "got=$($imp[1].range.start.line) want=$bDer"
  Check 'uri is the fixture file' (([string]$imp[0].uri) -like 'file:*uImpl.pas')
}
$solo = @($r.res[12][0])
Check 'implementation of Solo: exactly 1 Location at its body line' ($solo.Count -eq 1 -and $solo[0].range.start.line -eq $bSolo) "got=$($solo.Count)/$($solo[0].range.start.line) want=$bSolo"

$decl = @($r.res[13][0])
Check 'declaration from TDerived.Foo body header: 1 Location at the class-declaration line' ($decl.Count -eq 1 -and $decl[0].range.start.line -eq $lFooDer) "got=$($decl.Count)/$($decl[0].range.start.line) want=$lFooDer"

Check 'implementation on whitespace answers [] (not an error)' ($r.res.ContainsKey(14) -and @($r.res[14][0]).Count -eq 0 -and -not $r.err.ContainsKey(14))
Check 'declaration on whitespace answers [] (not an error)' ($r.res.ContainsKey(15) -and @($r.res[15][0]).Count -eq 0 -and -not $r.err.ContainsKey(15))

# ---- T4 (group-4 lane T): interface descendant, bodiless (abstract) descendant, forward declaration ----
$lines = [System.IO.File]::ReadAllLines($file2)
$uri = 'file:///' + ($file2.Replace([string][char]92, '/'))
$lIShapeDraw = LineOf '^\s*procedure Draw;$'
$lBaseDraw   = LineOf '^\s*procedure Draw; virtual; abstract;'
$lAbsFoo     = LineOf '^\s*procedure Foo; virtual; abstract;'
$lAbsDerFoo  = LineOf '^\s*procedure Foo; override; abstract;'
$lFwdClsFwd  = LineOf '^\s*TFwdCls = class;'
$lFwdClsDef  = LineOf '^\s*TFwdCls = class$'
$bCircle     = LineOf '^procedure TCircle\.Draw;'
$lFwd        = LineOf '^procedure Fwd; forward;'
$bFwd        = LineOf '^procedure Fwd;$' ($lFwd + 1)
$r2 = Session @(
  @{ method='textDocument/implementation'; line=$lBaseDraw;  col=(ColOf $lBaseDraw 'Draw') },   # 11
  @{ method='textDocument/implementation'; line=$lAbsFoo;    col=(ColOf $lAbsFoo 'Foo') },      # 12
  @{ method='textDocument/implementation'; line=$lIShapeDraw; col=(ColOf $lIShapeDraw 'Draw') }, # 13
  @{ method='textDocument/declaration';    line=$bFwd;       col=(ColOf $bFwd 'Fwd') },         # 14
  @{ method='textDocument/implementation'; line=$lFwd;       col=(ColOf $lFwd 'Fwd') },         # 15
  @{ method='textDocument/declaration';    line=$bCircle;    col=(ColOf $bCircle 'Draw') },     # 16
  @{ method='textDocument/declaration';    line=$lFwdClsDef; col=(ColOf $lFwdClsDef 'TFwdCls') } # 17
)
function Locs2([int]$id) { if ($r2.res.ContainsKey($id)) { return @($r2.res[$id][0]) } else { return @() } }
Write-Host ("  T4 lines: BaseDraw={0} AbsFoo={1} AbsDerFoo={2} Circle={3} Fwd={4} FwdBody={5} IShapeDraw={6}" -f $lBaseDraw,$lAbsFoo,$lAbsDerFoo,$bCircle,$lFwd,$bFwd,$lIShapeDraw) -ForegroundColor DarkGray
$a = @(Locs2 11)
Check 'T4 abstract method with a bodied descendant: implementation = the descendant body (1 Location)' ($a.Count -eq 1 -and $a[0].range.start.line -eq $bCircle) "got=$($a.Count)/$($a[0].range.start.line) want=$bCircle"
$b = @(Locs2 12)
Check 'T4 bodiless (abstract) descendant: implementation = the descendant DECLARATION line (1 Location)' ($b.Count -eq 1 -and $b[0].range.start.line -eq $lAbsDerFoo) "got=$($b.Count)/$($b[0].range.start.line) want=$lAbsDerFoo"
$c = @(Locs2 13)
Check 'T4 interface method: implementation includes the implementing class method (TShapeBase.Draw declaration)' (@($c | Where-Object { $_.range.start.line -eq $lBaseDraw }).Count -eq 1) "got=$(($c | ForEach-Object { $_.range.start.line }) -join ',') want-includes=$lBaseDraw"
$d = @(Locs2 14)
$f = @(Locs2 17)
Check 'T4 forward-declared CLASS: declaration from the full definition = the forward line (ForwardLine branch)' ($f.Count -eq 1 -and $f[0].range.start.line -eq $lFwdClsFwd) "got=$($f.Count)/$($f[0].range.start.line) want=$lFwdClsFwd"
Check 'T4 forward-declared routine: declaration = the forward line, not the body header' ($d.Count -eq 1 -and $d[0].range.start.line -eq $lFwd) "got=$($d.Count)/$($d[0].range.start.line) want=$lFwd"
# The two forward-ROUTINE checks (declaration at the body header, implementation at the forward line) pin
# current behaviour; they do not exercise ForwardLine (they pass with that branch removed). Only the
# forward-CLASS check above does.
$e = @(Locs2 15)
Check 'T4 forward-declared routine: implementation = the real body, not the forward line' ($e.Count -eq 1 -and $e[0].range.start.line -eq $bFwd) "got=$($e.Count)/$($e[0].range.start.line) want=$bFwd"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
