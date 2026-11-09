#Requires -Version 7
<#
  run_hover_crossdb_uses_guard.ps1 -- hover carries cross-DB uses on the card (wave 149 lane LX,
  UP 149 row: "hover passes extra stores to TDocFactsBuilder.Build so 'Used in:' / 'Called from:'
  carry cross-DB uses on the card").

  THE GAP (148 UP REPORT). `document --db A --db B` passes B to TDocFactsBuilder.Build as an
  extra store, so a property used only in another project's DB gets 'Used in: <B routine>' in the
  managed doc block. Hover took ONE store (the DB that holds the symbol), so the popup for the same
  property omitted that use: the card and the doc block disagreed.

  FIXTURE (manifest, two sections over one shared unit):
    shared\uProv.pas  TProvider.Value (property read GetValue), Work -- in BOTH DBs
    aside\uConsA.pas  GoA reads P.Value, calls P.Work              -- A only
    bside\uConsB.pas  GoB reads + writes P.Value, calls P.Work     -- B only

  Checks:
    H1  CLI `hover --qname uProv.TProvider.Value --db A --db B --format md`: the 'Used in:' line
        names GoA AND GoB.
    H2  CLI hover TProvider.GetValue (A, B): 'Used in (via property Value):' names GoB (the
        accessor echo list, the routine-side inbound line the card renders; 'Called from:' is a
        doc-block list the card does not render -- its callers come from hoverBundle).
    H3  CLI `--format json` facts carry GoB too (the IDE's json consumer).
    L1  LSP (lsp --db A --db B): textDocument/hover on Value in uProv.pas names GoB.
    L2  LSP draglint/hoverBundle model facts name GoB.
    P1  POSITIVE CONTROL: --db A alone never names GoB (CLI and LSP) -- the extra store is what
        adds it, and GoA is still there (the primary-store answer is unchanged).
  RED on an engine where hover takes one store (1.48.0-alpha): H1-H3, L1, L2 fail; P1 passes.
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(& "$PSScriptRoot\lib\DefaultEngineExe.ps1"),
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-xdb-$PID"
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
foreach ($d in 'shared', 'aside', 'bside') { New-Item -ItemType Directory (Join-Path $WorkDir $d) | Out-Null }

$prov = Join-Path $WorkDir 'shared\uProv.pas'
WriteAnsi $prov @'
unit uProv;

interface

type
  TProvider = class
  private
    FValue: Integer;
    function GetValue: Integer;
  public
    procedure Work;
    property Value: Integer read GetValue write FValue;
  end;

implementation

function TProvider.GetValue: Integer;
begin
  Result:= FValue;
end;

procedure TProvider.Work;
begin
end;

end.
'@
WriteAnsi (Join-Path $WorkDir 'aside\uConsA.pas') @'
unit uConsA;

interface

uses uProv;

type
  TConsA = class
  public
    function GoA(const P: TProvider): Integer;
  end;

implementation

function TConsA.GoA(const P: TProvider): Integer;
begin
  P.Work;
  Result:= P.Value;
end;

end.
'@
WriteAnsi (Join-Path $WorkDir 'bside\uConsB.pas') @'
unit uConsB;

interface

uses uProv;

type
  TConsB = class
  public
    procedure GoB(const P: TProvider);
  end;

implementation

procedure TConsB.GoB(const P: TProvider);
begin
  if P.Value > 0 then P.Work;
  P.Value:= 7;
end;

end.
'@

$cfg = Join-Path $WorkDir 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "SecA", "db": "a.sqlite", "include": ["shared", "aside"] },
      { "name": "SecB", "db": "b.sqlite", "include": ["shared", "bside"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
& $Exe index --all --config $cfg --only SecA --jobs 1 2>&1 | Out-Null
& $Exe index --all --config $cfg --only SecB --jobs 1 2>&1 | Out-Null
$dbA = Join-Path $WorkDir 'out\a.sqlite'
$dbB = Join-Path $WorkDir 'out\b.sqlite'
Check 'fixture: both DBs indexed' ((Test-Path $dbA) -and (Test-Path $dbB))

function Hover([string]$QName, [string]$Fmt, [string[]]$Dbs) {
  $a = @('hover', '--qname', $QName, '--format', $Fmt)
  foreach ($d in $Dbs) { $a += @('--db', $d) }
  return ((& $Exe @a 2>$null) -join "`n")
}
function UsedInLine([string]$md) { return (($md -split "`n") | Where-Object { $_ -match 'Used in:' }) -join ' / ' }
function ViaLine([string]$md) { return (($md -split "`n") | Where-Object { $_ -match 'Used in \(via property' }) -join ' / ' }

# ---------------- CLI ----------------
$mdAB = Hover 'uProv.TProvider.Value' 'md' @($dbA, $dbB)
$u = UsedInLine $mdAB
Check 'H1 CLI hover Value (A,B): Used in: names GoA' ($u -match 'GoA') $u
Check 'H1 CLI hover Value (A,B): Used in: names GoB (the B-only use)' ($u -match 'GoB') $u
$mdA = Hover 'uProv.TProvider.Value' 'md' @($dbA)
Check 'P1 CLI hover Value (A only): GoA, never GoB' ((UsedInLine $mdA) -match 'GoA' -and $mdA -notmatch 'GoB') (UsedInLine $mdA)
$wAB = Hover 'uProv.TProvider.GetValue' 'md' @($dbA, $dbB)
Check 'H2 CLI hover GetValue (A,B): Used in (via property Value): names GoB' ((ViaLine $wAB) -match 'GoB') (ViaLine $wAB)
$wA = Hover 'uProv.TProvider.GetValue' 'md' @($dbA)
Check 'P1 CLI hover GetValue (A only): GoA, never GoB' ((ViaLine $wA) -match 'GoA' -and $wA -notmatch 'GoB') (ViaLine $wA)
$jAB = Hover 'uProv.TProvider.Value' 'json' @($dbA, $dbB)
Check 'H3 CLI hover --format json (A,B): facts name GoB' ($jAB -match 'GoB') ("len=" + $jAB.Length)

# ---------------- LSP ----------------
$lines = [System.IO.File]::ReadAllLines($prov)
$ln = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*property Value:') { $ln = $i; break } }
$pos = @{ line = $ln; character = $lines[$ln].IndexOf('Value') + 1 }
$uri = 'file:///' + ($prov -replace '\\', '/')
function Session([string[]]$Dbs, [string]$Tag) {
  $td = @{ uri = $uri }
  $m  = Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } }
  $m += Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} }
  $m += Frame @{ jsonrpc='2.0'; id=2; method='textDocument/hover'; params=@{ textDocument=$td; position=$pos } }
  $m += Frame @{ jsonrpc='2.0'; id=3; method='draglint/hoverBundle'; params=@{ textDocument=$td; position=$pos } }
  $m += Frame @{ jsonrpc='2.0'; id=9; method='shutdown'; params=@{} }
  $inF  = Join-Path $WorkDir "in-$Tag.txt"
  $outF = Join-Path $WorkDir "out-$Tag.txt"
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  $a = @('lsp'); foreach ($d in $Dbs) { $a += @('--db', $d) }
  Start-Process $Exe -ArgumentList $a -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF `
    -RedirectStandardError (Join-Path $WorkDir "err-$Tag.txt") -NoNewWindow -Wait | Out-Null
  $r = @{}
  foreach ($mm in [regex]::Matches([System.IO.File]::ReadAllText($outF), '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($null -ne $o.id) { $r[[int]$o.id] = $o }
  }
  return $r
}
function HoverMd($resp) { if ($null -eq $resp -or $null -eq $resp.result) { return '' } return [string]$resp.result.contents.value }
function BundleFacts($resp) { if ($null -eq $resp -or $null -eq $resp.result -or $null -eq $resp.result.model) { return '' } return (@($resp.result.model.facts) -join ' | ') }

$ab = Session @($dbA, $dbB) 'ab'
$hm = HoverMd $ab[2]
Check 'L1 LSP hover Value (A,B): names GoA' ($hm -match 'GoA') (UsedInLine $hm)
Check 'L1 LSP hover Value (A,B): names GoB' ($hm -match 'GoB') (UsedInLine $hm)
$bf = BundleFacts $ab[3]
Check 'L2 LSP hoverBundle facts (A,B): name GoB' ($bf -match 'GoB') $bf
$oa = Session @($dbA) 'a'
$hmA = HoverMd $oa[2]; $bfA = BundleFacts $oa[3]
Check 'P1 LSP (A only): hover names GoA, never GoB' ($hmA -match 'GoA' -and $hmA -notmatch 'GoB') (UsedInLine $hmA)
Check 'P1 LSP (A only): hoverBundle never names GoB' ($bfA -notmatch 'GoB') $bfA

if ($script:Failed) { Write-Host 'run_hover_crossdb_uses_guard: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_hover_crossdb_uses_guard: PASS' -ForegroundColor Green
exit 0
} finally {
  if (-not $script:Failed -and (Test-Path $WorkDir)) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
