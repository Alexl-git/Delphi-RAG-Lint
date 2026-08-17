<#
  run_index_fingerprint_entry_points.ps1 -- the two index entry points must agree
  about one database's fingerprint.

  INBOX-indexer-fingerprint-disagrees-between-entry-points. `IndexerFingerprint`
  folds a platform token into the string, and the two callers supplied it from
  different places:

    manifest path   ApplyIndexerFingerprint(..., AItem.Platform)  -> '' for a
                    folder/closure section (Index.Plan.pas:50, by design)
    ad-hoc path     ApplyIndexerFingerprint(..., PpPlatform)      -> 'win64'

  Both are internally consistent; neither describes an engine change. But
  alternating them against ONE database made Prev <> Cur every time, so every
  file in scope was re-parsed for no reason -- and, worse, that silently disabled
  the per-file resume added for the library walk, because a stamp written by one
  entry point never matches the other's.

  The fix normalises inside IndexerFingerprint via EffectiveIndexPlatform, which
  is the SAME resolution ResolveIndexProfile already applied privately ('' ->
  Win64). The recorded token now describes what preprocessing actually did.

  WHY THIS SUITE IS SHAPED THIS WAY. The note warns that the obvious assertion --
  "the two entry points agree" -- passes trivially if both return ''. So nothing
  here compares fingerprint strings. It asserts the BEHAVIOUR that was wanted:
  after indexing by one entry point, indexing by the OTHER re-parses nothing.

    1  index --all --only <Section>            -> baseline, N files indexed
    2  index <dir> --db <same db>  (ad-hoc)    -> NO "Indexer changed",
                                                 "skipped N up-to-date", N = file count
    3  index --all --only <Section>  again    -> NO "Indexer changed", skipped N
                                                 (the round trip, both directions)
    4  index <dir> --db --no-preprocess       -> "Indexer changed" IS announced
                                                 (POSITIVE CONTROL: without it,
                                                  1-3 would also pass if the gate
                                                  never fired at all)

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_fpentry'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $scratch 'src') | Out-Null

# Three units, so "skipped N up-to-date" carries a number worth checking: a
# suite that only looked for the phrase would pass on "skipped 0 up-to-date",
# which is exactly what a full re-parse prints for the files it did NOT skip.
foreach ($u in 'alpha','beta','gamma') {
@"
unit $u;

interface

procedure ${u}Proc;

implementation

procedure ${u}Proc; begin end;

end.
"@ -replace "`r`n","`n" -replace "`n","`r`n" | Set-Content -Path (Join-Path $scratch "src\$u.pas") -Encoding ascii -NoNewline
}

$cfg = Join-Path $scratch 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "FpEntrySection", "db": "fpentry.sqlite", "include": ["src"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
$db = Join-Path $scratch 'out\fpentry.sqlite'

$EXPECTED_FILES = 3

Push-Location C:\TEMP
try {
  function Manifest() { return (& $exePath index --all --config $cfg --only FpEntrySection --jobs 1 2>&1 | Out-String) }
  function AdHoc([string[]]$extra) { return (& $exePath index (Join-Path $scratch 'src') --db $db @extra 2>&1 | Out-String) }

  $r1 = Manifest
  Check 'SANITY: the manifest run indexed the fixture' ($r1 -match '(?i)alpha\.pas')
  Check 'SANITY: the section DB exists' (Test-Path $db) $db

  # --- 2. manifest THEN ad-hoc ------------------------------------------------
  $r2 = AdHoc @()
  Check '2a. ad-hoc after manifest: no "Indexer changed"' `
        ($r2 -notmatch 'Indexer changed since this DB was built') `
        $(($r2 -split "`n" | Where-Object { $_ -match 'Indexer changed' }) -join ' ')
  $m2 = [regex]::Match($r2, 'skipped (\d+) up-to-date')
  Check '2b. ad-hoc after manifest: every file skipped up-to-date' `
        ($m2.Success -and ([int]$m2.Groups[1].Value -eq $EXPECTED_FILES)) `
        "skipped=$(if($m2.Success){$m2.Groups[1].Value}else{'<no match>'}) expected=$EXPECTED_FILES"
  $parsed2 = ([regex]::Matches($r2, '->\s*\d+ symbols')).Count
  Check '2c. ad-hoc after manifest: NO file was re-parsed' `
        ($parsed2 -eq 0) "files re-parsed=$parsed2 (expected 0 of $EXPECTED_FILES)"

  # --- 3. ad-hoc THEN manifest (the other direction) --------------------------
  $r3 = Manifest
  Check '3a. manifest after ad-hoc: no "Indexer changed"' `
        ($r3 -notmatch 'Indexer changed since this DB was built')
  # NOT "skipped N up-to-date" here: the manifest path never prints that summary
  # -- it prints per-file progress instead. The direct signal is that no file
  # emitted a '-> N symbols' line, which only a file that was actually PARSED
  # does. (Asserting the missing phrase would have failed forever against a
  # correct engine, which is what the first draft of this suite did.)
  $parsed3 = ([regex]::Matches($r3, '->\s*\d+ symbols')).Count
  Check '3b. manifest after ad-hoc: NO file was re-parsed' `
        ($parsed3 -eq 0) "files re-parsed=$parsed3 (expected 0 of $EXPECTED_FILES)"

  # --- 4. POSITIVE CONTROL: a REAL fingerprint change is still announced ------
  $r4 = AdHoc @('--no-preprocess')
  Check '4. positive control: a real fingerprint change IS still announced' `
        ($r4 -match 'Indexer changed since this DB was built')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
