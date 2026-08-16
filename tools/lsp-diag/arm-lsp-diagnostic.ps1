# arm-lsp-diagnostic.ps1
# Prepare the IDE to capture WHY DelphiLSP fails when CodeInsightUse64BitBinary=True
# in the 32-bit RAD Studio 13 IDE.
#
# RUN THIS BEFORE STARTING THE IDE. It changes IDE behaviour -- Code Insight will use
# the 64-bit server (the configuration that errors). Run disarm-lsp-diagnostic.ps1
# afterwards to restore.
#
# Usage:   powershell -ExecutionPolicy Bypass -File arm-lsp-diagnostic.ps1
# Restore: powershell -ExecutionPolicy Bypass -File disarm-lsp-diagnostic.ps1

$ErrorActionPreference = 'Stop'
$key   = 'HKCU:\Software\Embarcadero\BDS\37.0\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal'
$state = Join-Path $PSScriptRoot 'diag-state.json'

if (-not (Test-Path $key)) { throw "Code Insight key not found: $key" }

# --- 1. save current state so disarm can restore exactly -------------------------
$prev = @{
    CodeInsightUse64BitBinary = (Get-ItemProperty $key -Name 'CodeInsightUse64BitBinary' -ErrorAction SilentlyContinue).CodeInsightUse64BitBinary
    DelphiLSPLog_User         = [Environment]::GetEnvironmentVariable('DelphiLSPLog','User')
    ArmedAtUtc                = (Get-Date).ToUniversalTime().ToString('o')
}
$prev | ConvertTo-Json | Set-Content -Path $state -Encoding UTF8
"saved prior state -> $state"
"  CodeInsightUse64BitBinary was: $($prev.CodeInsightUse64BitBinary)"
"  DelphiLSPLog (User) was      : $($prev.DelphiLSPLog_User)"

# --- 2. enable DelphiLSP logging ------------------------------------------------
# delphicoreide370.bpl reads the env var 'DelphiLSPLog' and translates it into the
# '-LogModes <n>' argument it passes to DelphiLSP.exe. 7 = maximally verbose.
[Environment]::SetEnvironmentVariable('DelphiLSPLog','7','User')
"set DelphiLSPLog=7 (User scope)"

# --- 3. switch Code Insight to the 64-bit server (the failing configuration) -----
Set-ItemProperty -Path $key -Name 'CodeInsightUse64BitBinary' -Value 'True'
"set CodeInsightUse64BitBinary=True"

# --- 4. timestamp marker so the collector only gathers NEW logs ------------------
$marker = Join-Path $PSScriptRoot 'armed.marker'
Set-Content -Path $marker -Value (Get-Date).ToString('o') -Encoding UTF8

@"

ARMED.

Next steps:
  1. Start RAD Studio 13 (32-bit) from the Start Menu -- NOT from an already-open shell,
     so it inherits the new DelphiLSPLog environment variable.
  2. Open the project that reproduced the errors and let Code Insight run
     (open a unit, hover a symbol, trigger completion with Ctrl+Space).
  3. Reproduce the error and note the exact wording / dialog.
  4. Close the IDE.
  5. Run:  collect-lsp-diagnostic.ps1     <- gathers every log written since arming
  6. Run:  disarm-lsp-diagnostic.ps1      <- restores your previous settings

"@
