<#
  run_cyclefix_atomic.ps1 -- E18 Task 11: `cycles --fix --apply` writes all files or none, rolls
  back byte-identical, and verifies the result against the prediction after a child re-index.

  Needs dcc: SKIPs (exit 0) when rsvars.bat is missing. Every project copy and DB copy lives under
  %TEMP%; the platform library is used through a scratch copy only; no real _D-RAG DB is touched.
  (a) --apply --unit demogageport -> exit 0, written[] = 5 (measured: DemoUIConnect.pas,
      DemoGagePort.pas, CircularDemo.dpr, CircularDemo.dproj + the new leaf), one
      .BCK<n> backup per edited file and a recovery.txt, reindex.status = done, verified = true;
      `cycles` on the re-indexed DB copy prints 2 groups.
  (b) DRAGLINT_TEST_FAIL_WRITE_AT=3 (TextEdit.FailWriteForTests) -> exit 2, `rolled back, project
      not changed`, the tree (sources, backups, recovery.txt) byte-identical, no *.Untangle.pas,
      no .BCK file, the DB copy unchanged.
  (c) --no-reindex -> exit 0, reindex.status = skipped, verified = false, verify_reason =
      "not re-indexed", the DB copy unchanged.
  (d) (moved from Task 10 c) DRAGLINT_CYCLEFIX_BREAK=1 --apply -> one E2015 repair, compile ok.
  (e) (moved from Task 10 d) DRAGLINT_CYCLEFIX_BREAK=2 --apply --unit demoblueprint -> one E2010
      repair, compile ok.
  (f) DRAGLINT_CYCLEFIX_BREAK=3 (a break no repair covers) --apply -> exit 1, refusal
      compile-error carrying the dcc lines, the tree byte-identical, no new leaf, no .BCK.
  (g) target guard: a DIRECTORY index (not the project DB) -> the files are written and compiled,
      reindex.status = skipped with the reason, verified = false, that DB unchanged.
  (h) build timeout: DRAGLINT_CYCLEFIX_BUILD_TIMEOUT_MS=1 (test seam, project under TEMP) -> the
      baseline build is killed, exit 1, refusals[0].kind = build-timeout, nothing written.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [switch]$KeepScratch,
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-atomic-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [string]$Rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
)
# E18 T13: removes this run's scratch (WorkDir) however the run ends; kept only on failure when
# -KeepScratch is passed (the path is printed).
function Remove-Scratch {
  if ($script:Failed -and $KeepScratch) { Write-Host "scratch kept: $WorkDir" -ForegroundColor Yellow; return }
  Set-Location -LiteralPath $env:TEMP
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
trap { $script:Failed = $true; Remove-Scratch; break }

$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars) -- --apply needs dcc" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library to copy ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Demo = Join-Path $Repo 'circular-demo'
New-Item -ItemType Directory -Force $WorkDir | Out-Null
$Lib = Join-Path $WorkDir 'library-copy.sqlite'
Copy-Item $LibraryDb $Lib -Force

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}
# every file a build does not write: sources, .BCK<n> backups, recovery.txt, new leaves
function Get-TreeHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File -Recurse | Where-Object {
      $_.FullName -notmatch '\\(Win32|Win64|__history|__recovery)\\' -and
      $_.Extension -notmatch '^\.(dcu|exe|res|identcache|local|stat|dsk|map|rsm|drc)$' } |
    Sort-Object FullName | ForEach-Object { '{0}={1}' -f $_.FullName.Substring($Dir.Length), (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
function Get-FileSha([string]$Path) { return (Get-FileHash $Path -Algorithm SHA256).Hash }
function Backups([string]$Dir) { return @(Get-ChildItem $Dir -File | Where-Object { $_.Name -match '\.BCK\d+$' }) }
function New-Demo([string]$Tag) {
  $proj = Join-Path $WorkDir "$Tag-proj"
  Copy-Tree $Demo $proj
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $proj 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir "$Tag-index.log")
  return @{ Proj = $proj; Dproj = (Join-Path $proj 'CircularDemo.dproj'); Db = $db }
}
function Run-Fix([hashtable]$D, [string[]]$Extra, [hashtable]$Env = @{}, [bool]$Json = $true) {
  $errf = Join-Path $WorkDir ("stderr-{0}.txt" -f [guid]::NewGuid().ToString('N'))
  $a = @('cycles', '--fix', '--project', $D.Dproj, '--db', $D.Db, '--library-db', $Lib) + $Extra
  if ($Json) { $a += @('--format', 'json') }
  foreach ($k in $Env.Keys) { Set-Item "Env:$k" $Env[$k] }
  try {
    $out = (& $Exe @a 2>$errf | Out-String)
    $code = $LASTEXITCODE
  } finally { foreach ($k in $Env.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } }
  $err = if (Test-Path $errf) { [IO.File]::ReadAllText($errf) } else { '' }
  $j = $null
  if ($Json) { try { $j = $out | ConvertFrom-Json } catch { $j = $null } }
  return @{ Exit = $code; Out = $out; Err = $err; Json = $j }
}
function Cy($r) { if ($r.Json) { return @($r.Json.cycles)[0] } return $null }

# ---------------------------------------------------------------- (a) apply + verify
Write-Host '== (a) apply, re-index, verify' -ForegroundColor Cyan
$A = New-Demo 'a'
Check 'setup: demo indexed' (Test-Path $A.Db) ''
$r = Run-Fix $A @('--unit', 'demogageport', '--apply')
$cy = Cy $r
Check 'a: exit 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out) $($r.Err)"
Check 'a: mode = apply' ($r.Json.mode -eq 'apply') $r.Out
$written = @($cy.written)
Check 'a: written[] = 5 files (4 edited + 1 new)' ($written.Count -eq 5) ($written -join ', ')
Check 'a: the new leaf DemoGagePort.Untangle.pas is written' (@($written | Where-Object { "$_" -like '*DemoGagePort.Untangle.pas' }).Count -eq 1) ($written -join ', ')
Check 'a: the new leaf exists' (Test-Path (Join-Path $A.Proj 'DemoGagePort.Untangle.pas')) ''
Check 'a: one .BCK<n> backup per edited file (4)' ((Backups $A.Proj).Count -eq 4) ((Backups $A.Proj | ForEach-Object Name) -join ', ')
Check 'a: backups[] has 4 entries' (@($cy.backups).Count -eq 4) ($cy.backups | ConvertTo-Json -Compress)
Check 'a: recovery.txt written' (Test-Path (Join-Path $A.Proj 'recovery.txt')) ''
Check 'a: compile.status = ok' ($cy.compile.status -eq 'ok') ($cy.compile | ConvertTo-Json -Compress -Depth 4)
Check 'a: reindex.status = done' ($cy.reindex.status -eq 'done') ($cy.reindex | ConvertTo-Json -Compress)
Check 'a: verified = true' ($cy.verified -eq $true) "verified=$($cy.verified) reason=$($cy.verify_reason)`npredicted:`n$($cy.predicted)`nactual:`n$($cy.actual)"
$cyc = (& $Exe cycles --db $A.Db 2>$null | Out-String)
Check 'a: cycles on the re-indexed DB prints 2 groups' ($cyc -match '(?m)^2 circular unit group\(s\) found:') $cyc
Check 'a: ok = true, exit_code 0' (($r.Json.ok -eq $true) -and ($r.Json.exit_code -eq 0)) $r.Out

# ---------------------------------------------------------------- (b) a write failing part-way
Write-Host '== (b) write fails part-way -> byte-identical rollback' -ForegroundColor Cyan
$B = New-Demo 'b'
$hB = Get-TreeHash $B.Proj
$dbB = Get-FileSha $B.Db
$r = Run-Fix $B @('--unit', 'demogageport', '--apply') @{ DRAGLINT_TEST_FAIL_WRITE_AT = '3' }
Check 'b: exit 2' ($r.Exit -eq 2) "exit=$($r.Exit) $($r.Out)"
Check 'b: says rolled back, project not changed' ("$($r.Json.error)" -match 'rolled back, project not changed') $r.Out
$cy = Cy $r
Check 'b: refusal write-failed in the cycle' (@($cy.refusals | Where-Object { $_.kind -eq 'write-failed' }).Count -ge 1) $r.Out
Check 'b: tree byte-identical' ((Get-TreeHash $B.Proj) -eq $hB) ''
Check 'b: no .Untangle.pas left' (@(Get-ChildItem $B.Proj -Filter '*.Untangle.pas').Count -eq 0) ''
Check 'b: no .BCK left' ((Backups $B.Proj).Count -eq 0) ''
Check 'b: no recovery.txt left' (-not (Test-Path (Join-Path $B.Proj 'recovery.txt'))) ''
Check 'b: DB copy unchanged' ((Get-FileSha $B.Db) -eq $dbB) ''
$t = Run-Fix $B @('--unit', 'demogageport', '--apply') @{ DRAGLINT_TEST_FAIL_WRITE_AT = '3' } -Json $false
Check 'b: text run: exit 2 and the rollback line' (($t.Exit -eq 2) -and $t.Out.Contains('rolled back, project not changed')) $t.Out
Check 'b: text run: tree still byte-identical' ((Get-TreeHash $B.Proj) -eq $hB) ''

# ---------------------------------------------------------------- (c) --no-reindex
Write-Host '== (c) --no-reindex' -ForegroundColor Cyan
$C = New-Demo 'c'
$dbC = Get-FileSha $C.Db
$r = Run-Fix $C @('--unit', 'demogageport', '--apply', '--no-reindex')
$cy = Cy $r
Check 'c: exit 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
Check 'c: reindex.status = skipped' ($cy.reindex.status -eq 'skipped') ($cy.reindex | ConvertTo-Json -Compress)
Check 'c: verified = false, reason not re-indexed' (($cy.verified -eq $false) -and ($cy.verify_reason -eq 'not re-indexed')) "verified=$($cy.verified) reason=$($cy.verify_reason)"
Check 'c: the files are written' (@($cy.written).Count -eq 5) ''
Check 'c: DB copy unchanged' ((Get-FileSha $C.Db) -eq $dbC) ''

# ---------------------------------------------------------------- (d)/(e) BREAK seams on --apply (moved from Task 10)
foreach ($c in @(@('d', 'demogageport', '1', 'E2015'), @('e', 'demoblueprint', '2', 'E2010'))) {
  Write-Host "== ($($c[0])) BREAK=$($c[2]) --apply -> R4 $($c[3])" -ForegroundColor Cyan
  $X = New-Demo $c[0]
  $r = Run-Fix $X @('--unit', $c[1], '--apply', '--no-reindex') @{ DRAGLINT_CYCLEFIX_BREAK = $c[2] }
  $cy = Cy $r
  Check "$($c[0]): exit 0" ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out) $($r.Err)"
  Check "$($c[0]): stderr announces TEST BREAK active" ($r.Err.Contains('TEST BREAK active')) $r.Err
  Check "$($c[0]): compile.status = ok, two builds" (($cy.compile.status -eq 'ok') -and ($cy.compile.builds -eq 2)) ($cy.compile | ConvertTo-Json -Compress -Depth 4)
  Check "$($c[0]): repairs[0].code = $($c[3])" ((@($cy.repairs).Count -ge 1) -and (@($cy.repairs)[0].code -eq $c[3])) ($cy.repairs | ConvertTo-Json -Compress)
}

