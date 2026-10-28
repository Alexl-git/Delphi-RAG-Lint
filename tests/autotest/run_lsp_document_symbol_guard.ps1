#Requires -Version 7
<#
  run_lsp_document_symbol_guard.ps1 -- `textDocument/documentSymbol` (B1).

  WHAT THIS PINS, and why each part is here rather than "it returned something":

    THE METHOD IS ANSWERED (RED before B1: -32601 method not found) and
    `initialize` advertises documentSymbolProvider = true.

    THE TREE IS RIGHT. Top level = the unit's members (the unit symbol itself
    is not a root): TThing, TColor, MaxItems, GCounter, Driver, in source
    order. TThing.children = FCount, Thrice, Once, Never, Count with kinds
    8,6,6,6,7 (field, method x3, property) -- a flat list, or members at the
    top level, fails.

    KINDS ARE MAPPED. class 5, enum 10, const 14, var 13, procedure 12.

    LINES/COLUMNS ARE 0-BASED and are computed here FROM THE FIXTURE TEXT, not
    hard-coded: range.start.line is the declaration line, selectionRange is the
    name token (start col = index of the name on its line, end = + its length).

    NO LOCALS. Driver declares `T: TThing`; neither it nor any local may
    appear at any depth (CONTROL: the routine itself does appear).

    A PERCENT-ENCODED URI (`file:///c%3A/...`, what VS Code sends) resolves.
    An UNKNOWN URI answers [] (not an error).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-docsym-$PID"
)
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

$file = Join-Path $src 'uLens.pas'
WriteAnsi $file @'
unit uLens;

interface

type
  TThing = class
  private
    FCount: Integer;
  public
    procedure Thrice;
    procedure Once;
    procedure Never;
    property Count: Integer read FCount write FCount;
  end;

  TColor = (cRed, cGreen);

const
  MaxItems = 10;

var
  GCounter: Integer;

procedure Driver;

implementation

procedure TThing.Thrice;
begin
end;

procedure TThing.Once;
begin
end;

procedure TThing.Never;
begin
end;

procedure Driver;
var
  T: TThing;
begin
  T := TThing.Create;
  T.Thrice;
  T.Thrice;
  T.Thrice;
  T.Once;
end;

end.
'@

$edge = Join-Path $src 'uEdge.pas'
WriteAnsi $edge @'
unit uEdge;

interface

type
  TEdge = class
  public
    procedure Over(A: Integer); overload;
    procedure Over(const S: string); overload;
    class procedure Make;
  end;

{ Spare } procedure Spare;

procedure
  Wrapped2;

implementation

procedure TEdge.Over(A: Integer);
begin
end;

procedure TEdge.Over(const S: string);
begin
end;

class procedure TEdge.Make;
begin
end;

procedure Spare;
begin
end;

procedure Wrapped2;
begin
end;

end.
'@

$db = Join-Path $WorkDir 'sym.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
# 0-based line of the FIRST line matching $pattern (the declaration).
function LineOf([string]$pattern) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } }
  return -1
}

function Session([string]$uri, [string]$openText = $null) {
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  if ($openText -ne '') { $m += Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$openText } } } }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/documentSymbol'; params=@{ textDocument=@{ uri=$uri } } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir 'in.txt'
  $outF = Join-Path $WorkDir 'out.txt'
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
  $r = @{ init = $null; sym = $null; err = $null; raw = [System.IO.File]::ReadAllText($outF) }
  foreach ($mm in [regex]::Matches($r.raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 1) { $r.init = $o.result }
    if ($o.id -eq 2) {
      if ($null -ne $o.error) { $r.err = $o.error }
      else { $r.sym = ,@($o.result) }   # ,@() keeps an empty [] distinct from "no answer"
    }
  }
  return $r
}

# VS Code form: lower-case drive, colon percent-encoded.
$p = $file -replace '\\', '/'
$uri = 'file:///' + $p.Substring(0,1).ToLower() + '%3A' + $p.Substring(2)
$r = Session $uri
Check 'initialize advertises documentSymbolProvider' ($r.init.capabilities.documentSymbolProvider -eq $true) "caps=$($r.init.capabilities | ConvertTo-Json -Compress -Depth 3)"
Check 'the method answered (not -32601)' ($null -ne $r.sym) $(if ($r.err) { "error=$($r.err.code) $($r.err.message)" } else { '' })
if ($null -eq $r.sym) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }

