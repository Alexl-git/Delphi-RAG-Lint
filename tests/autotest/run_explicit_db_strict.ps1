<#
  run_explicit_db_strict.ps1 --
  An explicit `--db` naming a file that does not exist must REFUSE the run.

  THE DEFECT. Most verbs do `if not TFile.Exists(Db) then Continue;` -- they drop
  the missing database and answer from whatever is left, exit 0, with nothing on
  either stream. So `convert-scaffold --db app --db lib-typo` drafts rules from
  the app index alone, `convert-validate` then validates against that same short
  corpus and succeeds, and `convert-apply` rewrites a form on the strength of it.
  Every downstream step inherits the error while reporting success.

  Reported by the converter team 2026-09-09 against `proptree`; the owner ruled on
  2026-09-14 that it must be strict everywhere -- "without stricter type matching
  we cannot reliably convert or create conversion rules". A full audit then found
  40 sites, 31 needing the change, including three `query` subcommands (so `query`
  was not even self-consistent) and `lint <file>`, which silently drops the
  store-backed rules and reports FEWER findings: measured 429 with a good index
  vs 422 with a missing one, same exit code, silence on both streams.

  WHAT MAKES THIS GUARD HONEST. T1-T7 assert the refusal. On their own they would
  all pass against a build that exits 2 unconditionally -- i.e. against a
  completely broken engine. P1-P4 are the positive controls that forbid that
  reading, and V is the vacuity check. Do not delete a P row to make a run green.

  THE RED REQUIREMENT. Run this against the SHIPPED exe BEFORE building the fix.
  T1-T7 must FAIL for the lenient verbs and PASS for `query` (already strict); P1-P4
  must already PASS. A guard that is green before the fix is not evidence.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_explicit_db_strict",
  [switch]$ListRedOnly   # print a RED/GREEN matrix and exit 0 -- for capturing evidence pre-fix
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

# An orphaned engine holding a fixture DB turns every row below into a lock error
# that reads as a failure. Say so up front rather than letting it look like one.
$orphans = @(Get-Process drag-lint -ErrorAction SilentlyContinue)
if ($orphans.Count -gt 0) {
  Write-Host "NOTE: $($orphans.Count) drag-lint process(es) already running (LSP servers are normal)." -ForegroundColor DarkYellow
}

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$srcA = Join-Path $WorkDir 'a'; $srcB = Join-Path $WorkDir 'b'
New-Item -ItemType Directory -Path $srcA -Force | Out-Null
New-Item -ItemType Directory -Path $srcB -Force | Out-Null

Write-Ascii (Join-Path $srcA 'uAlpha.pas') @'
unit uAlpha;

interface

type
  TAlphaBase = class(TObject)
  private
    FTag: Integer;
  public
    procedure Touch;
    property Tag: Integer read FTag write FTag;
  end;

implementation

procedure TAlphaBase.Touch;
var
  Scratch: Integer;
begin
  if FTag > 0 then
    Scratch := FTag * 2;
  FTag := Scratch;
end;

end.
'@

Write-Ascii (Join-Path $srcB 'uBeta.pas') @'
unit uBeta;

interface

type
  TBetaThing = class(TObject)
  public
    procedure Run;
  end;

implementation

uses
  System.SysUtils;

procedure TBetaThing.Run;
var
  I: Integer;
  S: string;
begin
  for I := 0 to 3 do
    if I > 1 then
      S := IntToStr(I);
  if S = '' then
    Exit;
end;

end.
'@

$dbA   = Join-Path $WorkDir 'a.sqlite'
$dbB   = Join-Path $WorkDir 'b.sqlite'
$ghost = Join-Path $WorkDir 'ghost.sqlite'
$ghos2 = Join-Path $WorkDir 'ghost2.sqlite'
$rules = (Resolve-Path "$PSScriptRoot\..\..\rules").Path

& $exePath index $srcA --db $dbA 2>&1 | Out-Null
& $exePath index $srcB --db $dbB 2>&1 | Out-Null

$out = Join-Path $WorkDir 'o.txt'
$err = Join-Path $WorkDir 'e.txt'

# THE GHOST MUST BE DELETED BEFORE EVERY SINGLE RUN, AND THIS IS NOT FUSSINESS.
#
# The first version of this harness created the ghost path once and let the
# matrix run. Some verb OPENED it for write, and SQLite happily created an empty
# database there -- so every verb that ran later in the matrix was handed an
# existing (empty) index and legitimately exited 0. Those zeroes were recorded as
# "still lenient" when they were nothing of the kind, and a verb already strict
# (`query --name`) appeared lenient purely because it ran fifteenth.
#
# A guard whose own fixture is mutated by the thing under test measures the order
# of its rows. So: reset before each invocation, and record WHO created the file,
# which is itself a finding worth reporting rather than a nuisance to suppress.
$script:creators = @()
function Reset-Ghosts {
  foreach ($g in @($ghost, $ghos2)) { if (Test-Path $g) { Remove-Item $g -Force -ErrorAction SilentlyContinue } }
}

