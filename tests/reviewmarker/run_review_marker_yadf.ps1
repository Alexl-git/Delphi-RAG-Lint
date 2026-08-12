# THE load-bearing interop test: does a dl:ok marker survive the real YADF?
#
# The whole scheme rests on one bet -- that the marker travels with the code
# through a reformat. YADF is the formatter most likely to touch marked source in
# this shop, and it reindents, re-cases reserved words, and rewrites whitespace by
# design. Test D in run_review_marker_e2e.ps1 simulates that; this runs the actual
# binary, which is the only version of the claim that counts.
#
# Two assertions, both necessary:
#   1. the marker text survives verbatim (YADF round-trips end-of-line comments);
#   2. the HASH still matches afterwards, i.e. the normalisation really is immune
#      to what YADF changes. If this fails, the scheme is broken for the one tool
#      most likely to break it, and the failure is silent in production -- the
#      finding simply reappears with a stale hint nobody expected.
#
# Skips (exit 2) rather than fails when YADF is not built: this repo does not own
# YADF's build, and a missing sibling tool is not a drag-lint regression.

$ErrorActionPreference = 'Stop'
$exe  = Join-Path $PSScriptRoot '..\..\third_party\dll-win64\drag-lint.exe'
$yadf = 'C:\Projects\YADF\Win64\Debug\EXE\YADF.exe'

if (-not (Test-Path $exe))  { Write-Output "review-marker-yadf: FATAL -- no drag-lint at $exe"; exit 1 }
if (-not (Test-Path $yadf)) { Write-Output "review-marker-yadf: SKIP -- YADF not built at $yadf"; exit 2 }

$tmp = Join-Path $env:TEMP ("dl-marker-yadf-" + $PID)
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$src = Join-Path $tmp 'MarkYadf.pas'
$pass = 0; $fail = 0
function Check($name, $cond) {
  if ($cond) { $script:pass++; Write-Output "PASS  $name" }
  else       { $script:fail++; Write-Output "FAIL  $name" }
}

# Deliberately ugly input: odd indentation and an upper-case reserved word, so
# YADF has something real to change on the marked line.
$body = @(
  'unit MarkYadf;', '', 'interface', '', 'procedure Run;', '', 'implementation', '',
  'procedure Run;', 'begin', '      try', '    Beep;', '        EXCEPT', '  end;', 'end;', '', 'end.'
)
[IO.File]::WriteAllText($src, (($body -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding $false))

# Ask drag-lint for the hash of the marked line rather than computing it here --
# one source of truth, and it proves the CLI and the formatter agree.
[IO.File]::WriteAllText($src, ((($body -replace '        EXCEPT', '        EXCEPT // dl:ok try-except-swallowed')) -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false))
$msg  = (& $exe lint $src 2>&1 | Out-String)
$hash = ([regex]::Match($msg, 'try-except-swallowed@([0-9a-f]{4})')).Groups[1].Value
Check 'drag-lint supplied a hash' ($hash -match '^[0-9a-f]{4}$')

$marker = "// dl:ok try-except-swallowed@$hash -- rethrown by the caller"
[IO.File]::WriteAllText($src, ((($body -replace '        EXCEPT', "        EXCEPT $marker")) -join "`r`n") + "`r`n", (New-Object Text.UTF8Encoding $false))

# Clean BEFORE the reformat, or the test proves nothing about YADF.
$before = & $exe lint $src 2>&1 | Out-String
Check 'clean before reformat' ($before -notmatch 'try-except-swallowed:')

& $yadf $src 2>&1 | Out-Null
$after = [IO.File]::ReadAllText($src)

Check '1 marker text survives YADF verbatim' ($after -match [regex]::Escape($marker))
Check '1b YADF actually reformatted the line' ($after -notmatch '        EXCEPT ')

# The real assertion: still suppressed, and no stale hint.
$out = & $exe lint $src 2>&1 | Out-String
Check '2 hash still matches after YADF'   ($out -notmatch 'try-except-swallowed:')
Check '2b no stale hint after YADF'       ($out -notmatch 'review-marker-stale')

# File conventions must survive too -- these files are strict 7-bit ASCII + CRLF.
$bytes = [IO.File]::ReadAllBytes($src)
Check '3 still 7-bit ASCII' (-not ($bytes | Where-Object { $_ -gt 127 }))

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ''
Write-Output "review-marker-yadf: $pass pass / $fail fail / $($pass + $fail) total"
if ($fail -gt 0) { exit 1 } else { exit 0 }