# ---------------------------------------------------------------- (f) compile error -> rollback
Write-Host '== (f) unrepairable compile error -> rollback' -ForegroundColor Cyan
$F = New-Demo 'f'
$hF = Get-TreeHash $F.Proj
$dbF = Get-FileSha $F.Db
$r = Run-Fix $F @('--unit', 'demogageport', '--apply') @{ DRAGLINT_CYCLEFIX_BREAK = '3' }
$cy = Cy $r
Check 'f: exit 1' ($r.Exit -eq 1) "exit=$($r.Exit) $($r.Out) $($r.Err)"
$ce = @($cy.refusals | Where-Object { $_.kind -eq 'compile-error' })
Check 'f: refusal compile-error' ($ce.Count -eq 1) ($cy.refusals | ConvertTo-Json -Compress)
Check 'f: compile.status = error with the dcc lines' (($cy.compile.status -eq 'error') -and (@($cy.compile.errors).Count -ge 1) -and (@($cy.compile.errors)[0].code -match '^[EF]\d{4}$')) ($cy.compile | ConvertTo-Json -Compress -Depth 4)
Check 'f: no repair was made' (@($cy.repairs).Count -eq 0) ($cy.repairs | ConvertTo-Json -Compress)
Check 'f: rolled_back = true' ($cy.rolled_back -eq $true) ''
Check 'f: tree byte-identical' ((Get-TreeHash $F.Proj) -eq $hF) ''
Check 'f: no new leaf, no .BCK, no recovery.txt' ((@(Get-ChildItem $F.Proj -Filter '*.Untangle.pas').Count -eq 0) -and ((Backups $F.Proj).Count -eq 0) -and
  -not (Test-Path (Join-Path $F.Proj 'recovery.txt'))) ''
