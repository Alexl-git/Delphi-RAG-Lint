#Requires -Version 7
<#
  run_lsp_hover_called_from_guard.ps1 -- wave 150 lane LX2 item 1 (FOUND-BUG from 149 LX):
  the hover card never rendered 'Called from:'.

  Root cause: every hover surface renders TDocRegions.FormatPhase2FactLines (+ FormatUsedInLines),
  and 'Called from:' is a PHASE-1 inbound line -- only the doc-block writer
  (TDocFactsRenderer.RenderFactsBlock) emits it. So the line reached a hover ONLY when
  `document --apply` had already written it into the source /// block; an undocumented routine
  (the 'Analysis facts:' path) or a hand-written /// block never showed its callers in the
  textDocument/hover markdown (VS Code) or `hover --format md` (CLI). TDocFacts.CalledFrom was
  computed by TDocFactsBuilder.Build on every hover and then dropped.

  Checks (fixture: Target / DocTarget each called from CallerA and CallerB, Lonely called by none,
  Applied whose /// block already carries a 'Called from:' para):
    L1. textDocument/hover on Target (no-doc path): one 'Called from:' line naming CallerA and CallerB.
    L2. textDocument/hover on DocTarget (doc path, summary shown): the same line.
    L3. Lonely (no callers): no 'Called from:' line (negative).
    L4. Applied (doc block already holds the line): exactly ONE 'Called from:' -- never doubled.
    L5. draglint/hoverBundle model facts do NOT gain the line: the RAD Studio popup renders its
        own CALLED FROM grid from resolvedCallers (a fact line there would show the callers twice).
    C1. CLI `hover --qname uCf.TWorker.Target --format md`: the line, naming both callers.
    C2. CLI hover on Lonely: no line.
  Positive control: L1/L2/C1 FAIL on the 150 base build (1.49.0-alpha before LX2); L3/L4/L5/C2
  are the negatives that fail if the line is added unconditionally or to the bundle facts.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-cf-$PID"
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
$WorkDir = (Resolve-Path $WorkDir).Path
$src = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $src | Out-Null

$file = Join-Path $src 'uCf.pas'
WriteAnsi $file @'
unit uCf;

interface

type
  TWorker = class
  public
    procedure Target;
    /// <summary>A documented routine with two callers.</summary>
    procedure DocTarget;
    procedure Lonely;
    /// <summary>Its block was already written by document --apply.</summary>
    /// <remarks>
    /// <para>Called from: uCf.TWorker.CallerA (uCf.pas)</para>
    /// </remarks>
    procedure Applied;
    procedure CallerA;
    procedure CallerB;
  end;

implementation

procedure TWorker.Target;
begin
end;

procedure TWorker.DocTarget;
begin
end;

procedure TWorker.Lonely;
begin
end;

procedure TWorker.Applied;
begin
end;

procedure TWorker.CallerA;
begin
  Target;
  DocTarget;
  Applied;
end;

procedure TWorker.CallerB;
begin
  Target;
  DocTarget;
end;

end.
'@

$db = Join-Path $WorkDir 'cf.sqlite'
& $Exe index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

$lines = [System.IO.File]::ReadAllLines($file)
function PosOf([string]$pattern, [string]$word) {
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $pattern) { return @{ line = $i; character = $lines[$i].IndexOf($word) + 1 } }
  }
  throw "fixture line not found: $pattern"
}
$uri = 'file:///' + ($file -replace '\\', '/')
$pT = PosOf '^procedure TWorker\.Target;'    'Target'
$pD = PosOf '^procedure TWorker\.DocTarget;' 'DocTarget'
$pL = PosOf '^procedure TWorker\.Lonely;'    'Lonely'
$pA = PosOf '^procedure TWorker\.Applied;'   'Applied'

