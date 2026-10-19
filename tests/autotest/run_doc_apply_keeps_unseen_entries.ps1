<#
  run_doc_apply_keeps_unseen_entries.ps1 -- `document --unit --apply` keeps
  every inbound entry this index cannot see, on a NON-EMPTY render, and
  converges (B-05, 1.31.5).

  THE REPORT (docs\INBOX-document-apply-drops-facts-outside-the-db.md,
  DataCopy 2026-09-20): `document --unit uMicroniteFormat.pas --db DataCopy.sqlite
  --apply` took the `Used by: Test.*` / `Called from: Test.*` lines from 26 to 7.
  The project index is the compile closure and never holds Tests\*.pas, so the
  regeneration could not see those callers and simply omitted them. The guard
  of the day (run_doc_drift_document_apply.ps1) pinned `--qname` on a symbol
  whose fresh render is EMPTY; DataCopy's blocks have in-closure callers too,
  so they take the RESIDUAL path -- a different code path, and the one that
  still lost entries.

  RE-MEASURED 2026-10-18 on a scratch copy of DataCopy with 1.31.4: 82 distinct
  Test.* names before, 82 after, 0 lost; 28 doc-drift findings before the apply,
  0 after; a second apply is byte-identical. Fixed by the project-tag merge
  (ReconcileContent, 2026-09-23/24), which carries an untagged stored entry
  naming a unit this index cannot vouch for. This file pins that on the shape
  the report had, since no guard did:

    * CASE-UNIT: `--unit` on a block with BOTH in-closure callers and test
      callers; every Test.* entry survives, the in-scope ghost is removed
      (positive control: the regeneration really ran), `Covered by:` survives.
    * CASE-SUMMARY: a block whose fresh render is EMPTY under a declaration
      that also carries a hand-written <summary> -- so the merged comment is
      NOT empty and the empty-comment keep rule cannot be what saves it.
    * CASE-FIXED: a second apply writes nothing; doc-drift reports nothing.

  Bytes are compared on the APPLIED file -- a dry run proves the plan, never
  the bytes. Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-keepunseen-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$proj = Join-Path $root 'proj'
$tst  = Join-Path $proj 'Tests'
New-Item -ItemType Directory -Force -Path $tst | Out-Null

