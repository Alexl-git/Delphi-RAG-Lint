<#
  run_lint_rule_cache.ps1 -- whole-graph rule cache for `lint <file> --db`
  (spec docs\superpowers\specs\2026-10-14-whole-graph-rule-cache.md, AC1-AC16).

  circular-uses, enum-helper-separate-units and duplicate-global-decl read only
  the indexes, so `lint <file>` serves them from a cache keyed on the index
  files' size + last-write time (project AND library) and the engine. A cache is
  only acceptable if it can never answer differently from a live run, so:

  C0  POSITIVE CONTROLS: the fixture really triggers each cached rule, and
      repeated-type-switch under --rule (it ships OFF).
  C1  PARITY: every finding of every unit is identical with the cache off, on
      the run that fills it, and on a cached hit.
  C2  the second run is a HIT (DRAGLINT_PROFILE `rule-cache: hit`).
  C3  an edit that breaks the cycle + `index --project` -> next lint is a HIT
      (the indexer warmed it) AND the cycle is gone: a stale entry never wins.
  C4  a one-file `index <file> --db` (a writer that does not warm) restores the
      cycle -> MISS, and the cycle is back.
  C6  the library index changing -> MISS.
  C7  a corrupt cache file -> correct findings, MISS, file rewritten.
  C8  DRAGLINT_RULE_CACHE=0 -> nothing written.
  C9  a dl:ok repeated-type-switch marker is still accounted, and the cache
      never holds a repeated-type-switch row (it parses sources: AC16).
  C10 a --rule run never writes a partial entry, and reads a full one.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_rule_cache_$PID"
)
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$proj = Join-Path $WorkDir 'proj'; $libDir = Join-Path $WorkDir 'lib'; $cache = Join-Path $WorkDir 'cache'
New-Item -ItemType Directory -Path $proj, $libDir, $cache -Force | Out-Null
$env:DRAGLINT_RULE_CACHE_DIR = $cache
$env:DRAGLINT_RULE_CACHE     = $null

# circular-uses: interface-level cycle uCycA <-> uCycB.
$cycB_cycle = @'
unit uCycB;

interface

uses
  uCycA;

function FromB: Integer;

implementation

function FromB: Integer;
begin
  Result:= FromA;
end;

end.
'@
$cycB_nocycle = @'
unit uCycB;

interface

function FromB: Integer;

implementation

function FromB: Integer;
begin
  Result:= 2;
end;

end.
'@
Write-Ascii (Join-Path $proj 'uCycA.pas') @'
unit uCycA;

interface

uses
  uCycB;

function FromA: Integer;

implementation

function FromA: Integer;
begin
  Result:= 1;
end;

end.
'@
Write-Ascii (Join-Path $proj 'uCycB.pas') $cycB_cycle

# duplicate-global-decl: the same interface global in two units.
foreach ($u in 'uG1','uG2') {
  Write-Ascii (Join-Path $proj "$u.pas") @"
unit $u;

interface

var
  GShared: Integer;

implementation

end.
"@
}

# enum-helper-separate-units: TFruit in uEnum, its helper in uHelp.
Write-Ascii (Join-Path $proj 'uEnum.pas') @'
unit uEnum;

interface

type
  TFruit = (fApple, fPear);

implementation

end.
'@
Write-Ascii (Join-Path $proj 'uHelp.pas') @'
unit uHelp;

interface

uses
  uEnum;

type
  TFruitHelper = record helper for TFruit
    function Name: string;
  end;

implementation

function TFruitHelper.Name: string;
begin
  Result:= 'fruit';
end;

end.
'@

# repeated-type-switch: the same selector in three distinct routines (ships OFF).
$rtsSrc = @'
unit uRts;

interface

uses
  uEnum;

function R1(pK: TFruit): Integer;
function R2(pK: TFruit): Integer;
function R3(pK: TFruit): Integer;

implementation

function R1(pK: TFruit): Integer;
begin
  Result:= 0;
  case pK of
    fApple: Result:= 1;
    fPear : Result:= 2;
  end;
end;

function R2(pK: TFruit): Integer;
begin
  Result:= 0;
  case pK of
    fApple: Result:= 3;
    fPear : Result:= 4;
  end;
end;