$top = @($r.sym[0])
function Find($arr, [string]$name) { @($arr | Where-Object { $_.name -eq $name }) | Select-Object -First 1 }
$names = ($top | ForEach-Object { $_.name }) -join ','
Check 'top level = unit members in source order' ($names -eq 'TThing,TColor,MaxItems,GCounter,Driver') "got=$names"
Check 'the unit symbol is not a root' ($null -eq (Find $top 'uLens'))

$kinds = @{ TThing = 5; TColor = 10; MaxItems = 14; GCounter = 13; Driver = 12 }
foreach ($k in $kinds.Keys) {
  $s = Find $top $k
  Check "kind of $k is $($kinds[$k])" ($null -ne $s -and $s.kind -eq $kinds[$k]) "got=$($s.kind)"
}

$thing = Find $top 'TThing'
$ch = @($thing.children)
Check 'TThing.children names' ((($ch | % { $_.name }) -join ',') -eq 'FCount,Thrice,Once,Never,Count') "got=$(($ch | % { $_.name }) -join ',')"
Check 'TThing.children kinds 8,6,6,6,7' ((($ch | % { $_.kind }) -join ',') -eq '8,6,6,6,7') "got=$(($ch | % { $_.kind }) -join ',')"

# 0-based lines/columns computed from the fixture text.
$declThing = LineOf '^\s*TThing = class'
Check 'TThing range.start.line is the declaration line (0-based)' ($thing.range.start.line -eq $declThing) "want=$declThing got=$($thing.range.start.line)"
Check 'TThing range ends after it starts' ($thing.range.end.line -gt $thing.range.start.line)
Check 'TThing selectionRange line' ($thing.selectionRange.start.line -eq $declThing)
$col = $lines[$declThing].IndexOf('TThing')
Check 'TThing selectionRange is the name token' ($thing.selectionRange.start.character -eq $col -and $thing.selectionRange.end.character -eq $col + 6) "want=$col..$($col+6) got=$($thing.selectionRange.start.character)..$($thing.selectionRange.end.character)"
$thr = Find $ch 'Thrice'
$declThr = LineOf '^\s*procedure Thrice;'
Check 'Thrice line is its interface declaration line' ($thr.range.start.line -eq $declThr) "want=$declThr got=$($thr.range.start.line)"
$colThr = $lines[$declThr].IndexOf('Thrice')
Check 'Thrice selectionRange is the name token (not the keyword)' ($thr.selectionRange.start.character -eq $colThr -and $thr.selectionRange.end.character -eq $colThr + 6) "want=$colThr got=$($thr.selectionRange.start.character)"
$cnt = Find $ch 'Count'
Check 'Count line' ($cnt.range.start.line -eq (LineOf '^\s*property Count')) "got=$($cnt.range.start.line)"
$drv = Find $top 'Driver'
Check 'Driver line is its interface declaration line' ($drv.range.start.line -eq (LineOf '^procedure Driver;')) "got=$($drv.range.start.line)"

# No locals at any depth.
function AllNames($arr) { foreach ($s in $arr) { $s.name; if ($s.children) { AllNames @($s.children) } } }
$all = @(AllNames $top)
Check 'no local variable T anywhere' (-not ($all -contains 'T')) "all=$($all -join ',')"
Check 'CONTROL: the routine Driver does appear' ($all -contains 'Driver')
Check 'Driver has no children' ($null -eq $drv.children)

# I1 (B1 fix round 1): range must CONTAIN selectionRange at every depth, for
# every symbol of BOTH fixtures. RED before the fix: a routine whose declaration
# keyword sits left of a short range end produced selectionRange past range.end.
function Before($a, $b) { ($a.line -lt $b.line) -or ($a.line -eq $b.line -and $a.character -le $b.character) }
function Walk($arr, $acc) { foreach ($s in $arr) { $acc.Add($s); if ($s.children) { Walk @($s.children) $acc } } }
function ContainmentBad($arr) {
  $acc = New-Object System.Collections.Generic.List[object]
  Walk $arr $acc
  return @($acc | Where-Object { -not ((Before $_.range.start $_.selectionRange.start) -and (Before $_.selectionRange.end $_.range.end)) } | ForEach-Object { $_.name })
}
$bad = ContainmentBad $top
Check 'range contains selectionRange for every symbol (uLens)' ($bad.Count -eq 0) "bad=$($bad -join ',')"

