<#
  run_release_pack_payload_guard.ps1 -- everything build\pack-lint-release.ps1
  claims to ship must EXIST, and the component converter must still be in the list.

  WHY THIS EXISTS
  ---------------
  Until 2026-09-09 the release archive contained drag-lint.exe, the parser DLLs,
  rules\ and five documents. The component converter -- ConvRulesEditor.exe, the
  starter rule books, casts.castlib and the converter docs -- existed ONLY in this
  checkout. Nothing was broken; the feature simply never left the building, and no
  test could notice, because a release is judged by what it contains and there was
  no statement anywhere of what it was supposed to contain.

  So the pack script's Copy-Item list IS that statement, and this runner holds it
  to two things a silent regression would violate:

    1  every literal source path it copies exists in the repo (a wildcard must
       match at least one file). $ErrorActionPreference=Stop already makes the
       pack FAIL on a missing source -- but only at release time, on the one day
       nobody wants to debug a path. This moves that failure into the battery.

    2  the converter payload is still listed at all. Check 1 alone cannot see a
       DELETION: remove the whole converter block and every remaining path still
       exists, so check 1 goes green over a release that quietly dropped the
       feature again. Check 2 is the positive control -- it is the assertion that
       fails if this guard's whole reason for existing is undone.

  WHAT IT DELIBERATELY DOES NOT DO
  --------------------------------
  It does not build, and it does not run the pack. Both build outputs the pack
  copies -- src\cli\<Plat>\Release\drag-lint.exe and ConvRulesEditor.exe -- are
  gitignored and absent from a clean checkout, so asserting they exist would fail
  on exactly the machine that has not built yet. They are SKIPPED AND NAMED below,
  never silently dropped: a skip nobody can see is how the missing payload lasted
  as long as it did.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:Failed = $false

function Check([string]$What, [bool]$Ok, [string]$Detail) {
  if ($Ok) { Write-Host ("  PASS  {0}" -f $What) }
  else     { Write-Host ("  FAIL  {0}  -- {1}" -f $What, $Detail) -ForegroundColor Red
             $script:Failed = $true }
}

$pack = Join-Path $repo 'build\pack-lint-release.ps1'
if (-not (Test-Path -LiteralPath $pack)) {
  Write-Host "RELEASE PACK PAYLOAD GUARD: FAIL -- build\pack-lint-release.ps1 is missing" -ForegroundColor Red
  exit 1
}
$text = Get-Content -LiteralPath $pack -Raw

Write-Host 'check 1 -- every literal source the pack copies exists'

# Only `Join-Path $repo "<literal>"` forms are checked. A capture containing '$'
# is interpolated at run time (the per-platform exe and the DLL loop), so it is
# reported as a skip rather than guessed at.
$paths   = [regex]::Matches($text, 'Join-Path\s+\$repo\s+"([^"]+)"') |
           ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$skipped = @()
$checked = 0

foreach ($p in $paths) {
  if ($p -match '\$')     { $skipped += "$p (interpolated at run time)"; continue }
  if ($p -match '\.exe$') { $skipped += "$p (build output, gitignored)"; continue }

  $full = Join-Path $repo $p
  if ($p -match '[\*\?]') {
    $hit = @(Get-ChildItem -Path $full -ErrorAction SilentlyContinue)
    Check "$p matches at least one file" ($hit.Count -gt 0) 'wildcard matched nothing'
  } else {
    Check "$p exists" (Test-Path -LiteralPath $full) 'no such file in the repo'
  }
  $checked++
}
Write-Host ("  ({0} literal path(s) checked)" -f $checked)
foreach ($s in $skipped) { Write-Host ("  NOTE  skipped {0}" -f $s) -ForegroundColor DarkGray }

Write-Host ''
Write-Host 'check 2 -- the component converter is still in the payload'

# Each entry is the substring that proves one piece of the converter reaches the
# archive. Matched against the script SOURCE, so deleting a Copy-Item fails here
# even though the file it copied still exists on disk.
$required = @(
  @{ What = 'the editor exe is copied';          Needle = 'ConvRulesEditor.exe") $stg' }
  @{ What = 'the editor is built by the pack';   Needle = '_build_convrules_editor_local.bat' }
  @{ What = 'the editor build is gated';         Needle = 'BUILD_EXITCODE=0' }
  @{ What = 'the editor manual is copied';       Needle = 'convrules-editor-manual.md' }
  @{ What = 'the DSL reference is copied';       Needle = 'convrules-dsl.md' }
  @{ What = 'the starter rule books are copied'; Needle = 'convrules\sample.rules' }
  @{ What = 'casts.castlib is copied';           Needle = 'casts.castlib' }
)
foreach ($r in $required) {
  Check $r.What ($text.Contains($r.Needle)) ("build\pack-lint-release.ps1 no longer contains: " + $r.Needle)
}

# The catalog index stores ABSOLUTE paths into the build machine's checkout, so
# shipping it hands the user a coverage index pointing at folders they do not
# have. Its absence is a DECISION; assert it stays one.
Check 'convrules-catalog.index is NOT shipped' (-not $text.Contains('convrules-catalog.index")')) 'the catalog index carries absolute build-machine paths and must not be packed'

Write-Host ''
if ($script:Failed) { Write-Host 'RELEASE PACK PAYLOAD GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RELEASE PACK PAYLOAD GUARD: PASS' -ForegroundColor Green
exit 0