function R3(pK: TFruit): Integer;
begin
  Result:= 0;
  case pK of
    fApple: Result:= 5;
    fPear : Result:= 6;
  end;
end;

end.
'@
Write-Ascii (Join-Path $proj 'uRts.pas') $rtsSrc

Write-Ascii (Join-Path $proj 'Proj.dpr') @'
program Proj;

uses
  uCycA, uCycB, uG1, uG2, uEnum, uHelp, uRts;

begin
end.
'@

# A tiny LIBRARY index, passed explicitly so no run touches the machine's real one.
Write-Ascii (Join-Path $libDir 'uLibOnly.pas') @'
unit uLibOnly;

interface

function LibFn: Integer;

implementation

function LibFn: Integer;
begin
  Result:= 7;
end;

end.
'@
$lib = Join-Path $WorkDir 'lib.sqlite'
$idxL = & $exePath index $libDir --db $lib 2>&1 | Out-String
Check 'SANITY: library fixture indexed' ($LASTEXITCODE -eq 0) $idxL

$db   = Join-Path $WorkDir 'proj.sqlite'
$dpr  = Join-Path $proj 'Proj.dpr'
# --rule-cache-warm wait: these checks need the warm FINISHED when index returns
# (the default runs it in the background since 2026-10-15; that path has its own
# suite, run_rule_cache_warm_background.ps1).
$idxP = & $exePath index --project $dpr --db $db --library-db $lib --rule-cache-warm wait 2>&1 | Out-String
Check 'SANITY: project fixture indexed (index --project)' ($LASTEXITCODE -eq 0 -and $idxP -notmatch '\b[1-9]\d* errors\b') $idxP

$UNITS  = @('uCycA.pas','uCycB.pas','uG1.pas','uG2.pas','uEnum.pas','uHelp.pas','uRts.pas')
$CACHED = @('circular-uses','enum-helper-separate-units','duplicate-global-decl')

