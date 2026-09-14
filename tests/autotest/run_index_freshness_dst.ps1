<#
  run_index_freshness_dst.ps1 --
  The staleness note is FALSE for every file whose mtime falls in the OTHER DST
  period from the one in force right now.

  WHY THIS IS A SEPARATE RUNNER FROM run_index_freshness.ps1. That runner's F1
  is documented as the mtime-equivalence test, and it is -- but it is
  STRUCTURALLY INCAPABLE of catching this defect, because it creates its fixture
  files during the run. Every file it indexes therefore carries a mtime in the
  CURRENT DST period, which is the one period where the two conversions agree.
  A guard that can only be fed the input that passes is not a guard; this repo
  has documented that failure mode repeatedly, so the fixture is the whole point
  of this file and it is built by BACK-DATING into the opposite period.

  THE MECHANISM, from the RTL's own source rather than from inference.
  System.SysUtils.FileAgeInternal converts with FileTimeToLocalFileTime and says
  so in a comment:

      // FileAge uses the current TimeZone/time-offset.
      // To use the file's TimeZone, System.IOUtils.TFile.GetLastWriteTime
      // should be used.

  FileTimeToLocalFileTime applies the offset in force NOW. TFile.GetLastWriteTime
  applies the offset in force WHEN THE FILE WAS WRITTEN. The indexer writes
  mtimes with DateTimeToUnix(TFile.GetLastWriteTime(P), False)
  (DRagLint.Core.Indexer.pas:882) and the freshness probe read them back with
  FileAge (DRagLint.Index.Freshness.pas:183), so the two disagree by exactly one
  hour for every file dated in the other DST period -- and agree perfectly for
  every file dated in this one.

  Measured 2026-09-14 on library-Win64: the engine reported 3258 of 7001 files
  changed immediately after a complete from-scratch re-parse, against a corpus in
  which ZERO files had changed and 100% of the stored stamps were correct.

  WHAT A NO-DST MACHINE DOES. On a zone with no daylight saving there is no
  "other period" and no fixture can be built, so this runner SKIPs and says so.
  It must never pass silently there -- a vacuous pass on the build box is how
  this defect survived in the first place.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_index_freshness_dst"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

# ---- find a date in the OPPOSITE DST period, or skip -----------------------
# Probed rather than assumed: "six months back" is NOT reliably the other period
# (from mid-September that lands in March, which is already daylight time in the
# US), and the sign of the difference flips between hemispheres.
$tz    = [System.TimeZoneInfo]::Local
$now   = Get-Date
$nowIsDst = $tz.IsDaylightSavingTime($now)
$other = $null
foreach ($back in 1..11) {
  $cand = $now.AddMonths(-$back)
  if ($tz.IsDaylightSavingTime($cand) -ne $nowIsDst) { $other = $cand; break }
}

if ($null -eq $other) {
  Write-Host "SKIP: local zone '$($tz.Id)' has no DST transition in the last 11 months." -ForegroundColor Yellow
  Write-Host "      This defect is a local<->UTC offset mismatch and cannot be reproduced here." -ForegroundColor DarkGray
  exit 0
}

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

# Two units, and the CONTROL is load-bearing. uNow carries a current-period
# mtime and must stay clean whatever happens; if the fix were to break the
# ordinary case, "0 changed" alone could not tell us -- the control is what
# separates "fixed" from "check disabled".
Write-Ascii (Join-Path $src 'uNow.pas') @'
unit uNow;

interface

function Widen(AValue: Integer): Integer;

implementation

function Widen(AValue: Integer): Integer;
var
  Scratch: Integer;
begin
  if AValue > 0 then
    Scratch := AValue * 2;
  Result := Scratch;
end;

end.
'@

Write-Ascii (Join-Path $src 'uBackDated.pas') @'
unit uBackDated;

interface

procedure Emit(ACount: Integer);

implementation

uses
  System.SysUtils;

procedure Emit(ACount: Integer);
var
  I: Integer;
  S: string;
