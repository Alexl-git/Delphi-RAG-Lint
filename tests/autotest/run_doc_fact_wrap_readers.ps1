<#
  run_doc_fact_wrap_readers.ps1 -- every reader of a STORED managed block reads a
  fact list the writer split over several `///` lines (1.20.5, Task 2).

  WHY. dcc 37.0 rejects an over-long source line with F2069 "Line too long
  (more than 1023 characters)"; measured 2026-09-30, a line that crosses one of
  the compiler's 4 KB read blocks fails at 1021 characters, so 1020 is the only
  length that compiles wherever the line lands. The inbound lists of a
  reconciliation block are uncapped by design, so they can exceed it. Owner
  ruling 2026-09-29: break such a line at entry boundaries, ONLY when it is
  over DOC_FACT_MAX_COLS (1000). Readers go first: a reader that parses one
  PHYSICAL line at a time sees only the first line of a wrapped list, and
    * MergeInboundFacts writes the merged list over line 1 and leaves the
      continuation lines -- duplicated entries, and a long line again;
    * doc-forget (ProjectTags) skips a continuation line because it carries no
      label, so a tag on it is never listed and never forgotten.

  THE FIXTURE. A `dl:shared ProjA, ProjB` unit Shared.pas with two routines and
  HAND-WRITTEN stored blocks, CRLF, tagged the way run_doc_project_tags.ps1
  writes them (the tag is the --db BASE NAME, so the DBs are ProjA.sqlite and
  ProjB.sqlite):
    * Target  -- a SHORT `Called from:` list wrapped over 3 lines; the ProjB-only
                 entries sit on the continuation lines. [ProjA]uA.A3 is missing,
                 so ProjA's run is a real merge, not a no-op.
    * Target2 -- a LONG list (40 ProjB-only entries, ~1500 characters) wrapped
                 over 3 lines, also missing ProjA's caller, so the merged list
                 has to be written through the wrap. Its stored block also
                 carries a ProjB-only `Covered by:` that ProjA does not render:
                 it is re-inserted AFTER the wrapped `Called from:` -- after its
                 LAST physical line (ReinsertAt), not inside it.
    * Target3 -- the same long list, but ProjA renders NO `Called from:` for it
                 (nothing in ProjA calls it; it calls Target, so its block still
                 renders). The stored label is RE-INSERTED by the merge -- the
                 second write site, which must wrap too.

  ARMS
    F1  merge     ProjA documents: every entry exactly once, the ProjB-only
                  entries from the continuation lines kept, no line over 1000,
                  and a second run is a no-op (file hash unchanged).
                  Controller ruling R2: a short list rewritten by the engine
                  legitimately collapses to ONE line (it fits), so no assertion
                  counts the physical lines of the short list.
    F2  forget    on the ORIGINAL fixture: --list-tags counts the [ProjB] tags on
                  the continuation lines; --project ProjB drops the ProjB-only
                  entries that sat there, removes every ProjB tag, keeps
                  [ProjA,ProjB] entries as [ProjA], and drops the emptied Target2
                  line WHOLE (all its physical lines).
    F3  CRLF      after F1 and after F2, every 0x0A is preceded by 0x0D.
    F4  wrapped   (Task 3) Wide.pas' Target4 has 150 ProjA callers, so the
        fresh     FRESH render is itself wrapped (the renderer breaks it); the
                  stored list holds three of them tagged [ProjA] and 30
                  ProjB-only entries. The merge must fold the fresh side too:
                  180 entries, each exactly once, every ProjA entry tagged
                  [ProjA], no line over 1000, and a fixed point.
    F5  legacy    (Task 3, R5b) a legacy fact line WITHOUT <para>, over 1000
                  characters, through doc-forget: it stays ONE line (a wrapped
                  legacy line would orphan its continuation, which FoldFactLine
                  cannot fold back) and keeps the tags it was not asked to drop.

  Explicit --db everywhere; nothing touches a real project database.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-fact-wrap-readers-$PID"
)
$ownWorkDir = -not $PSBoundParameters.ContainsKey('WorkDir')
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force -LiteralPath $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$shDir = Join-Path $WorkDir 'shared'
$aDir  = Join-Path $WorkDir 'appA'
$bDir  = Join-Path $WorkDir 'appB'
foreach ($d in $shDir, $aDir, $bDir) { New-Item -ItemType Directory $d | Out-Null }
$dbA    = Join-Path $WorkDir 'ProjA.sqlite'
$shared = Join-Path $shDir 'Shared.pas'

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Run([string[]]$xs) { $o = & $Exe @xs 2>&1 | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }

