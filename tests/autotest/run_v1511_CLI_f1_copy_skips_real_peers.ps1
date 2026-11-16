<#
  run_v1511_CLI_f1_copy_skips_real_peers.ps1 -- lane v1511 CLI, item F1 (found by B16).
  lint-all on a DB COPY derived its dl:shared marker peers -- and the sibling stores of the
  shared-unit rules -- from the manifest, i.e. from the REAL sibling DBs (a whole lint-all
  of each). Now, when --db is not the DB the manifest registers: the marker-peer pass is
  skipped with one stderr note, and each sibling DB is replaced by the file of the same name
  beside the copy (or dropped). Evidence is the engine's own trace (DRAGLINT_PEER_TRACE),
  never an mtime.
  Hermetic fixture (manifest SecA / SecB via --config):
    A  positive control: --db = the registered a.sqlite -> the peer b.sqlite IS run;
    B  --db = a copy of a.sqlite beside a copy of b.sqlite -> no peer run, the note, no
       trace line names the registered out\ DBs, the sibling is remapped to the copy.
  Optional C (-YadfDb <copy>, only when B passed, so an old engine never reaches a real DB):
    lint-all --rule review-marker-unused on a YADF copy -> peers-skipped, and no trace line
    names C:\Projects\YADF\_D-RAG.
  Usage: pwsh -File tests\autotest\run_v1511_CLI_f1_copy_skips_real_peers.ps1 [-Exe <exe>] [-YadfDb <copy.sqlite>]
