# run_naming_presets_roundtrip.ps1 -- Task 6 (Batch F): naming.presets RMW
# contract test for the dock naming Options frame (TLintOptionsFrame in
# DragLint.Plugin.LintOptionsFrame.pas).
#
# BACKGROUND / OVERRIDE OF THE ORIGINAL TASK BRIEF: the brief assumed presets
# live in the manifest (drag-lint.json) via a ManifestPathForWrite-style
# resolver. That was corrected (user-confirmed) during implementation:
# presets live in drag-lint-lint.json (the LINT config) instead, resolved by
# the frame's EXISTING CfgPath function (<projdir>\drag-lint-lint.json, or ''
# when no project is open). See docs/superpowers/specs/2026-07-08-batch-f-
# butterfly-dock-and-portable-presets-design.md section 3.1 for the full
# rationale (naming rule values + the CLI's LoadLintConfig reader both
# already use drag-lint-lint.json, so presets belong alongside them).
#
# The IDE helpers (ReadNamingPresets / WriteNamingPreset / DeleteNamingPreset)
# are not headless-callable (they need a live IDE + open project via
# IOTAModuleServices to resolve CfgPath). This test instead validates the
# SAME manifest CONTRACT via a pure PowerShell read-modify-write: a new
# top-level "naming" object holding a "presets" array, added/updated without
# dropping sibling top-level keys ("rules"/"profiles"/etc). It doubles as the
# format spec the Pascal RMW (WriteNamingPreset) must satisfy.

$ErrorActionPreference = 'Stop'

$script:Failed = $false
function Check([bool]$Ok, [string]$Msg) {
    if ($Ok) {
        Write-Host ("  [PASS] {0}" -f $Msg) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0}" -f $Msg) -ForegroundColor Red
        $script:Failed = $true
    }
}

$tmp = Join-Path $env:TEMP ("draglint-presets-{0}.json" -f (Get-Random))

