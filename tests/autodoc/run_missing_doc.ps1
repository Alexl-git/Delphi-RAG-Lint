<#
  run_missing_doc.ps1 -- missing-doc lint rule (ADF Task 7).

  Exercises TDocLintRules.RunMissingDoc through `lint-all --db <db> --json`
  (missing-doc needs the whole symbol store -- symbol_docs join -- so it can
  only run on the store-backed project path, never the bare per-file `lint`).

  Fixture: fixtures\docmiss\miss.pas
    Documented   -- public, HAS a real /// doc comment       -> NOT flagged
    Undocumented -- public, has NO doc comment at all         -> FLAGGED (the one finding)
    Stubbed      -- public, has a drag-lint MANAGED stub doc  -> NOT flagged (doc-drift's job,
                    no double-report -- a managed stub still counts as "documented")
    TThing.Helper-- private class method, no doc              -> NOT flagged (private, exempt)

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\docmiss\miss.pas')).Path

$scratch = Join-Path C:\TEMP 'draglint_docmiss'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$target = Join-Path $scratch 'miss.pas'
$db     = Join-Path $scratch 'docmiss.sqlite'
Copy-Item $fixture $target -Force

# missing-doc ships OFF by default (ADF Task 11b -- 1302 first-run findings on
# drag-lint's own tree); opt it in explicitly for this suite via --config, same
# mechanism as the other OFF-by-default rules (feature-envy/split-variable).
$cfg = Join-Path $scratch 'docmiss.config.json'
'{ "enabled": ["missing-doc"] }' | Set-Content -Path $cfg -Encoding ascii -NoNewline

Push-Location C:\TEMP
try {
  & $exePath index $scratch --db $db 2>$null | Out-Null

  $out = & $exePath lint-all --db $db --config $cfg --json 2>$null
  $raw = ($out -join "`n")
  # lint-all --json prints one pretty-printed JSON array preceded/followed by
  # plain progress/summary text on other lines -- extract just the array.
  $arrStart = $raw.IndexOf('[')
  $arrEnd   = $raw.LastIndexOf(']')
  Check 'lint-all emitted a JSON array' (($arrStart -ge 0) -and ($arrEnd -gt $arrStart))
  $findings = @()
  if ($arrStart -ge 0 -and $arrEnd -gt $arrStart) {
    $jsonText = $raw.Substring($arrStart, $arrEnd - $arrStart + 1)
    $findings = @(ConvertFrom-Json $jsonText)
  }

  $missingDoc = @($findings | Where-Object { $_.rule -eq 'missing-doc' })

  Check 'exactly one missing-doc finding' ($missingDoc.Count -eq 1)
  if ($missingDoc.Count -ge 1) {
    Check 'the finding is on miss.pas' ($missingDoc[0].file_path -like '*miss.pas')
  }

  # Confirm it is NOT reported for Documented, Stubbed, or the private Helper --
  # find-by-line: Undocumented is declared at line 14 of the fixture.
  $lines = @($missingDoc | ForEach-Object { $_.start_line })
  Check 'flagged line is Undocumented''s declaration line (14)' ($lines -contains 14)

  # No finding on the Documented (line 12), Stubbed (line 22), TThing (line 26,
  # documented at the type level), or Helper (line 28) lines.
  Check 'no missing-doc finding on Documented''s line (12)' (-not ($lines -contains 12))
  Check 'no missing-doc finding on Stubbed''s declaration line (22)' (-not ($lines -contains 22))
  Check 'no missing-doc finding on TThing''s declaration line (26)' (-not ($lines -contains 26))
  Check 'no missing-doc finding on Helper''s declaration line (28)' (-not ($lines -contains 28))
  Check 'exactly-one-finding equals the Undocumented line' ($missingDoc.Count -eq 1 -and $lines[0] -eq 14)

  # ADF Task 13 regression: missing-doc must be GENUINELY OFF at runtime, not just
  # in the rules catalog. A BARE lint-all (no --config, no --disable) must yield
  # ZERO missing-doc findings -- proving the store-backed lint-all path adds
  # missing-doc to its default-disabled set (the catalog default_enabled=false does
  # NOT suppress runtime output on its own; it is driven by DefDisabled/ShouldKeep).
  # Before the fix this fired the full 1302-style wave on every bare run.
  $bareOut = & $exePath lint-all --db $db --json 2>$null
  $bareRaw = ($bareOut -join "`n")
  $bS = $bareRaw.IndexOf('['); $bE = $bareRaw.LastIndexOf(']')
  $bareFindings = @()
  if ($bS -ge 0 -and $bE -gt $bS) { $bareFindings = @(ConvertFrom-Json $bareRaw.Substring($bS, $bE - $bS + 1)) }
  $bareMissing = @($bareFindings | Where-Object { $_.rule -eq 'missing-doc' })
  Check 'BARE lint-all (no config/disable) yields ZERO missing-doc findings (OFF by default at runtime)' ($bareMissing.Count -eq 0)
  # ...and doc-drift is unaffected (stays ON) -- sanity that we only disabled missing-doc.
  # (miss.pas has no drifted doc comments, so 0 doc-drift is expected regardless; the
  #  point here is that the BARE run did not error and produced a parseable array.)
  Check 'BARE lint-all emitted a JSON array (did not error)' (($bS -ge 0) -and ($bE -gt $bS))
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