Check 'f: DB copy unchanged' ((Get-FileSha $F.Db) -eq $dbF) ''

# ---------------------------------------------------------------- (g) target guard
Write-Host '== (g) re-index target guard' -ForegroundColor Cyan
$G = @{ Proj = (Join-Path $WorkDir 'g-proj'); Db = (Join-Path $WorkDir 'g-dir.sqlite') }
Copy-Tree $Demo $G.Proj
$G.Dproj = Join-Path $G.Proj 'CircularDemo.dproj'
& $Exe index $G.Proj --db $G.Db *> (Join-Path $WorkDir 'g-index.log')
$dbG = Get-FileSha $G.Db
$r = Run-Fix $G @('--unit', 'demogageport', '--apply')
$cy = Cy $r
Check 'g: the plan was applied (compile ok)' ($cy.compile.status -eq 'ok') "exit=$($r.Exit) $($r.Out)"
Check 'g: reindex.status = skipped, reason names the project index rule' (($cy.reindex.status -eq 'skipped') -and ("$($cy.reindex.reason)" -match 'project index')) ($cy.reindex | ConvertTo-Json -Compress)
Check 'g: verified = false' ($cy.verified -eq $false) ''
Check 'g: the directory DB is unchanged' ((Get-FileSha $G.Db) -eq $dbG) ''