try {
    Write-Host 'Seed drag-lint-lint.json with sibling keys (rules, profiles)' -ForegroundColor Cyan

    # Sibling keys that a real drag-lint-lint.json already carries; the RMW
    # must preserve both verbatim.
    @'
{ "rules": [ { "id": "naming-method-case", "enabled": true } ], "profiles": { "strict": { "rules": [] } } }
'@ | Set-Content -Encoding ascii $tmp

    $seeded = Get-Content -Raw $tmp | ConvertFrom-Json
    Check ($seeded.rules.Count -eq 1) 'fixture seeded: rules present'
    Check ($null -ne $seeded.profiles.strict) 'fixture seeded: profiles present'

    Write-Host ''
    Write-Host 'Simulate WriteNamingPreset("My", [p,F,T,E,I,P,PascalCase,PascalCase])' -ForegroundColor Cyan

    # Mirrors the Pascal RMW: parse existing JSON, reuse/create the
    # top-level "naming" object, rebuild "presets" minus any same-name
    # entry (SameText), append the new preset, re-serialize the WHOLE root.
    $j = Get-Content -Raw $tmp | ConvertFrom-Json
    if (-not (Get-Member -InputObject $j -Name 'naming' -MemberType NoteProperty)) {
        # PSCustomObject (not a hashtable) so a further Add-Member on $j.naming
        # attaches a NoteProperty, matching how ConvertFrom-Json itself
        # represents nested JSON objects.
        $j | Add-Member -NotePropertyName naming -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $preset = [ordered]@{
        name   = 'My'
        values = [ordered]@{
            param_prefix     = 'p'
            field_prefix     = 'F'
            class_prefix     = 'T'
            exception_prefix = 'E'
            interface_prefix = 'I'
            pointer_prefix   = 'P'
            method_case      = 'PascalCase'
            local_case       = 'PascalCase'
        }
    }
    $j.naming | Add-Member -NotePropertyName presets -NotePropertyValue @($preset) -Force
    ($j | ConvertTo-Json -Depth 8) | Set-Content -Encoding ascii $tmp

    Write-Host ''
    Write-Host 'Read back and assert the contract' -ForegroundColor Cyan

    $r = Get-Content -Raw $tmp | ConvertFrom-Json
    Check ($r.naming.presets.Count -eq 1) 'exactly one saved preset'
    Check ($r.naming.presets[0].name -eq 'My') 'preset name survives ("My")'
    Check ($r.naming.presets[0].values.param_prefix -eq 'p') 'values.param_prefix survives ("p")'
    Check ($r.naming.presets[0].values.field_prefix -eq 'F') 'values.field_prefix survives ("F")'
    Check ($r.naming.presets[0].values.class_prefix -eq 'T') 'values.class_prefix survives ("T")'
    Check ($r.naming.presets[0].values.exception_prefix -eq 'E') 'values.exception_prefix survives ("E")'
    Check ($r.naming.presets[0].values.interface_prefix -eq 'I') 'values.interface_prefix survives ("I")'
    Check ($r.naming.presets[0].values.pointer_prefix -eq 'P') 'values.pointer_prefix survives ("P")'
    Check ($r.naming.presets[0].values.method_case -eq 'PascalCase') 'values.method_case survives'
    Check ($r.naming.presets[0].values.local_case -eq 'PascalCase') 'values.local_case survives'
    Check ($r.rules.Count -eq 1) 'sibling "rules" key preserved'
    Check ($null -ne $r.profiles.strict) 'sibling "profiles" key preserved'

    Write-Host ''
    Write-Host 'Simulate overwrite-by-name: WriteNamingPreset("My", [A,...]) replaces, does not duplicate' -ForegroundColor Cyan

    $j2 = Get-Content -Raw $tmp | ConvertFrom-Json
    $newPreset = [ordered]@{
        name   = 'My'
        values = [ordered]@{
            param_prefix = 'A'; field_prefix = 'F'; class_prefix = 'T'
            exception_prefix = 'E'; interface_prefix = 'I'; pointer_prefix = 'P'
            method_case = 'PascalCase'; local_case = 'PascalCase'
        }
    }
    # rebuild presets minus any same-name (case-insensitive) entry, then append
    $kept = @($j2.naming.presets | Where-Object { $_.name.ToUpperInvariant() -ne 'MY' })
    $j2.naming.presets = $kept + @($newPreset)
    ($j2 | ConvertTo-Json -Depth 8) | Set-Content -Encoding ascii $tmp

    $r2 = Get-Content -Raw $tmp | ConvertFrom-Json
    Check ($r2.naming.presets.Count -eq 1) 'overwrite-by-name: still exactly one preset (no duplicate)'
    Check ($r2.naming.presets[0].values.param_prefix -eq 'A') 'overwrite-by-name: values updated ("A")'
    Check ($r2.rules.Count -eq 1) 'overwrite: sibling "rules" key still preserved'

    Write-Host ''
    Write-Host 'Simulate DeleteNamingPreset("My"): rebuild presets minus the named entry' -ForegroundColor Cyan

    $j3 = Get-Content -Raw $tmp | ConvertFrom-Json
    $j3.naming.presets = @($j3.naming.presets | Where-Object { $_.name.ToUpperInvariant() -ne 'MY' })
    ($j3 | ConvertTo-Json -Depth 8) | Set-Content -Encoding ascii $tmp

    $r3 = Get-Content -Raw $tmp | ConvertFrom-Json
    $remaining = @($r3.naming.presets)
    Check ($remaining.Count -eq 0) 'delete: no presets remain'
    Check ($r3.rules.Count -eq 1) 'delete: sibling "rules" key still preserved'
    Check ($null -ne $r3.profiles.strict) 'delete: sibling "profiles" key still preserved'
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
}

Write-Host ''
if ($script:Failed) {
    Write-Host 'RESULT: FAIL' -ForegroundColor Red
    exit 1
} else {
    Write-Host 'RESULT: PASS' -ForegroundColor Green
    exit 0
}
