<#
  run_lint_stand_in_for.ps1 -- docs\PLAN-SESSION-47.md T2
  (docs\INBOX-ide-per-unit-view-omits-79pct-of-lint-all.md)

  The IDE lints an UNSAVED buffer by writing it to
  %TEMP%\drag-lint-live-<tick>.pas and linting that. `DoLint` decides which
  index covers a file by asking whether the DB CONTAINS that path, so a temp
  path always answers no and the store is dropped:

      [flowdb] eff=C:\TEMP\drag-lint-live-1787955386000.pas db= store=False fid=0

  Every store-backed check then degrades silently. `--stand-in-for <realpath>`
  splits TEXT from IDENTITY: analyse the snapshot's text, answer as the real
  file for store membership, file id, unit-name and the reported path.

  THE FIXTURE IS THE ARGUMENT. A record local whose own Init method DEFINES it
  is the exact shape that manufactured the false errors: a record has no
  constructor, so `R.Init` is what assigns it. Store-free, IsRecordType has no
  naming-convention fallback BY DESIGN and answers False for everything, so the
  read after the initialiser call is reported as a DEFINITE
  used-before-assignment at ERROR severity. Store-backed it is correctly silent.
  Measured on this project's own source: 23 such errors store-free vs 3
  store-backed -- 20 of 23 red gutter marks manufactured by a missing store.

  B2 IS THE LOAD-BEARING CONTROL. If the snapshot linted WITHOUT --stand-in-for
  did not differ from the real file, the fixture would be store-insensitive and
  B3's equality assertion would pass vacuously -- it would be comparing two
  identical store-free runs and calling that success. B2 asserts the difference
  exists before B3 claims to have closed it.

  INDEX ABSOLUTE. A relative index target writes relative path rows, the
  membership probe misses, and the store is silently dropped -- the run then
  looks store-backed while answering store-free, which is this very bug passing
  its own test.

  The snapshot deliberately lives OUTSIDE the indexed folder and carries the
  IDE's own name shape, so it cannot be in the index by accident.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_stand_in_for"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
$proj = Join-Path $WorkDir 'proj'
$snapDir = Join-Path $WorkDir 'snap'
New-Item -ItemType Directory -Path $proj    -Force | Out-Null
New-Item -ItemType Directory -Path $snapDir -Force | Out-Null

$fixture = @'
unit uStandIn;

interface

type
  TCfgRec = record
    Count: Integer;
    procedure Init;
  end;

procedure UseIt;

implementation

procedure TCfgRec.Init;
begin
  Count:= 0;
end;

procedure UseIt;
var
  R: TCfgRec;
begin
  R.Init;
  if R.Count > 0 then Exit;
end;

{ Deliberate, store-INDEPENDENT finding. Without at least one finding that
  survives on the store-backed real path, the equality assertion below compares
  two EMPTY sets and passes for a build where the flag does not exist at all.
  That is not a hypothetical: it is what this guard did on its first run. }
procedure Swallow;
begin
  try
    UseIt;
  except
  end;
end;

end.
'@

$real = Join-Path $proj 'uStandIn.pas'
Write-Ascii $real $fixture
$db = Join-Path $WorkDir 'standin.sqlite'

# ABSOLUTE index target -- see the header.
$idx = & $exePath index $proj --db $db 2>&1 | Out-String
Check 'SANITY: fixture indexed with no errors' `
      ($LASTEXITCODE -eq 0 -and $idx -notmatch '\b[1-9]\d* errors\b') $idx

# The IDE's own snapshot name shape, outside the indexed folder.
$snap = Join-Path $snapDir 'drag-lint-live-1787955386000.pas'
Copy-Item $real $snap -Force

function Findings($text) {
  @($text -split "`r?`n" | Where-Object { $_ -match '\[(error|warning|info|hint)\]\s+[a-z0-9-]+:' }) -join "`n"
}
function UbaCount($text) {
  @($text -split "`r?`n" | Where-Object { $_ -match 'used-before-assignment' }).Count
}

$realOut = & $exePath lint $real --db $db --rules-dir $rules 2>&1 | Out-String
$snapBare = & $exePath lint $snap --db $db --rules-dir $rules 2>&1 | Out-String
$snapStand = & $exePath lint $snap --stand-in-for $real --db $db --rules-dir $rules 2>&1 | Out-String