function Rows($json) { @(if ($json -and $json.Trim()) { $json | ConvertFrom-Json } else { @() }) }
function Tuples($rows) { @($rows | ForEach-Object { '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.rule, $_.severity, ([IO.Path]::GetFileName($_.file_path)), $_.start_line, $_.start_col, $_.message } | Sort-Object) }
function LintOne($leaf, [string[]]$extra = @()) {
  $errF = Join-Path $WorkDir 'one.err'
  $env:DRAGLINT_PROFILE = '1'
  $j = & $exePath lint (Join-Path $proj $leaf) --db $db --library-db $lib --rules-dir $rules --json @extra 2>$errF | Out-String
  $env:DRAGLINT_PROFILE = $null
  [pscustomobject]@{ Rows = (Rows $j); Prof = (Get-Content $errF -Raw) }
}
function CacheState($prof) { if ($prof -match 'rule-cache: (hit|miss|skipped)') { $Matches[1] } else { '(none)' } }
function CacheFiles { @(Get-ChildItem $cache -Filter 'rules-*.json' -ErrorAction SilentlyContinue) }

# --- C0 controls ---------------------------------------------------------------
$allRows = Rows (& $exePath lint-all --db $db --library-db $lib --rules-dir $rules --json 2>$null | Out-String)
foreach ($r in $CACHED) {
  Check "C0  CONTROL: lint-all reports $r" (@($allRows | Where-Object rule -eq $r).Count -gt 0) "fixture must trigger $r or the parity checks prove nothing"
}
$rtsRows = Rows (& $exePath lint-all --db $db --library-db $lib --rules-dir $rules --rule repeated-type-switch --json 2>$null | Out-String)
Check 'C0  CONTROL: --rule repeated-type-switch reports it (3 distinct routines)' (@($rtsRows | Where-Object rule -eq 'repeated-type-switch').Count -gt 0) ""

# --- C8 + C1(off): cache disabled ------------------------------------------------
# The index --project above may already have WARMED an entry (Task 2); C8 asks
# whether a DISABLED run writes, so start it from an empty cache dir.
CacheFiles | Remove-Item -Force
$env:DRAGLINT_RULE_CACHE = '0'
$off = @{}; foreach ($u in $UNITS) { $off[$u] = Tuples (LintOne $u).Rows }
$env:DRAGLINT_RULE_CACHE = $null
Check 'C8  DRAGLINT_RULE_CACHE=0 writes nothing' ((CacheFiles).Count -eq 0) "found: $((CacheFiles).Name -join ', ')"

# --- C1/C2: fill, then hit ---------------------------------------------------------
$first = LintOne 'uCycA.pas'
Check 'C2  first run on an empty cache is a MISS' ((CacheState $first.Prof) -eq 'miss') "state: $(CacheState $first.Prof)"
Check 'C2  ...and writes the cache' ((CacheFiles).Count -eq 1) "files: $((CacheFiles).Count)"
$second = LintOne 'uCycA.pas'
Check 'C2  the next run is a HIT' ((CacheState $second.Prof) -eq 'hit') "state: $(CacheState $second.Prof)"

# --- C13: the cache lives OUTSIDE the user's indexes ----------------------------
# Decision 2026-10-23 (lane W6-L): single-file `lint` keeps its rule cache in
# DRAGLINT_RULE_CACHE_DIR / %LOCALAPPDATA%\drag-lint\cache, keyed per exe build,
# and never writes the --db or --library-db. A cold (filling) plus a warm run
# must leave both index files byte-identical. C2 above is the positive control
# that these runs really wrote a cache entry.
CacheFiles | Remove-Item -Force
$dbHash0  = (Get-FileHash $db).Hash
$libHash0 = (Get-FileHash $lib).Hash
Check 'C13 SANITY: both index files hash' ($dbHash0 -and $libHash0) "db=$dbHash0 lib=$libHash0"
$c13a = LintOne 'uCycA.pas'
$c13b = LintOne 'uCycA.pas'
Check 'C13 CONTROL: the two runs were a cache MISS then a HIT' (((CacheState $c13a.Prof) -eq 'miss') -and ((CacheState $c13b.Prof) -eq 'hit')) "states: $(CacheState $c13a.Prof) / $(CacheState $c13b.Prof)"
Check 'C13 single-file lint leaves the --db byte-identical' ((Get-FileHash $db).Hash -eq $dbHash0) ""
Check 'C13 ...and the --library-db byte-identical' ((Get-FileHash $lib).Hash -eq $libHash0) ""
Check 'C13 ...and its cache file is NOT beside the --db' (@(CacheFiles | Where-Object { $_.DirectoryName -eq (Split-Path $db -Parent) }).Count -eq 0 -and (CacheFiles).Count -eq 1) "files: $((CacheFiles).FullName -join ', ')"
$fill = @{ 'uCycA.pas' = Tuples $first.Rows }; $hit = @{ 'uCycA.pas' = Tuples $second.Rows }
foreach ($u in $UNITS | Where-Object { $_ -ne 'uCycA.pas' }) { $hit[$u] = Tuples (LintOne $u).Rows }
foreach ($u in $UNITS) {
  $d1 = @(Compare-Object $off[$u] $hit[$u])
  Check "C1  $u -- cached findings == cache-off findings ($($off[$u].Count))" ($d1.Count -eq 0) (($d1 | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join ' ; ')
}
$d0 = @(Compare-Object $off['uCycA.pas'] $fill['uCycA.pas'])
Check 'C1  uCycA.pas -- cache-FILLING run == cache-off' ($d0.Count -eq 0) (($d0 | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join ' ; ')
Check 'C1  CONTROL: uCycA really carries a circular-uses finding' (@($off['uCycA.pas'] | Where-Object { $_ -like 'circular-uses|*' }).Count -gt 0) ""

# --- C9 / AC16 -----------------------------------------------------------------------
$cacheTxt = [string](CacheFiles | Select-Object -First 1 | ForEach-Object { [IO.File]::ReadAllText($_.FullName) })
Check 'C9  the cache never holds a repeated-type-switch row (AC16)' ($cacheTxt -notmatch 'repeated-type-switch') ""

# --- C10: --rule never writes a partial entry; reads a full one ---------------------
$r10 = LintOne 'uCycA.pas' @('--rule','circular-uses')
Check 'C10 --rule circular-uses on a full entry is a HIT' ((CacheState $r10.Prof) -eq 'hit') "state: $(CacheState $r10.Prof)"
CacheFiles | Remove-Item -Force
$r10b = LintOne 'uCycA.pas' @('--rule','circular-uses')
Check 'C10 --rule on a cold cache answers correctly' (@($r10b.Rows | Where-Object rule -eq 'circular-uses').Count -gt 0) ""
Check 'C10 ...and does NOT write a partial entry' ((CacheFiles).Count -eq 0) "files: $((CacheFiles).Count)"

# --- C7: corrupt cache file ----------------------------------------------------------
LintOne 'uCycA.pas' | Out-Null
$cf = [string](CacheFiles | Select-Object -First 1).FullName; if (-not $cf) { $cf = Join-Path $cache 'rules-missing.json' }
[IO.File]::WriteAllText($cf, '{"format":1,"key":{"engine":', [Text.Encoding]::ASCII)
$c7 = LintOne 'uCycA.pas'
Check 'C7  a truncated cache file is a MISS, not an error' ((CacheState $c7.Prof) -eq 'miss') "state: $(CacheState $c7.Prof)"
Check 'C7  ...with correct findings' (@(Compare-Object $off['uCycA.pas'] (Tuples $c7.Rows)).Count -eq 0) ""
$c7b = LintOne 'uCycA.pas'
Check 'C7  ...and the file is rewritten (next run hits)' ((CacheState $c7b.Prof) -eq 'hit') "state: $(CacheState $c7b.Prof)"

# --- C6: library change invalidates ----------------------------------------------------
(Get-Item $lib).LastWriteTime = (Get-Item $lib).LastWriteTime.AddSeconds(5)
$c6 = LintOne 'uG1.pas'
Check 'C6  the library index changing makes the next run a MISS' ((CacheState $c6.Prof) -eq 'miss') "state: $(CacheState $c6.Prof)"

# --- C11: a partial entry is TOPPED UP, its other rules carried --------------------
CacheFiles | Remove-Item -Force
# Carrying only matters when a run needs rules the entry LACKS while NOT needing
# one it HAS: entry {circular-uses}, then a run with circular-uses disabled needs
# {enum, dup}. Without carrying, that run writes {enum, dup} and loses
# circular-uses, so the next default run misses again.
$p11 = LintOne 'uCycA.pas' @('--disable','enum-helper-separate-units,duplicate-global-decl')
$txtA = [string](CacheFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) })
Check 'C11 step 1: the entry holds circular-uses only' (($txtA -match '"circular-uses"') -and ($txtA -notmatch '"enum-helper-separate-units"') -and ($txtA -notmatch '"duplicate-global-decl"')) "state: $(CacheState $p11.Prof)"
$q11 = LintOne 'uCycA.pas' @('--disable','circular-uses')
Check 'C11 step 2: a run needing {enum, dup} is a MISS (lacks)' ($q11.Prof -match 'rule-cache: miss \(lacks ') (($q11.Prof -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' / ')
$txtB = [string](CacheFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) })
Check 'C11 ...and writes an entry that STILL holds circular-uses (carried) plus the two it computed' (($txtB -match '"circular-uses"') -and ($txtB -match '"enum-helper-separate-units"') -and ($txtB -match '"duplicate-global-decl"')) ""
$h11 = LintOne 'uCycA.pas'
Check 'C11 step 3: a default run is now a HIT' ((CacheState $h11.Prof) -eq 'hit') "state: $(CacheState $h11.Prof)"
Check 'C11 ...with correct findings' (@(Compare-Object $off['uCycA.pas'] (Tuples $h11.Rows)).Count -eq 0) ""

# --- C12: a run that needs none of the cached rules writes nothing ------------------
CacheFiles | Remove-Item -Force
$p12 = LintOne 'uCycA.pas' @('--disable','circular-uses,enum-helper-separate-units,duplicate-global-decl')
Check 'C12 a run needing none of the cached rules writes no (empty) entry' ((CacheFiles).Count -eq 0) "files: $((CacheFiles).Count); $(($p12.Prof -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' / ')"

# --- C3/C5: edit + index --project -> warmed HIT, and the NEW answer ----------------
Write-Ascii (Join-Path $proj 'uCycB.pas') $cycB_nocycle
$idx3 = & $exePath index --project $dpr --db $db --library-db $lib --rule-cache-warm wait 2>&1 | Out-String
Check 'SANITY: reindex after breaking the cycle' ($LASTEXITCODE -eq 0) $idx3
Check 'C5  index --project reports that it WARMED the cache' ($idx3 -match 'rule-cache: warmed \d+ finding') (($idx3 -split "`n" | Where-Object { $_ -match 'rule-cache|WARNING' }) -join ' / ')
$c3 = LintOne 'uCycA.pas'
Check 'C3  the lint after index --project is a HIT (the indexer warmed the cache)' ((CacheState $c3.Prof) -eq 'hit') "state: $(CacheState $c3.Prof); index said: $(($idx3 -split "`n" | Where-Object { $_ -match 'rule-cache' }) -join ' / ')"
Check 'C3  ...and the broken cycle is GONE (no stale answer)' (@($c3.Rows | Where-Object rule -eq 'circular-uses').Count -eq 0) (($c3.Rows | Where-Object rule -eq 'circular-uses' | ForEach-Object message) -join ' ; ')

# --- C4: a writer that does not warm (one-file index) ----------------------------------
Write-Ascii (Join-Path $proj 'uCycB.pas') $cycB_cycle
$idx4 = & $exePath index (Join-Path $proj 'uCycB.pas') --db $db --library-db $lib 2>&1 | Out-String
Check 'SANITY: one-file reindex restoring the cycle' ($LASTEXITCODE -eq 0) $idx4
$c4 = LintOne 'uCycA.pas'
Check 'C4  after a one-file index the next run is a MISS' ((CacheState $c4.Prof) -eq 'miss') "state: $(CacheState $c4.Prof)"
Check 'C4  ...and the cycle is BACK' (@($c4.Rows | Where-Object rule -eq 'circular-uses').Count -gt 0) ""

# --- C9: a marker on the OFF, never-cached rule is still accounted ---------------------
$rtsLine = [int](@($rtsRows | Where-Object { $_.rule -eq 'repeated-type-switch' -and $_.file_path -like '*uRts.pas' })[0].start_line)
$srcLines = $rtsSrc -split "`n" | ForEach-Object { $_.TrimEnd("`r") }
$srcLines[$rtsLine - 1] = $srcLines[$rtsLine - 1] + '  // dl:ok repeated-type-switch -- fixture'
Write-Ascii (Join-Path $proj 'uRts.pas') ($srcLines -join "`n")
$probe = LintOne 'uRts.pas'
$hash = if (($probe.Rows | Where-Object rule -like 'review-marker-*' | ForEach-Object message) -join ' ' -match 'repeated-type-switch@([0-9a-f]{4})') { $Matches[1] } else { '' }
Check 'SANITY: the engine proposes a hash for the rts marker' ($hash -ne '') (($probe.Rows | Where-Object rule -like 'review-marker-*' | ForEach-Object message) -join ' ; ')
$srcLines[$rtsLine - 1] = $srcLines[$rtsLine - 1].Replace('dl:ok repeated-type-switch --', "dl:ok repeated-type-switch@$hash --")
Write-Ascii (Join-Path $proj 'uRts.pas') ($srcLines -join "`n")
$c9 = LintOne 'uRts.pas'
$mk = @($c9.Rows | Where-Object { $_.rule -in 'review-marker-unused','review-marker-stale' } | ForEach-Object { "$($_.rule):$($_.start_line) $($_.message)" })
Check 'C9  dl:ok repeated-type-switch@hash is NOT reported unused/stale' ($mk.Count -eq 0) ($mk -join ' ; ')
$cacheTxt2 = [string](CacheFiles | Select-Object -First 1 | ForEach-Object { [IO.File]::ReadAllText($_.FullName) })
Check 'C9  ...and the cache still holds no repeated-type-switch row' ($cacheTxt2 -notmatch 'repeated-type-switch') ""

Write-Host ''
if ($fail) { Write-Host 'run_lint_rule_cache: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_rule_cache: PASS' -ForegroundColor Green
exit 0
} finally {
  $env:DRAGLINT_PROFILE = $null; $env:DRAGLINT_RULE_CACHE = $null; $env:DRAGLINT_RULE_CACHE_DIR = $null
  foreach ($d23 in @("C:\TEMP\draglint_rule_cache_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
