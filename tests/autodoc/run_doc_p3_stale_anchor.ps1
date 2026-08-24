<#
  run_doc_p3_stale_anchor.ps1 -- PHASE A2: the doc applier must verify the
  anchor it is about to write at.

  THE DEFECT
  ----------
  docs\INBOX-document-qname-second-apply-nests-block-on-stale-anchor.md.

  Two `document --qname --apply` runs against two members of ONE class, with no
  reindex between them:

    1. the first apply inserts N lines above `constructor Create`;
    2. every declaration below moves down by N;
    3. the store still holds `Ping`'s PRE-EDIT start_line, which now points
       INSIDE the block just written;
    4. the second apply anchors there.

  Observed before the fix: two `<remarks>` opens and two closes stacked above
  `constructor Create`, Ping's facts inside Create's block, `Ping` itself left
  undocumented -- and exit 0 with `doc: created -- 1 edit(s) applied`. The XML
  is malformed, so the tooltip renders whatever the IDE makes of it.

  THIS IS THE FOURTH INSTANCE OF ONE ROOT CAUSE -- a writer that trusts index
  coordinates without verifying what is actually at them. `unused-local`'s fixer
  destroyed 72 lines; the naming autofix wrote onto `then`/`else` and exited 0;
  and this. The other three were fixed by making the check STRUCTURAL inside
  TTextEditApplier, and that is where this one is fixed too -- one verification
  path, not a second one bolted onto the doc verb.

  WHAT IS ASSERTED
  ----------------
  The engine must never write at an unverified coordinate. Per ruling D-2 a
  suspected stale index means REINDEX AND RETRY, so the passing behaviour is not
  merely "refused" but "recovered": both members end up documented, each block
  above its OWN declaration, and the file is well-formed.

  Three separate claims, because a fix that satisfies one can still fail
  another:

    NESTING     no doc region contains a second <remarks> open before its close.
    ATTRIBUTION Create's block carries Create's facts and Ping's carries Ping's.
                A merged-but-flat block would satisfy NESTING alone.
    RECOVERY    Ping is documented at all. Refusing to write anything would also
                satisfy NESTING and ATTRIBUTION, and would leave the user with a
                verb that silently does half its job.

  CONTROL: the same fixture documented in ONE `--unit` pass. That path computes
  every edit from a single snapshot and was never affected, so it shows the
  fixture is documentable at all and pins what the --qname pair must converge to.

  Runs from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$fx      = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docp3\staleanchor.pas')).Path

# ---------------------------------------------------------------------------
# Helpers. Standalone by convention -- every runner in this directory carries
# its own copies rather than dot-sourcing a shared module.
# ---------------------------------------------------------------------------

# The contiguous run of ///-prefixed lines immediately above the 1-based line
# whose text matches $declRx, per-line trimmed and newline-joined. Located by
# TEXT rather than by an index line number on purpose: the index is the thing
# under suspicion here, so a runner that asked it where to look could be misled
# by the same staleness it is testing for.
function Get-DocBlockAbove([string[]]$lines, [string]$declRx) {
  $d = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $declRx) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($i = $d - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i].Trim())
  }
  return ([string]::Join("`n", $acc.ToArray()) -replace '</?para>', '')
}

# True when $block opens a <remarks> while one is already open -- the exact
# malformation the defect produced.
function Test-NestedRemarks([string]$block) {
  $depth = 0
  foreach ($l in ($block -split "`n")) {
    if ($l -match '</remarks>') { $depth-- }
    elseif ($l -match '<remarks>') { if ($depth -gt 0) { return $true }; $depth++ }
  }
  return $false
}

function New-Case([string]$dir) {
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
  New-Item -ItemType Directory -Path $dir | Out-Null
  Copy-Item $fx (Join-Path $dir 'staleanchor.pas') -Force
  return @{ Dir = $dir; Pas = (Join-Path $dir 'staleanchor.pas'); Db = (Join-Path $dir 'h.sqlite') }
}