Check 'B1  the real file, store-backed, is SILENT about the record local' `
      ((UbaCount $realOut) -eq 0) `
      "expected no used-before-assignment; got: $(($realOut -split "`r?`n" | Where-Object { $_ -match 'used-before-assignment' }) -join ' | ')"

Check 'B2  CONTROL: the same text at a temp path, WITHOUT --stand-in-for, differs' `
      ((UbaCount $snapBare) -ge 1) `
      "the snapshot must lose the store and report the false error -- if this is 0 the fixture is store-INSENSITIVE and B3 would pass vacuously"

# ANTI-VACUITY. On this guard's FIRST run against the unfixed build, B3 and B4
# both PASSED: --stand-in-for FATALed, produced no findings, the fixture then
# produced none on the real path either, and "" -eq "" was reported as success.
# Equality is only evidence when there is something to be equal about.
Check 'B0  ANTI-VACUITY: the real store-backed run produces findings to compare' `
      ((Findings $realOut).Trim().Length -gt 0) `
      "with an empty finding set B3/B4 pass for a build that does not even accept the flag"

Check 'B3  --stand-in-for reproduces the real file findings EXACTLY' `
      ((Findings $snapStand) -eq (Findings $realOut) -and (Findings $realOut).Trim().Length -gt 0) `
      "real:`n$(Findings $realOut)`nstand-in:`n$(Findings $snapStand)"

Check 'B4  no output line names the snapshot path' `
      ($snapStand -notmatch [regex]::Escape($snap)) `
      "a half-applied path rewrite reads as correct in a spot check and puts marks in the wrong file"

# The membership probe must have answered for the REAL file, not the snapshot.
$env:DRAGLINT_DEBUG = '1'
$dbg = & $exePath lint $snap --stand-in-for $real --db $db --rules-dir $rules 2>&1 | Out-String
Remove-Item Env:\DRAGLINT_DEBUG
Check 'B5  the store resolved for the stand-in identity (store=True, fid<>0)' `
      ($dbg -match 'store=True' -and $dbg -notmatch 'fid=0\b') `
      (($dbg -split "`n" | Where-Object { $_ -match '\[flowdb\]' }) -join ' ')

# --- B6: the materialisation must never write into the SOURCE tree -----------
# Delphi's ExtractFileName splits on '\' and ':' but NOT '/', so the ordinary
# path C:/proj/uStandIn.pas yielded the ROOTED '/proj/uStandIn.pas'; TPath.Combine
# returned that instead of joining, and TFile.Copy wrote it back over the real
# source file (driveless -> resolved against the current drive). Content happened
# to be identical so nothing was lost and NOTHING WARNED -- it was caught by an
# mtime that had no business moving. Forward slashes are the trigger, so the
# guard uses them deliberately.
$fwdReal = $real -replace '\\','/'
$fwdSnap = $snap -replace '\\','/'
$beforeWrite = (Get-Item $real).LastWriteTimeUtc.Ticks
$fwdOut = & $exePath lint $fwdSnap --stand-in-for $fwdReal --db $db --rules-dir $rules 2>&1 | Out-String
$afterWrite  = (Get-Item $real).LastWriteTimeUtc.Ticks

Check 'B6  a forward-slash --stand-in-for does NOT write to the real source file' `
      ($beforeWrite -eq $afterWrite) `
      "the real file's mtime moved -- the materialisation escaped the temp directory and wrote into the source tree"

Check 'B6b CONTROL: that same forward-slash run still produced the findings' `
      ((Findings $fwdOut).Trim().Length -gt 0) `
      "if this is empty B6 passes for a run that did nothing at all"

# --- B7: paths embedded in MESSAGES must be rewritten too ---------------------
# duplicate-code writes "also at <path>:<line>" (CloneChecks.pas:300) using the
# ANALYSED path, so rewriting only FilePath left the reader pointed at a temp
# file. The finding COUNTS matched exactly; only a byte comparison caught it.
Check 'B7  no finding MESSAGE names the materialised stand-in directory' `
      ($snapStand -notmatch 'drag-lint-standin-\d+') `
      "a message still carries the temp path: $(($snapStand -split "`r?`n" | Where-Object { $_ -match 'drag-lint-standin-' } | Select-Object -First 1))"

Write-Host ''
if ($fail) { Write-Host 'run_lint_stand_in_for: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_lint_stand_in_for: PASS' -ForegroundColor Green
exit 0