#>
param(
  [string]$Exe = (Join-Path $PSScriptRoot '..\..\src\cli\Win64\Debug\drag-lint.exe'),
  [string]$YadfDb = ''
)
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path $env:TEMP ("v1511_cli_f1_" + $PID)
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail" -ForegroundColor Red; $script:fail++ }
}
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
function ReadTrace([string]$Path) { if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' } }
$oldTrace = $env:DRAGLINT_PEER_TRACE
try {
  foreach ($d in 'shared', 'common', 'bside', 'copy') { New-Item -ItemType Directory -Path (Join-Path $scratch $d) -Force | Out-Null }
  WriteAscii (Join-Path $scratch 'shared\gone.pas') @'
unit gone; // dl:shared SecA, SecB

interface

procedure Touchgone(var B: Integer);

implementation

procedure Touchgone(var B: Integer);
begin
  B := B + 1; // dl:ok duplicate-code@1a2b -- planted: no finding on this line under any DB
end;

end.
'@
  WriteAscii (Join-Path $scratch 'common\a.pas') "unit a;`n`ninterface`n`nprocedure RunA;`n`nimplementation`n`nuses`n  gone;`n`nprocedure RunA;`nvar`n  N: Integer;`nbegin`n  gone.Touchgone(N);`nend;`n`nend.`n"
  WriteAscii (Join-Path $scratch 'bside\b.pas') "unit b;`n`ninterface`n`nprocedure RunB;`n`nimplementation`n`nuses`n  gone;`n`nprocedure RunB;`nvar`n  N: Integer;`nbegin`n  gone.Touchgone(N);`nend;`n`nend.`n"
  $cfg = Join-Path $scratch 'manifest.drag-lint.json'
  @"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "SecA", "db": "a.sqlite", "include": ["shared", "common"] },
      { "name": "SecB", "db": "b.sqlite", "include": ["shared", "bside"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
  $dbA = Join-Path $scratch 'out\a.sqlite'; $dbB = Join-Path $scratch 'out\b.sqlite'
  Push-Location $scratch
  try {
    & $exePath index --all --config $cfg --only SecA --jobs 1 2>&1 | Out-Null
    & $exePath index --all --config $cfg --only SecB --jobs 1 2>&1 | Out-Null
  } finally { Pop-Location }
  Check '0. sanity: both registered DBs exist' ((Test-Path $dbA) -and (Test-Path $dbB))

  # A -- positive control: the registered DB still runs its peer
  $trA = Join-Path $scratch 'traceA.txt'
  $env:DRAGLINT_PEER_TRACE = $trA
  $outA = (& $exePath lint-all --db $dbA --config $cfg 2>&1 | Out-String)
  $tA = ReadTrace $trA
  Check 'A1. registered --db: the peer b.sqlite is run (text note)' ($outA -match 'shared-db: running [^\r\n]*b\.sqlite') (($outA -split "`r?`n" | Select-String 'shared-db') -join ' | ')
  Check 'A2. registered --db: the trace records the peer run' ($tA -match '(?m)^peer [^\r\n]*\\out\\b\.sqlite') $tA
  Check 'A3. registered --db: no peers-skipped' (-not ($tA -match 'peers-skipped'))

  # B -- a copy beside a sibling copy
  $cpA = Join-Path $scratch 'copy\a.sqlite'; $cpB = Join-Path $scratch 'copy\b.sqlite'
  Copy-Item $dbA $cpA; Copy-Item $dbB $cpB
  $trB = Join-Path $scratch 'traceB.txt'
  $env:DRAGLINT_PEER_TRACE = $trB
  $outB = (& $exePath lint-all --db $cpA --config $cfg 2>&1 | Out-String)
  $tB = ReadTrace $trB
  Check 'B1. copy --db: no peer lint-all is run' (-not ($outB -match 'shared-db: running')) (($outB -split "`r?`n" | Select-String 'shared-db') -join ' | ')
  Check 'B2. copy --db: one note says the peer DBs were skipped' ($outB -match 'peer DBs skipped: --db [^\r\n]*not the registered project DB')
  Check 'B3. copy --db: the trace records peers-skipped' ($tB -match '(?m)^peers-skipped ') $tB
  $outDir = [regex]::Escape((Join-Path $scratch 'out') + '\')
  Check 'B4. copy --db: no trace line opens or runs a registered out\ DB' (-not ($tB -match "(?m)^(peer|sibling-open) [^\r\n]*$outDir")) $tB
  Check 'B5. copy --db: the sibling b.sqlite is remapped to the copy beside --db' ($tB -match ('(?m)^sibling-remap [^\r\n]*\\out\\b\.sqlite -> ' + [regex]::Escape($cpB))) $tB
  Check 'B6. copy --db: --shared-db (explicit peers) still runs' ((& $exePath lint-all --db $cpA --config $cfg --shared-db $cpB 2>&1 | Out-String) -match 'shared-db: running [^\r\n]*copy\\b\.sqlite')

  # C -- the real-world shape, only on an engine that passed B
  if ($YadfDb -ne '') {
    if ($script:fail -gt 0) { Write-Host 'SKIP C: B failed -- an engine without the fix would reach the REAL YADF DBs' }
    elseif (-not (Test-Path -LiteralPath $YadfDb)) { Write-Host "SKIP C: no copy at $YadfDb" }
    else {
      $cpY = Join-Path $scratch 'yadf-copy.sqlite'
      Copy-Item -LiteralPath $YadfDb $cpY
      $trC = Join-Path $scratch 'traceC.txt'
      $env:DRAGLINT_PEER_TRACE = $trC
      & $exePath lint-all --db $cpY --rule review-marker-unused --json 1>$null 2> (Join-Path $scratch 'c.err')
      $tC = ReadTrace $trC
      Check 'C1. YADF copy: the peer pass was reached and skipped' ($tC -match '(?m)^peers-skipped ') $tC
      Check 'C2. YADF copy: no trace line names C:\Projects\YADF\_D-RAG' (-not ($tC -match '(?m)^(peer|sibling-open) [^\r\n]*C:\\Projects\\YADF\\_D-RAG')) $tC
    }
  }
} finally {
  $env:DRAGLINT_PEER_TRACE = $oldTrace
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if ($fail -gt 0) { Write-Host "FAIL ($fail)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
