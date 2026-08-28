<#
  run_index_all_failed_section_summary.ps1 -- `index --all` must ROLL UP its
  failed sections at the end, by name.

  WHAT THIS IS NOT ABOUT, because the plan that asked for it had it wrong.
  PLAN-SESSION-44 T5 asked to "make one failing section non-fatal-but-loud:
  continue, exit non-zero, print FAILED sections:", with the control "the
  unfixed build abandons section 2". Measured against the engine before a line
  was written: it does NOT abandon it. BuildPlanItem wraps its whole body in
  try..except, returns False, and both driver loops carry on and set Result:=1.
  Two thirds of that task were already true, and the stated control would have
  failed against CORRECT code -- the exact trap this repo has hit before.

  SO THE SUBJECT IS THE THIRD PART ONLY: the roll-up. A failure is announced
  inline, once, at the moment it happens. On a 27-section `index --all` that
  line is thousands of lines up a scrolling log, and the run ends with a
  cheerful per-section trailer and nothing else. The operator's question at the
  end is "did anything fail, and what?", and until now the answer required
  scrolling. Exit code 1 says SOMETHING failed and never says what.

  THE CONTROLS, and why each one is here rather than implied:

    C1  the healthy section still builds. This is the part that already worked,
        so it is a REGRESSION guard: the roll-up must not be bought by turning
        a failure fatal again.
    C2  a failing run still exits non-zero. Also already true, also pinned.
    N1  the summary does NOT name the healthy section. Without this, an
        implementation that listed every section would pass "it names Broken1".
    N2  a run where nothing fails prints NO summary at all. Without this, a
        summary printed unconditionally would satisfy every positive check.

  Both driver paths are exercised, because they are separate loops with
  separate bookkeeping: sequential (--jobs 1) and parallel (--jobs 2, which
  spawns one child per section and needs --config).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP 'draglint_failsum'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

# Two independent healthy source roots, so a section can fail BETWEEN two good
# ones -- the ordering that shows whether the driver carried on.
foreach ($n in 1..2) {
  $d = Join-Path $scratch "src$n"
  New-Item -ItemType Directory -Path $d | Out-Null
  Write-Ascii (Join-Path $d "uGood$n.pas") @"
unit uGood$n;

interface

type
  TGood$n = class
  public
    procedure Work$n;
  end;

implementation

procedure TGood$n.Work$n;
begin
end;

end.
"@
}

$outDir = Join-Path $scratch 'out'
New-Item -ItemType Directory -Path $outDir | Out-Null

# A section FAILS when its include names a project file that is not there:
# BuildPlanItem reports "project file NOT FOUND", then "FAILED, 1 project
# file(s) yielded no source", and returns False WITHOUT raising. That is the
# ordinary failure shape, and the one the roll-up has to catch.
function SectionJson([string]$Name, [string]$Db, [string]$Include) {
  '      { "name": "' + $Name + '", "db": "' + $Db + '", "include": ["' + ($Include -replace '\\','\\') + '"] }'
}

function WriteCfg([string]$Path, [string[]]$Sections) {
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 4096, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "$($outDir -replace '\\','\\')",
    "sections": [
$($Sections -join ",`n")
    ]
  }
}
"@ | Set-Content $Path -Encoding ascii
}

$missing1 = Join-Path $scratch 'NoSuchOne.dproj'
$missing2 = Join-Path $scratch 'NoSuchTwo.dproj'
$src1     = Join-Path $scratch 'src1'
$src2     = Join-Path $scratch 'src2'

# Broken1, Healthy, Broken2 -- the healthy one is in the MIDDLE on purpose.
$cfgMixed = Join-Path $scratch 'mixed.json'
WriteCfg $cfgMixed @(
  (SectionJson 'Broken1' 'broken1.sqlite' $missing1),
  (SectionJson 'Healthy' 'healthy.sqlite' $src1),
  (SectionJson 'Broken2' 'broken2.sqlite' $missing2)
)

# Nothing broken -- the negative control's corpus.
$cfgClean = Join-Path $scratch 'clean.json'
WriteCfg $cfgClean @(
  (SectionJson 'CleanA' 'cleana.sqlite' $src1),
  (SectionJson 'CleanB' 'cleanb.sqlite' $src2)
)

function RunAll([string]$Cfg, [int]$Jobs) {
  $out  = (& $exePath index --all --config $Cfg --jobs $Jobs 2>&1 | Out-String)
  return @{ Out = $out; Code = $LASTEXITCODE }
}

