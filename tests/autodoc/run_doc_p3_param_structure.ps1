<#
  run_doc_p3_param_structure.ps1 -- PHASE A3 (rulings D-3, D-4) and PHASE A4.

  THE CONTRADICTION THIS CLOSES
  -----------------------------
  docs\INBOX-datacopy-2026-08-06-...-doc-lint-defects.md, section 3. `document`
  never wrote a <param> tag -- deliberately, on the ground that no harvester for
  param descriptions existed -- while `doc-drift` reported those same tags as
  missing. 22 findings on one corpus that no command in the tool could clear:
  the two halves could never converge.

  RULING D-3 -- STRUCTURE ALWAYS, MEANING ONLY WHERE THE CODE CARRIES IT. An
  automatic generator supplies structure, not meaning. So every signature
  parameter now gets a <param name="..."> tag; its BODY is filled only from a
  comment sitting beside that parameter INSIDE the parameter list, which is the
  one place the source actually states what the parameter means.

  RULING D-4 -- TWO PARTS, TWO RULES. Structure is regenerated on every run;
  a hand-written meaning is never overwritten. `Kept` is the control for that,
  and it is asserted across TWO applies, because "not overwritten" is a claim
  about the second run, not the first.

  PHASE A4 -- and doc-drift must then ACCEPT the generated form. A present tag
  satisfies "has a tag" whether or not it has a body; a MISSING tag is still
  reported. Without this the A3 change would merely reword the 22 findings
  instead of clearing them, so the drift half is asserted here, in the same
  runner, against the same file.

  NON-VACUITY. The drift assertions run against a file that really was
  documented (asserted first) and the rule is shown to still FIRE for a param
  that genuinely has no tag -- otherwise "no findings" would be indistinguishable
  from a rule that was switched off.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\paramdoc.pas')).Path

# ---------------------------------------------------------------------------
# Helpers. Standalone by convention -- every runner in this directory carries
# its own copies rather than dot-sourcing a shared module.
# ---------------------------------------------------------------------------

function Get-FileMd5([string]$p) { (Get-FileHash -Algorithm MD5 -Path $p).Hash }

# The contiguous run of ///-prefixed lines immediately above the first line
# matching $declRx. Located by TEXT so the runner never has to ask the index
# where a declaration moved to after an apply.
function Get-DocBlockAbove([string[]]$lines, [string]$declRx) {
  $d = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declRx) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($i = $d - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i].Trim())
  }
  return [string]::Join("`n", $acc.ToArray())
}

# The body of <param name="$name"> in $block with the provenance marker
# stripped, whitespace collapsed. Returns $null when the TAG IS ABSENT --
# distinct from '' , which means the tag is present and empty. That distinction
# is the entire point of ruling D-3, so the helper must not blur it.
function Get-ParamBody([string]$block, [string]$name) {
  $flat = ($block -split "`n" | ForEach-Object { $_ -replace '^\s*///\s?','' }) -join ' '
  $m = [regex]::Match($flat, '<param\s+name="' + [regex]::Escape($name) + '">([\s\S]*?)</param>')
  if (-not $m.Success) { return $null }
  $b = $m.Groups[1].Value -replace '<!--\s*drag-lint:auto[^>]*-->',''
  return ($b -replace '\s+',' ').Trim()
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== paramdoc.pas, document --unit --apply ===' -ForegroundColor Cyan

$sc = Join-Path C:\TEMP 'draglint_docp3_paramdoc'
if (Test-Path $sc) { Remove-Item $sc -Recurse -Force }
New-Item -ItemType Directory -Path $sc | Out-Null
$tgt = Join-Path $sc 'paramdoc.pas'
$db  = Join-Path $sc 'p.sqlite'
Copy-Item $fx $tgt -Force

& $exePath index $sc --db $db 2>$null | Out-Null

# --- PRECONDITIONS ----------------------------------------------------------
$pre = [IO.File]::ReadAllLines($tgt)
Check 'PRECONDITION: the only /// lines in the fixture are Kept''s hand-written pair' `
  (@($pre | Where-Object { $_ -match '^\s*///' }).Count -eq 2) `
  ("count=" + @($pre | Where-Object { $_ -match '^\s*///' }).Count)
Check 'PRECONDITION: the parameter-list comments the harvest reads are present in the source' `
  ((@($pre | Where-Object { $_ -match '\{ how many times to repeat \}' }).Count -eq 1) -and
   (@($pre | Where-Object { $_ -match '\{ the label shown to the user \}' }).Count -eq 1)) ''

# ===========================================================================
# APPLY (cycle 1)
# ===========================================================================
& $exePath document --unit $tgt --db $db --apply --no-backup 2>$null | Out-Null
$md5Cycle1 = Get-FileMd5 $tgt
$lines = [IO.File]::ReadAllLines($tgt)

$blkPlain   = Get-DocBlockAbove $lines '^function Plain\('
$blkNoted   = Get-DocBlockAbove $lines '^function Noted\('
$blkGrouped = Get-DocBlockAbove $lines '^function Grouped\('
$blkKept    = Get-DocBlockAbove $lines '^function Kept\('

foreach ($p in @(@{N='Plain';B=$blkPlain}, @{N='Noted';B=$blkNoted}, @{N='Grouped';B=$blkGrouped}, @{N='Kept';B=$blkKept})) {
  Check ("de-vacuator: {0} rendered a doc block at all" -f $p.N) ($p.B -match '///') ($p.B -replace "`n",' | ')
}

