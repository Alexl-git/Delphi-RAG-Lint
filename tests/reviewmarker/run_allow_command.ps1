# End-to-end contract of `drag-lint allow`, the one way a marker ever reaches a
# source file. Editors shell out to this -- the Delphi IDE popup today, a VS Code
# code action some day -- so if this command is right, every surface is right, and
# no editor gets to format a marker itself.
#
# The pure hash/merge rules are covered by ReviewMarkerTests.dpr. What only an
# end-to-end run can pin down is the file-level behaviour: that a dry-run really
# writes nothing, that --apply leaves the file 7-bit ASCII + CRLF with its final
# newline intact, and that re-allowing a STALE marker refreshes its hash while
# leaving a neighbouring stale marker alone. That last one is the whole design:
# re-validating a review nobody re-examined is the failure the hash exists to stop.

$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe'
if (-not (Test-Path $exe)) { Write-Output "allow-command: FATAL -- no exe at $exe"; exit 1 }

$tmp = Join-Path $env:TEMP ("dl-allow-" + $PID)
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$src = Join-Path $tmp 'AllowDemo.pas'
$pass = 0; $fail = 0

function Check($name, $cond) {
  if ($cond) { $script:pass++; Write-Output "PASS  $name" }
  else       { $script:fail++; Write-Output "FAIL  $name" }
}

# 'except' lands on line 13. try-except-swallowed is deliberately chosen over
# empty-except: the empty-* family is comment-SENSITIVE (measured 2026-08-12), so
# it would go quiet on the marker's comment alone and prove nothing about the
# marker itself.
function Write-Fixture($exceptLine) {
  $body = @(
    'unit AllowDemo;', '', 'interface', '', 'procedure Run;', '', 'implementation', '',
    'procedure Run;', 'begin', '  try', '    Beep;', $exceptLine, '  end;', 'end;', '', 'end.'
  )
  [IO.File]::WriteAllText($src, (($body -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
}

function LintRules {
  $out = & $exe lint $src 2>&1 | Out-String
  ([regex]::Matches($out, '\[\w+\]\s+([a-z0-9-]+):')) | ForEach-Object { $_.Groups[1].Value }
}

function MarkerOn($n) {
  $line = (Get-Content $src)[$n - 1]
  if ($line -match 'dl:ok\s+(.+?)(\s+--|$)') { $Matches[1] } else { '' }
}

# --- dry-run writes nothing -------------------------------------------------
Write-Fixture '  except'
Check 'baseline reports try-except-swallowed' ((LintRules) -contains 'try-except-swallowed')
$before = [IO.File]::ReadAllBytes($src)
$dry = & $exe allow $src --fix-line 13 --fix-rule try-except-swallowed 2>&1 | Out-String
Check 'dry-run exits 0' ($LASTEXITCODE -eq 0)
Check 'dry-run previews the new line' ($dry -match '\+\s+except\s+// dl:ok try-except-swallowed@[0-9a-f]{4}')
Check 'dry-run leaves the file byte-identical' (@(Compare-Object $before ([IO.File]::ReadAllBytes($src))).Count -eq 0)

# --- apply ------------------------------------------------------------------
& $exe allow $src --fix-line 13 --fix-rule try-except-swallowed --apply | Out-Null
Check 'apply exits 0' ($LASTEXITCODE -eq 0)
Check 'apply records the rule' ((MarkerOn 13) -match '^try-except-swallowed@[0-9a-f]{4}$')
Check 'apply clears the finding' ((LintRules) -notcontains 'try-except-swallowed')

$bytes = [IO.File]::ReadAllBytes($src)
$text  = [Text.Encoding]::ASCII.GetString($bytes)
Check 'file stays 7-bit ASCII'      (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0)
Check 'file keeps CRLF only'        ([regex]::Matches($text, "(?<!`r)`n").Count -eq 0)
Check 'file keeps its final newline' ($text.EndsWith("`r`n"))
Check 'apply leaves no trailing space' ((Get-Content $src)[12] -notmatch '\s$')

# --- idempotence ------------------------------------------------------------
$stable = [IO.File]::ReadAllBytes($src)
& $exe allow $src --fix-line 13 --fix-rule try-except-swallowed --apply | Out-Null
Check 're-allow of a valid marker is a byte no-op' (@(Compare-Object $stable ([IO.File]::ReadAllBytes($src))).Count -eq 0)

# --- refusals ---------------------------------------------------------------
$guard = [IO.File]::ReadAllBytes($src)
& $exe allow $src --fix-line 13 --fix-rule not-a-real-rule --apply 2>&1 | Out-Null
Check 'unknown rule id exits 2' ($LASTEXITCODE -eq 2)
& $exe allow $src --fix-line 13 --fix-rule review-marker-stale --apply 2>&1 | Out-Null
Check 'review-marker-stale cannot be allowed' ($LASTEXITCODE -eq 2)
& $exe allow $src --fix-line 999 --fix-rule try-except-swallowed --apply 2>&1 | Out-Null
Check 'line past EOF exits 2' ($LASTEXITCODE -eq 2)
& $exe allow $src --fix-rule try-except-swallowed --apply 2>&1 | Out-Null
Check 'missing --fix-line exits 2' ($LASTEXITCODE -eq 2)
Check 'no refusal touched the file' (@(Compare-Object $guard ([IO.File]::ReadAllBytes($src))).Count -eq 0)

# --- the stale path: allow again, and only the rule you clicked -------------
# Two reviews on one line, then an edit that invalidates BOTH. Re-allowing one
# must refresh that one and leave its neighbour reported stale.
Write-Fixture '  except'
& $exe allow $src --fix-line 13 --fix-rule try-except-swallowed --apply | Out-Null
& $exe allow $src --fix-line 13 --fix-rule empty-except          --apply | Out-Null
Check 'two rules merge into one dl:ok comment' (([regex]::Matches((Get-Content $src)[12], 'dl:ok')).Count -eq 1)
# Edit the reviewed CODE, carrying the marker comment along untouched -- exactly
# what happens when a human changes a line somebody had already reviewed. Both
# recorded hashes now describe a line that no longer exists.
$lines = Get-Content $src
$lines[12] = $lines[12] -replace '^\s*except', '  except Beep;'
[IO.File]::WriteAllText($src, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))
Check 'edited line re-reports the finding' ((LintRules) -contains 'try-except-swallowed')

$staleBefore = MarkerOn 13
& $exe allow $src --fix-line 13 --fix-rule try-except-swallowed --apply | Out-Null
$after = MarkerOn 13
Check 'stale re-allow rewrites the marker' ($after -ne $staleBefore)
Check 'stale re-allow clears the finding'  ((LintRules) -notcontains 'try-except-swallowed')
Check 'stale re-allow keeps both rules'    (($after -split ',').Count -eq 2)
# The neighbour was not re-examined, so its hash must be exactly what it was.
$oldNeighbour = ($staleBefore -split ',\s*' | Where-Object { $_ -like 'empty-except@*' })
$newNeighbour = ($after       -split ',\s*' | Where-Object { $_ -like 'empty-except@*' })
Check 'neighbour keeps its stale hash' ($oldNeighbour -eq $newNeighbour)

Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Write-Output ''
Write-Output "allow-command: $pass pass / $fail fail / $($pass + $fail) total"
if ($fail -gt 0) { exit 1 } else { exit 0 }