# stdout and stderr SPLIT: T3 asserts stdout stays empty, which a merged stream
# could not see.
function Run-Verb([string[]]$VerbArgs, [int]$TimeoutSec = 90, [string]$Label = '') {
  Reset-Ghosts
  $p = Start-Process -FilePath $exePath -ArgumentList $VerbArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WorkingDirectory 'C:\TEMP'
  if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill($true) } catch {}; return @{ Code = -1; Out=''; Err='(timed out)' } }
  $made = @(@($ghost, $ghos2) | Where-Object { Test-Path $_ } | ForEach-Object { Split-Path $_ -Leaf })
  if ($made.Count -gt 0 -and $Label -ne '') { $script:creators += ("{0} -> {1}" -f $Label, ($made -join '+')) }
  Reset-Ghosts
  return @{
    Code = $p.ExitCode
    Out  = ((Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) + '')
    Err  = ((Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue) + '')
  }
}

# The engine prints "(loaded defaults from ...)" on stderr on every run, and the
# lint verbs print a progress channel there too. Neither is an answer, so T3's
# "stdout is empty" must ignore banner-ish stdout lines only.
function StdoutIsSilent([string]$T) {
  $lines = @(($T -split "`r?`n") | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\(loaded defaults' })
  return ($lines.Count -eq 0)
}

# Each row: Name, args WITHOUT --db, whether it is an already-strict control.
# Arguments were taken from `--help` verbatim: a wrong flag exits 3 ("Unknown
# argument") which would look exactly like strictness and fake a pass. V below
# catches that by requiring the good-DB run to actually work.
$fileA = (Join-Path $srcA 'uAlpha.pas')
$matrix = @(
  @{ N='proptree';          A=@('proptree','--qname','uAlpha.TAlphaBase','--depth','1'); Strict=$false }
  @{ N='reverse-calltree';  A=@('reverse-calltree','--qname','uAlpha.TAlphaBase.Touch'); Strict=$false }
  @{ N='butterfly';         A=@('butterfly','--qname','uAlpha.TAlphaBase.Touch');        Strict=$false }
  @{ N='hover';             A=@('hover','--qname','uAlpha.TAlphaBase');                  Strict=$false }
  @{ N='usages';            A=@('usages','--name','Touch');                              Strict=$false }
  @{ N='typeat';            A=@('typeat',"$($fileA):8:15");                              Strict=$false }
  @{ N='find-unit';         A=@('find-unit','--name','TBetaThing','--in',$fileA);         Strict=$false }
  @{ N='lint';              A=@('lint',$fileA,'--rules-dir',$rules);                      Strict=$false }
  @{ N='lint-all';          A=@('lint-all','--rules-dir',$rules);                         Strict=$false }
  @{ N='check-ast';         A=@('check-ast',$fileA);                                      Strict=$false }
  @{ N='wiring';            A=@('wiring','--coverage');                                   Strict=$false }
  @{ N='exceptions-sync';   A=@('exceptions-sync');                                       Strict=$false }
  @{ N='deps-report';       A=@('deps-report');                                           Strict=$false }
  @{ N='convert-scaffold';  A=@('convert-scaffold','--from','uAlpha.TAlphaBase','--to','uBeta.TBetaThing'); Strict=$false }
  @{ N='query --name';      A=@('query','--name','TAlphaBase');                            Strict=$true  }
  @{ N='query type-usage';  A=@('query','type-usage','--in',$fileA,'--names','TAlphaBase'); Strict=$false }
)

Check 'V the verb matrix is populated' ($matrix.Count -ge 15) "only $($matrix.Count) verb(s)"

# ---- P1 POSITIVE CONTROL: every verb actually WORKS with two good DBs --------
# Without this, T1-T7 pass against a build that exits 2 for everything.
$brokenGood = @()
foreach ($m in $matrix) {
  $r = Run-Verb ($m.A + @('--db',$dbA,'--db',$dbB))
  # 0 = answered; 1 = a legitimate "not found / findings present" answer for
  # several of these verbs. 2 or 3 means the invocation itself is wrong.
  if ($r.Code -ge 2) { $brokenGood += ("{0} (exit {1}: {2})" -f $m.N, $r.Code, (($r.Out + $r.Err) -split "`r?`n" | Where-Object { $_ -match 'ERROR|FATAL|Unknown' } | Select-Object -First 1)) }
}
Check 'P1 POSITIVE CONTROL every verb answers with two GOOD --db' ($brokenGood.Count -eq 0) `
      ("these did not work even with valid databases, so their T-rows would be meaningless: " + ($brokenGood -join ' | '))

# ---- P3 POSITIVE CONTROL: silence when everything exists ---------------------
$quiet = Run-Verb (@('proptree','--qname','uAlpha.TAlphaBase','--depth','1','--db',$dbA,'--db',$dbB))
Check 'P3 POSITIVE CONTROL two good --db produce NO "does not exist" line' `
      (($quiet.Err -notmatch 'does not exist') -and ($quiet.Out -notmatch 'does not exist')) `
      'the error fires when nothing is wrong'

# ---- T1/T2/T3: the refusal ---------------------------------------------------
$t1 = @(); $t2 = @(); $t3 = @()
foreach ($m in $matrix) {
  $r = Run-Verb ($m.A + @('--db',$dbA,'--db',$ghost)) 90 $m.N
  if ($r.Code -ne 2) { $t1 += ("{0}=exit{1}" -f $m.N, $r.Code) }
  $both = $r.Out + "`n" + $r.Err
  if (($both -notmatch 'ghost\.sqlite') -or ($both -notmatch '#2 of 2')) {
    $t2 += ("{0}[{1}]" -f $m.N, $(if($both -match 'ghost\.sqlite'){'no-ordinal'}else{'unnamed'}))
  }
  if (-not (StdoutIsSilent $r.Out)) { $t3 += $m.N }
}
Check 'T1 a missing explicit --db exits 2 on every verb' ($t1.Count -eq 0) `
      ("still not 2: " + ($t1 -join ', '))
Check 'T2 the message names the ghost path AND its ordinal (#2 of 2)' ($t2.Count -eq 0) `
      ("incomplete message: " + ($t2 -join ', '))
Check 'T3 stdout carries NO partial answer when a --db is missing' ($t3.Count -eq 0) `
      ("answered anyway on stdout: " + ($t3 -join ', '))

# ---- T4: a single missing --db --------------------------------------------
$t4 = @()
foreach ($m in $matrix) {
  $r = Run-Verb ($m.A + @('--db',$ghost)) 90 $m.N
  if (($r.Code -ne 2) -or ($($r.Out + $r.Err) -notmatch '#1 of 1')) { $t4 += ("{0}=exit{1}" -f $m.N, $r.Code) }
}
Check 'T4 a single missing --db exits 2 and says "#1 of 1"' ($t4.Count -eq 0) `
      ("degraded silently or mis-numbered: " + ($t4 -join ', '))

# ---- T6: ordinal is the POSITION, not a constant ----------------------------
$first = Run-Verb @('proptree','--qname','uAlpha.TAlphaBase','--db',$ghost,'--db',$dbA)
$last  = Run-Verb @('proptree','--qname','uAlpha.TAlphaBase','--db',$dbA,'--db',$ghost)
Check 'T6 the ordinal tracks the position in the argument list' `
      ((($first.Out + $first.Err) -match '#1 of 2') -and (($last.Out + $last.Err) -match '#2 of 2')) `
      "first-position run should say '#1 of 2', last-position '#2 of 2'"

# ---- T7: EVERY missing path is named, not just the first --------------------
$two = Run-Verb @('proptree','--qname','uAlpha.TAlphaBase','--db',$ghost,'--db',$ghos2)
$twoText = $two.Out + $two.Err
Check 'T7 two missing --db name BOTH (one run, not two)' `
      (($twoText -match 'ghost\.sqlite') -and ($twoText -match 'ghost2\.sqlite')) `
      'only the first missing path was reported, so a second typo costs another round trip'

# ---- V: the refusal must not CREATE what it refused -------------------------
# `serve` creates an empty SQLite file at a missing --db path today. Any verb
# that does this manufactures an authoritative-looking empty index from a typo.
Check 'V no verb CREATED the database it was told did not exist' `
      ($script:creators.Count -eq 0) `
      ("these manufactured an empty index from a typo, which then answers 'nothing' convincingly: " +
       (($script:creators | Select-Object -Unique) -join ', '))

# ---- P2 POSITIVE CONTROL: the manifest path is untouched --------------------
# With NO --db the engine resolves through the manifest, which already drops
# absent files. If the new check leaked into that path, this turns red.
$noDb = Run-Verb @('proptree','--qname','uAlpha.TAlphaBase','--depth','1')
Check 'P2 POSITIVE CONTROL a run with NO --db is not hit by the new error' `
      (($noDb.Err -notmatch 'does not exist:') -and ($noDb.Out -notmatch 'does not exist:')) `
      "manifest-resolved runs must be unaffected; got exit $($noDb.Code)"

Write-Host ''
if ($ListRedOnly) { Write-Host 'evidence run -- exit 0 regardless' -ForegroundColor DarkGray; exit 0 }
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