$crlf = "`r`n"
function WriteAscii($path, $lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join $crlf) + $crlf), (New-Object System.Text.ASCIIEncoding))
}
function Run([string[]]$xs) {
  $o = & $Exe @xs 2>&1 | Out-String
  [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}
# One declaration's OWN block (walk back over its /// run) -- a file-wide match
# is vacuous whenever another block carries the same text.
function BlockAbove([string]$path, [string]$declPat) {
  $ls = [IO.File]::ReadAllLines($path)
  $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $declPat) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) {
    if ($ls[$i] -notmatch '^\s*///') { break }
    $acc = ,$ls[$i] + $acc
  }
  return ($acc -join "`n")
}
function TestEntries([string]$block) {
  @([regex]::Matches($block, 'Test\.Prod\.[A-Za-z0-9_.]+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
}
function Edit([string]$path, [scriptblock]$f) {
  $t = [IO.File]::ReadAllText($path)
  [IO.File]::WriteAllText($path, (& $f $t), (New-Object System.Text.ASCIIEncoding))
}

# --- fixture ----------------------------------------------------------------
$uProd = Join-Path $proj 'uProd.pas'
WriteAscii $uProd @(
  'unit uProd;', 'interface',
  'type', '  TProd = class', '  public',
  '    procedure Ping;', '    procedure ProdOnly;',
  '    /// <summary>Hand-written, and it stays.</summary>',
  '    procedure OnlyTestedDoc;',
  '  end;',
  'implementation',
  'procedure TProd.Ping; begin end;',
  'procedure TProd.ProdOnly; begin end;',
  'procedure TProd.OnlyTestedDoc; begin end;',
  'end.')
WriteAscii (Join-Path $proj 'uOther.pas') @(
  'unit uOther;', 'interface', 'procedure OtherCalls;', 'implementation', 'uses uProd;',
  'procedure OtherCalls;', 'var P: TProd;', 'begin', '  P:= TProd.Create;', '  P.Ping;', '  P.ProdOnly;', 'end;',
  'end.')
WriteAscii (Join-Path $tst 'Test.Prod.pas') @(
  'unit Test.Prod;', 'interface', 'procedure TestAll;', 'procedure TestDoc;', 'implementation', 'uses uProd;',
  'procedure TestAll;', 'var P: TProd;', 'begin', '  P:= TProd.Create;', '  P.Ping;', 'end;',
  'procedure TestDoc;', 'var P: TProd;', 'begin', '  P:= TProd.Create;', '  P.Ping;', '  P.OnlyTestedDoc;', 'end;',
  'end.')
WriteAscii (Join-Path $proj 'Prod.dpr') @('program Prod;', "uses uProd in 'uProd.pas', uOther in 'uOther.pas';", 'begin', 'end.')

$wide = Join-Path $root 'wide.sqlite'
$prod = Join-Path $root 'prod.sqlite'
$r = Run @('index',$proj,'--db',$wide);                                     Check 'setup: wide (folder) index built'   ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('index','--project',(Join-Path $proj 'Prod.dpr'),'--db',$prod);  Check 'setup: prod (closure) index built' ($r.Code -eq 0) "exit $($r.Code)"
$q = Run @('query','--name','TestAll','--db',$prod)
Check 'setup: the closure DB does NOT hold the test unit' ($q.Out -notmatch 'Test\.Prod') 'TestAll absent from prod.sqlite'

# Blocks are ENGINE-WRITTEN from the wide DB: the shape DataCopy had.
$r = Run @('document','--unit',$uProd,'--db',$wide,'--apply')
Check 'setup: fact blocks written from the WIDE db' ($r.Code -eq 0) "exit $($r.Code)"
$pingBefore = BlockAbove $uProd 'procedure Ping;'
$docBefore  = BlockAbove $uProd 'procedure OnlyTestedDoc;'
Check 'setup: Ping''s block has an IN-CLOSURE caller (non-empty render)' ($pingBefore -match 'uOther') 'the residual path'
Check 'setup: Ping''s block names TWO test callers' ((TestEntries $pingBefore).Count -ge 2) ((TestEntries $pingBefore) -join ', ')
Check 'setup: Ping''s block carries an engine-written Covered by:' ($pingBefore -match 'Covered by:') 'wide db saw the tests'
Check 'setup: OnlyTestedDoc keeps its hand summary beside the block' (($docBefore -match 'Hand-written') -and ($docBefore -match 'Test\.Prod')) $docBefore

# Age Ping's block with an in-scope ghost -- the regeneration MUST run and MUST
# remove it (otherwise "kept the test entries" is vacuous: nothing was written).
# Entries are sorted, so uOther.* sits LAST in Ping's list; ProdOnly's block
# gets the same ghost (in-closure, reaped the same way) and is not asserted on.
Edit $uProd { param($t) $t.Replace('uOther.OtherCalls (uOther.pas)</para>', 'uOther.NoSuchProc (uOther.pas), uOther.OtherCalls (uOther.pas)</para>') }
$pingBefore = BlockAbove $uProd 'procedure Ping;'
Check 'setup: the ghost landed in Ping''s own block' ($pingBefore -match 'NoSuchProc') 'scoped to Ping'
$r = Run @('index','--project',(Join-Path $proj 'Prod.dpr'),'--db',$prod)
Check 'setup: closure DB reindexed after the edits' ($r.Code -eq 0) "exit $($r.Code)"
$entriesBefore = TestEntries $pingBefore

# --- CASE-UNIT ---------------------------------------------------------------
$r = Run @('document','--unit',$uProd,'--db',$prod,'--apply')
Check 'CASE-UNIT document --unit --apply ran from the closure db' ($r.Code -eq 0) $r.Out.Trim()
$pingAfter = BlockAbove $uProd 'procedure Ping;'
Check 'CASE-UNIT the in-scope ghost was removed (the regeneration ran)' ($pingAfter -notmatch 'NoSuchProc') $pingAfter
Check 'CASE-UNIT the in-closure caller survived' ($pingAfter -match 'uOther\.OtherCalls') $pingAfter
$entriesAfter = TestEntries $pingAfter
$lost = @(Compare-Object $entriesBefore $entriesAfter | Where-Object SideIndicator -eq '<=' | ForEach-Object InputObject)
Check 'CASE-UNIT every Test.* entry survived in Ping''s block' ($lost.Count -eq 0) "lost: $($lost -join ', ')"
Check 'CASE-UNIT Covered by: survived in Ping''s block' ($pingAfter -match 'Covered by:') $pingAfter
Check 'CASE-UNIT the file is still 7-bit ASCII with CRLF' `
  ((-not ([IO.File]::ReadAllBytes($uProd) | Where-Object { $_ -gt 127 })) -and ([IO.File]::ReadAllText($uProd) -notmatch '(?<!\r)\n')) 'bytes'

# --- CASE-SUMMARY: empty fresh render under a hand summary -------------------
$docAfter = BlockAbove $uProd 'procedure OnlyTestedDoc;'
Check 'CASE-SUMMARY the hand summary is still there' ($docAfter -match 'Hand-written') $docAfter
Check 'CASE-SUMMARY the test caller this index cannot see is still there' ($docAfter -match 'Called from: .*Test\.Prod') $docAfter
Check 'CASE-SUMMARY Covered by: is still there' ($docAfter -match 'Covered by:') $docAfter

# --- CASE-FIXED: convergence ------------------------------------------------
$r = Run @('index','--project',(Join-Path $proj 'Prod.dpr'),'--db',$prod)
$d = Run @('lint',$uProd,'--db',$prod,'--project-rules','--rule','doc-drift')
Check 'CASE-FIXED doc-drift reports nothing on the applied file' ($d.Out -match '(?m)^0 finding\(s\)') $d.Out.Trim()
$h0 = (Get-FileHash $uProd -Algorithm MD5).Hash
$r = Run @('document','--unit',$uProd,'--db',$prod,'--apply')
$h1 = (Get-FileHash $uProd -Algorithm MD5).Hash
Check 'CASE-FIXED a second document --apply is byte-identical' ($h0 -eq $h1) "$h0 vs $h1"

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
