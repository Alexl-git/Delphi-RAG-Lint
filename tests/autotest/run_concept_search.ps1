<#
  run_concept_search.ps1 -- acceptance test for `query --concept` (ranked BM25
  concept search over identifier words + doc-comment prose).

  Contract: C:\TEMP\claude\lanes\gaps\agent-xj5\CONTRACT.md ("CLI surface", "Tests").
  Fixture : tests\fixtures\concept-search (TDeltaPipe.ApplyRowDelta + distractors).

  Every negative assertion has a positive control on the same DB in the same run:
    * "zebra quantum" -> 0 hits is only meaningful because "apply row changes"
      found ApplyRowDelta on the same DB just before;
    * "removed routine is gone" follows "it was found" on the same DB;
    * "old doc word gone" follows "old doc word found";
    * exit 3 after dropping the tables follows exit 0 before dropping them.

  Everything is built in a scratch folder under $env:TEMP (or -Scratch); no real
  project DB is ever opened. Exit code: 0 on full pass, 1 on any failure.

  Usage: pwsh -File tests\autotest\run_concept_search.ps1 [-Exe <drag-lint.exe>] [-Scratch <dir>]
#>
[CmdletBinding()]
param(
  [string] $Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string] $Scratch = ''
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if ($Ok) { $script:Pass++ } else { $script:Fail++; $script:Failed = $true }
}

Write-Host '== query --concept: ranked concept search ==' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$Fixture = (Resolve-Path "$PSScriptRoot\..\fixtures\concept-search").Path
$DropPy  = Join-Path $PSScriptRoot 'concept_search_drop_tables.py'

if ([string]::IsNullOrWhiteSpace($Scratch)) {
  $Scratch = Join-Path ([IO.Path]::GetTempPath()) ('draglint-concept-' + [Guid]::NewGuid().ToString('N'))
}
$null = New-Item -ItemType Directory -Force -Path $Scratch
$Work = Join-Path $Scratch 'fx'
$null = New-Item -ItemType Directory -Force -Path $Work
Copy-Item "$Fixture\*" $Work
$Proj  = Join-Path $Work 'ConceptFx.dproj'
$Db    = Join-Path $Scratch 'concept.sqlite'
$Extra = Join-Path $Work 'ExtraUnit.pas'
$Delta = Join-Path $Work 'DeltaUnit.pas'

