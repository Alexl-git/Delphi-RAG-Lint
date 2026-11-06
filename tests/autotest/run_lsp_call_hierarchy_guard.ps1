#Requires -Version 7
<#
  run_lsp_call_hierarchy_guard.ps1 -- `textDocument/prepareCallHierarchy`,
  `callHierarchy/incomingCalls`, `callHierarchy/outgoingCalls` (lane 145 lsp).

  Fixture: A calls B twice, B calls C once, C calls nothing; a class method Run calls A.
  Positive controls (a handler answering null / [] or a constant fails them):
    initialize advertises callHierarchyProvider.
    prepare on B's name -> one item named B (selectionRange on the name).
    incoming(B) -> exactly one caller A with TWO fromRanges (A's two call lines).
    incoming(A) -> the method Run; incoming(Run) -> [] (nobody calls it).
    outgoing(B) -> exactly one callee C with one fromRange on B's body line.
    outgoing(C) -> [].
  Honest misses: prepare on whitespace, on a type name, and in a file the index does not hold -> null,
  never an error and never a wrong item. A stale item (unknown id) -> [].
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-callhier-$PID"
)
if (-not $Exe) { $Exe = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\src\cli\Win64\Debug\drag-lint.exe' }
. (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'lsp_stdio_helpers.ps1')
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uCall.pas'
WriteAnsi $file @'
unit uCall;

interface

type
  TRunner = class
  public
    procedure Run;
  end;

procedure A;
procedure B;
procedure C;

implementation

procedure C;
begin
end;

procedure B;
begin
  C;
end;

procedure A;
begin
  B;
  B;
end;

procedure TRunner.Run;
begin
  A;
end;

end.
'@
$loose = Join-Path $WorkDir 'loose.pas'
WriteAnsi $loose "unit loose;`ninterface`nprocedure Z;`nimplementation`nprocedure Z;`nbegin`nend;`nend.`n"

$db = Join-Path $WorkDir 'call.sqlite'
$ea = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $Exe index $src --db $db 2>&1 | Out-Null
$ErrorActionPreference = $ea
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function LineOf([string]$pattern, [int]$from = 0) { for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { return $i } } return -1 }
$uri = 'file:///' + ($file -replace '\\', '/')
$looseUri = 'file:///' + ($loose -replace '\\', '/')

$bBody = LineOf '^procedure B;$' ((LineOf '^implementation') + 1)
$aBody = LineOf '^procedure A;$' ((LineOf '^implementation') + 1)
$cBody = LineOf '^procedure C;$' ((LineOf '^implementation') + 1)
$runBody = LineOf '^procedure TRunner\.Run;'
$callsInA = @((LineOf '^  B;$' $aBody), (LineOf '^  B;$' ((LineOf '^  B;$' $aBody) + 1)))
$cInB = LineOf '^  C;$' $bBody
$tName = LineOf '^  TRunner = class'

function Prep([int]$line, [int]$col, [string]$u = $uri) { @{ method='textDocument/prepareCallHierarchy'; params=(PosParams $u $line $col) } }
$r1 = LspSession $Exe $WorkDir $db @(
  (Prep $bBody 10),        # 11 B
  (Prep $aBody 10),        # 12 A
  (Prep $cBody 10),        # 13 C
  (Prep $runBody 19),      # 14 Run
  (Prep 1 0),              # 15 blank line
  (Prep $tName 4),         # 16 type name
  (Prep 2 5 $looseUri)     # 17 file not in the index
)
Check 'initialize advertises callHierarchyProvider' ($r1.init.capabilities.callHierarchyProvider -eq $true)
Check 'prepare answered (not -32601)' ($r1.res.ContainsKey(11)) $(if ($r1.err.Count) { 'error=' + (($r1.err.Values | % { $_.code }) -join ',') })
if (-not $r1.res.ContainsKey(11)) { Write-Host 'FAIL -- nothing to assert against.' -ForegroundColor Red; exit 1 }
$pb = @($r1.res[11][0])
Check 'prepare on B: one item named B' ($pb.Count -eq 1 -and $pb[0].name -eq 'B') "got=$($pb.Count)/$($pb[0].name)"
Check 'prepare item selectionRange is on the name (line of the declaration, width 1)' ($pb.Count -eq 1 -and ($pb[0].selectionRange.end.character - $pb[0].selectionRange.start.character) -eq 1)
Check 'prepare on whitespace -> null' ($r1.res.ContainsKey(15) -and (IsNull $r1 15) -and -not $r1.err.ContainsKey(15))
Check 'prepare on a type name -> null (not a routine)' ($r1.res.ContainsKey(16) -and (IsNull $r1 16))
Check 'prepare in an unindexed file -> null (not an error)' ($r1.res.ContainsKey(17) -and (IsNull $r1 17) -and -not $r1.err.ContainsKey(17))

$itemB = $pb[0]; $itemA = @($r1.res[12][0])[0]; $itemC = @($r1.res[13][0])[0]; $itemRun = @($r1.res[14][0])[0]
$stale = @{ name='B'; kind=12; uri=$uri; range=$itemB.range; selectionRange=$itemB.selectionRange; data=@{ id=999999; path=$file } }
$r2 = LspSession $Exe $WorkDir $db @(
  @{ method='callHierarchy/incomingCalls'; params=@{ item=$itemB } },   # 11
  @{ method='callHierarchy/outgoingCalls'; params=@{ item=$itemB } },   # 12
  @{ method='callHierarchy/incomingCalls'; params=@{ item=$itemA } },   # 13
  @{ method='callHierarchy/incomingCalls'; params=@{ item=$itemRun } }, # 14
  @{ method='callHierarchy/outgoingCalls'; params=@{ item=$itemC } },   # 15
  @{ method='callHierarchy/incomingCalls'; params=@{ item=$stale } }    # 16
)
$inB = @($r2.res[11][0])
Check 'incoming(B): exactly one caller, A' ($inB.Count -eq 1 -and $inB[0].from.name -eq 'A') "got=$($inB.Count)/$($inB[0].from.name)"
if ($inB.Count -eq 1) {
  $fr = @($inB[0].fromRanges)
  Check 'incoming(B): two fromRanges, on the two call lines in A' ($fr.Count -eq 2 -and $fr[0].start.line -eq $callsInA[0] -and $fr[1].start.line -eq $callsInA[1]) "got=$(($fr | % { $_.start.line }) -join ',') want=$($callsInA -join ',')"
}
$outB = @($r2.res[12][0])
Check 'outgoing(B): exactly one callee, C, with one fromRange on the call line' ($outB.Count -eq 1 -and $outB[0].to.name -eq 'C' -and @($outB[0].fromRanges).Count -eq 1 -and $outB[0].fromRanges[0].start.line -eq $cInB) "got=$($outB.Count)/$($outB[0].to.name)"
$inA = @($r2.res[13][0])
Check 'incoming(A): the method Run' ($inA.Count -eq 1 -and $inA[0].from.name -eq 'Run') "got=$($inA.Count)/$($inA[0].from.name)"
Check 'incoming(Run): [] (nobody calls it)' ($r2.res.ContainsKey(14) -and @($r2.res[14][0]).Count -eq 0)
Check 'outgoing(C): [] (calls nothing)' ($r2.res.ContainsKey(15) -and @($r2.res[15][0]).Count -eq 0)
Check 'a stale item (unknown id) answers [] not an error' ($r2.res.ContainsKey(16) -and @($r2.res[16][0]).Count -eq 0 -and -not $r2.err.ContainsKey(16))

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
