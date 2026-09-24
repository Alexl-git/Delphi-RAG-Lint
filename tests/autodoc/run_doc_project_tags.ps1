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

  2026-09-24 ADDITIONS
  --------------------------------------------------------------------------------
    5. D28 -- `Covered by:` joins the tagged regime. ProjB gains a test,
       Test.Shared.TSharedTests.Ping_works, calling SharedProc: B renders it
       `[ProjB]`-tagged, A keeps it, and when B drops the test B reaps it. Before
       D28 the label was preserved WHOLE by a carry-over, so it was never tagged
       and never reaped -- and a fresh render replaced a stored line wholesale,
       losing the untagged legacy entry this section plants as its control.
    6. D27 -- the tag is the project the INDEX RECORDS, not the DB file name.
       ProjA indexed into `not-the-project-name.sqlite` must see no drift on the
       entries `[ProjA]` tagged and must write `[ProjA]`, never its file name.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$root = Join-Path ([IO.Path]::GetTempPath()) "dl-projtags-$PID"
if (Test-Path $root) { Remove-Item -Recurse -Force $root }
try {
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
function CoveredBy([string]$blk) { if ($blk -match 'Covered by: ([^<]*)</para>') { $Matches[1] } else { '' } }
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

# --- 5. D28: `Covered by:` is tagged and reaped like the other inbound labels ---
# A legacy, UNTAGGED test entry naming a unit no index holds -- the shape every
# pre-D28 `Covered by:` line has. It must survive every run below.
$ls = [IO.File]::ReadAllLines($uShared)
$out = @()
foreach ($l in $ls) {
  $out += $l
  if ($l -match '^\s*/// <para>Called from: ') { $out += '/// <para>Covered by: Test.Gone.TGoneTests.Old_works</para>' }
}
[IO.File]::WriteAllText($uShared, (($out -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
Check 'COVERED setup: the legacy Covered-by line is in place' ((CoveredBy (Shared)) -eq 'Test.Gone.TGoneTests.Old_works') (CoveredBy (Shared))

Write-Ascii (Join-Path $appB 'Test.Shared.pas') @'
unit Test.Shared;

interface

type
  TSharedTests = class
  public
    procedure Ping_works;
  end;

implementation

uses uShared;

procedure TSharedTests.Ping_works;
begin
  SharedProc;
end;

end.
'@
Write-Ascii (Join-Path $appB 'ProjB.dpr') @'
program ProjB;
uses uShared in '..\shared\uShared.pas', uB2 in 'uB2.pas', Test.Shared in 'Test.Shared.pas';
begin
end.
'@
IndexA; IndexB
$pingPat = '^\[ProjB\]Test\.Shared\.TSharedTests\.Ping_works( \(unverified\))?$'
$r = Run @('document', '--unit', $uShared, '--db', $dbB, '--apply', '--no-backup')
$cb = CoveredBy (Shared); $ce = Entries $cb
Check 'COVERED 1: B renders its test tagged [ProjB]' (@($ce | Where-Object { $_ -match $pingPat }).Count -eq 1) $cb
Check 'COVERED 1: the untagged legacy test entry survives B''s render' ($ce -contains 'Test.Gone.TGoneTests.Old_works') $cb

$r = Run @('document', '--unit', $uShared, '--db', $dbA, '--apply', '--no-backup')
$cb = CoveredBy (Shared); $ce = Entries $cb
Check 'COVERED 2: A (which cannot see the test) keeps B''s entry' (@($ce | Where-Object { $_ -match $pingPat }).Count -eq 1) $cb
Check 'COVERED 2: A keeps the legacy entry' ($ce -contains 'Test.Gone.TGoneTests.Old_works') $cb
IndexA; IndexB
foreach ($pair in @(@('A', $dbA), @('B', $dbB))) {
  $d = (Run @('doc-drift', '--qname', 'uShared.SharedProc', '--db', $pair[1])).Out
  Check "COVERED CONVERGED: no drift under Proj$($pair[0])" ($d -notmatch 'ddFactsBlockStale') $d.Trim()
  $h = (Get-FileHash $uShared).Hash
  $null = Run @('document', '--unit', $uShared, '--db', $pair[1], '--apply', '--no-backup')
  Check "COVERED CONVERGED: a second Proj$($pair[0]) run is byte-identical" ((Get-FileHash $uShared).Hash -eq $h) ''
}

# B deletes the test: it leaves the program and the folder.
Write-Ascii (Join-Path $appB 'ProjB.dpr') @'
program ProjB;
uses uShared in '..\shared\uShared.pas', uB2 in 'uB2.pas';
begin
end.
'@
Move-Item -LiteralPath (Join-Path $appB 'Test.Shared.pas') -Destination (Join-Path $root 'Test.Shared.pas.gone')
IndexB
$r = Run @('document', '--unit', $uShared, '--db', $dbB, '--apply', '--no-backup')
$cb = CoveredBy (Shared); $ce = Entries $cb
Check 'COVERED 3: B reaps its own entry for the deleted test' (@($ce | Where-Object { $_ -match 'Ping_works' }).Count -eq 0) $cb
Check 'COVERED 3 CONTROL: the untagged legacy entry is still preserved' ($ce -contains 'Test.Gone.TGoneTests.Old_works') $cb

# --- 6. D27: the tag is the index's RECORDED project, not its file name ---------
IndexA
$null = Run @('document', '--unit', $uShared, '--db', $dbA, '--apply', '--no-backup')
$cf = CalledFrom (Shared)
Check 'NAME setup: A''s six callers carry [ProjA] again' ((@((Entries $cf) | Where-Object { $_ -like '`[ProjA`]*' })).Count -eq 6) $cf
$dbX = Join-Path $root 'not-the-project-name.sqlite'
$r = Run @('index', '--project', (Join-Path $appA 'ProjA.dpr'), '--db', $dbX)
Check 'NAME setup: ProjA indexed into a DB NOT named after it' ($r.Code -eq 0) ''
$d = (Run @('doc-drift', '--qname', 'uShared.SharedProc', '--db', $dbX)).Out
Check 'NAME: doc-drift through that DB sees no drift on [ProjA]''s entries' ($d -notmatch 'ddFactsBlockStale') $d.Trim()
$lint = (Run @('lint', $uShared, '--db', $dbX, '--rule', 'doc-drift', '--project-rules')).Out
Check 'NAME: lint --rule doc-drift through that DB reports 0 drift' ($lint -notmatch '\[warning\] doc-drift') $lint.Trim()
$h = (Get-FileHash $uShared).Hash
$r = Run @('document', '--unit', $uShared, '--db', $dbX, '--apply', '--no-backup')
Check 'NAME: document --apply through that DB leaves the block byte-identical' ((Get-FileHash $uShared).Hash -eq $h) (CalledFrom (Shared))
Check 'NAME: no entry is ever tagged with the DB file name' (([IO.File]::ReadAllText($uShared)) -notmatch 'not-the-project-name') (CalledFrom (Shared))
} finally {
  if (Test-Path $root) { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
