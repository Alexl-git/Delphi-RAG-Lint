<#
  run_coherence_summary.ps1 -- the coherence summary must ATTRIBUTE, and it must
  be able to print zeros.

  Why this exists
  ---------------
  reconcile-project reported `coherence: members=105 incoherent=105 scanned=105`
  and it was read as a broken check. It was not: IsIncoherent ORs three
  orthogonal causes, and a run straight after a FULL REINDEX makes every member
  compile-stale by definition -- a reindex refreshes files.mtime, but only a
  compile sweep writes last_compiled_unix. The number was correct and useless,
  because it could not tell "the index is garbage" from "you just reindexed".

  A metric that is always 100% carries no information either way, and it was
  printed as though it did.

  What is checked, and why both halves are here
  ---------------------------------------------
  Splitting one number into three could be satisfied by a fix that simply never
  counts anything -- so the assertions are paired:

    * the three causes must SUM to `incoherent` (no member unattributed, none
      double-counted);
    * a cause must FIRE when its condition holds -- compile-stale on a
      never-compiled index, index-stale after touching a member;
    * and ZEROS MUST BE REACHABLE. A second run immediately after the first must
      print all zeros. Without this, "always 100%" would just have become
      "always something", which is the same defect wearing three names.

  `incoherent` is asserted to SURVIVE in JSON: it is an existing key and the
  --json contract is one valid object on stdout.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Fixture = "$PSScriptRoot\..\fixtures\reconcile",
  [string]$WorkDir = "$env:TEMP\draglint_coherence_summary"
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

Write-Host '== coherence summary attributes its causes ==' -ForegroundColor Cyan
$Exe     = (Resolve-Path $Exe).Path
$Fixture = (Resolve-Path $Fixture).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Copy-Item "$Fixture\*" $WorkDir
$db = Join-Path $WorkDir 't.sqlite'

function Reconcile([string[]]$extra = @()) {
  $out = & $Exe reconcile-project (Join-Path $WorkDir 'App.dpr') --db $db @extra 2>&1 | Out-String
  return $out
}
function Counters([string]$text) {
  $m = [regex]::Match($text,
    'coherence:\s*members=(\d+)\s+incoherent=(\d+)\s+\(notIndexed=(\d+)\s+indexStale=(\d+)\s+compileStale=(\d+)\)\s+scanned=(\d+)')
  if (-not $m.Success) { return $null }
  return [pscustomobject]@{
    Members = [int]$m.Groups[1].Value; Incoherent = [int]$m.Groups[2].Value
    NotIndexed = [int]$m.Groups[3].Value; IndexStale = [int]$m.Groups[4].Value
    CompileStale = [int]$m.Groups[5].Value; Scanned = [int]$m.Groups[6].Value
  }
}

& $Exe index $WorkDir --db $db 2>&1 | Out-Null

# --- run 1: nothing has ever been compiled -> compile-stale must FIRE --------
$c1 = Counters (Reconcile)
Check 'the summary reports all three causes' ($null -ne $c1) `
  $(if ($null -eq $c1) { 'coherence line did not match the expected shape' } else { '' })
if ($null -eq $c1) { Write-Host 'FATAL: no coherence line'; exit 1 }
Check 'run 1: the causes SUM to incoherent' `
  (($c1.NotIndexed + $c1.IndexStale + $c1.CompileStale) -eq $c1.Incoherent) `
  "$($c1.NotIndexed)+$($c1.IndexStale)+$($c1.CompileStale) vs $($c1.Incoherent)"
Check 'run 1: compile-stale FIRES on a never-compiled index' `
  ($c1.CompileStale -gt 0) "compileStale=$($c1.CompileStale)"