# ---------------------------------------------------------------- (i) mtimes + BOM restored (fix round 1)
Write-Host '== (i) rollback restores bytes AND mtimes (BOM file, pre-existing recovery.txt)' -ForegroundColor Cyan
function Get-TreeStamps([string]$Dir) {
  return ((Get-ChildItem $Dir -File -Recurse | Where-Object {
      $_.FullName -notmatch '\\(Win32|Win64|__history|__recovery)\\' -and
      $_.Extension -notmatch '^\.(dcu|exe|res|identcache|local|stat|dsk|map|rsm|drc)$' } |
    Sort-Object FullName | ForEach-Object { '{0}={1}@{2}' -f $_.FullName.Substring($Dir.Length), (Get-FileHash $_.FullName -Algorithm SHA256).Hash, $_.LastWriteTimeUtc.Ticks }) -join ';')
}
function New-BomDemo([string]$Tag) {
  $proj = Join-Path $WorkDir "$Tag-proj"
  Copy-Tree $Demo $proj
  $gp = Join-Path $proj 'DemoGagePort.pas'
  [IO.File]::WriteAllBytes($gp, [byte[]](0xEF, 0xBB, 0xBF) + [IO.File]::ReadAllBytes($gp))
  $rec = Join-Path $proj 'recovery.txt'
  [IO.File]::WriteAllText($rec, "[2020-01-01 00:00:00] an earlier run`r`n", [Text.Encoding]::ASCII)
  foreach ($f in Get-ChildItem $proj -File) { $f.LastWriteTimeUtc = [datetime]::new(2021, 3, 4, 5, 6, 7, [DateTimeKind]::Utc) }
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project (Join-Path $proj 'CircularDemo.dproj') --db $db *> (Join-Path $WorkDir "$Tag-index.log")
  return @{ Proj = $proj; Dproj = (Join-Path $proj 'CircularDemo.dproj'); Db = $db }
}
$I = New-BomDemo 'i'
$sI = Get-TreeStamps $I.Proj
$r = Run-Fix $I @('--unit', 'demogageport', '--apply') @{ DRAGLINT_CYCLEFIX_BREAK = '3' }
$cy = Cy $r
Check 'i: compile-error rollback, exit 1' (($r.Exit -eq 1) -and ($cy.rolled_back -eq $true) -and (@($cy.written) -like '*DemoGagePort.pas').Count -eq 1) "exit=$($r.Exit) $($r.Out)"
Check 'i: bytes AND mtimes of every file (BOM unit, recovery.txt) restored' ((Get-TreeStamps $I.Proj) -eq $sI) ''
Check 'i: DemoGagePort.pas still starts with the UTF-8 BOM' ((@([IO.File]::ReadAllBytes((Join-Path $I.Proj 'DemoGagePort.pas'))[0..2]) -join ',') -eq '239,187,191') ''