# stdout and stderr captured separately (the engine prints a banner on stderr).
function Run([string[]]$A) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($x in $A) { $psi.ArgumentList.Add($x) }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync()
  $e = $p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  return @{ Exit = $p.ExitCode; Out = $o.Result; Err = $e.Result }
}
function Index() { return Run @('index', '--project', $Proj, '--db', $Db) }
function Concept([string]$Words, [string[]]$More = @()) {
  $r = Run (@('query', '--concept', $Words, '--db', $Db, '--json') + $More)
  $j = $null
  try { $j = $r.Out | ConvertFrom-Json } catch { }
  $r['Json'] = $j
  return $r
}
function Hits($r) { if ($null -ne $r.Json -and $null -ne $r.Json.hits) { return @($r.Json.hits) } else { return @() } }
function Qn($r, [int]$i) { $h = @(Hits $r); if ($h.Count -gt $i) { return [string]$h[$i].qname } else { return '' } }
function HasQ($r, [string]$Suffix, [int]$Top = 100) {
  $h = @(Hits $r)
  for ($i = 0; $i -lt [Math]::Min($Top, $h.Count); $i++) { if ([string]$h[$i].qname -like "*$Suffix") { return $true } }
  return $false
}
function Brief($r) { return "exit=$($r.Exit) top=$(Qn $r 0) err=$(($r.Err -split "`n")[0])" }
function WriteAscii([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}

# ---- 0. selftest + fresh index -------------------------------------------
$r = Run @('selftest', 'ident-words')
Check 'selftest ident-words: exit 0, IDENTWORDS-OK' (($r.Exit -eq 0) -and ($r.Out -match 'IDENTWORDS-OK')) "exit=$($r.Exit) out=$($r.Out.Trim())"

$r = Index
Check 'control: fixture index exits 0' ($r.Exit -eq 0) "exit=$($r.Exit) err=$(($r.Err -split "`n")[0])"

# ---- 1. ranking ------------------------------------------------------------
$r = Concept 'apply row changes'
Check '"apply row changes": exit 0 and rank 1 = ApplyRowDelta' (($r.Exit -eq 0) -and ((Qn $r 0) -like '*TDeltaPipe.ApplyRowDelta')) (Brief $r)
$positive = ($r.Exit -eq 0) -and (@(Hits $r).Count -gt 0)

$r = Concept 'delta pipe'
Check '"delta pipe": TDeltaPipe in top 3' (HasQ $r 'TDeltaPipe' 3) (Brief $r)

$r = Concept 'lantern'
Check '"lantern" (remarks-only word) hits ApplyRowDelta' (HasQ $r 'TDeltaPipe.ApplyRowDelta') (Brief $r)
$h = @(Hits $r)
$lm = @(); if ($h.Count -gt 0) { $lm = @($h[0].matched) }
Check '"lantern": matched column list names remarks' ($lm -contains 'remarks') "matched=$($lm -join ',')"

$r = Concept 'ApplyRowDelta'
Check '"ApplyRowDelta" (exact identifier): rank 1 = ApplyRowDelta' ((Qn $r 0) -like '*TDeltaPipe.ApplyRowDelta') (Brief $r)

# ---- 2. --kind filter (control: unfiltered contains a non-class kind) ------
$r = Concept 'delta pipe'
$kinds = @(Hits $r | ForEach-Object { [string]$_.kind })
Check 'control: unfiltered "delta pipe" returns a non-class kind too' (@($kinds | Where-Object { $_ -ne 'class' }).Count -gt 0) "kinds=$($kinds -join ',')"
$r = Concept 'delta pipe' @('--kind', 'class')
$kinds = @(Hits $r | ForEach-Object { [string]$_.kind })
Check '--kind class: hits exist and every hit is a class' (($kinds.Count -gt 0) -and (@($kinds | Where-Object { $_ -ne 'class' }).Count -eq 0)) "kinds=$($kinds -join ',') $(Brief $r)"

# ---- 3. --json shape + text output ----------------------------------------
$r = Concept 'apply row changes'
$j = $r.Json
$h = @(Hits $r)
$shape = ($null -ne $j) -and ($j.query -eq 'apply row changes') -and ($j.count -eq $h.Count) -and ($null -ne $j.allTermsCount) -and ($h.Count -gt 0)
if ($shape) {
  $x = $h[0]
  $names = @($x.PSObject.Properties.Name)
  foreach ($n in 'rank','qname','kind','file','line','score','matched','allTerms') { if ($names -notcontains $n) { $shape = $false } }
  if ($shape -and ($x.rank -ne 1)) { $shape = $false }
}
Check '--json shape: query/count/allTermsCount/hits[rank,qname,kind,file,line,score,matched,allTerms]' $shape (Brief $r)

$t = Run @('query', '--concept', 'apply row changes', '--db', $Db)
$tHead = ($t.Out -split "`n")[0]
Check 'text output: header "concept ...: N hit(s) (M match every word)" and an ApplyRowDelta row' (($t.Exit -eq 0) -and ($t.Out -match '(?m)^concept "apply row changes": \d+ hit\(s\) \(\d+ match every word\)') -and ($t.Out -match 'TDeltaPipe\.ApplyRowDelta')) "exit=$($t.Exit) out=$tHead"

# ---- 4. no hits: exit 1 (positive control = $positive above) ---------------
$r = Concept 'zebra quantum'
Check 'control for no-hit: "apply row changes" found hits on this same DB' $positive ''
Check '"zebra quantum": 0 hits, exit 1' (($r.Exit -eq 1) -and (@(Hits $r).Count -eq 0)) (Brief $r)

# ---- 5. incremental: add / remove a documented routine ---------------------
$extraBase = [IO.File]::ReadAllText($Extra)
$extraWith = @"
unit ExtraUnit;

interface

type
  TExtra = class
  public
    procedure Placeholder;
    /// <summary>Polishes the quokka whiskers before the parade.</summary>
    procedure PolishWhiskers;
  end;

implementation

procedure TExtra.Placeholder;
begin
end;

procedure TExtra.PolishWhiskers;
begin
end;

end.
"@
$r = Concept 'quokka whiskers'
Check 'control: before the edit "quokka whiskers" has no hit' (($r.Exit -eq 1) -and -not (HasQ $r 'PolishWhiskers')) (Brief $r)
WriteAscii $Extra $extraWith
$null = Index
$r = Concept 'quokka whiskers'
Check 'incremental add: reindex -> PolishWhiskers found by its doc words' (HasQ $r 'TExtra.PolishWhiskers') (Brief $r)
$r2 = Concept 'PolishWhiskers'
Check 'incremental add: found by identifier too (control for the removal check)' (HasQ $r2 'TExtra.PolishWhiskers') (Brief $r2)
WriteAscii $Extra $extraBase
$null = Index
$r = Concept 'quokka whiskers'
$r2 = Concept 'PolishWhiskers'
Check 'incremental remove: reindex -> no ghost (doc words and identifier)' ($r.Exit -le 1) -and ($r2.Exit -le 1) -and (-not (HasQ $r 'PolishWhiskers')) -and (-not (HasQ $r2 'PolishWhiskers')) "doc: $(Brief $r) ident: $(Brief $r2)"

# ---- 6. edit a doc word ----------------------------------------------------
$r = Concept 'lantern'
Check 'control: "lantern" found before the doc edit' (HasQ $r 'TDeltaPipe.ApplyRowDelta') (Brief $r)
$dtext = [IO.File]::ReadAllText($Delta)
WriteAscii $Delta ($dtext.Replace('lantern buffer', 'pelican buffer'))
$null = Index
$rOld = Concept 'lantern'
$rNew = Concept 'pelican'
Check 'doc edit: old word "lantern" gone' ($rOld.Exit -le 1) -and (-not (HasQ $rOld 'TDeltaPipe.ApplyRowDelta')) (Brief $rOld)
Check 'doc edit: new word "pelican" finds ApplyRowDelta' (HasQ $rNew 'TDeltaPipe.ApplyRowDelta') (Brief $rNew)

# ---- 7. backfill / degrade -------------------------------------------------
$before = Concept 'apply row changes'
$beforeTop = Qn $before 0
Check 'control: query works (exit 0, rank 1 ApplyRowDelta) before dropping the tables' (($before.Exit -eq 0) -and ($beforeTop -like '*TDeltaPipe.ApplyRowDelta')) (Brief $before)

$py = & python -I $DropPy $Db 2>&1
$pyExit = $LASTEXITCODE
Check 'drop symbol_search, symbol_search_fts and their triggers (python helper)' (($pyExit -eq 0) -and ("$py" -match 'DROPPED')) "exit=$pyExit $py"

$r = Run @('query', '--concept', 'apply row changes', '--db', $Db)
$noteRe = 'note: this index has no concept-search table yet; run "drag-lint index" on it once'
Check 'tables dropped: query exits 3 with the one-line note, no crash' (($r.Exit -eq 3) -and ($r.Err -match [regex]::Escape($noteRe)) -and ($r.Err -notmatch '(?i)exception|access violation|EAbort|stack trace')) "exit=$($r.Exit) err=$(($r.Err -split "`n")[0])"

$ix = Index
Check 'backfill: index after the drop exits 0' ($ix.Exit -eq 0) "exit=$($ix.Exit) err=$(($ix.Err -split "`n")[0])"
$after = Concept 'apply row changes'
Check 'backfill: same rank-1 answer as before the drop' (($after.Exit -eq 0) -and ((Qn $after 0) -eq $beforeTop) -and ($beforeTop -ne '')) "before=$beforeTop after=$(Qn $after 0)"
# The index summary ("Done. Files: N, ..., skipped M up-to-date") must show every file skipped: nothing re-parsed.
$all = $ix.Out + "`n" + $ix.Err
$m = [regex]::Match($all, '(?m)^Done\. Files: (\d+),.*?skipped (\d+) up-to-date')
$sumLine = (($all -split "`n") | Where-Object { $_ -match '^Done\.' } | Select-Object -First 1)
Check 'backfill: the index run re-parsed 0 files (skipped == Files, > 0)' ($m.Success -and ([int]$m.Groups[1].Value -gt 0) -and ($m.Groups[1].Value -eq $m.Groups[2].Value)) "summary=$sumLine"
[IO.Directory]::Delete($Scratch, $true)
Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