# The comment block directly above the declaration matching $DeclPat.
function BlockAbove([string]$DeclPat) {
  $ls = [IO.File]::ReadAllLines($shared); $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $DeclPat) { $d = $i; break } }
  if ($d -lt 0) { return ,@() }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) { if ($ls[$i] -notmatch '^\s*///') { break }; $acc = ,$ls[$i] + $acc }
  return ,$acc
}
# The block's text with every `///` prefix removed and the lines joined by one
# blank -- the LOGICAL view, in which a wrapped list is one list.
function Logical([string[]]$Block) {
  (($Block | ForEach-Object { $_ -replace '^\s*///\s?', '' }) -join ' ') -replace '\s+', ' '
}
function CalledFrom([string]$Logical) { if ($Logical -match 'Called from: (.*?)</para>') { $Matches[1] } else { '' } }
function Entries([string]$List) {
  # split on commas OUTSIDE a [tag,set]
  $out = @(); $depth = 0; $cur = ''
  foreach ($ch in $List.ToCharArray()) {
    if ($ch -eq '[') { $depth++ } elseif ($ch -eq ']') { $depth-- }
    if ($ch -eq ',' -and $depth -eq 0) { $out += $cur.Trim(); $cur = '' } else { $cur += $ch }
  }
  if ($cur.Trim() -ne '') { $out += $cur.Trim() }
  return ,$out
}
function BareLfCount([string]$Path) {
  $b = [IO.File]::ReadAllBytes($Path); $n = 0
  for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -eq 10 -and ($i -eq 0 -or $b[$i - 1] -ne 13)) { $n++ } }
  return $n
}
function MaxLineLen([string]$Path) {
  $m = 0; foreach ($l in [IO.File]::ReadAllLines($Path)) { if ($l.Length -gt $m) { $m = $l.Length } }; return $m
}
function TagCount([string]$Text, [string]$Tag) {
  $n = 0
  foreach ($m in [regex]::Matches($Text, '\[([^\]]*)\]')) {
    foreach ($t in $m.Groups[1].Value.Split(',')) { if ($t.Trim() -eq $Tag) { $n++ } }
  }
  return $n
}

# --- fixture ------------------------------------------------------------------
$long = @(1..40 | ForEach-Object { '[ProjB]uZ.RemoteCaller{0:D2} (uZ.pas)' -f $_ })
$longL1 = ($long[0..13]  -join ', ') + ','
$longL2 = ($long[14..27] -join ', ') + ','
$longL3 = ($long[28..39] -join ', ')

$fixture = @"
unit Shared;   // dl:shared ProjA, ProjB

interface

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: [ProjA]uA.A1 (uA.pas), [ProjA]uA.A2 (uA.pas),
/// [ProjA,ProjB]uX.Foo (uX.pas), [ProjB]uZ.Z1 (uZ.pas),
/// [ProjB]uZ.Z2 (uZ.pas), [ProjB]uZ.Z3 (uZ.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Target;
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: $longL1
/// $longL2
/// $longL3</para>
/// <para>Covered by: [ProjB]TestShared.TTests.Target2_works (TestShared.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Target2;
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: $longL1
/// $longL2
/// $longL3</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Target3;

implementation

procedure Target;
begin
end;

procedure Target2;
begin
end;

procedure Target3;
begin
  Target;