Push-Location C:\TEMP
try {
  # ---------------------------------------------------------------- sequential
  Remove-Item (Join-Path $outDir '*.sqlite') -Force -ErrorAction SilentlyContinue
  $seq = RunAll $cfgMixed 1

  Check 'C1 sequential: the healthy section between two failures STILL BUILDS' `
        (Test-Path (Join-Path $outDir 'healthy.sqlite')) $seq.Out
  Check 'C2 sequential: the run still exits non-zero' `
        ($seq.Code -ne 0) "exit=$($seq.Code)"
  Check 'sequential: a FAILED sections roll-up is printed' `
        ($seq.Out -match 'FAILED sections') $seq.Out
  Check 'sequential: the roll-up NAMES both failed sections' `
        (($seq.Out -match 'FAILED sections.*Broken1') -and ($seq.Out -match 'FAILED sections.*Broken2')) `
        (($seq.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -join ' | ')
  Check 'sequential: it counts them (2 of 3)' `
        ($seq.Out -match 'FAILED sections \(2 of 3\)') `
        (($seq.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -join ' | ')
  # ORDERING -- A REGRESSION PIN, NOT A POSITIVE CONTROL. Said plainly because
  # the difference matters and this repo has been bitten by the confusion.
  #
  # RunAll captures with `2>&1 |`, so the engine's stdout is a PIPE (fully
  # buffered) while stderr is not. The roll-up was once observed overtaking a
  # trailer that had not been written yet and landing mid-log, which is why
  # ReportFailedSections flushes stdout first. But it is a RACE: the same
  # config and the same unflushed binary ordered correctly on re-measurement,
  # so this Check PASSES with or without the flush and CANNOT be used as
  # evidence that the flush works. Manufacturing a reliable RED would mean
  # engineering buffer pressure, which is not worth it for a two-line fix
  # that is obviously correct on its own terms.
  #
  # What it IS good for: if the roll-up is ever moved before the build loop,
  # or a trailer is moved after it, this goes red deterministically. The
  # summary is only a summary if it comes last.
  $lines   = $seq.Out -split "`r?`n"
  $iRollup = [Array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match 'FAILED sections' })
  $iLastTr = [Array]::FindLastIndex($lines, [Predicate[string]]{ param($l) $l -match '^=== .* ===$' })
  Check 'sequential: the roll-up comes AFTER the last section trailer (pipe-buffered stdout)' `
        (($iRollup -ge 0) -and ($iLastTr -ge 0) -and ($iRollup -gt $iLastTr)) `
        "rollupIdx=$iRollup lastTrailerIdx=$iLastTr"

  # N1: without this, listing every section would satisfy every check above.
  Check 'N1 sequential: the roll-up does NOT name the healthy section' `
        (-not (($seq.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -match 'Healthy')) `
        (($seq.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -join ' | ')

  # ------------------------------------------------------------------ parallel
  # A separate loop with separate bookkeeping: one child process per section.
  Remove-Item (Join-Path $outDir '*.sqlite') -Force -ErrorAction SilentlyContinue
  $par = RunAll $cfgMixed 2

  Check 'C3 parallel: the healthy section STILL BUILDS' `
        (Test-Path (Join-Path $outDir 'healthy.sqlite')) $par.Out
  Check 'parallel: a FAILED sections roll-up is printed' `
        ($par.Out -match 'FAILED sections') $par.Out
  Check 'parallel: the roll-up NAMES both failed sections' `
        (($par.Out -match 'FAILED sections.*Broken1') -and ($par.Out -match 'FAILED sections.*Broken2')) `
        (($par.Out -split "`r?`n" | Where-Object { $_ -match 'FAILED sections' }) -join ' | ')

  # ---------------------------------------------- N2: silence when all is well
  Remove-Item (Join-Path $outDir '*.sqlite') -Force -ErrorAction SilentlyContinue
  $ok = RunAll $cfgClean 1

  Check 'N2 an all-healthy run prints NO roll-up' `
        ($ok.Out -notmatch 'FAILED sections') $ok.Out
  Check 'N2 control: and that run really did build both sections' `
        ((Test-Path (Join-Path $outDir 'cleana.sqlite')) -and (Test-Path (Join-Path $outDir 'cleanb.sqlite'))) $ok.Out
  Check 'N2 control: and exits zero' `
        ($ok.Code -eq 0) "exit=$($ok.Code)"
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
