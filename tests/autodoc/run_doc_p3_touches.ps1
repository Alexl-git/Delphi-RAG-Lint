<#
  run_doc_p3_touches.ps1 -- Auto-Document Phase 3, Task 13:
  the Touches:/Transaction: facts, and the 'Effect-free (proven)' line.

  CATEGORIES, NOT CALL SITES. 'Touches: file system' says what class of external
  surface the routine reaches, not which method it called -- the call site is
  already in 'Calls:'. Stored as 'resources|transactions' in ONE column; either
  side may be empty, and assertion 5 pins that exact wire format so a later
  reader cannot quietly change it.

  MATCH SHAPE IS PART OF THE RULE, not just the name. The curated lists are
  matched by the SHAPE the name is used in, because a bare name match would lie:
    TFile / TRegistry / THTTPClient ...  a TYPE receiver -- matched anywhere
    AssignFile / Rewrite / Reset / ...   a bare CALL ENTITY, and only WITH
                                         arguments (so a user's own parameterless
                                         `Reset;` is not read as the intrinsic)
    StartTransaction / Commit / ...      a DOT MEMBER name only
  Without that discipline a method named Reset or Commit -- both extremely
  common -- would manufacture a false "file system" or "Transaction:" claim.

  THE EFFECT LINE IS A POSITIVE CLAIM. Purity v2 (2026-09-22) replaced the
  render-time `Pure` guess -- derived from these same facts being empty, so it
  could never see past the routine's own body -- with 'Effect-free (proven)',
  read from symbol_facts.effect_free, which the `purity` resolve stage proves
  interprocedurally by translating every callee's summary through the caller's
  arguments. Its ABSENCE is no longer a claim of any kind. Assertion 4 is what
  keeps it honest, by proving a routine WITH a detected effect never gets it;
  assertion 3 is the positive control, without which 4 would pass on a gate
  that fires for nobody.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\touches.pas')).Path

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

function Get-BlockAbove([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return '' }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($j = $idx - 1; $j -ge 0; $j--) {
    if ($lines[$j] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$j].Trim())
  }
  return [string]::Join("`n", $acc.ToArray())
}

# The text after "<label>: " on its own fact line, or '' when the label is absent.
function Get-FactLine([string]$block, [string]$label) {
  foreach ($l in ($block -split "`n")) {
    $t = ($l -replace '^\s*///\s?','' -replace '</?para>','').Trim()
    if ($t -match "^$label`: (.*)$") { return $Matches[1].Trim() }
  }
  return ''
}

# True when the block carries a standalone 'Effect-free (proven)' fact line.
# Anchored on the WHOLE line: the label must never be matched inside another
# line's prose.
function Test-HasEffectFree([string]$block) {
  foreach ($l in ($block -split "`n")) {
    if ((($l -replace '^\s*///\s?','' -replace '</?para>','').Trim()) -eq 'Effect-free (proven)') { return $true }
  }
  return $false
}
# The retired label. Kept as its own probe so assertion 3b can state that the
# rename really happened, rather than leaving "no Pure anywhere" to be inferred
# from Test-HasEffectFree passing.
function Test-HasLegacyPure([string]$block) {
  foreach ($l in ($block -split "`n")) {
    if ((($l -replace '^\s*///\s?','' -replace '</?para>','').Trim()) -eq 'Pure') { return $true }
  }
  return $false
}

