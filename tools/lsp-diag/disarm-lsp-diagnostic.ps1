# disarm-lsp-diagnostic.ps1
# Restore exactly what arm-lsp-diagnostic.ps1 changed.

$ErrorActionPreference = 'Stop'
$key   = 'HKCU:\Software\Embarcadero\BDS\37.0\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal'
$state = Join-Path $PSScriptRoot 'diag-state.json'

if (-not (Test-Path $state)) {
    Write-Warning "No diag-state.json found -- nothing recorded to restore."
    Write-Warning "Falling back to known-good defaults: CodeInsightUse64BitBinary=False, DelphiLSPLog cleared."
    Set-ItemProperty -Path $key -Name 'CodeInsightUse64BitBinary' -Value 'False'
    [Environment]::SetEnvironmentVariable('DelphiLSPLog', $null, 'User')
    "restored defaults."
    return
}

$prev = Get-Content $state -Raw | ConvertFrom-Json

if ($null -ne $prev.CodeInsightUse64BitBinary) {
    Set-ItemProperty -Path $key -Name 'CodeInsightUse64BitBinary' -Value $prev.CodeInsightUse64BitBinary
    "restored CodeInsightUse64BitBinary = $($prev.CodeInsightUse64BitBinary)"
} else {
    Set-ItemProperty -Path $key -Name 'CodeInsightUse64BitBinary' -Value 'False'
    "CodeInsightUse64BitBinary had no prior value -- set to False"
}

[Environment]::SetEnvironmentVariable('DelphiLSPLog', $prev.DelphiLSPLog_User, 'User')
"restored DelphiLSPLog (User) = $(if ($prev.DelphiLSPLog_User) { $prev.DelphiLSPLog_User } else { '<unset>' })"

Remove-Item (Join-Path $PSScriptRoot 'armed.marker') -ErrorAction SilentlyContinue
"disarmed. Restart the IDE for settings to take effect."
