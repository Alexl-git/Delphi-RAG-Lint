# End-to-end contract of the dl:ok reviewed-marker, through the real CLI.
#
# The pure unit is covered by ReviewMarkerTests.dpr; this pins the part that unit
# tests cannot reach -- that the ONE central filter in FinalizeAndOutput actually
# suppresses, actually re-reports when the line changes, and actually survives the
# reformat YADF performs.
#
# State E is the load-bearing one. Without it a marker keeps suppressing a line
# somebody has since edited, which is a real defect hidden behind an old
# signature -- strictly worse than never having marked it.

$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe'
if (-not (Test-Path $exe)) { Write-Output "review-marker-e2e: FATAL -- no exe at $exe"; exit 1 }

$tmp  = Join-Path $env:TEMP ("dl-marker-e2e-" + $PID)
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$src  = Join-Path $tmp 'MarkDemo.pas'
$pass = 0; $fail = 0

function Check($name, $cond) {
  if ($cond) { $script:pass++; Write-Output "PASS  $name" }
  else       { $script:fail++; Write-Output "FAIL  $name" }
}

# Writes the fixture with $line as the 'except' line (line 13), CRLF + ASCII.
function Write-Fixture($exceptLine) {
  $body = @(
    'unit MarkDemo;', '', 'interface', '', 'procedure Run;', '', 'implementation', '',
    'procedure Run;', 'begin', '  try', '    Beep;', $exceptLine, '  end;', 'end;', '', 'end.'
  )
  [IO.File]::WriteAllText($src, (($body -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
}

function LintRules {
  $out = & $exe lint $src 2>&1 | Out-String
  # rule ids look like: "  [warning] rule-id: message"
  ([regex]::Matches($out, '\[\w+\]\s+([a-z0-9-]+):')) | ForEach-Object { $_.Groups[1].Value }
}

# --- the rule under test is comment-INSENSITIVE, verified by the probe below ---
Write-Fixture '  except'
$base = LintRules
Check 'baseline reports try-except-swallowed' ($base -contains 'try-except-swallowed')

# A: marker with no @hash -- honoured, but explicitly flagged unverifiable.
Write-Fixture '  except // dl:ok try-except-swallowed'
$r = LintRules
Check 'A hashless marker suppresses'            (-not ($r -contains 'try-except-swallowed'))
Check 'A hashless marker reports stale'         ($r -contains 'review-marker-stale')

# The hint names the hash to use, so the fix is copy-paste rather than guesswork.
$msg  = (& $exe lint $src 2>&1 | Out-String)
$hash = ([regex]::Match($msg, 'try-except-swallowed@([0-9a-f]{4})')).Groups[1].Value
Check 'A hint supplies the correct hash'        ($hash -match '^[0-9a-f]{4}$')

# B: wrong hash -- finding comes BACK, plus the stale hint.
Write-Fixture '  except // dl:ok try-except-swallowed@dead -- deliberately wrong'
$r = LintRules
Check 'B wrong hash re-reports the finding'     ($r -contains 'try-except-swallowed')
Check 'B wrong hash reports stale'              ($r -contains 'review-marker-stale')

# C: correct hash -- clean.
Write-Fixture "  except // dl:ok try-except-swallowed@$hash -- rethrown by the caller"
$r = LintRules
Check 'C correct hash suppresses'               (-not ($r -contains 'try-except-swallowed'))
Check 'C correct hash is silent'                (-not ($r -contains 'review-marker-stale'))

# D: THE YADF PROPERTY. Reindent + re-case the same code; the review must hold,
#    because whitespace is dropped and identifiers are lowercased before hashing.
Write-Fixture "      EXCEPT   // dl:ok try-except-swallowed@$hash -- rethrown by the caller"
$r = LintRules
Check 'D survives reindent + recase'            (-not ($r -contains 'try-except-swallowed'))
Check 'D no false stale after reformat'         (-not ($r -contains 'review-marker-stale'))

# E: the code genuinely changes -- the suppression MUST break.
Write-Fixture "  except on E: Exception do // dl:ok try-except-swallowed@$hash -- rethrown by the caller"
$r = LintRules
Check 'E real edit breaks the suppression'      ($r -contains 'try-except-swallowed')
Check 'E real edit reports stale'               ($r -contains 'review-marker-stale')

# F: comment-sensitivity guard. empty-except stops firing the moment ANY comment
#    is added, so a dl:ok for it must never be reported as unused -- that loop has
#    no exit (mark -> rule silenced -> "remove it" -> finding returns).
Write-Fixture '  except // dl:ok empty-except@0000'
$r = LintRules
Check 'F comment-sensitive rule not called unused' (-not ($r -contains 'review-marker-unused'))

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ''
Write-Output "review-marker-e2e: $pass pass / $fail fail / $($pass + $fail) total"
if ($fail -gt 0) { exit 1 } else { exit 0 }
