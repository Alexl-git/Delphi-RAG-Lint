<#
  pending_doc_drift_document_apply.ps1 -- RED ON PURPOSE. A confirmed, unfixed gap.

  `document --apply` DELETES managed facts that the index structurally cannot
  see. It is the exact command DataCopy's report named, and it is NOT gated by
  the `fixable` flag, so the Step-1 fix (run_doc_drift_unseen_units.ps1) does
  not protect it. Measured 2026-09-02 on this fixture:

      document --qname uProd.TProd.OnlyTested --db <closure.sqlite> --apply
        -> doc: removed -- 1 edit(s) applied (.bak written)

  and the block loses BOTH `Called from: Test.Prod.TestAll (Test.Prod.pas)` and
  `Covered by: Test.Prod.TestAll` -- true facts about tests that exist.

  It goes GREEN when Step 2 lands: the writer preserving stored entries whose
  unit this index cannot vouch for, on UNMARKED units, the way it already does
  on `dl:shared` ones.

  THREE VACUITIES PRODUCED THIS ASSERTION BEFORE IT WAS HONEST, all in one
  sitting, and they are why the setup checks below are not optional:
    1. matching `Test.Prod` file-wide -- TProd's CLASS block names it too, so the
       assertion passed while OnlyTested's block was being deleted;
    2. no reindex after the preceding --apply, so `document` refused at an
       unverified coordinate ("Nothing was written") and the assertion passed
       because the command never ran;
    3. the control symbol was itself called by the test, so its block was
       legitimately unvouchable.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-unseen-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$proj = Join-Path $root 'proj'
$tst  = Join-Path $proj 'Tests'
New-Item -ItemType Directory -Force -Path $tst | Out-Null

$crlf = "`r`n"
function WriteAscii($path, $lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join $crlf) + $crlf), (New-Object System.Text.ASCIIEncoding))
}
# --- READ ONE DECLARATION'S OWN BLOCK ----------------------------------------
# ASSERTIONS MUST BE SCOPED TO THE BLOCK UNDER TEST. The first version matched
# `Test.Prod` anywhere in the file, and TProd's CLASS-level block names it too --
# so CASE-FIX and CASE-DOC both passed while `document --apply` was deleting
# OnlyTested's block outright ("doc: removed -- 1 edit(s) applied", losing both
# `Called from: Test.Prod.TestAll` and `Covered by:`). A file-wide match is a
# vacuous assertion whenever any OTHER block carries the same text.
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

function Run([string[]]$xs) {
  $o = & $Exe @xs 2>&1 | Out-String
  [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}

# --- fixture ----------------------------------------------------------------
WriteAscii (Join-Path $proj 'uProd.pas') @(
  'unit uProd;', 'interface',
  'type', '  TProd = class', '  public',
  '    procedure Ping;', '    procedure ProdOnly;', '    procedure OnlyTested;', '  end;',
  'implementation',
  'procedure TProd.Ping; begin end;',
  'procedure TProd.ProdOnly; begin end;',
  'procedure TProd.OnlyTested; begin end;',
  'end.')
WriteAscii (Join-Path $proj 'uOther.pas') @(
  'unit uOther;', 'interface', 'procedure OtherCalls;', 'implementation', 'uses uProd;',
  'procedure OtherCalls;', 'var P: TProd;', 'begin', '  P:= TProd.Create;', '  P.Ping;', '  P.ProdOnly;', 'end;',
  'end.')
WriteAscii (Join-Path $tst 'Test.Prod.pas') @(
  'unit Test.Prod;', 'interface', 'procedure TestAll;', 'implementation', 'uses uProd;',
  'procedure TestAll;', 'var P: TProd;', 'begin', '  P:= TProd.Create;', '  P.Ping;', '  P.OnlyTested;', 'end;',
  'end.')
WriteAscii (Join-Path $proj 'Prod.dpr') @(
  'program Prod;',
  "uses uProd in 'uProd.pas', uOther in 'uOther.pas';",
  'begin', 'end.')

$wide = Join-Path $root 'wide.sqlite'
$prod = Join-Path $root 'prod.sqlite'

$r = Run @('index',$proj,'--db',$wide);                              Check 'setup: wide (folder) index built'   ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('index','--project',(Join-Path $proj 'Prod.dpr'),'--db',$prod); Check 'setup: prod (closure) index built' ($r.Code -eq 0) "exit $($r.Code)"

# The closure DB must NOT hold the test unit -- otherwise every case below is
# vacuous. Assert it, do not assume it.
$q = Run @('query','--name','TestAll','--db',$prod)
Check 'setup: the closure DB does NOT hold the test unit' ($q.Out -notmatch 'Test\.Prod') 'TestAll absent from prod.sqlite'
$q = Run @('query','--name','TestAll','--db',$wide)
Check 'setup: the wide DB DOES hold the test unit' ($q.Out -match 'TestAll') 'TestAll present in wide.sqlite'

# --- blocks are ENGINE-WRITTEN from the wide DB, then the prod DB is reindexed
$r = Run @('document','--unit',(Join-Path $proj 'uProd.pas'),'--db',$wide,'--apply')
Check 'setup: fact blocks written from the WIDE db' ($r.Code -eq 0) "exit $($r.Code)"
$src = [System.IO.File]::ReadAllText((Join-Path $proj 'uProd.pas'))
Check 'setup: the written block names the TEST unit' ($src -match 'Test\.Prod') 'Test.Prod appears in uProd.pas'

# EACH SHAPE MUST LAND IN A BLOCK THAT HAS ONLY THAT SHAPE.
# Three earlier attempts got this wrong and CONTROL-1 went red against a CORRECT
# engine every time -- the control doing its job, on the fixture:
#   1. a global -replace put `Covered by:` into BOTH blocks;
#   2. the control used Ping, which the TEST also calls, so its block truthfully
#      named an unseen unit and was rightly not vouchable;
#   3. the source was cut AT each declaration -- but a doc block PRECEDES its
#      declaration, so both injections landed one block early.
# Hence: anchor on the declaration line and walk BACKWARD into its own block,
# and assert afterwards that each injection landed where it was aimed.
#
#   ProdOnly's block   -> only the in-scope ghost   (must stay FIXABLE)
#   OnlyTested's block -> only the unseen-test loss (must stop being FIXABLE)
$lines = [System.Collections.ArrayList]@($src -split "`r?`n")

function InjectAbove([System.Collections.ArrayList]$ls, [string]$declPat, [string]$text) {
  $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $declPat) { $d = $i; break } }
  if ($d -lt 0) { return -1 }
  # Walk back over this declaration's own /// block to its first fact line.
  for ($i = $d - 1; $i -ge 0; $i--) {
    if ($ls[$i] -notmatch '^\s*///') { break }
    if ($ls[$i] -match '<para>(Called from:|Used by:|Used in units:)') { $ls.Insert($i, $text); return $i }
  }
  return -1
}

