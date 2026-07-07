<#
  run_missing_doc_fix.ps1 -- missing-doc "Fix it" (ADF Task 11c).

  missing-doc is FIXABLE but SINGLE-FIX-ONLY: a single targeted finding
  (lint-all --fix --fix-line <L> --fix-rule missing-doc) inserts the same
  DocInsight comment `document --qname` produces (a managed block); the blanket
  batch (lint-all --fix, no narrowing) EXCLUDES it (so it never injects TODO
  stubs project-wide).

  Fixture: fixtures\missingdocfix\missfix.pas
    Undocumented(Value: Integer): Integer  -- line 16, public, NO doc, has a
        param + a caller (CallsIt) -> the missing-doc finding whose Fix-it
        inserts a document-qname comment (<param name="Value">, <returns>,
        Called-from facts).
    CallsIt: Integer                       -- public, NO doc, calls Undocumented
        (Called-from source). Also a missing-doc finding, never targeted.
  No documented decl -> nothing for doc-drift to touch, so the blanket-batch
  check can assert byte-for-byte no change.

  missing-doc + doc-drift are store-backed (only run on lint-all/lint-project),
  and ship OFF by default (ADF Task 11b) -> enabled here via --config.

  Part A -- single-fix WORKS: lint-all --fix --fix-line 16 --fix-rule missing-doc
    --apply INSERTS a /// DocInsight comment with a managed block on the
    Undocumented decl (matching document --qname output).
  Part B -- IDEMPOTENT: re-index + a 2nd single-fix finds no missing-doc (the
    decl now has a doc) -> no-op.
  Part C -- batch EXCLUDES it: on a fresh copy, lint-all --fix --apply (blanket
    batch, missing-doc enabled) does NOT insert a doc-comment for the missing-doc
    case -- the file's Undocumented decl is UNCHANGED (single-fix-only excluded).
  Part D -- rules --json reports missing-doc fixable=true.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\missingdocfix\missfix.pas')).Path
$L       = 16   # the Undocumented decl line in the fixture

# ---- Part A + B: single-fix (own scratch) ---------------------------------
$scratch = Join-Path C:\TEMP 'draglint_missdocfix_single'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target  = Join-Path $scratch 'missfix.pas'
$db      = Join-Path $scratch 'missfix.sqlite'
Copy-Item $fixture $target -Force