end;

end.
"@
Write-Ascii $shared $fixture
$original = [IO.File]::ReadAllBytes($shared)

Write-Ascii (Join-Path $shDir 'uX.pas') @'
unit uX;

interface

procedure Foo;

implementation

uses Shared;

procedure Foo; begin Target; end;

end.
'@
Write-Ascii (Join-Path $aDir 'uA.pas') @'
unit uA;

interface

procedure A1;
procedure A2;
procedure A3;

implementation

uses Shared;

procedure A1; begin Target; Target2; end;
procedure A2; begin Target; end;
procedure A3; begin Target; end;

end.
'@
Write-Ascii (Join-Path $aDir 'ProjA.dpr') @'
program ProjA;
uses Shared in '..\shared\Shared.pas', uX in '..\shared\uX.pas', uA in 'uA.pas',
  Wide in '..\shared\Wide.pas', uW in 'uW.pas';
begin
end.
'@
Write-Ascii (Join-Path $bDir 'uZ.pas') @'
unit uZ;

interface

procedure Z1;
procedure Z2;
procedure Z3;

implementation

uses Shared;

procedure Z1; begin Target; end;
procedure Z2; begin Target; end;
procedure Z3; begin Target; end;

end.
'@
Write-Ascii (Join-Path $bDir 'ProjB.dpr') @'
program ProjB;
uses Shared in '..\shared\Shared.pas', uX in '..\shared\uX.pas', uZ in 'uZ.pas';
begin
end.
'@

# F4 (Task 3): Target4 has 150 ProjA callers, so its FRESH render is wrapped.
# The stored list holds three of them, tagged, and 30 ProjB-only entries.
$wide   = Join-Path $shDir 'Wide.pas'
$wStored = @('[ProjA]uW.W001 (uW.pas)', '[ProjA]uW.W002 (uW.pas)', '[ProjA]uW.W150 (uW.pas)') +
           @(1..30 | ForEach-Object { '[ProjB]uZ.Far{0:D2} (uZ.pas)' -f $_ })
Write-Ascii $wide @"
unit Wide;   // dl:shared ProjA, ProjB

interface

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: $($wStored -join ', ')</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Target4;

implementation

procedure Target4;
begin
end;

end.
"@
$wDecls = (1..150 | ForEach-Object { 'procedure W{0:D3};' -f $_ }) -join "`n"
$wImpls = (1..150 | ForEach-Object { 'procedure W{0:D3}; begin Target4; end;' -f $_ }) -join "`n"
Write-Ascii (Join-Path $aDir 'uW.pas') "unit uW;`n`ninterface`n`n$wDecls`n`nimplementation`n`nuses Wide;`n`n$wImpls`n`nend.`n"

# F5 (Task 3, R5b): a LEGACY fact line -- no <para> -- over 1000 characters.
$legacy = Join-Path $WorkDir 'Legacy.pas'
$legacyEntries = @('[ProjA]uA.A1 (uA.pas)') + @(1..45 | ForEach-Object { '[ProjB]uZ.RemoteCaller{0:D2} (uZ.pas)' -f $_ }) + @('[ProjC]uC.C1 (uC.pas)')
Write-Ascii $legacy @"
unit Legacy;   // dl:shared ProjA, ProjB, ProjC

interface

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: $($legacyEntries -join ', ')
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Old;

implementation

procedure Old;
begin
end;

end.
"@
$r = Run @('index', '--project', (Join-Path $aDir 'ProjA.dpr'), '--db', $dbA)
Check 'setup: ProjA indexed' (($r.Code -eq 0) -and (Test-Path $dbA)) ($r.Out.Trim() -split "`n" | Select-Object -Last 1)
Check 'setup: the stored Target list spans 3 physical lines' (((BlockAbove '^procedure Target;') | Where-Object { $_ -match 'uZ\.|uA\.|uX\.' }).Count -eq 3) ''
Check 'setup: every stored line is within the limit' ((MaxLineLen $shared) -le 1000) "max $(MaxLineLen $shared)"

