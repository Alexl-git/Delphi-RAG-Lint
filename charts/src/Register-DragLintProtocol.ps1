<#
  Register-DragLintProtocol.ps1 -- makes draglint:// clickable from a browser.

  Writes ONE key under HKCU (per-user, never HKLM), so it needs no elevation
  and is removed by one -Unregister. Nothing else on the machine is touched.

    HKCU:\Software\Classes\draglint
      (default)                = "URL:drag-lint protocol"
      "URL Protocol"           = ""
      shell\open\command\(default) = powershell -File Open-DragLintUri.ps1 "%1"

  To undo:  .\Register-DragLintProtocol.ps1 -Unregister
  Or by hand: Remove-Item HKCU:\Software\Classes\draglint -Recurse
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch] $Unregister,
  [string] $HandlerPath = (Join-Path $PSScriptRoot 'Open-DragLintUri.ps1')
)

$ErrorActionPreference = 'Stop'
$root = 'HKCU:\Software\Classes\draglint'

if ($Unregister) {
  if (Test-Path $root) {
    if ($PSCmdlet.ShouldProcess($root, 'Remove')) {
      Remove-Item $root -Recurse -Force
      Write-Host "unregistered: $root"
    }
  } else { Write-Host "nothing to remove: $root" }
  return
}

if (-not (Test-Path -LiteralPath $HandlerPath)) { throw "handler not found: $HandlerPath" }
$handler = (Resolve-Path -LiteralPath $HandlerPath).Path

# pwsh if present, else Windows PowerShell -- both ship the pipe client we need
$ps = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $ps) { $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }

$cmd = '"{0}" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" "%1"' -f $ps, $handler

if ($PSCmdlet.ShouldProcess($root, 'Register draglint:// protocol')) {
  New-Item -Path $root -Force | Out-Null
  Set-ItemProperty -Path $root -Name '(default)'   -Value 'URL:drag-lint protocol'
  Set-ItemProperty -Path $root -Name 'URL Protocol' -Value ''
  $cmdKey = Join-Path $root 'shell\open\command'
  New-Item -Path $cmdKey -Force | Out-Null
  Set-ItemProperty -Path $cmdKey -Name '(default)' -Value $cmd

  Write-Host "registered: $root"
  Write-Host "  handler : $handler"
  Write-Host "  host    : $ps"
  Write-Host "  undo    : .\Register-DragLintProtocol.ps1 -Unregister"
}
