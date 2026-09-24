<#
  run_doc_project_tags.ps1 -- two projects share one unit; `document --apply`
  from either must NOT delete the facts the other contributed, and each project
  reaps only the entries tagged with ITS name.

  THE DEFECT (docs\INBOX-document-apply-drops-facts-outside-the-db.md, ENG-4)
  --------------------------------------------------------------------------------
  DataCopy and its test project are SEPARATE indexes over one set of production
  units. `document --apply` from DataCopy's DB silently deleted `Called from:`
  entries naming the test project. Measured 2026-09-22: the merge already
  preserved unseen entries on an UNTRUNCATED line, but a stored line carrying
  `(+N more)` was never merged (a window is not the list), so the whole line was
  replaced by DataCopy's own capped render and every visible foreign entry went
  with it. `Covered by:` / `Used by:` survived; `Called from:` did not.

  THE DESIGN (owner, 2026-09-16 and 2026-09-22/23)
  --------------------------------------------------------------------------------
    * an inbound entry on a reconciled block carries the projects that rendered
      it: `[ProjA,ProjB]uX.Foo (uX.pas)` -- the name is the --db base name;
    * a run adds and removes only ITS tag; an entry goes when its set empties;
    * an UNTAGGED (legacy) entry keeps the old rules -- preserved while this
      index cannot see its unit -- so no existing fact is lost to the migration;
    * a private unit is unchanged (no tags ever);
    * `doc-forget` removes / renames a tag, drops untagged leftovers, lists tags.

  Every assertion is scoped to SharedProc's OWN block (see BlockAbove), because
  a file-wide match passes whenever any other block carries the same text.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('dl-projtags-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$shr  = Join-Path $root 'shared'
$appA = Join-Path $root 'appA'
$appB = Join-Path $root 'appB'
foreach ($d in $shr, $appA, $appB) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$dbA  = Join-Path $root 'ProjA.sqlite'
$dbB  = Join-Path $root 'ProjB.sqlite'
$uShared = Join-Path $shr 'uShared.pas'

function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Run([string[]]$xs) { $o = & $exePath @xs 2>&1 | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
function BlockAbove([string]$path, [string]$declPat) {
  $ls = [IO.File]::ReadAllLines($path); $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $declPat) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) { if ($ls[$i] -notmatch '^\s*///') { break }; $acc = ,$ls[$i] + $acc }
  return ($acc -join "`n")
}
function CalledFrom([string]$blk) { if ($blk -match 'Called from: ([^<]*)</para>') { $Matches[1] } else { '' } }
function Entries([string]$line) {
  # split on commas OUTSIDE a [tag,set]
  $out = @(); $depth = 0; $cur = ''
  foreach ($ch in $line.ToCharArray()) {
    if ($ch -eq '[') { $depth++ } elseif ($ch -eq ']') { $depth-- }
    if ($ch -eq ',' -and $depth -eq 0) { $out += $cur.Trim(); $cur = '' } else { $cur += $ch }
  }
  if ($cur.Trim() -ne '') { $out += $cur.Trim() }
  return ,$out
}
function Shared() { BlockAbove $uShared '^procedure SharedProc;' }
function IndexA() { $r = Run @('index', '--project', (Join-Path $appA 'ProjA.dpr'), '--db', $dbA); if ($r.Code -ne 0) { Write-Host $r.Out } }
function IndexB() { $r = Run @('index', '--project', (Join-Path $appB 'ProjB.dpr'), '--db', $dbB); if ($r.Code -ne 0) { Write-Host $r.Out } }

# --- fixture: SharedProc, called six times by ProjA and once by ProjB --------
# Six A callers exceed docs.max_callers (5), so a plain render of this unmarked
# unit is a `(+N more)` window -- the shape that lost the entries.
Write-Ascii $uShared @'
unit uShared;

interface

procedure SharedProc;

implementation

procedure SharedProc;
begin
end;

end.
'@
Write-Ascii (Join-Path $appA 'uA.pas') @'
unit uA;

interface

procedure A1;
procedure A2;
procedure A3;
procedure A4;
procedure A5;
procedure A6;
procedure APrivate;

implementation

uses uShared;

procedure A1; begin SharedProc; end;
procedure A2; begin SharedProc; end;
procedure A3; begin SharedProc; end;
procedure A4; begin SharedProc; end;
procedure A5; begin SharedProc; end;
procedure A6; begin SharedProc; APrivate; end;
procedure APrivate; begin end;

end.
'@
Write-Ascii (Join-Path $appA 'ProjA.dpr') @'
program ProjA;
uses uShared in '..\shared\uShared.pas', uA in 'uA.pas';
begin
end.
'@
Write-Ascii (Join-Path $appB 'uB.pas') @'
unit uB;