function Get-StoredTouches([string]$db, [string]$name) {
  $py = @"
import sqlite3
c = sqlite3.connect(r'$db')
r = c.execute('''SELECT f.touches FROM symbols s
                 JOIN symbol_facts f ON f.symbol_id = s.id
                 WHERE s.name = ?''', ('$name',)).fetchall()
if not r: print('<norow>')
else: print('<null>' if r[0][0] is None else '[' + r[0][0] + ']')
"@
  return ((python -c $py 2>&1) -join ' ').Trim()
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== touches.pas -- Touches:/Transaction: + Effect-free (proven) ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_touches'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'touches.pas'
$db  = Join-Path $sc 't.sqlite'
Copy-Item $fx $tgt -Force

& $exePath index $sc --db $db 2>$null | Out-Null
Check 'index exits 0' ($LASTEXITCODE -eq 0)

& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check 'apply exits 0' ($LASTEXITCODE -eq 0)
$md5Cycle1 = Get-FileMd5 $tgt
& $exePath index $sc --db $db 2>$null | Out-Null

$lines   = [IO.File]::ReadAllLines($tgt)
$blkRead = Get-BlockAbove $lines '^function ReadConfig\(const APath: string\): string;'
$blkTxn  = Get-BlockAbove $lines '^procedure RunTxn\(ATxn: TTxn\);'
$blkAdd  = Get-BlockAbove $lines '^function AddUp\(A, B: Integer\): Integer;'
Check 'de-vacuator: ReadConfig got a doc block' ($blkRead -ne '') ''
Check 'de-vacuator: RunTxn got a doc block'     ($blkTxn  -ne '') ''
Check 'de-vacuator: AddUp got a doc block'      ($blkAdd  -ne '') ''

# --- (1) resource category. -------------------------------------------------
$touch = Get-FactLine $blkRead 'Touches'
Check '1. ReadConfig renders "Touches: file system"' ($touch -eq 'file system') `
  ("got=[$touch] block=" + ($blkRead -replace "`n",' | '))
Check '1. and claims neither registry nor network' `
  (-not ($touch -match 'registry|network')) "got=[$touch]"

# --- (2) transaction verbs, in the fixed order. -----------------------------
$txn = Get-FactLine $blkTxn 'Transaction'
Check '2. RunTxn renders "Transaction: starts, commits"' ($txn -eq 'starts, commits') `
  ("got=[$txn] block=" + ($blkTxn -replace "`n",' | '))

# --- (3) the effect line, on a routine the stage proved effect-free. --------
Check '3. AddUp renders the Effect-free (proven) line' (Test-HasEffectFree $blkAdd) `
  ("block=" + ($blkAdd -replace "`n",' | '))
Check '3b. AddUp does NOT render the retired Pure line' (-not (Test-HasLegacyPure $blkAdd)) `
  ("block=" + ($blkAdd -replace "`n",' | '))
Check '3. AddUp has no Touches: line'     ((Get-FactLine $blkAdd 'Touches')     -eq '') ''
Check '3. AddUp has no Transaction: line' ((Get-FactLine $blkAdd 'Transaction') -eq '') ''

# --- (4) THE HONESTY CHECK: a routine WITH an effect is never effect-free. --
Check '4. ReadConfig is NOT effect-free (it touches the file system)' (-not (Test-HasEffectFree $blkRead)) `
  ("block=" + ($blkRead -replace "`n",' | '))
Check '4. RunTxn is NOT effect-free (it drives a transaction)' (-not (Test-HasEffectFree $blkTxn)) `
  ("block=" + ($blkTxn -replace "`n",' | '))

# --- (5) the wire format, pinned. -------------------------------------------
$storedRead = Get-StoredTouches $db 'ReadConfig'
$storedTxn  = Get-StoredTouches $db 'RunTxn'
$storedAdd  = Get-StoredTouches $db 'AddUp'
Check '5. symbol_facts.touches for ReadConfig is exactly "file system|"' ($storedRead -eq '[file system|]') "got=$storedRead"
Check '5. symbol_facts.touches for RunTxn is exactly "|starts, commits"' ($storedTxn -eq '[|starts, commits]') "got=$storedTxn"
Check '5. symbol_facts.touches for AddUp is empty or NULL' `
  (($storedAdd -eq '[]') -or ($storedAdd -eq '<null>') -or ($storedAdd -eq '<norow>')) "got=$storedAdd"

# --- (6) idempotency. -------------------------------------------------------
& $exePath document --unit $tgt --db $db --apply 2>$null | Out-Null
Check '6. a second apply after a reindex is byte-identical' `
  ((Get-FileMd5 $tgt) -eq $md5Cycle1) ("c1=$md5Cycle1 c2=" + (Get-FileMd5 $tgt))

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
