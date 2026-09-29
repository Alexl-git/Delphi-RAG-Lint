# Guard: a command that could not do what was asked must SAY SO and exit non-zero.
#
# The INBOX sweep of 2026-08-16 found four notes describing one defect wearing
# four names: a command narrows its work and then reports success for the
# narrowed set as if it were the whole one. This runner is the shared home for
# that family, so the next instance is added here rather than filed separately.
#
# Covered so far:
#   * `index --all --only <name>` where <name> matches no section
#     (docs\INBOX-index-only-nonmatching-section-is-a-silent-noop.md)
#
# Deliberately still open, and NOT asserted here because they are unfixed --
# add arms as each lands, do not delete this list:
#   * `lint <file>` reports 0 findings for whole-run rules that lint-all reports
#   * `lint-all` never scans .dpr bodies and still says "N file(s) scanned"
#   * `lint-all --project` ignores drag-lint-lint.json sitting beside the .dproj
#
# Usage: pwsh -File tests/autotest/run_cli_narrowing_is_reported.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }

# --dry-run throughout except the positive control, so this runner never rebuilds
# a real index as a side effect of asserting an error path.

# --- 1. a selector matching nothing -----------------------------------------
$o = & $Exe index --all --only 'NoSuchSectionXYZ' --dry-run 2>&1 | Out-String
$e = $LASTEXITCODE
Check 'a non-matching --only exits non-zero' ($e -ne 0) "exit=$e"
Check 'it names the selector that matched nothing' ($o -match 'NoSuchSectionXYZ')
Check 'it lists what IS selectable' ($o -match 'selectable( for this platform)? \(\d+\)')