$cfg = Join-Path $scratch 'missfix.config.json'
'{ "enabled": ["missing-doc"] }' | Set-Content -Path $cfg -Encoding ascii -NoNewline

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  # Sanity: a missing-doc finding is reported on the Undocumented line (15).
  $rawL = (& $exePath lint-all --db $db --config $cfg --json 2>$null) -join "`n"
  $aS = $rawL.IndexOf('['); $aE = $rawL.LastIndexOf(']')
  $findings = @()
  if ($aS -ge 0 -and $aE -gt $aS) { $findings = @(ConvertFrom-Json $rawL.Substring($aS, $aE - $aS + 1)) }
  $md = @($findings | Where-Object { $_.rule -eq 'missing-doc' -and $_.start_line -eq $L })
  Check 'A0 missing-doc finding present on the Undocumented line (16)' ($md.Count -ge 1)

  # --- Part A: single-fix INSERTS the document-qname comment ---
  # ADF Task 13: missing-doc ships OFF by default, so --fix must opt it in via
  # --config (the same "enabled":["missing-doc"] used for the sanity lint above) --
  # otherwise ShouldKeep drops the finding before the --fix block builds edits.
  # --fix-rule NARROWS the surviving set; it does not re-enable a disabled rule.
  & $exePath lint-all --db $db --config $cfg --fix --fix-line $L --fix-rule missing-doc --apply --no-backup 2>$null | Out-Null
  $txt = [IO.File]::ReadAllText($target)
  Check 'A1 inserted a /// DocInsight comment'          ($txt -match '///\s*<summary>')
  Check 'A2 inserted a managed drag-lint:auto block'   ($txt.Contains('<!-- drag-lint:auto BEGIN -->') -and $txt.Contains('<!-- drag-lint:auto END -->'))
  Check 'A3 comment carries <param name="Value">'      ($txt -match '///\s*<param name="Value">')
  Check 'A4 comment carries <returns>'                 ($txt -match '///\s*<returns>')
  Check 'A5 comment carries a Called-from fact (CallsIt)' ($txt -match 'Called from:.*missfix\.CallsIt')
  # the /// comment must PRECEDE the Undocumented decl (its function line moved down).
  $lines = [IO.File]::ReadAllLines($target)
  $declIx = -1
  for ($i=0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'function Undocumented\(Value: Integer\): Integer;' -and $lines[$i] -notmatch '///') { $declIx = $i; break } }
  Check 'A6 the Undocumented decl still exists after the fix' ($declIx -ge 1)
  if ($declIx -ge 1) {
    $above = ($lines[0..($declIx-1)] -join "`n")
    Check 'A7 a /// comment precedes the Undocumented decl' ($above -match '///\s*<summary>')
  }

  # --- Part B: IDEMPOTENT -- re-index, 2nd single-fix is a no-op (decl now documented) ---
  & $exePath index $scratch --db $db 2>$null | Out-Null
  $rawB = (& $exePath lint-all --db $db --config $cfg --json 2>$null) -join "`n"
  $bS = $rawB.IndexOf('['); $bE = $rawB.LastIndexOf(']')
  $findingsB = @()
  if ($bS -ge 0 -and $bE -gt $bS) { $findingsB = @(ConvertFrom-Json $rawB.Substring($bS, $bE - $bS + 1)) }
  $mdB = @($findingsB | Where-Object { $_.rule -eq 'missing-doc' -and $_.start_line -eq $L })
  Check 'B1 no missing-doc finding on the now-documented decl (idempotent)' ($mdB.Count -eq 0)
  $before2 = [IO.File]::ReadAllText($target)
  # opt missing-doc in again (OFF by default -- ADF Task 13); the decl is now
  # documented so this is a no-op regardless, but the finding must survive to reach
  # the --fix block for the no-op path to be genuinely exercised.
  & $exePath lint-all --db $db --config $cfg --fix --fix-line $L --fix-rule missing-doc --apply --no-backup 2>$null | Out-Null
  $after2 = [IO.File]::ReadAllText($target)
  Check 'B2 2nd single-fix is byte-identical (no-op)' ($before2 -eq $after2)

  # ---- Part C: blanket batch EXCLUDES missing-doc ------------------------
  $scratchB = Join-Path C:\TEMP 'draglint_missdocfix_batch'
  if (Test-Path $scratchB) { Remove-Item $scratchB -Recurse -Force }
  New-Item -ItemType Directory -Path $scratchB | Out-Null
  $targetB = Join-Path $scratchB 'missfix.pas'
  $dbB     = Join-Path $scratchB 'missfix.sqlite'
  $cfgB    = Join-Path $scratchB 'missfix.config.json'
  Copy-Item $fixture $targetB -Force
  '{ "enabled": ["missing-doc"] }' | Set-Content -Path $cfgB -Encoding ascii -NoNewline
  & $exePath index $scratchB --db $dbB 2>$null | Out-Null

  $beforeBatch = [IO.File]::ReadAllText($targetB)
  # blanket batch: --fix with NO --fix-line / --fix-rule narrowing.
  & $exePath lint-all --db $dbB --config $cfgB --fix --apply --no-backup 2>$null | Out-Null
  $afterBatch = [IO.File]::ReadAllText($targetB)
  Check 'C1 blanket batch did NOT insert a doc-comment for missing-doc' (-not ($afterBatch -match '///\s*<param name="Value">'))
  Check 'C2 Undocumented decl unchanged by the blanket batch (single-fix-only excluded)' ($beforeBatch -eq $afterBatch)

  # ---- Part D: rules --json fixable ---------------------------------------
  $rj = & $exePath rules --json 2>$null | Out-String
  $ro = $rj | ConvertFrom-Json
  $byId = @{}; foreach($r in $ro.rules){ $byId[$r.id] = $r }
  Check 'D1 missing-doc fixable=true' ($byId['missing-doc'].fixable -eq $true)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
