<#
  run_doc_drift_unseen_units.ps1 -- a managed facts block must not be
  advertised as auto-fixable when the regeneration would DELETE true facts this
  database cannot see.

  THE DEFECT (DataCopy, 2026-09-02, docs\INBOX-doc-drift-vs-split-project-test-dbs.md).
  Under the one-DB-per-project layout a production project DB is exactly the
  compile closure, so it can NEVER hold a test caller. Fact blocks written when
  one DB covered production AND tests now regenerate to a strict subset:

    stored : Covered by: <41 tests>            Used by: <30 entries>
    fresh  : (no Covered by: line at all)      Used by: <2 entries>

  doc-drift reports ddFactsBlockStale [FIXABLE] and the offered repair makes the
  committed record LESS TRUE. 43 findings across 9 units in DataCopy, firing for
  ever, caused by no code change.

  MEASURED, and it is why this suite tests two shapes and not one:
    * `Used by:` / `Called from:` / `Used in units:` are NARROWED (entry-level).
    * `Covered by:` is DELETED WHOLE. It names tests by definition, so a closure
      DB can never reproduce any of it, and it is NOT in INBOUND_LABELS -- it
      falls to the byte-compared residual and the existing shared-facts
      forgiveness never sees it. A fix that widened only the three inbound
      labels would leave the LARGEST loss untouched.

  STEP 1 SCOPE (this file, first commit): stop calling it FIXABLE. The finding
  still reports; it is simply no longer offered as a safe automatic repair.
  Preserving the facts on regeneration is Step 2.

  POSITIVE CONTROLS COME FIRST, deliberately. A predicate that answered "never
  fixable" would pass every Step-1 assertion below while silently disabling the
  feature; CONTROL-1 is what forbids that. This repo has shipped 8 vacuous
  fixtures across 3 projects -- the known-firing case leads.

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

# --- CONTROL-1: an IN-SCOPE entry that is genuinely gone stays FIXABLE -------
# ProdOnly is called by uOther and by no test. uOther.pas IS in the closure, and
# uOther.NoSuchProc does not exist. The engine
# can vouch for its absence, so this must remain an offered repair. If this goes
# red the predicate has over-reached and disabled the feature.
Check 'CONTROL-1 an in-scope ghost entry is reported' ($pingT -match 'ddFactsBlockStale') $($pingT.Trim())
Check 'CONTROL-1 an in-scope ghost entry is still FIXABLE' ($pingT -match '\[FIXABLE\]') $($pingT.Trim())

# --- CASE-A: entries naming a unit the closure cannot see -> NOT fixable ----
Check 'CASE-A a block naming an unseen TEST unit is reported' ($onlyT -match 'ddFactsBlockStale') $($onlyT.Trim())
Check 'CASE-A a block naming an unseen TEST unit is NOT fixable (text)' ($onlyT -notmatch '\[FIXABLE\]') $($onlyT.Trim())
Check 'CASE-A a block naming an unseen TEST unit is NOT fixable (json)' ($onlyJ -notmatch '"fixable"\s*:\s*true') $($onlyJ.Trim())

# --- CASE-COVERED: a whole label the regeneration drops -> NOT fixable ------
# `Covered by:` is absent from the fresh render entirely, and is not in
# INBOUND_LABELS, so entry-level forgiveness cannot see it.
$reg = (Run @('document','--qname','uProd.TProd.OnlyTested','--db',$prod)).Out
Check 'CASE-COVERED the regeneration really does drop the whole label' `
  ($reg -notmatch 'Covered by:') 'no Covered by: in the proposed text'

# --- CASE-FIX: --fix --apply must not delete what it cannot vouch for -------
$before = [System.IO.File]::ReadAllText((Join-Path $proj 'uProd.pas'))
$null = Run @('lint-all','--db',$prod,'--fix','--apply')
$after = [System.IO.File]::ReadAllText((Join-Path $proj 'uProd.pas'))
Check 'CASE-FIX --fix --apply leaves the TEST entries in place' ($after -match 'Test\.Prod') 'Test.Prod survived --apply'
Check 'CASE-FIX --fix --apply leaves the Covered by: line in place' ($after -match 'Covered by:') 'Covered by: survived --apply'

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
