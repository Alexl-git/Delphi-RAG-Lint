<#
  run_index_fingerprint_commit.ps1 -- the indexer fingerprint is stamped AFTER
  the walk, not before it.

  INBOX-index-runs-are-not-resumable (correctness half). ApplyIndexerFingerprint
  used to call SetMetaValue BEFORE the walk started. An engine/schema/platform
  change then correctly forced a full re-parse, but the new fingerprint was
  ALREADY recorded -- so an interrupted run (these take hours on the library
  indexes) left the next run reading Prev = Cur, concluding nothing had changed,
  and taking the up-to-date skip over every file the killed run never reached.
  Those files silently kept parses produced by the OLD engine.

  The fix moves the stamp to CommitIndexerFingerprint, called only once a walk
  completes. An interrupted run now costs time and nothing else.

  What this suite pins is the OTHER half -- that the commit still happens on
  success. That is the regression the fix could introduce: if the stamp were
  dropped on some path, every run would re-parse everything forever, which is
  slow but silent, so nothing else would catch it.

    1  first index of a fresh DB                       -> baseline
    2  same flags again        -> NO "Indexer changed", files skipped up-to-date
                                  (proves the fingerprint WAS committed in 1)
    3  --no-preprocess (different fingerprint) -> "Indexer changed" announced
                                  (positive control: the gate still detects a
                                   real change -- without this, step 2 would
                                   also pass if the gate never fired at all)
    4  --no-preprocess again    -> NO "Indexer changed"
                                  (proves the commit happens on that path too)

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_fpcommit'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$db = Join-Path $scratch 'fp.sqlite'

# A small, self-contained unit -- this suite is about the meta row, not parsing.
@'
unit fpprobe;

interface

procedure Alpha;
procedure Beta;

implementation

procedure Alpha; begin end;
procedure Beta;  begin Alpha; end;

end.
'@ -replace "`r`n","`n" -replace "`n","`r`n" | Set-Content -Path (Join-Path $scratch 'fpprobe.pas') -Encoding ascii -NoNewline

Push-Location C:\TEMP
try {
  function RunIndex([string[]]$extra) {
    return (& $exePath index $scratch --db $db @extra 2>&1 | Out-String)
  }

  $r1 = RunIndex @()
  Check 'SANITY: first run indexed the fixture' ($r1 -match 'fpprobe\.pas\s*->\s*\d+ symbols')

  $r2 = RunIndex @()
  Check 'step 2: no "Indexer changed" on an unchanged re-run (fingerprint WAS committed)' `
        ($r2 -notmatch 'Indexer changed since this DB was built')
  Check 'step 2: the file was skipped as up-to-date (no needless re-parse)' `
        ($r2 -match 'skipped \d+ up-to-date')

  $r3 = RunIndex @('--no-preprocess')
  Check 'step 3 (positive control): a real fingerprint change IS announced' `
        ($r3 -match 'Indexer changed since this DB was built')

  $r4 = RunIndex @('--no-preprocess')
  Check 'step 4: no "Indexer changed" on the repeat (committed on this path too)' `
        ($r4 -notmatch 'Indexer changed since this DB was built')
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
