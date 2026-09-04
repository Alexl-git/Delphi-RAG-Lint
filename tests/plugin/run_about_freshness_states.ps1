<#
  run_about_freshness_states.ps1 -- the About window's index FRESHNESS must
  distinguish current / resolve-owed / reparse-owed, and the two owed states
  must not collapse into each other.

  WHY THIS EXISTS, AND WHY ITS ABSENCE WAS THE POINT.

  `4993460` shipped the feature. Its own note
  (docs\INBOX-Done\INBOX-about-window-cannot-see-index-staleness.md) closed with
  an explicit instruction:

    "Guard it against the reason it exists: the test must FAIL when a database
     is aged behind the current constants and the window still reports [ok] --
     not merely assert that a fresh one reports [ok], which is the vacuous
     version and passes today."

  The guard was never written. So for three days the state was exactly the
  vacuity the note warned about: a fresh index reporting `current` is what
  happens with the feature switched OFF, and nothing could tell the two apart.

  The failure it protects against is not cosmetic. The unit's own header says a
  stale index "answers confidently, just with older and fewer results", and the
  About window exists to stop precisely that. A green tick that means only "the
  file is present" is worse than no tick.

  TWO HALVES, because the logic lives in two places.

  A. BEHAVIOURAL, against the ENGINE. Freshness is delegated to
     `info --json --db`, which is what made the feature affordable (MEASURED at
     0.099 s for a project index PLUS the 2.37 GB library index in ONE spawn --
     three orders of magnitude from the 38 s figure the "never open a database"
     performance contract was written against, and that 38 s was `schema
     --format json` counting every table, not an indexed lookup). Because it is
     the CLI that decides, the aged cases can be tested headlessly and for real.

  B. STATIC, against the PLUGIN's mapping. There is no headless harness for the
     BPL -- the tests\plugin runners are all source-text checks for that reason.
     What is checkable is that VerdictLine keeps the three verdicts on three
     different severities. Both halves carry their own POSITIVE CONTROL, because
     a text scan that cannot fail is this repo's commonest wound.

  ONE DELIBERATE DIVERGENCE FROM THE NOTE, STATED RATHER THAN QUIETLY DROPPED.
  The note asked for the resolve-owed line to name `--resolve-only`. The shipped
  text says "re-resolve needed (minutes)". The load-bearing property is that the
  CHEAP remedy is signalled as cheap, so that is what is asserted; asserting a
  literal flag name the code does not use would fail against correct code. The
  note also expected reparse-owed at dsWarn; it ships at dsBad, which is
  stronger, and that is asserted as-shipped.

  Needs: python (sqlite3) -- the same dependency run_resolver_stamp_absent_is_stale
  already has, and for the same reason: ageing a fingerprint is a write the
  engine deliberately offers no verb for.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Dir     = "$PSScriptRoot\..\..\src\delphi-plugin",
  [string]$WorkDir = "$env:TEMP\draglint_about_freshness",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("  [{0}] {1}" -f (@('FAIL', 'PASS')[[int]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "        $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function W($p, $s) {
  [System.IO.File]::WriteAllText($p, (($s -replace "`r`n", "`n") -replace "`n", "`r`n"),
                                 (New-Object System.Text.UTF8Encoding($false)))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$diagPath = Join-Path $Dir 'DragLint.Plugin.Diagnose.pas'
if (-not (Test-Path $diagPath)) { Write-Host "FATAL: not found: $diagPath" -ForegroundColor Red; exit 2 }
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
  Write-Host 'SKIP: python not on PATH -- ageing a fingerprint needs sqlite3' -ForegroundColor Yellow
  exit 0
}

# =============================== HALF A ====================================
Write-Host '== A. the ENGINE decides freshness, and must tell the three states apart ==' -ForegroundColor Cyan

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path (Join-Path $WorkDir '_D-RAG') | Out-Null
W (Join-Path $WorkDir 'uA.pas') @'
unit uA;
interface
procedure Go;
implementation
procedure Go;
begin
end;
end.
'@
W (Join-Path $WorkDir 'App.dpr') @'
program App;
uses
  uA in 'uA.pas';
begin
end.
'@
$db = Join-Path $WorkDir '_D-RAG\App.sqlite'

$py = Join-Path $WorkDir 'exec.py'
[System.IO.File]::WriteAllText($py,
  "import sqlite3,sys`nc=sqlite3.connect(sys.argv[1])`nc.execute(sys.argv[2])`nc.commit();c.close()`n",
  [System.Text.Encoding]::ASCII)

function Reindex { & $Exe index --project (Join-Path $WorkDir 'App.dpr') --db $db 2>&1 | Out-Null }
function IndexRow {
  $j = (& $Exe info --json --db $db 2>$null) -join "`n"
  $i = $j.IndexOf('{')
  if ($i -lt 0) { return $null }
  try { return ($j.Substring($i) | ConvertFrom-Json).indexes[0] } catch { return $null }
}

Reindex
$rowOk = IndexRow
Check 'CONTROL: an untouched index reports verdict=current' `
  (($null -ne $rowOk) -and ($rowOk.verdict -eq 'current')) `
  "got '$($rowOk.verdict)' -- if the control is not current, the aged cases below prove nothing"

# --- resolve-owed: the CHEAP owed state -------------------------------------
& python $py $db "DELETE FROM schema_meta WHERE key='resolver_fingerprint'" | Out-Null
$rowRes = IndexRow
Check 'a MISSING resolver stamp is resolve-owed, not current' `
  (($null -ne $rowRes) -and ($rowRes.verdict -eq 'resolve-owed')) `
  "got '$($rowRes.verdict)' -- an absent stamp read as fresh is the failure recorded as 'a MISSING stamp is STALE, not fresh'"
Check 'and it is flagged on the RESOLVER, not the indexer' `
  (($null -ne $rowRes) -and ($rowRes.resolver_stale -eq $true) -and ($rowRes.indexer_stale -eq $false)) `
  "resolver_stale=$($rowRes.resolver_stale) indexer_stale=$($rowRes.indexer_stale) -- mislabelling the cheap state as the expensive one is how a re-resolve is deferred for ever"

# --- reparse-owed: the EXPENSIVE owed state ---------------------------------
Reindex
& python $py $db "UPDATE schema_meta SET value='v=0.0.1-ancient;schema=21;pp=1;plat=win64' WHERE key='indexer_fingerprint'" | Out-Null
$rowRep = IndexRow
Check 'an index a whole extractor version behind is reparse-owed' `
  (($null -ne $rowRep) -and ($rowRep.verdict -eq 'reparse-owed')) `
  "got '$($rowRep.verdict)' -- this is the exact case the About window used to show [ok] for"
Check 'and it is flagged on the INDEXER' `
  (($null -ne $rowRep) -and ($rowRep.indexer_stale -eq $true)) `
  "indexer_stale=$($rowRep.indexer_stale)"

# THE ASSERTION THAT MAKES THE THREE ABOVE MEAN SOMETHING. If freshness ever
# degrades to a constant -- which is precisely what the pre-4993460 behaviour
# was, since [ok] meant "the file exists" -- every case above could still pass
# individually. They must be three DISTINCT answers.
$verdicts = @($rowOk.verdict, $rowRes.verdict, $rowRep.verdict) | Where-Object { $_ } | Sort-Object -Unique
Check 'CONTROL: the three states are three DISTINCT verdicts' ($verdicts.Count -eq 3) `
  "got: $($verdicts -join ', ') -- a freshness report that cannot vary is the [ok]-means-present bug again"

# And the fixture must genuinely have been aged, or the two cases above are
# measuring an unmodified database.
$fp = (& $Exe sql --query "SELECT value FROM schema_meta WHERE key='indexer_fingerprint'" --db $db --json 2>$null) -join "`n"
Check 'FIXTURE INTEGRITY: the ageing write actually took' ($fp -match '0\.0\.1-ancient') `
  'the UPDATE did not land, so "reparse-owed" above was not produced by an aged index'

# =============================== HALF B ====================================
Write-Host ''
Write-Host '== B. the PLUGIN maps the three verdicts to three severities ==' -ForegroundColor Cyan

function CheckMapping($src, $label) {
  $ok = $true
  $why = @()
  # VerdictLine's body, isolated so an unrelated dsOk elsewhere cannot satisfy these.
  if ($src -match '(?s)function VerdictLine\(const AVerdict: string\): TDiagLine;(.*?)\r?\nend;') {
    $body = $Matches[1]
    if ($body -notmatch "SameText\(AVerdict, 'current'\)[\s\S]{0,200}?dsOk")       { $ok = $false; $why += "current is not dsOk" }
    if ($body -notmatch "SameText\(AVerdict, 'resolve-owed'\)[\s\S]{0,200}?dsWarn"){ $ok = $false; $why += "resolve-owed is not dsWarn" }
    if ($body -notmatch "SameText\(AVerdict, 'reparse-owed'\)[\s\S]{0,200}?dsBad") { $ok = $false; $why += "reparse-owed is not dsBad" }
    if ($body -notmatch "AVerdict = ''[\s\S]{0,200}?dsWarn")                        { $ok = $false; $why += "an ABSENT verdict is not dsWarn" }
    if ($body -notmatch '(?i)minutes')                                              { $ok = $false; $why += "resolve-owed does not signal the CHEAP cost" }
    if ($body -notmatch '(?i)STALE')                                                { $ok = $false; $why += "reparse-owed does not say answers are stale" }
  } else { $ok = $false; $why += 'VerdictLine not found' }
  return ,@($ok, ($why -join '; '))
}

$diag = Get-Content $diagPath -Raw
$r = CheckMapping $diag 'shipped'
Check 'VerdictLine keeps the three verdicts on three severities, with honest text' $r[0] $r[1]

# The two owed states must be DIFFERENT severities. This is the property the
# code's own comment argues for -- "treating the cheap one as the expensive one
# is how a re-resolve gets deferred indefinitely" -- and it is the one a
# well-meaning simplification would erase.
Check 'the two owed states are NOT collapsed to one severity' `
  ($diag -match "resolve-owed'\)[\s\S]{0,200}?dsWarn" -and $diag -match "reparse-owed'\)[\s\S]{0,200}?dsBad") `
  'resolve-owed (minutes) and reparse-owed (hours) must stay distinguishable'

# >>> POSITIVE CONTROL for half B. A static scan that cannot fail is worthless,
# so break a COPY in exactly the way that matters -- reparse-owed reported as
# healthy, which is the original bug -- and require the same check to fail.
$broken = $diag -replace "(SameText\(AVerdict, 'reparse-owed'\)[\s\S]{0,200}?)dsBad", '$1dsOk'
$rb = CheckMapping $broken 'broken'
Check 'POSITIVE CONTROL: mapping reparse-owed to dsOk makes half B FAIL' `
  ((-not $rb[0]) -and ($broken -ne $diag)) `
  'the static check passed against a deliberately broken copy -- it cannot detect the bug it exists for'

Write-Host ''
if ($script:fail) { Write-Host 'ABOUT-FRESHNESS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'ABOUT-FRESHNESS GUARD: PASS' -ForegroundColor Green
exit 0