$gi = InjectAbove $lines 'procedure ProdOnly;'   '/// <para>Called from: uOther.NoSuchProc (uOther.pas)</para>'
Check 'setup: the ghost landed in ProdOnly''s own block' ($gi -ge 0) "line $gi"
$ci = InjectAbove $lines 'procedure OnlyTested;' '/// <para>Covered by: Test.Prod.TProdTests.Ping_works, Test.Prod.TProdTests.OnlyTested_works</para>'
Check 'setup: the Covered-by landed in OnlyTested''s own block' ($ci -ge 0) "line $ci"
Check 'setup: the two injections are in DIFFERENT blocks' (($gi -ge 0) -and ($ci -gt $gi + 1)) "ghost@$gi covered@$ci"
$src = ($lines -join $crlf)
[System.IO.File]::WriteAllText((Join-Path $proj 'uProd.pas'), $src, (New-Object System.Text.ASCIIEncoding))

$r = Run @('index','--project',(Join-Path $proj 'Prod.dpr'),'--db',$prod)
Check 'setup: closure DB reindexed after the edits' ($r.Code -eq 0) "exit $($r.Code)"

function DriftJson($qname, $db) { (Run @('doc-drift','--qname',$qname,'--db',$db,'--json')).Out }
function DriftText($qname, $db) { (Run @('doc-drift','--qname',$qname,'--db',$db)).Out }

$pingJ = DriftJson 'uProd.TProd.ProdOnly'   $prod
$pingT = DriftText 'uProd.TProd.ProdOnly'   $prod
$onlyJ = DriftJson 'uProd.TProd.OnlyTested' $prod
$onlyT = DriftText 'uProd.TProd.OnlyTested' $prod

$uProdPas = Join-Path $proj 'uProd.pas'

# --- CASE-DOC: `document --apply` is the command the ORIGINAL REPORT named ----
# lint-all --fix --apply is gated on the fixable flag. `document --apply` may
# not be. If it is not, Step 1 does not protect the very command that was
# reported, and the [FIXABLE] label was only half the exposure.
# REINDEX FIRST. CASE-FIX's --apply shifted lines, so document refuses at an
# unverified coordinate ("the reindex FAILED. Nothing was written") -- and the
# assertions below then pass because the command NEVER RAN. That is the third
# distinct vacuity this one suite has produced; assert the command did work.
$r = Run @('index','--project',(Join-Path $proj 'Prod.dpr'),'--db',$prod)
Check 'CASE-DOC setup: reindexed before document --apply' ($r.Code -eq 0) "exit $($r.Code)"
$docRun = Run @('document','--qname','uProd.TProd.OnlyTested','--db',$prod,'--apply')
Check 'CASE-DOC setup: document --apply actually ran (not refused at a stale coordinate)' `
  ($docRun.Out -notmatch 'Nothing was written') ($docRun.Out -split "`r?`n" | Where-Object { $_ -match 'doc:' })
Write-Host ("      document --apply said: " + ($docRun.Out -split "`r?`n" | Where-Object { $_ -match 'doc:' }) )
$blkDoc = BlockAbove $uProdPas 'procedure OnlyTested;'
Check 'CASE-DOC document --apply leaves the TEST entries in OnlyTested''s block' ($blkDoc -match 'Test\.Prod') 'scoped to OnlyTested'
Check 'CASE-DOC document --apply leaves the Covered by: line in OnlyTested''s block' ($blkDoc -match 'Covered by:') 'scoped to OnlyTested'


Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
if ($fail) { Write-Host 'FAIL (expected -- Step 2 not yet shipped)' -ForegroundColor Yellow; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