begin
  for I := 0 to ACount do
    if I > 2 then
      S := IntToStr(I);
  if S = '' then
    Exit;
end;

end.
'@

$backDated = Join-Path $src 'uBackDated.pas'
(Get-Item $backDated).LastWriteTime = $other

# The fixture must actually BE what the test claims. A back-date that silently
# did not take would produce a green run that proves nothing.
$stamped = (Get-Item $backDated).LastWriteTime
Check 'FIXTURE the back-dated unit really sits in the other DST period' `
      ($tz.IsDaylightSavingTime($stamped) -ne $nowIsDst) `
      ("now dst=$nowIsDst ($($now.ToString('yyyy-MM-dd'))), fixture dst=$($tz.IsDaylightSavingTime($stamped)) ($($stamped.ToString('yyyy-MM-dd')))")

$db  = Join-Path $WorkDir 'fresh.sqlite'
$out = Join-Path $WorkDir 'o.txt'
$err = Join-Path $WorkDir 'e.txt'

& $exePath index $src --db $db 2>&1 | Out-Null

Push-Location C:\TEMP
try {
  $p = Start-Process -FilePath $exePath `
        -ArgumentList @('lint-all','--db',$db,'--rules-dir',$rules) `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $stderrText = (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)
  $stdoutText = (Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue)

  # VACUITY: if the run produced no findings at all the pipeline did not work,
  # and a silent stderr would mean nothing.
  $findings = @(($stdoutText -split "`r?`n") | Where-Object { $_ -match ':\d+:\d+\s+\[(error|warning|info|hint)\]' })
  Check 'VACUITY the fixture produced findings at all' ($findings.Count -gt 0) `
        'no findings -- the engine did not lint the fixture, so stderr proves nothing'

  # ---- D1: THE DEFECT ------------------------------------------------------
  Check 'D1 an index built moments ago emits NO staleness note for a back-dated file' `
        (-not ($stderrText -match 'indexed file\(s\) changed')) `
        ("stderr said: " + (($stderrText -split "`r?`n" | Where-Object { $_ -match 'note:' }) -join ' | ') +
         "  -- FileAge applies the CURRENT utc offset, the indexer applied the file's own")

  # ---- D2: POSITIVE CONTROL -- the check must still WORK on a back-dated file
  # Without this, "skip every file dated in the other DST period" would pass D1
  # perfectly while destroying the staleness signal for roughly half the corpus.
  # So: modify the back-dated file, keeping its mtime in the SAME other period,
  # and require the note to fire and name it.
  #
  # The first version of this assertion just grepped stderr for the filename.
  # That could never pass: stderr is also the lint-all PROGRESS channel, which
  # prints "[1/2] 45% uBackDated.pas" on every run. It failed against the fixed
  # build and against the broken one alike -- a check that cannot distinguish
  # them. The assertion is therefore scoped to the note LINE, not to stderr.
  $changedTo = $other.AddDays(-10)
  (Get-Item $backDated).LastWriteTime = $changedTo
  Check 'FIXTURE the modified stamp is STILL in the other DST period' `
        ($tz.IsDaylightSavingTime($changedTo) -ne $nowIsDst) `
        "moved to $($changedTo.ToString('yyyy-MM-dd')) -- if this crossed back, D2 tests the easy case"

  $p2 = Start-Process -FilePath $exePath `
        -ArgumentList @('lint-all','--db',$db,'--rules-dir',$rules) `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $err2 = (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)
  $noteLines = @(($err2 -split "`r?`n") | Where-Object { $_ -match 'indexed file\(s\) changed' })

  Check 'D2 a back-dated file that REALLY changed is still detected' `
        (($noteLines.Count -gt 0) -and ($noteLines -join ' ') -match 'uBackDated\.pas') `
        ("note line(s): " + ($noteLines -join ' | ') +
         "  -- if silent, the fix suppressed the check for back-dated files instead of correcting it")
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
