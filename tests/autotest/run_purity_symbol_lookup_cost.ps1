<#
  run_purity_symbol_lookup_cost.ps1 -- the purity stage's per-symbol lookups
  must be cheap, because the stage is WHOLE-DB on every index run that wrote
  anything -- including a one-file incremental.

  THE DEFECT (2026-10-29, "why does a one-unit rescan take minutes"). On this
  repo's own 277-file project a one-file `index --project` spent ~40 s in the
  purity stage, 30.7 s of it in 55,693 calls to TSQLiteSymbolStore.GetSymbolById
  (0.55 ms each): every call created a TFDQuery, set its SQL, prepared and
  described it, read one row and freed it. The purity stage resolves the target
  of every read / call / member ref through it, so the cost is O(symbols in the
  project) however few files changed.

  THE FIX keeps ONE prepared statement for the lookup (PrepareStatements), so a
  lookup is bind + step + read. Same SQL, same row mapper: the rows returned are
  identical, only the per-call setup is gone.

  CASES
    V   the fixture indexes and the profiled re-index prints the lookup line
    P1  POSITIVE CONTROL: the instrument saw >= 1000 lookups (a lookup count of
        0 would make the cost assertion vacuous)
    C1  mean symbol-load cost per lookup below 0.15 ms (0.55 ms before the fix)
    C2  single-row fetches are at most 5% of lookups (100% before the fix)
    E1  every routine's purity verdict after the one-file incremental equals a
        fresh --rebuild of the same tree (the speed-up writes nothing different)

  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_purity_lookup_$PID",
  [double]$MaxMsPerLookup = 0.15
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function W($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory -Path $WorkDir | Out-Null

# Generated fixture: 8 units x 150 routines, each with two locals, a param and
# reads of all three, plus a call to the previous routine -- every read binds a
# DISTINCT local/param symbol, so the stage looks up thousands of symbols.
$UnitCount = 8
$RoutineCount = 150
$dprUses = @()
for ($u = 1; $u -le $UnitCount; $u++) {
  $decl = [Text.StringBuilder]::new()
  $impl = [Text.StringBuilder]::new()
  for ($r = 1; $r -le $RoutineCount; $r++) {
    [void]$decl.AppendLine("function U${u}R${r}(pIn${r}: Integer): Integer;")
    [void]$impl.AppendLine("function U${u}R${r}(pIn${r}: Integer): Integer;")
    [void]$impl.AppendLine("var")
    [void]$impl.AppendLine("  LA${r}, LB${r}: Integer;")
    [void]$impl.AppendLine("begin")
    [void]$impl.AppendLine("  LA${r} := pIn${r} + 1;")
    [void]$impl.AppendLine("  LB${r} := LA${r} * pIn${r};")
    if ($r -gt 1) { [void]$impl.AppendLine("  LB${r} := LB${r} + U${u}R$($r - 1)(LA${r});") }
    [void]$impl.AppendLine("  Result := LA${r} + LB${r};")
    [void]$impl.AppendLine("end;")
    [void]$impl.AppendLine("")
  }
  W (Join-Path $WorkDir "uGen$u.pas") ("unit uGen$u;`n`ninterface`n`n" + $decl.ToString() + "`nimplementation`n`n" + $impl.ToString() + "end.`n")
  $dprUses += "  uGen$u in 'uGen$u.pas'"
}
W (Join-Path $WorkDir 'App.dpr') ("program App;`nuses`n" + ($dprUses -join ",`n") + ";`nbegin`nend.`n")
$dpr = Join-Path $WorkDir 'App.dpr'
$db  = Join-Path $WorkDir 'App.sqlite'
$ref = Join-Path $WorkDir 'Ref.sqlite'

& $exePath index --project $dpr --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db) $db

# One-file change, then the profiled incremental run.
[IO.File]::AppendAllText((Join-Path $WorkDir 'uGen1.pas'), "{ changed }`r`n", [Text.Encoding]::ASCII)
$env:DRAGLINT_PROFILE = '1'
try { $out = & $exePath index --project $dpr --db $db 2>&1 | ForEach-Object { "$_" } }
finally { Remove-Item Env:\DRAGLINT_PROFILE -ErrorAction SilentlyContinue }
$rx = 'symbol lookups (\d+): single-row fetches (\d+) in ([\d.]+)s, per-file preload (\d+) row\(s\) in ([\d.]+)s'
$line = $out | Where-Object { $_ -match $rx } | Select-Object -First 1
Check 'V the profiled re-index printed the symbol-lookup line' ($null -ne $line) (($out | Select-Object -Last 8) -join ' | ')
if ($line -match $rx) {
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $n = [int]$Matches[1]; $single = [int]$Matches[2]
  $secs = [double]::Parse($Matches[3], $inv) + [double]::Parse($Matches[5], $inv)
  Check "P1 POSITIVE CONTROL the stage looked up >= 1000 symbols (saw $n)" ($n -ge 1000) $line
  $ms = if ($n -gt 0) { $secs * 1000.0 / $n } else { [double]::MaxValue }
  Check ("C1 mean symbol-load cost per lookup {0:N3} ms is below {1} ms" -f $ms, $MaxMsPerLookup) ($ms -lt $MaxMsPerLookup) $line
  Check "C2 single-row fetches ($single) are at most 5% of lookups ($n) -- the per-file preload serves the rest" ($single * 20 -le $n) $line
}
# Equivalence: the incremental DB's verdicts equal a fresh rebuild of the same tree.
& $exePath index --project $dpr --db $ref --rebuild 2>&1 | Out-Null
$q = "SELECT s.qualified_name, f.effect_free, f.effect_summary, f.effect_witness FROM symbols s JOIN symbol_facts f ON f.symbol_id = s.id WHERE ifnull(f.body_loc,0) > 0 ORDER BY s.qualified_name"
$a = (& $exePath sql --db $db  --json --limit 100000 --query $q 2>$null | ConvertFrom-Json).rows | ForEach-Object { $_ -join '|' }
$b = (& $exePath sql --db $ref --json --limit 100000 --query $q 2>$null | ConvertFrom-Json).rows | ForEach-Object { $_ -join '|' }
Check "E1 POSITIVE CONTROL both databases hold the fixture's routines ($(@($a).Count) / $(@($b).Count))" ((@($a).Count -ge ($UnitCount * $RoutineCount)) -and (@($b).Count -ge ($UnitCount * $RoutineCount))) ''
$diff = Compare-Object @($a) @($b)
Check "E1 incremental purity verdicts equal a --rebuild ($(@($diff).Count) differing row(s))" (@($diff).Count -eq 0) (($diff | Select-Object -First 3 | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join ' || ')

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