# --- (1) D-3 STRUCTURE: every signature param gets a tag. -------------------
# Reaffirmed by the user 2026-08-09: "Autodocument has to produce the param
# section among other things if it does not reflect the correct situation.
# Warnings and errors is what Linter produces." <param> is structural -- it
# mirrors the signature -- and is NOT one of the "empty sections are omitted"
# cases (those are <summary>/<returns>, which carry prose and nothing else).
Check 'D-3 STRUCTURE: Plain''s undocumented params BOTH get a <param> tag' `
  (($null -ne (Get-ParamBody $blkPlain 'AFirst')) -and ($null -ne (Get-ParamBody $blkPlain 'ASecond'))) `
  ($blkPlain -replace "`n",' | ')
Check 'D-3 STRUCTURE: ... and their bodies are EMPTY -- structure is not meaning' `
  (((Get-ParamBody $blkPlain 'AFirst') -eq '') -and ((Get-ParamBody $blkPlain 'ASecond') -eq '')) `
  ("first=[" + (Get-ParamBody $blkPlain 'AFirst') + "] second=[" + (Get-ParamBody $blkPlain 'ASecond') + "]")

# --- (2) D-3 MEANING: harvested from the parameter list. --------------------
Check 'D-3 MEANING: AFirst''s body is the comment beside it in the parameter list' `
  ((Get-ParamBody $blkNoted 'AFirst') -eq 'how many times to repeat') `
  ("got=[" + (Get-ParamBody $blkNoted 'AFirst') + "]")
Check 'D-3 MEANING: ASecond''s body is ITS OWN comment, not AFirst''s' `
  ((Get-ParamBody $blkNoted 'ASecond') -eq 'the label shown to the user') `
  ("got=[" + (Get-ParamBody $blkNoted 'ASecond') + "]")

# A comment beside one name in a shared-type group belongs to that name; the
# comment after the type belongs to the group.
Check 'D-3 MEANING: a comment beside ONE name of a group is that name''s' `
  ((Get-ParamBody $blkGrouped 'ALeft') -eq 'the left edge') `
  ("got=[" + (Get-ParamBody $blkGrouped 'ALeft') + "]")
Check 'D-3 MEANING: the group''s post-type comment covers the name that has none of its own' `
  ((Get-ParamBody $blkGrouped 'ARight') -eq 'a coordinate, in pixels') `
  ("got=[" + (Get-ParamBody $blkGrouped 'ARight') + "]")

# --- (3) D-4: hand-written meaning survives. --------------------------------
Check 'D-4: a hand-written <param> body is preserved on the first apply' `
  ((Get-ParamBody $blkKept 'AKept') -eq 'Hand-written meaning that must survive every re-run.') `
  ("got=[" + (Get-ParamBody $blkKept 'AKept') + "]")

# ===========================================================================
# APPLY (cycle 2) -- "never overwritten" is a claim about the SECOND run.
# ===========================================================================
& $exePath index $sc --db $db 2>$null | Out-Null
& $exePath document --unit $tgt --db $db --apply --no-backup 2>$null | Out-Null
$md5Cycle2 = Get-FileMd5 $tgt
Check 'IDEMPOTENT: a second --apply after a reindex is byte-identical' ($md5Cycle1 -eq $md5Cycle2) `
  "md5_1=$md5Cycle1 md5_2=$md5Cycle2"

$lines2   = [IO.File]::ReadAllLines($tgt)
$blkKept2 = Get-DocBlockAbove $lines2 '^function Kept\('
Check 'D-4: the hand-written body is STILL untouched after a second apply' `
  ((Get-ParamBody $blkKept2 'AKept') -eq 'Hand-written meaning that must survive every re-run.') `
  ("got=[" + (Get-ParamBody $blkKept2 'AKept') + "]")
Check 'D-4 (de-vacuator): the hand-written summary beside it also survived' `
  ($blkKept2 -match 'Hand-written, and authoritative\.') ($blkKept2 -replace "`n",' | ')

# ===========================================================================
# PHASE A4 -- doc-drift must accept the generated form.
# ===========================================================================
$drift = (& $exePath lint-all $sc --db $db --rule doc-drift 2>&1) | ForEach-Object { "$_" }
$missing = @($drift | Where-Object { $_ -match 'has no <param> tag' })
Check 'A4: doc-drift reports NO "has no <param> tag" for a file document just wrote' `
  ($missing.Count -eq 0) (($missing | Select-Object -First 5) -join ' | ')

# ... and the rule is not simply switched off. A param added to the SIGNATURE
# after the fact has no tag, and that must still be reported.
$extra = [IO.File]::ReadAllLines($tgt) | ForEach-Object {
  $_ -replace '^function Plain\(AFirst: Integer; ASecond: string\): Integer;$',
              'function Plain(AFirst: Integer; ASecond: string; AThird: Boolean): Integer;'
}
$sw = New-Object System.IO.StreamWriter($tgt, $false, [Text.Encoding]::ASCII)
foreach ($l in $extra) { $sw.Write($l); $sw.Write("`r`n") }
$sw.Close()
& $exePath index $sc --db $db 2>$null | Out-Null
$drift2 = (& $exePath lint-all $sc --db $db --rule doc-drift 2>&1) | ForEach-Object { "$_" }
Check 'A4 (de-vacuator): a param with NO tag is still reported -- the rule still fires' `
  (@($drift2 | Where-Object { $_ -match 'AThird' -and $_ -match 'has no <param> tag' }).Count -ge 1) `
  (($drift2 | Where-Object { $_ -match 'doc-drift' } | Select-Object -First 5) -join ' | ')

# --- ENCODING: the repo's invariant, on a file two applies have rewritten. --
$bytes = [IO.File]::ReadAllBytes($tgt)
Check 'ENCODING: the applied file is strict 7-bit ASCII' `
  (@($bytes | Where-Object { $_ -ge 128 }).Count -eq 0) ''

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
