<#
  run_index_freshness.ps1 --
  docs\superpowers\specs\2026-08-13-db-authority-and-freshness.md

  The owner ruling says "a stale DB is not authoritative; the answer is to
  rescan, not to report". Until now NOTHING said so, and the failure is silent
  by construction: a stale index answers confidently with fewer results.

  It reproduced in this repo while the fix was being written. `type-name-prefix`
  fired on a minutes-old `EDefAsgnGenMismatch = class(Exception)` because the
  class was not in the index yet -- exception ancestry is resolved through the
  store, so without it the check falls through to the plain T-prefix branch. The
  finding was plausible, confident and wrong, and only a reindex revealed it.

  This guards the DECISION-FREE half: a stderr note. The ruling's open questions
  (refuse vs warn vs auto-reindex; gate per-command or once at resolution) are
  NOT answered, and a warning cannot pre-empt them.

  F1 IS THE LOAD-BEARING ONE, and not for the reason it looks. The probe reads
  mtimes with FileAge while the INDEXER writes them with
  DateTimeToUnix(TFile.GetLastWriteTime(P), False). Those are different Win32
  paths. If they disagree by even one second, every file reports changed and the
  note fires on EVERY command against EVERY index -- which reads as a broken
  index rather than a broken check. F1 builds an index and requires ZERO changed
  files, so it IS that equivalence test, and it is the assertion that fails first
  if anyone swaps the mtime call.

  ON F4, STATED RATHER THAN QUIETLY MISSING: the "DB has no stamp -> stay
  silent" path is not exercised end-to-end, because removing a meta row needs a
  sqlite shell and this tree ships none. It is covered obliquely -- F2 can only
  warn if the stamp was written, so a stamp that never got written turns F2 red.
  What is NOT covered is a pre-upgrade DB staying quiet; that is one `if` on an
  empty GetMetaValue.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_index_freshness"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
$rules   = (Resolve-Path $RulesDir).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

Write-Ascii (Join-Path $src 'uAlpha.pas') @'
unit uAlpha;

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

Write-Ascii (Join-Path $src 'uBeta.pas') @'
unit uBeta;

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

$db  = Join-Path $WorkDir 'fresh.sqlite'
$out = Join-Path $WorkDir 'o.txt'
$err = Join-Path $WorkDir 'e.txt'

& $exePath index $src --db $db 2>&1 | Out-Null

# Runs lint-all with stdout and stderr captured SEPARATELY -- the whole point of
# F3 is that they do not mix, so a runner that merged them could not see it.
function RunSplit() {
  $p = Start-Process -FilePath $exePath `
        -ArgumentList @('lint-all','--db',$db,'--rules-dir',$rules) `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  return @{
    Code = $p.ExitCode
    Out  = (Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue)
    Err  = (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)
  }
}
function FindingsOnly([string]$T) {
  ,@(($T -split "`r?`n") | Where-Object { $_ -match ':\d+:\d+\s+\[(error|warning|info|hint)\]' } | Sort-Object)
}

Push-Location C:\TEMP
try {
  $fresh = RunSplit
  $fFresh = FindingsOnly $fresh.Out

  Check 'VACUITY the fixture produces findings at all' ($fFresh.Count -gt 0) `
        'no findings -- F5 would be comparing two empty sets'

  # ---- F1: a just-built index is silent, WHICH IS THE MTIME EQUIVALENCE TEST --
  Check 'F1 a freshly built index emits NO staleness note' `
        (-not ($fresh.Err -match 'indexed file\(s\) changed')) `
        ("stderr said: " + (($fresh.Err -split "`r?`n" | Where-Object { $_ -match 'note:' }) -join ' | ') +
         "  -- FileAge and the indexer's DateTimeToUnix(TFile.GetLastWriteTime(..), False) disagree")

  # ---- F2: a changed file is noticed --------------------------------------
  Start-Sleep -Milliseconds 1100   # mtime resolution: make the write unambiguous
  (Get-Item (Join-Path $src 'uAlpha.pas')).LastWriteTime = (Get-Date)
  $stale = RunSplit
  $fStale = FindingsOnly $stale.Out

  Check 'F2 a modified file produces the staleness note on stderr' `
        ($stale.Err -match '1 of 2 indexed file\(s\) changed') `
        ("stderr: " + (($stale.Err -split "`r?`n" | Where-Object { $_ -match 'note:' }) -join ' | '))

  Check 'F2 the note names the changed file and the repair command' `
        (($stale.Err -match 'uAlpha\.pas') -and ($stale.Err -match 'drag-lint index')) `
        'a warning that names neither the file nor the fix gets read once and then ignored'

  # ---- F3: STDOUT IS SACRED ------------------------------------------------
  # --format json / sarif parse stdout. One advisory line there silently breaks
  # every downstream consumer, and the schema-version message four lines above
  # this one in OpenReadOnlyStore already makes exactly that mistake.
  Check 'F3 the note NEVER appears on stdout' `
        (-not ($stale.Out -match 'note:.*indexed file')) `
        'the advisory leaked into stdout, which corrupts --format json/sarif'

  # ---- F5: advisory means advisory ----------------------------------------
  Check 'F5 findings are IDENTICAL stale vs fresh' `
        (($fFresh -join "`n") -eq ($fStale -join "`n")) `
        "fresh=$($fFresh.Count) stale=$($fStale.Count) -- the note must not change what is reported"

  Check 'F5 the exit code is unchanged' ($fresh.Code -eq $stale.Code) `
        "fresh=$($fresh.Code) stale=$($stale.Code) -- a note is not a failure"

  # ---- F6: reindexing clears it -------------------------------------------
  # The note tells the reader to reindex. If doing so does not silence it, the
  # advice is wrong and the reader learns to ignore the line.
  & $exePath index $src --db $db 2>&1 | Out-Null
  $healed = RunSplit
  Check 'F6 the note the fix advises actually silences it' `
        (-not ($healed.Err -match 'indexed file\(s\) changed')) `
        'still warning after the reindex it recommended'
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