# --- run 2: ZEROS MUST BE REACHABLE -----------------------------------------
$c2 = Counters (Reconcile)
Check 'run 2: a coherent project prints ZEROS (the always-100% mode is dead)' `
  (($null -ne $c2) -and ($c2.Incoherent -eq 0) -and ($c2.CompileStale -eq 0) -and `
   ($c2.IndexStale -eq 0) -and ($c2.NotIndexed -eq 0)) `
  $(if ($c2) { "incoherent=$($c2.Incoherent) compileStale=$($c2.CompileStale)" } else { 'no match' })
Check 'run 2: scanned counts REAL rescans, not members' `
  (($null -ne $c2) -and ($c2.Scanned -eq 0)) $(if ($c2) { "scanned=$($c2.Scanned)" } else { '' })

# --- run 3: touching a member must be seen as INDEX-stale, not compile-stale -
(Get-Item (Join-Path $WorkDir 'uMain.pas')).LastWriteTime = (Get-Date)
$c3 = Counters (Reconcile)
Check 'run 3: a touched member is INDEX-stale' `
  (($null -ne $c3) -and ($c3.IndexStale -ge 1)) $(if ($c3) { "indexStale=$($c3.IndexStale)" } else { 'no match' })
Check 'run 3: it is not misattributed to not-indexed' `
  (($null -ne $c3) -and ($c3.NotIndexed -eq 0)) $(if ($c3) { "notIndexed=$($c3.NotIndexed)" } else { '' })
Check 'run 3: the causes SUM to incoherent' `
  (($null -ne $c3) -and (($c3.NotIndexed + $c3.IndexStale + $c3.CompileStale) -eq $c3.Incoherent)) ''

# --- JSON keeps the old key and gains the new ones --------------------------
# The CLI prints its banner ('loaded defaults from ...', the FTS5 probe) on
# stderr AFTER the document, so a merged capture is not parseable as-is. The
# engine has SliceJsonBracket for the same reason; slice here rather than
# assert against a stream nothing promised was pure.
# stdout ONLY. With $ErrorActionPreference='Stop', 2>&1 turns the CLI's stderr
# banner into ErrorRecords, which Out-String renders with PS7 decoration --
# extra text and extra braces after the document. That is what made the slice
# end at 1397 instead of 1345 and fail to parse.
$j   = (& $Exe reconcile-project (Join-Path $WorkDir 'App.dpr') --db $db --json 2>$null) -join "`n"
# LastIndexOf('}') is NOT good enough: trailing banner/diagnostic text can
# contain a brace, which makes the slice end past the document and fail to
# parse -- measured here (ei=1397 vs a real 1345). Count depth from the first
# brace, skipping braces inside strings, exactly as SliceJsonBracket does.
function BalancedJson([string]$s) {
  $start = $s.IndexOf('{'); if ($start -lt 0) { return '' }
  $depth = 0; $inStr = $false; $esc = $false
  for ($i = $start; $i -lt $s.Length; $i++) {
    $c = $s[$i]
    if ($inStr) {
      if     ($esc)        { $esc = $false }
      elseif ($c -eq '') { $esc = $true  }
      elseif ($c -eq '"') { $inStr = $false }
      continue
    }
    if     ($c -eq '"') { $inStr = $true }
    elseif ($c -eq '{')  { $depth++ }
    elseif ($c -eq '}')  { $depth--; if ($depth -eq 0) { return $s.Substring($start, $i - $start + 1) } }
  }
  return ''
}
$obj = $null
$slice = BalancedJson $j
if ($slice -ne '') { try { $obj = ($slice | ConvertFrom-Json) } catch { } }
Check 'json stdout is ONE valid object' ($null -ne $obj) ''
Check 'json keeps `incoherent` (existing consumers)' `
  (($null -ne $obj) -and ($null -ne $obj.coherence) -and ($null -ne $obj.coherence.incoherent)) ''
Check 'json carries the three causes' `
  (($null -ne $obj) -and ($null -ne $obj.coherence.notIndexed) -and `
   ($null -ne $obj.coherence.indexStale) -and ($null -ne $obj.coherence.compileStale)) ''

Write-Host ''
if ($script:Failed) { Write-Host 'COHERENCE SUMMARY GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'COHERENCE SUMMARY GUARD: PASS' -ForegroundColor Green
exit 0