# I2: edge-case declarations.
$ep = $edge -replace '\\', '/'
$euri = 'file:///' + $ep.Substring(0,1).ToLower() + '%3A' + $ep.Substring(2)
$re = Session $euri
Check 'edge file answered' ($null -ne $re.sym)
if ($null -ne $re.sym) {
  $elines = [System.IO.File]::ReadAllLines($edge)
  function ELineOf([string]$p) { for ($i = 0; $i -lt $elines.Count; $i++) { if ($elines[$i] -match $p) { return $i } } return -1 }
  $etop = @($re.sym[0])
  Check 'edge control: top level = TEdge,Spare,Wrapped2' ((($etop | % { $_.name }) -join ',') -eq 'TEdge,Spare,Wrapped2') "got=$(($etop | % { $_.name }) -join ',')"
  $bad = ContainmentBad $etop
  Check 'range contains selectionRange for every symbol (uEdge)' ($bad.Count -eq 0) "bad=$($bad -join ',')"
  $edgeCls = Find $etop 'TEdge'
  $ech = @($edgeCls.children)
  Check 'overload pair: two Over children plus Make' ((($ech | % { $_.name }) -join ',') -eq 'Over,Over,Make') "got=$(($ech | % { $_.name }) -join ',')"
  $o1 = ELineOf '^\s*procedure Over\(A'
  $o2 = ELineOf '^\s*procedure Over\(const'
  Check 'overload 1 on its own declaration line' ($ech[0].range.start.line -eq $o1) "want=$o1 got=$($ech[0].range.start.line)"
  Check 'overload 2 on its own declaration line' ($ech[1].range.start.line -eq $o2) "want=$o2 got=$($ech[1].range.start.line)"
  $oc = $elines[$o2].IndexOf('Over')
  Check 'overload 2 selectionRange is the name token' ($ech[1].selectionRange.start.character -eq $oc -and $ech[1].selectionRange.end.character -eq $oc + 4) "want=$oc got=$($ech[1].selectionRange.start.character)"
  $ml = ELineOf '^\s*class procedure Make'
  $mc = $elines[$ml].IndexOf('Make')
  Check 'class procedure: kind 6, selectionRange is Make (not the keyword)' ($ech[2].kind -eq 6 -and $ech[2].selectionRange.start.character -eq $mc -and $ech[2].selectionRange.end.character -eq $mc + 4) "want=$mc got=$($ech[2].selectionRange.start.character)"
  $sp = Find $etop 'Spare'
  $sl = ELineOf '^\{ Spare \} procedure Spare;'
  $sc = $elines[$sl].LastIndexOf('Spare')
  Check 'name in a comment before the declaration: selectionRange is the declared name' ($sp.selectionRange.start.line -eq $sl -and $sp.selectionRange.start.character -eq $sc) "want=$sc got=$($sp.selectionRange.start.character)"
  $w = Find $etop 'Wrapped2'
  $wl = ELineOf '^procedure$'
  Check 'multi-line declaration: selectionRange stays on the declaration line (keyword-column fallback)' ($w.selectionRange.start.line -eq $w.range.start.line -and $w.range.start.line -eq $wl) "want=$wl got=$($w.range.start.line)/$($w.selectionRange.start.line)"
}

# S6: the OPEN BUFFER wins over the file on disk. The buffer indents the
# Thrice declaration by 6 more columns than the disk copy, so the name token
# sits 6 columns further right; reading the disk would answer the old column.
$bufText = (($lines | ForEach-Object { if ($_ -match '^\s*procedure Thrice;') { '      ' + $_ } else { $_ } }) -join "`r`n") + "`r`n"
$rb = Session $uri $bufText
if ($null -ne $rb.sym) {
  $bThing = Find @($rb.sym[0]) 'TThing'
  $bThr = Find @($bThing.children) 'Thrice'
  $wantCol = $colThr + 6
  Check 'S6: selectionRange follows the OPEN BUFFER, not the disk file' ($bThr.selectionRange.start.character -eq $wantCol) "want=$wantCol got=$($bThr.selectionRange.start.character)"
} else { Check 'S6: documentSymbol answered with an open buffer' $false }

# Unknown file -> [].
$r2 = Session 'file:///c%3A/no/such/dir/Nope.pas'
Check 'unknown URI answers [] (not an error)' ($null -ne $r2.sym -and @($r2.sym[0]).Count -eq 0 -and $null -eq $r2.err) $(if ($r2.err) { "error=$($r2.err.code)" } else { '' })

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