Write-Host 'fact-wrap readers' -ForegroundColor Cyan

# ------------------------------------------------------------------ F1: merge --
$r = Run @('document', '--unit', $shared, '--db', $dbA, '--apply', '--no-backup')
Check 'F1: document --apply ran' ($r.Code -eq 0) ($r.Out.Trim() -split "`n" | Select-Object -Last 1)

$es = Entries (CalledFrom (Logical (BlockAbove '^procedure Target;')))
$dups = @($es | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Check 'F1: Target -- no entry is duplicated' ($dups.Count -eq 0) "duplicates: $($dups -join ' | ')"
Check 'F1: Target -- ProjA''s missing caller was merged in' ($es -contains '[ProjA]uA.A3 (uA.pas)') ($es -join ' | ')
foreach ($z in 'Z1', 'Z2', 'Z3') {
  Check "F1: Target -- ProjB-only uZ.$z from a continuation line survives" ($es -contains "[ProjB]uZ.$z (uZ.pas)") ''
}
Check 'F1: Target -- the shared entry keeps both tags' ($es -contains '[ProjA,ProjB]uX.Foo (uX.pas)') ''
# eight: the fixture's six, ProjA's missing uA.A3, and Shared.Target3 (Target3 calls Target)
Check 'F1: Target -- exactly eight entries' ($es.Count -eq 8) "$($es.Count): $($es -join ' | ')"

$blk2 = BlockAbove '^procedure Target2;'
$es2  = Entries (CalledFrom (Logical $blk2))
$dups2 = @($es2 | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Check 'F1: Target2 -- no entry is duplicated' ($dups2.Count -eq 0) "duplicates: $($dups2.Count)"
Check 'F1: Target2 -- all 40 ProjB-only entries survive' ((@($es2 | Where-Object { $_ -like '`[ProjB`]uZ.RemoteCaller*' })).Count -eq 40) "$($es2.Count) entries"
Check 'F1: Target2 -- ProjA''s caller was merged in' ($es2 -contains '[ProjA]uA.A1 (uA.pas)') ''
Check 'F1: Target2 -- the merged list is written wrapped (more than one line)' ((@($blk2 | Where-Object { $_ -match 'RemoteCaller' })).Count -gt 1) ''
$lg2 = Logical $blk2
Check 'F1: Target2 -- Covered by is re-inserted whole, after the whole Called from list' ($lg2 -match 'RemoteCaller40 \(uZ\.pas\)</para> <para>Covered by: \[ProjB\]TestShared\.TTests\.Target2_works \(TestShared\.pas\)</para>') $lg2
Check 'F1: Target2 -- every physical line in the block is a /// line with no stray fact split' ((@($blk2 | Where-Object { $_ -match '<para>' })).Count -eq (@($blk2 | Where-Object { $_ -match '</para>' })).Count) ''
$blk3 = BlockAbove '^procedure Target3;'
$es3  = Entries (CalledFrom (Logical $blk3))
Check 'F1: Target3 -- the re-inserted list keeps all 40 entries, once each' (($es3.Count -eq 40) -and ((@($es3 | Sort-Object -Unique)).Count -eq 40)) "$($es3.Count) entries"
Check 'F1: Target3 -- the rendered facts are there too' ((Logical $blk3) -match 'Calls: .*Target') (Logical $blk3)
Check 'F1: Target3 -- the re-inserted list is written wrapped' ((@($blk3 | Where-Object { $_ -match 'RemoteCaller' })).Count -gt 1) ''
Check 'F1: no line of Shared.pas exceeds 1000 characters' ((MaxLineLen $shared) -le 1000) "max $(MaxLineLen $shared)"
Check 'F3: no bare LF after the merge' ((BareLfCount $shared) -eq 0) "bare LF: $(BareLfCount $shared)"

# Reindex first: the fixed point is asserted against the index of what was
# just written, not against a stale one.
$null = Run @('index', '--project', (Join-Path $aDir 'ProjA.dpr'), '--db', $dbA)
$h = (Get-FileHash $shared).Hash
$r = Run @('document', '--unit', $shared, '--db', $dbA, '--apply', '--no-backup')
Check 'F1: a second document run is a no-op' ((Get-FileHash $shared).Hash -eq $h) ($r.Out.Trim() -split "`n" | Select-Object -Last 1)

# ----------------------------------------------------------------- F2: forget --
# On the ORIGINAL fixture: after F1 the short list fits one line again (R2), so
# it no longer has a continuation line to test.
[IO.File]::WriteAllBytes($shared, $original)
$origText = [IO.File]::ReadAllText($shared)
$wantB = TagCount $origText 'ProjB'
$wantA = TagCount $origText 'ProjA'
$lt = (Run @('doc-forget', '--scope', $shared, '--list-tags')).Out
Check "F2: --list-tags counts every ProjB tag, continuation lines included ($wantB)" ($lt -match "(?m)^\s*$wantB\s+ProjB\s*$") $lt.Trim()
Check "F2: --list-tags counts every ProjA tag ($wantA)" ($lt -match "(?m)^\s*$wantA\s+ProjA\s*$") ''

$r = Run @('doc-forget', '--scope', $shared, '--project', 'ProjB', '--apply', '--no-backup')
Check 'F2: doc-forget ran' ($r.Code -eq 0) ''
# 4 tags in Target (uX + Z1..Z3), 40 each in Target2 and Target3 plus Target2's
# Covered by; Z1..Z3, all 80 and the test entry empty: 3 lines go whole.
Check 'F2: the counts include the continuation lines' ($r.Out -match '85 tag\(s\) removed, 0 renamed, 84 entr\(y/ies\) dropped, 3 line\(s\) dropped') ($r.Out.Trim() -split "`n" | Select-Object -Last 1)
$after = [IO.File]::ReadAllText($shared)
Check 'F2: no ProjB tag remains anywhere' ((TagCount $after 'ProjB') -eq 0) "left: $(TagCount $after 'ProjB')"
$es = Entries (CalledFrom (Logical (BlockAbove '^procedure Target;')))
Check 'F2: Target -- the ProjB-only entries on the continuation lines are gone' (-not ($es -match 'uZ\.')) ($es -join ' | ')
Check 'F2: Target -- [ProjA,ProjB] became [ProjA]' ($es -contains '[ProjA]uX.Foo (uX.pas)') ($es -join ' | ')
Check 'F2: Target -- ProjA entries kept' (($es -contains '[ProjA]uA.A1 (uA.pas)') -and ($es -contains '[ProjA]uA.A2 (uA.pas)')) ''
$blk2 = BlockAbove '^procedure Target2;'
Check 'F2: Target2 -- the emptied fact is dropped WHOLE, continuation lines too' (-not (($blk2 -join "`n") -match 'RemoteCaller|Called from')) ($blk2 -join ' / ')
Check 'F2: Target2 -- its fence is intact' ((($blk2 -join "`n") -match 'drag-lint:auto BEGIN') -and (($blk2 -join "`n") -match 'drag-lint:auto END')) ''
Check 'F3: no bare LF after doc-forget' ((BareLfCount $shared) -eq 0) "bare LF: $(BareLfCount $shared)"

# ------------------------------------------------------- F4: wrapped fresh ----
function BlockAboveIn([string]$Path, [string]$DeclPat) {
  $ls = [IO.File]::ReadAllLines($Path); $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $DeclPat) { $d = $i; break } }
  if ($d -lt 0) { return ,@() }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) { if ($ls[$i] -notmatch '^\s*///') { break }; $acc = ,$ls[$i] + $acc }
  return ,$acc
}
# F2 rewrote Shared.pas: reindex, so F4 runs on an index of what is on disk.
$null = Run @('index', '--project', (Join-Path $aDir 'ProjA.dpr'), '--db', $dbA)
$r = Run @('document', '--unit', $wide, '--db', $dbA, '--apply', '--no-backup')
Check 'F4: document --apply ran' ($r.Code -eq 0) ($r.Out.Trim() -split "`n" | Select-Object -Last 1)
$blk4 = BlockAboveIn $wide '^procedure Target4;'
$es4  = Entries (CalledFrom (Logical $blk4))
$bare4 = @($es4 | ForEach-Object { $_ -replace '^\[[^\]]*\]', '' })
$dups4 = @($bare4 | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Check 'F4: Target4 -- 180 entries (150 ProjA + 30 ProjB)' ($es4.Count -eq 180) "$($es4.Count) entries"
Check 'F4: Target4 -- no entry is duplicated (tags ignored)' ($dups4.Count -eq 0) "duplicates: $($dups4.Count) e.g. $($dups4 | Select-Object -First 3)"
Check 'F4: Target4 -- every ProjA caller is tagged [ProjA]' ((@($es4 | Where-Object { $_ -like '`[ProjA`]uW.W*' })).Count -eq 150) "$((@($es4 | Where-Object { $_ -like '`[ProjA`]uW.W*' })).Count) tagged"
Check 'F4: Target4 -- all 30 ProjB-only entries survive' ((@($es4 | Where-Object { $_ -like '`[ProjB`]uZ.Far*' })).Count -eq 30) ''
Check 'F4: Target4 -- the merged list is written wrapped' ((@($blk4 | Where-Object { $_ -match 'uW\.W' })).Count -gt 1) ''
Check 'F4: no line of Wide.pas exceeds 1000 characters' ((MaxLineLen $wide) -le 1000) "max $(MaxLineLen $wide)"
$null = Run @('index', '--project', (Join-Path $aDir 'ProjA.dpr'), '--db', $dbA)
$h = (Get-FileHash $wide).Hash
$r = Run @('document', '--unit', $wide, '--db', $dbA, '--apply', '--no-backup')
Check 'F4: a second document run is a no-op' ((Get-FileHash $wide).Hash -eq $h) ($r.Out.Trim() -split "`n" | Select-Object -Last 1)

# ------------------------------------------------------------- F5: legacy -----
$r = Run @('doc-forget', '--scope', $legacy, '--project', 'ProjC', '--apply', '--no-backup')
Check 'F5: doc-forget ran' ($r.Code -eq 0) ($r.Out.Trim() -split "`n" | Select-Object -Last 1)
$blk5 = BlockAboveIn $legacy '^procedure Old;'
$fact5 = @($blk5 | Where-Object { $_ -match 'uZ\.|uA\.' })
Check 'F5: the legacy line stays ONE physical line' ($fact5.Count -eq 1) "$($fact5.Count) lines"
Check 'F5: it is still a legacy line (no <para> added)' (($fact5 -join ' ') -notmatch '<para>') ''
Check 'F5: the ProjC entry is gone' (($fact5 -join ' ') -notmatch 'uC\.C1') ''
$l5 = $fact5 -join ' '
Check 'F5: the ProjA and ProjB tags are kept' (((TagCount $l5 'ProjA') -eq 1) -and ((TagCount $l5 'ProjB') -eq 45)) "ProjA $(TagCount $l5 'ProjA'), ProjB $(TagCount $l5 'ProjB')"
Check 'F5: POSITIVE CONTROL -- the line really is over 1000 characters' ((MaxLineLen $legacy) -gt 1000) "max $(MaxLineLen $legacy)"
Check 'F3: no bare LF after the legacy forget' ((BareLfCount $legacy) -eq 0) "bare LF: $(BareLfCount $legacy)"
Write-Host ''
if ($script:Failed) { Write-Host 'run_doc_fact_wrap_readers: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_doc_fact_wrap_readers: OK' -ForegroundColor Green
exit 0
} finally {
  if ($ownWorkDir -and (Test-Path -LiteralPath $WorkDir)) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