# ---------------------------------------------------------------- (j) a raise after the write (fix round 1)
Write-Host '== (j) an exception after the write -> rollback, exit 2' -ForegroundColor Cyan
$J = New-BomDemo 'j'
$sJ = Get-TreeStamps $J.Proj
$dbJ = Get-FileSha $J.Db
$r = Run-Fix $J @('--unit', 'demogageport', '--apply') @{ DRAGLINT_CYCLEFIX_BREAK = '4' }
$cy = Cy $r
Check 'j: exit 2' ($r.Exit -eq 2) "exit=$($r.Exit) $($r.Out) $($r.Err)"
Check 'j: error says rolled back, project not changed' ("$($r.Json.error)" -match 'rolled back, project not changed') $r.Out
Check 'j: refusal build-error carrying the exception message' (@($cy.refusals | Where-Object { ($_.kind -eq 'build-error') -and ("$($_.reason)" -match 'TEST BREAK 4') }).Count -eq 1) ($cy.refusals | ConvertTo-Json -Compress)
Check 'j: rolled_back = true' ($cy.rolled_back -eq $true) ''
Check 'j: bytes AND mtimes of every file restored' ((Get-TreeStamps $J.Proj) -eq $sJ) ''
Check 'j: DB copy unchanged' ((Get-FileSha $J.Db) -eq $dbJ) ''

# ---------------------------------------------------------------- (k) the write-failure seam is TEMP-only (fix round 1)
Write-Host '== (k) DRAGLINT_TEST_FAIL_WRITE_AT ignored outside TEMP' -ForegroundColor Cyan
$outRoot = Join-Path $env:LOCALAPPDATA "drag-lint-cyclefix-atomic-$PID"
try {
  $kp = Join-Path $outRoot 'k-proj'
  Copy-Tree $Demo $kp
  $K = @{ Proj = $kp; Dproj = (Join-Path $kp 'CircularDemo.dproj'); Db = (Join-Path $outRoot 'k.sqlite') }
  & $Exe index --project $K.Dproj --db $K.Db *> (Join-Path $WorkDir 'k-index.log')
  $r = Run-Fix $K @('--unit', 'demogageport', '--apply', '--no-reindex') @{ DRAGLINT_TEST_FAIL_WRITE_AT = '1' }
  Check 'k: outside TEMP the seam is ignored: exit 0, 5 files written' (($r.Exit -eq 0) -and (@((Cy $r).written).Count -eq 5)) "exit=$($r.Exit) $($r.Out)"
} finally {
  if (Test-Path $outRoot) { [IO.Directory]::Delete($outRoot, $true) }
}

# ---------------------------------------------------------------- (h) build timeout
Write-Host '== (h) build timeout' -ForegroundColor Cyan
$H = New-Demo 'h'
$hH = Get-TreeHash $H.Proj
$r = Run-Fix $H @('--unit', 'demogageport', '--apply') @{ DRAGLINT_CYCLEFIX_BUILD_TIMEOUT_MS = '1' }
Check 'h: exit 1' ($r.Exit -eq 1) "exit=$($r.Exit) $($r.Out)"
Check 'h: refusals[0].kind = build-timeout' (@($r.Json.refusals)[0].kind -eq 'build-timeout') $r.Out
Check 'h: stderr announces the timeout seam' ($r.Err.Contains('TEST BUILD TIMEOUT active')) $r.Err
Check 'h: nothing written' ((Get-TreeHash $H.Proj) -eq $hH) ''

Write-Host ''
Remove-Scratch
if ($script:Failed) { Write-Host "FAILED ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS ($script:Passed)" -ForegroundColor Green
exit 0