# A name listed twice read as two sections. ResolvePlan emits one item per
# platform for a library section, so with no --platform the list said
# "Library, Library". The count must be the number of DISTINCT names.
function Get-Selectable([string]$Text) {
    $m = [regex]::Match($Text, 'selectable( for this platform)? \((\d+)\): ([^\r\n]*)')
    if (-not $m.Success) { return $null }
    # Split on commas OUTSIDE parentheses: "Library (Win32, Win64)" is ONE entry.
    $items = @([regex]::Split($m.Groups[3].Value, ',\s*(?![^()]*\))') | Where-Object { $_.Trim() -ne '' })
    $names = @($items | ForEach-Object { ($_ -replace '\s*\(.*\)$', '').Trim() })
    return @{ ForPlatform = $m.Groups[1].Success; Count = [int]$m.Groups[2].Value
              Items = $items; Names = $names }
}
$sel = Get-Selectable $o
$dups = if ($sel) { @($sel.Names | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object Name) } else { @('<no list>') }
Check 'no section name appears twice in the selectable list' ($dups.Count -eq 0) ("dups=" + ($dups -join ','))
Check 'the selectable count is the number of distinct names' `
      ($sel -and ($sel.Count -eq @($sel.Names | Select-Object -Unique).Count)) ("count=" + $(if ($sel) { $sel.Count }) + " names=" + $(if ($sel) { $sel.Names.Count }))
Check 'it states that nothing was indexed' ($o -match 'nothing was indexed')

# --- 2. one valid selector + one typo ---------------------------------------
# The case a bare "did anything match?" check cannot catch: the valid name
# satisfies it while the typo is silently dropped. This is the arm that forces
# per-selector reporting.
$o2 = & $Exe index --all --only 'DragLint-Cli,NoSuchSectionXYZ' --dry-run 2>&1 | Out-String
$e2 = $LASTEXITCODE
Check 'a partially-matching --only still exits non-zero' ($e2 -ne 0) "exit=$e2"
Check 'it names the typo' ($o2 -match 'NoSuchSectionXYZ')
Check 'it does NOT accuse the valid selector' (-not ($o2 -match 'section:[^\r\n]*DragLint-Cli'))

# --- 3. POSITIVE CONTROL ----------------------------------------------------
# Without this, "always exit non-zero on --only" would pass every arm above.
$o3 = & $Exe index --all --only 'DragLint-Cli' --dry-run 2>&1 | Out-String
$e3 = $LASTEXITCODE
Check 'a VALID --only still exits 0' ($e3 -eq 0) "exit=$e3"
Check 'a valid --only reports no error' (-not ($o3 -match 'matched no configured section'))

# --- 4. the selectable list on a CONTROLLED manifest ------------------------
# Arm 1 reads whatever the engine's own manifest holds, which may or may not
# expand a library for two platforms. This arm guarantees it does: an ENGINE
# COPY in %TEMP% with its own drag-lint.json (Library for Win32 AND Win64), run
# from a CWD under %TEMP%, --dry-run only.
$root4 = Join-Path $env:TEMP "draglint_narrowing_$PID"
try {
    if (Test-Path $root4) { Remove-Item $root4 -Recurse -Force }
    $eng4 = Join-Path $root4 'eng'
    New-Item -ItemType Directory -Path $eng4, (Join-Path $root4 'proj'), (Join-Path $root4 'fold') | Out-Null
    $exeDir = Split-Path (Resolve-Path $Exe).Path -Parent
    Copy-Item (Resolve-Path $Exe).Path (Join-Path $eng4 'drag-lint.exe') -Force
    Get-ChildItem -Path $exeDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName (Join-Path $eng4 $_.Name) -Force }
    if (Test-Path (Join-Path $exeDir 'rules')) { Copy-Item (Join-Path $exeDir 'rules') (Join-Path $eng4 'rules') -Recurse -Force }
    $exe4 = Join-Path $eng4 'drag-lint.exe'
    $mf4 = @{
        settings = @{ defaultPlatform = 'Win64'; maxJobs = 1 }
        indexes  = @{ sections = @(
            @{ name = 'P-Foo';     include = @('..\proj\Foo.dpr') },
            @{ name = 'FolderSec'; include = @('..\fold') },
            @{ name = 'Library';   db = 'library-{platform}.sqlite'; source = 'registry-libraries'; platforms = @('Win32', 'Win64') }
        ) }
    } | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText((Join-Path $eng4 'drag-lint.json'), ($mf4 -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $root4 'proj\Foo.dpr'), "program Foo;`r`n`r`nbegin`r`nend.`r`n", [Text.Encoding]::ASCII)

    Push-Location $root4
    try {
        $o4 = & $exe4 index --all --only 'NoSuchSectionXYZ' --dry-run 2>&1 | Out-String
        $e4 = $LASTEXITCODE
        $s4 = Get-Selectable $o4
        Check '4a (no --platform) still exits non-zero and lists the selectable names' (($e4 -ne 0) -and ($null -ne $s4)) "exit=$e4 out=[$($o4.Trim())]"
        if ($s4) {
            Check '4b ... worded "selectable", NOT "for this platform" (no platform was chosen)' (-not $s4.ForPlatform) $o4.Trim()
            Check '4c ... three DISTINCT names, counted as three' `
                  (($s4.Count -eq 3) -and ($s4.Names.Count -eq 3) -and (@($s4.Names | Select-Object -Unique).Count -eq 3)) `
                  ("count=$($s4.Count) items=" + ($s4.Items -join ' | '))
            Check '4d ... the library is listed ONCE, with both platforms' `
                  (@($s4.Items | Where-Object { $_ -eq 'Library (Win32, Win64)' }).Count -eq 1) ($s4.Items -join ' | ')
        }

        $o5 = & $exe4 index --all --only 'NoSuchSectionXYZ' --platform Win64 --dry-run 2>&1 | Out-String
        $s5 = Get-Selectable $o5
        Check '4e (--platform Win64) is worded "selectable for this platform"' ([bool]($s5 -and $s5.ForPlatform)) $o5.Trim()
        if ($s5) {
            Check '4f ... and lists the library once, as plain "Library" (one platform)' `
                  ((@($s5.Items | Where-Object { $_ -eq 'Library' }).Count -eq 1) -and ($s5.Count -eq 3)) ($s5.Items -join ' | ')
        }

        # Positive control on the same copy: the de-duplicated name still SELECTS.
        $o6 = & $exe4 index --all --only 'Library' --dry-run 2>&1 | Out-String
        $e6 = $LASTEXITCODE
        Check '4g positive control: --only Library (the listed name) exits 0' ($e6 -eq 0) "exit=$e6 out=[$($o6.Trim())]"
    } finally { Pop-Location }
} finally {
    if (Test-Path -LiteralPath $root4) { Remove-Item -LiteralPath $root4 -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