interface

procedure BCaller;

implementation

uses uShared;

procedure BCaller; begin SharedProc; end;

end.
'@
Write-Ascii (Join-Path $appB 'uB2.pas') @'
unit uB2;

interface

procedure BCaller2;

implementation

uses uShared;

procedure BCaller2; begin SharedProc; end;

end.
'@
Write-Ascii (Join-Path $appB 'ProjB.dpr') @'
program ProjB;
uses uShared in '..\shared\uShared.pas', uB in 'uB.pas';
begin
end.
'@

IndexA; IndexB
$q = Run @('query', '--name', 'BCaller', '--db', $dbA)
Check 'setup: ProjA''s index does NOT hold uB' ($q.Out -notmatch 'uB\.BCaller') ''
$q = Run @('query', '--name', 'A1', '--db', $dbB)
Check 'setup: ProjB''s index does NOT hold uA' ($q.Out -notmatch 'uA\.A1') ''

# --- the LEGACY block: written once by a DB that saw both projects, truncated -
# It names ProjB's caller and a caller in a unit NO project holds any more,
# inside a `(+N more)` window -- exactly DataCopy's stored shape.
$t = [IO.File]::ReadAllText($uShared)
$t = $t.Replace("interface`r`n`r`nprocedure SharedProc;", @"
interface

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: uA.A1 (uA.pas), uA.A2 (uA.pas), uB.BCaller (uB.pas), uGone.Old (uGone.pas), uA.A3 (uA.pas) (+3 more)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SharedProc;
"@.Replace("`r`n", "`n").Replace("`n", "`r`n"))
[IO.File]::WriteAllText($uShared, $t, [Text.Encoding]::ASCII)
Check 'setup: the legacy block is in place' ((Shared) -match 'uB\.BCaller.*\(\+3 more\)') ''
Check 'setup: the unit is NOT marked dl:shared (participation is derived)' ($t -notmatch 'dl:shared') ''
IndexA; IndexB

# --- 1. ProjA writes: nothing it cannot see is lost ---------------------------
$r = Run @('document', '--unit', $uShared, '--db', $dbA, '--apply', '--no-backup')
Check 'A: document --apply ran' ($r.Code -eq 0) $r.Out.Trim()
$cf = CalledFrom (Shared); $es = Entries $cf
Check 'A: ProjB''s caller SURVIVES (the ENG-4 loss)' ($es -contains 'uB.BCaller (uB.pas)') $cf
Check 'A: an entry in a unit no index holds survives, untagged' ($es -contains 'uGone.Old (uGone.pas)') $cf
Check 'A: the list is WHOLE -- no (+N more) window' ($cf -notmatch '\(\+\d+ more\)') $cf
foreach ($n in 1..6) { Check "A: uA.A$n is present and tagged [ProjA]" ($es -contains "[ProjA]uA.A$n (uA.pas)") '' }
Check 'A: exactly eight entries' ($es.Count -eq 8) "$($es.Count): $cf"

$r = Run @('document', '--unit', (Join-Path $appA 'uA.pas'), '--db', $dbA, '--apply', '--no-backup')
Check 'A: a PRIVATE unit carries no tag' (([IO.File]::ReadAllText((Join-Path $appA 'uA.pas'))) -notmatch '\[ProjA\]') ''

IndexA; IndexB
$d = (Run @('doc-drift', '--qname', 'uShared.SharedProc', '--db', $dbA)).Out
Check 'A: the checker agrees -- no drift after A''s write' ($d -notmatch 'ddFactsBlockStale') $d.Trim()

# --- 2. ProjB writes: adopts its legacy entry, leaves A's alone ----------------
$r = Run @('document', '--unit', $uShared, '--db', $dbB, '--apply', '--no-backup')
$cf = CalledFrom (Shared); $es = Entries $cf
Check 'B: its own legacy entry is now tagged [ProjB]' ($es -contains '[ProjB]uB.BCaller (uB.pas)') $cf
foreach ($n in 1..6) { Check "B: [ProjA]uA.A$n is left as it stands" ($es -contains "[ProjA]uA.A$n (uA.pas)") '' }
Check 'B: the unclaimed legacy entry survives' ($es -contains 'uGone.Old (uGone.pas)') $cf

IndexA; IndexB
foreach ($pair in @(@('A', $dbA), @('B', $dbB))) {
  $d = (Run @('doc-drift', '--qname', 'uShared.SharedProc', '--db', $pair[1])).Out
  Check "CONVERGED: no drift under Proj$($pair[0])" ($d -notmatch 'ddFactsBlockStale') $d.Trim()
  $h = (Get-FileHash $uShared).Hash
  $null = Run @('document', '--unit', $uShared, '--db', $pair[1], '--apply', '--no-backup')
  Check "CONVERGED: a second Proj$($pair[0]) run is byte-identical" ((Get-FileHash $uShared).Hash -eq $h) ''
}

# --- 3. REAPING: ProjB drops uB for uB2 -----------------------------------------
# uB is now OUTSIDE ProjB's closure, so without a tag the entry would be
# unvouchable and preserved for ever. Its [ProjB] tag is what lets B reap it.
Write-Ascii (Join-Path $appB 'ProjB.dpr') @'
program ProjB;
uses uShared in '..\shared\uShared.pas', uB2 in 'uB2.pas';
begin
end.
'@
IndexB
$q = Run @('query', '--name', 'BCaller', '--db', $dbB, '--exact')
Check 'setup: uB has left ProjB''s index' ($q.Out -notmatch 'uB\.BCaller \(|uB\.pas') ''
$r = Run @('document', '--unit', $uShared, '--db', $dbB, '--apply', '--no-backup')
$cf = CalledFrom (Shared); $es = Entries $cf
Check 'REAP: B''s tagged entry for a unit it no longer holds is gone' ($es -notcontains '[ProjB]uB.BCaller (uB.pas)' -and $cf -notmatch 'uB\.BCaller') $cf
Check 'REAP: B''s new caller is recorded' ($es -contains '[ProjB]uB2.BCaller2 (uB2.pas)') $cf
Check 'REAP: A''s entries untouched' ((@($es | Where-Object { $_ -like '`[ProjA`]*' })).Count -eq 6) $cf
Check 'REAP CONTROL: the UNTAGGED unseen entry is still preserved' ($es -contains 'uGone.Old (uGone.pas)') $cf

IndexA
$h = (Get-FileHash $uShared).Hash
$null = Run @('document', '--unit', $uShared, '--db', $dbA, '--apply', '--no-backup')
Check 'REAP: A''s next run does not touch B''s entries' ((Get-FileHash $uShared).Hash -eq $h) ''

# --- 4. doc-forget ------------------------------------------------------------
$lt = (Run @('doc-forget', '--scope', $shr, '--list-tags')).Out
Check 'FORGET --list-tags counts ProjA x6' ($lt -match '(?m)^\s*6\s+ProjA\s*$') $lt.Trim()
Check 'FORGET --list-tags counts ProjB x1' ($lt -match '(?m)^\s*1\s+ProjB\s*$') ''
Check 'FORGET --list-tags counts the untagged leftover' ($lt -match '(?m)^\s*1\s+\(untagged') ''

$h = (Get-FileHash $uShared).Hash
$r = Run @('doc-forget', '--scope', $shr, '--project', 'ProjA')
Check 'FORGET dry run reports six removals' ($r.Out -match '6 tag\(s\) removed') $r.Out.Trim()
Check 'FORGET dry run writes nothing' ((Get-FileHash $uShared).Hash -eq $h) ''

$r = Run @('doc-forget', '--scope', $shr, '--rename', 'ProjB=Bee', '--apply', '--no-backup')
Check 'FORGET --rename renames in place' ((Entries (CalledFrom (Shared))) -contains '[Bee]uB2.BCaller2 (uB2.pas)') (CalledFrom (Shared))

$r = Run @('doc-forget', '--scope', $uShared, '--untagged', '--apply', '--no-backup')
Check 'FORGET --untagged drops the unclaimed leftover' ((CalledFrom (Shared)) -notmatch 'uGone') (CalledFrom (Shared))

$r = Run @('doc-forget', '--scope', $shr, '--project', 'proja', '--apply', '--no-backup')
$es = Entries (CalledFrom (Shared))
Check 'FORGET --project removes the tag case-insensitively; emptied entries go' ($es.Count -eq 1 -and $es[0] -eq '[Bee]uB2.BCaller2 (uB2.pas)') ($es -join ' | ')

# A label OUTSIDE a fence is prose and is never rewritten.
$prose = Join-Path $root 'prose.pas'
Write-Ascii $prose @'
unit prose;
interface
/// Mentions Called from: [ProjA]uA.A1 (uA.pas) in prose.
procedure P;
implementation
procedure P; begin end;
end.
'@
$h = (Get-FileHash $prose).Hash
$null = Run @('doc-forget', '--scope', $prose, '--project', 'ProjA', '--apply', '--no-backup')
Check 'FORGET the fence is the scope -- prose is untouched' ((Get-FileHash $prose).Hash -eq $h) ''
$r = Run @('doc-forget', '--scope', $prose)
Check 'FORGET with no operation is a usage error' ($r.Code -eq 2) "exit $($r.Code)"

if ($script:Failed) { Write-Host "FAIL (scratch kept: $root)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
