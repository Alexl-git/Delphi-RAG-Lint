<#
  run_doc_p3_mutates.ps1 -- Auto-Document Phase 3, Task 11:
  the `Mutates:` fact -- var/out parameters the routine writes through.

  Closes the Phase-2 T4 deferred gap: that task classified FIELD reads/writes
  only, so a procedure whose entire job is to fill an `out` parameter reported
  nothing at all.

  WHAT COUNTS AS A MUTATION, and what deliberately does not. The walk mirrors
  AnalyzeReadsWrites' node-shape rules over the SAME body node (no second parse):

    AList := X          bare-identifier assignment LHS   -> MUTATION
    AList[0] := X       indexed LHS, bare-identifier base -> MUTATION
    Inc(AList) / Dec()  mutating intrinsic, first arg     -> MUTATION
    SetLength(AList, N) an ordinary call's var argument   -> NOT DETECTED
    AObj.Field := X     a dot LHS                         -> NOT DETECTED

  The last two are absence-over-a-wrong-fact, the same stance AnalyzeReadsWrites
  takes: resolving whether an arbitrary callee's parameter is var/out is the
  cross-referenced work Phase 2 explicitly declined, and a dot LHS mutates the
  POINTEE, which for a class-typed parameter is not the parameter. THE FIXTURE
  CARRIES `SetLength(AList, AConst)` ON PURPOSE, immediately above a real
  indexed write: if the SetLength form is ever taught to the walk, this file
  already contains the case, and until then assertion 1 proves the `var` arm is
  carried by the indexed write rather than by an undetected SetLength.

  A VALUE parameter must NEVER appear -- assertion 3. Without it the walk could
  "pass" by reporting every assigned identifier, which is the failure mode that
  would make the fact useless in real code.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\mutates.pas')).Path

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

function Get-DeclLine([string]$db, [string]$name) {
  $j = (& $exePath query --name $name --db $db --json 2>$null) -join "`n"
  $o = $null; try { $o = ($j | ConvertFrom-Json) } catch { return 0 }
  if ($null -eq $o) { return 0 }
  foreach ($r in @($o)) { if ($r.section -eq 'interface') { return [int]$r.start_line } }
  return 0
}

function Get-DocBlockAtLine([string[]]$lines, [int]$declLine1) {
  $i = $declLine1 - 2
  if ($i -lt 0) { return '' }
  if ($lines[$i].Trim() -eq '') { $i-- }
  $acc = New-Object System.Collections.Generic.List[string]
  for (; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i].Trim())
  }
  return [string]::Join("`n", $acc.ToArray())
}

function Get-Block([string]$db, [string]$path, [string]$name) {
  return (Get-DocBlockAtLine ([IO.File]::ReadAllLines($path)) (Get-DeclLine $db $name))
}

# The 'Mutates: ...' line out of a doc block, /// stripped, or '' when absent.
function Get-MutatesLine([string]$block) {
  foreach ($l in ($block -split "`n")) {
    $t = ($l -replace '^\s*///\s?','' -replace '</?para>','')
    if ($t -match '^\s*Mutates:\s*(.*)$') { return $Matches[1].Trim() }
  }
  return ''
}