$td = @{ uri = $uri }
$m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
$m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
$m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/hover'; params=@{ textDocument=$td; position=$pT } }
$m += Frame @{ jsonrpc='2.0'; id=3; method='textDocument/hover'; params=@{ textDocument=$td; position=$pD } }
$m += Frame @{ jsonrpc='2.0'; id=4; method='textDocument/hover'; params=@{ textDocument=$td; position=$pL } }
$m += Frame @{ jsonrpc='2.0'; id=5; method='textDocument/hover'; params=@{ textDocument=$td; position=$pA } }
$m += Frame @{ jsonrpc='2.0'; id=6; method='draglint/hoverBundle'; params=@{ textDocument=$td; position=$pT } }
$m += Frame @{ jsonrpc='2.0'; id=9; method='shutdown'; params=@{} }
$inF  = Join-Path $WorkDir 'in.txt'
$outF = Join-Path $WorkDir 'out.txt'
[System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
Start-Process $Exe -ArgumentList @('lsp', '--db', $db) -WorkingDirectory $WorkDir `
  -RedirectStandardInput $inF -RedirectStandardOutput $outF `
  -RedirectStandardError (Join-Path $WorkDir 'err.txt') -NoNewWindow -Wait | Out-Null
$r = @{}
foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
  if ($null -ne $o.id) { $r[[int]$o.id] = $o }
}
function HoverMd($resp) { if ($null -eq $resp -or $null -eq $resp.result) { return '' } return [string]$resp.result.contents.value }
function CfLines([string]$md) { return @(($md -split "`n") | Where-Object { $_ -match 'Called from:' }) }
function Flat([string]$md) { return ($md -replace "`r?`n", ' / ') }

$mdT = HoverMd $r[2]; $mdD = HoverMd $r[3]; $mdL = HoverMd $r[4]; $mdA = HoverMd $r[5]
Check 'L0 every hover answered (non-empty markdown)' ($mdT -ne '' -and $mdD -ne '' -and $mdL -ne '' -and $mdA -ne '')
$cT = @(CfLines $mdT)
Check 'L1 Target (no-doc path): one Called from: line naming CallerA and CallerB' ($cT.Count -eq 1 -and $cT[0] -match 'CallerA' -and $cT[0] -match 'CallerB') ("md=" + (Flat $mdT))
$cD = @(CfLines $mdD)
Check 'L2 DocTarget (doc path): one Called from: line naming CallerA and CallerB' ($cD.Count -eq 1 -and $cD[0] -match 'CallerA' -and $cD[0] -match 'CallerB') ("md=" + (Flat $mdD))
Check 'L2 control: the doc path really is the doc path (summary shown)' ($mdD -match 'documented routine with two callers')
Check 'L3 Lonely (no callers): no Called from: line' ((CfLines $mdL).Count -eq 0) ("md=" + (Flat $mdL))
Check 'L4 Applied (block already holds the line): exactly one Called from:' (([regex]::Matches($mdA, 'Called from:')).Count -eq 1) ("md=" + (Flat $mdA))
$b = $r[6].result
$bf = @(); if ($null -ne $b -and $null -ne $b.model) { $bf = @($b.model.facts) }
Check 'L5 hoverBundle answered with a model' ($null -ne $b -and $null -ne $b.model) ("raw=" + ($r[6] | ConvertTo-Json -Compress -Depth 6))
Check 'L5 hoverBundle model facts carry NO Called from: (the popup has its resolvedCallers grid)' (@($bf | Where-Object { $_ -match 'Called from:' }).Count -eq 0) ("facts=" + ($bf -join ' | '))
Check 'L5 hoverBundle resolvedCallers still lists both callers' (@($b.resolvedCallers).Count -ge 2)

$cli = (& $Exe hover --qname uCf.TWorker.Target --db $db --format md 2>$null) -join "`n"
$cc = @(CfLines $cli)
Check 'C1 CLI hover --format md Target: one Called from: naming CallerA and CallerB' ($cc.Count -eq 1 -and $cc[0] -match 'CallerA' -and $cc[0] -match 'CallerB') ("md=" + (Flat $cli))
$cliL = (& $Exe hover --qname uCf.TWorker.Lonely --db $db --format md 2>$null) -join "`n"
Check 'C2 CLI hover Lonely: answered, no Called from:' ($cliL -match 'Lonely' -and (CfLines $cliL).Count -eq 0) ("md=" + (Flat $cliL))

if ($script:Failed) { Write-Host 'run_lsp_hover_called_from_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lsp_hover_called_from_guard: PASS' -ForegroundColor Green
exit 0
} finally {
  if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