Push-Location C:\TEMP
try {

Write-Host ''
Write-Host '=== staleanchor.pas: two --qname applies with no reindex between ===' -ForegroundColor Cyan

# ===========================================================================
# CONTROL -- one --unit pass, the path that was never affected.
# ===========================================================================
$ctl = New-Case 'C:\TEMP\draglint_docp3_staleanchor_ctl'
& $exePath index $ctl.Dir --db $ctl.Db 2>$null | Out-Null
& $exePath document --unit $ctl.Pas --db $ctl.Db --apply --no-backup 2>$null | Out-Null
$ctlLines = [IO.File]::ReadAllLines($ctl.Pas)
$ctlCreate = Get-DocBlockAbove $ctlLines '^\s*constructor Create\('
$ctlPing   = Get-DocBlockAbove $ctlLines '^\s*procedure Ping\('
Check 'CONTROL: one --unit pass documents BOTH members' `
  (($ctlCreate -match '///') -and ($ctlPing -match '///')) `
  ("create=[" + ($ctlCreate -replace "`n",' | ') + "] ping=[" + ($ctlPing -replace "`n",' | ') + "]")
Check 'CONTROL: ... and neither block is nested' `
  ((-not (Test-NestedRemarks $ctlCreate)) -and (-not (Test-NestedRemarks $ctlPing))) ''

# ===========================================================================
# THE CASE -- two --qname applies, no reindex between them.
# ===========================================================================
$c = New-Case 'C:\TEMP\draglint_docp3_staleanchor'
& $exePath index $c.Dir --db $c.Db 2>$null | Out-Null

$out1 = & $exePath document --qname staleanchor.TZeiss.Create --db $c.Db --apply --no-backup 2>&1
$rc1  = $LASTEXITCODE
$out2 = & $exePath document --qname staleanchor.TZeiss.Ping   --db $c.Db --apply --no-backup 2>&1
$rc2  = $LASTEXITCODE

Check 'the first apply succeeded (de-vacuator: the pair must actually run)' ($rc1 -eq 0) `
  ("rc=$rc1 out=[" + (($out1 | ForEach-Object { "$_" }) -join ' | ') + "]")

$lines = [IO.File]::ReadAllLines($c.Pas)
$blkCreate = Get-DocBlockAbove $lines '^\s*constructor Create\('
$blkPing   = Get-DocBlockAbove $lines '^\s*procedure Ping\('

# --- NESTING ----------------------------------------------------------------
Check 'NESTING: Create''s doc block does not contain a nested <remarks>' `
  (-not (Test-NestedRemarks $blkCreate)) ($blkCreate -replace "`n",' | ')
Check 'NESTING: the file holds as many </remarks> as <remarks> in each block' `
  ((([regex]::Matches($blkCreate,'<remarks>')).Count -eq ([regex]::Matches($blkCreate,'</remarks>')).Count) -and `
   (([regex]::Matches($blkPing  ,'<remarks>')).Count -eq ([regex]::Matches($blkPing  ,'</remarks>')).Count)) `
  ("create=[" + ($blkCreate -replace "`n",' | ') + "] ping=[" + ($blkPing -replace "`n",' | ') + "]")

# --- RECOVERY ---------------------------------------------------------------
# Ruling D-2: a suspected stale index means reindex and retry, so the verb must
# RECOVER rather than merely decline. A refusal would satisfy every nesting and
# attribution check above while leaving the user's second command undone.
Check 'RECOVERY: Ping ends up documented above its OWN declaration' `
  ($blkPing -match '///') ("rc=$rc2 out=[" + (($out2 | ForEach-Object { "$_" }) -join ' | ') + "]")
Check 'RECOVERY: the second command reported success' ($rc2 -eq 0) `
  ("rc=$rc2 out=[" + (($out2 | ForEach-Object { "$_" }) -join ' | ') + "]")

# --- ATTRIBUTION ------------------------------------------------------------
# A flat but MERGED block would pass NESTING. These pin whose facts are whose:
# only Ping calls Create, so 'Calls:' belongs to Ping and 'Called from:' to
# Create, and neither may appear in the other's block.
Check 'ATTRIBUTION: Create''s block carries Create''s facts, not Ping''s' `
  (($blkCreate -match 'Called from:') -and (-not ($blkCreate -match 'Calls:'))) `
  ($blkCreate -replace "`n",' | ')
Check 'ATTRIBUTION: Ping''s block carries Ping''s facts, not Create''s' `
  (($blkPing -match 'Calls:') -and (-not ($blkPing -match 'Called from:'))) `
  ($blkPing -replace "`n",' | ')

# --- The pair converges on what the single-pass CONTROL produces. -----------
# Compared on the FACT lines only: the two paths need not agree on ordering of
# unrelated tags, but they must agree about the content they mined.
function Get-FactLines([string]$block) {
  return (($block -split "`n" | Where-Object { $_ -match 'Called from:|Calls:|Pure' } |
           ForEach-Object { ($_ -replace '^\s*///\s?','' -replace '</?para>','').Trim() }) -join ' ; ')
}
Check 'the --qname pair mined the same facts as the single --unit pass (Create)' `
  ((Get-FactLines $blkCreate) -eq (Get-FactLines $ctlCreate)) `
  ("qname=[" + (Get-FactLines $blkCreate) + "] unit=[" + (Get-FactLines $ctlCreate) + "]")
Check 'the --qname pair mined the same facts as the single --unit pass (Ping)' `
  ((Get-FactLines $blkPing) -eq (Get-FactLines $ctlPing)) `
  ("qname=[" + (Get-FactLines $blkPing) + "] unit=[" + (Get-FactLines $ctlPing) + "]")

# --- ENCODING: the repo's invariant, on a file two applies have rewritten. --
$bytes = [IO.File]::ReadAllBytes($c.Pas)
Check 'ENCODING: the applied file is strict 7-bit ASCII' `
  (@($bytes | Where-Object { $_ -ge 128 }).Count -eq 0) ''
Check 'ENCODING: the applied file has no bare LF (CRLF throughout)' `
  (([regex]::Matches([IO.File]::ReadAllText($c.Pas), "(?<!`r)`n")).Count -eq 0) ''

}
finally { Pop-Location }

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