# symbol_facts.mutates_params for the routine named $name, read straight out of
# the DB. '<null>' when the column is NULL, '<norow>' when there is no facts row.
function Get-StoredMutates([string]$db, [string]$name) {
  $py = @"
import sqlite3, sys
c = sqlite3.connect(r'$db')
r = c.execute('''SELECT f.mutates_params FROM symbols s
                 LEFT JOIN symbol_facts f ON f.symbol_id = s.id
                 WHERE s.name = ? AND f.symbol_id IS NOT NULL''', ('$name',)).fetchall()
if not r: print('<norow>')
else: print('<null>' if r[0][0] is None else r[0][0])
"@
  return ((python -c $py 2>&1) -join ' ').Trim()
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== mutates.pas -- the Mutates: fact ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_mutates'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'mutates.pas'
$db  = Join-Path $sc 'm.sqlite'
Copy-Item $fx $tgt -Force

& $exePath index $sc --db $db 2>$null | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# PRECONDITIONS -- the fixture still carries the three parameter modes and both
# write forms the assertions below are about.
$pre = [IO.File]::ReadAllLines($tgt)
Check 'PRECONDITION: FillBoth declares one var, one out and one value parameter' `
  (@($pre | Where-Object { $_ -match 'procedure FillBoth\(var AList: TArray<Integer>; out AReason: string; AConst: Integer\)' }).Count -eq 2) ''
Check 'PRECONDITION: the body carries BOTH the SetLength form and a real indexed write' `
  ((@($pre | Where-Object { $_ -match 'SetLength\(AList, AConst\);' }).Count -eq 1) -and
   (@($pre | Where-Object { $_ -match 'AList\[0\] := AConst;' }).Count -eq 1)) ''

& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check 'apply exits 0' ($LASTEXITCODE -eq 0)
$md5Cycle1 = Get-FileMd5 $tgt
& $exePath index $sc --db $db 2>$null | Out-Null

$blkFill = Get-Block $db $tgt 'FillBoth'
$blkPure = Get-Block $db $tgt 'PureAdd'
Check 'de-vacuator: FillBoth got a doc block at all' ($blkFill -ne '') ''
Check 'de-vacuator: PureAdd got a doc block at all (so "no Mutates line" is a real absence)' `
  ($blkPure -ne '') ''

# --- (1) both the var and the out parameter, order-insensitive. -------------
$mut = Get-MutatesLine $blkFill
Check '1. FillBoth renders a Mutates: line' ($mut -ne '') ("block=" + ($blkFill -replace "`n",' | '))
Check '1. Mutates: names the OUT parameter as "AReason (out)"' ($mut -match 'AReason \(out\)') "got=[$mut]"
Check '1. Mutates: names the VAR parameter as "AList (var)"'   ($mut -match 'AList \(var\)')   "got=[$mut]"

# --- (2) a routine that mutates nothing gets no line. -----------------------
Check '2. PureAdd has NO Mutates: line' ((Get-MutatesLine $blkPure) -eq '') `
  ("block=" + ($blkPure -replace "`n",' | '))

# --- (3) the value parameter never appears, anywhere. -----------------------
$allMut = @()
foreach ($n in @('FillBoth','PureAdd','Driver')) { $allMut += (Get-MutatesLine (Get-Block $db $tgt $n)) }
Check '3. the value parameter AConst appears in NO Mutates: line' `
  (-not (($allMut -join ' ') -match '\bAConst\b')) ("lines=[" + ($allMut -join '] [') + "]")

# --- (4) the column itself, read straight out of the DB. --------------------
$storedFill = Get-StoredMutates $db 'FillBoth'
$storedPure = Get-StoredMutates $db 'PureAdd'
Check '4. symbol_facts.mutates_params is non-empty for FillBoth' `
  (($storedFill -ne '') -and ($storedFill -ne '<null>') -and ($storedFill -ne '<norow>')) "got=[$storedFill]"
Check '4. symbol_facts.mutates_params is empty or NULL for PureAdd' `
  (($storedPure -eq '') -or ($storedPure -eq '<null>') -or ($storedPure -eq '<norow>')) "got=[$storedPure]"

# --- (5) idempotency. -------------------------------------------------------
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check '5. a second apply after a reindex is byte-identical' `
  ((Get-FileMd5 $tgt) -eq $md5Cycle1) ("c1=$md5Cycle1 c2=" + (Get-FileMd5 $tgt))
Check '5. the Mutates: line survived the second apply' `
  ((Get-MutatesLine (Get-Block $db $tgt 'FillBoth')) -ne '') ''

# --- ENCODING. --------------------------------------------------------------
$bytes = [IO.File]::ReadAllBytes($tgt)
Check 'ENCODING: the applied file is strict 7-bit ASCII' `
  (@($bytes | Where-Object { $_ -ge 128 }).Count -eq 0) ''
Check 'ENCODING: the applied file has no bare LF (CRLF throughout)' `
  (([regex]::Matches([IO.File]::ReadAllText($tgt), "(?<!`r)`n")).Count -eq 0) ''

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
