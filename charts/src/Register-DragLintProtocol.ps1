<#
  Register-DragLintProtocol.ps1 -- makes draglint:// clickable from a browser.

  Writes ONE key under HKCU (per-user, never HKLM), so it needs no elevation
  and is removed by one -Unregister. It also COPIES the handler to a stable
  per-user place and registers the COPY, so the registration survives the
  checkout it was made from (ruling ASK-R1):

    %LOCALAPPDATA%\drag-lint\Open-DragLintUri.ps1          the installed handler

    HKCU:\Software\Classes\draglint
      (default)                = "URL:drag-lint protocol"
      "URL Protocol"           = ""
      shell\open\command\(default) = "<interpreter>" -NoProfile -NonInteractive
          -WindowStyle Hidden -ExecutionPolicy Bypass -File "<installed handler>" "%1"

  The interpreter is chosen for a path that survives a PowerShell update, never
  (Get-Command pwsh).Source -- on a Store install that is the VERSIONED package
  folder (...\WindowsApps\Microsoft.PowerShell_7.6.6.0_x64__...), deleted by the next
  update. In order:
    1. $env:ProgramFiles\PowerShell\7\pwsh.exe              (MSI install; REG_SZ)
    2. %LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe        (Store alias; written
       unexpanded as REG_EXPAND_SZ)
    3. %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe  (5.1; the handler
       runs there too)
  A path containing \WindowsApps\Microsoft.PowerShell_ is refused, however it arrives.

  A handler SOURCE inside a *-wt\ worktree is refused without -Force: a worktree copy
  may be unmerged work. -DryRun returns what WOULD be written (Key, Kind, Interpreter,
  Command, HandlerSource, HandlerInstalled) and touches nothing -- no registry write,
  no copy. -ProgramFilesRoot / -LocalAppDataRoot / -SystemRootDir only move where the
  interpreter PROBE looks (tests).

  To undo:  .\Register-DragLintProtocol.ps1 -Unregister   (removes the key and the copy)
  Or by hand: Remove-Item HKCU:\Software\Classes\draglint -Recurse
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [switch] $Unregister,
  [switch] $DryRun,
  [switch] $Force,
  [string] $HandlerPath = (Join-Path $PSScriptRoot 'Open-DragLintUri.ps1'),
  [string] $InstallDir  = (Join-Path $env:LOCALAPPDATA 'drag-lint'),
  [string] $Interpreter,
  [string] $ProgramFilesRoot = $env:ProgramFiles,
  [string] $LocalAppDataRoot = $env:LOCALAPPDATA,
  [string] $SystemRootDir    = $env:SystemRoot
)

$ErrorActionPreference = 'Stop'
$root = 'HKCU:\Software\Classes\draglint'
$installed = Join-Path $InstallDir 'Open-DragLintUri.ps1'

if ($Unregister) {
  if (Test-Path $root) {
    if ($PSCmdlet.ShouldProcess($root, 'Remove')) {
      Remove-Item $root -Recurse -Force
      Write-Host "unregistered: $root"
    }
  } else { Write-Host "nothing to remove: $root" }
  if (Test-Path -LiteralPath $installed) {
    if ($PSCmdlet.ShouldProcess($installed, 'Remove')) { Remove-Item -LiteralPath $installed -Force; Write-Host "removed: $installed" }
  }
  return
}

if (-not (Test-Path -LiteralPath $HandlerPath)) { throw "handler not found: $HandlerPath" }
$handler = (Resolve-Path -LiteralPath $HandlerPath).Path
if ($handler -match '-wt\\' -and -not $Force) {
  throw ("the handler source $handler is inside a worktree (*-wt\) -- register from the main checkout, " +
         'or pass -Force to install this copy deliberately')
}

# ---- the interpreter: a path that survives a PowerShell update -------------------
$kind = 'String'
if ($Interpreter) { $ps = $Interpreter }
elseif (Test-Path -LiteralPath (Join-Path $ProgramFilesRoot 'PowerShell\7\pwsh.exe')) { $ps = Join-Path $ProgramFilesRoot 'PowerShell\7\pwsh.exe' }
elseif (Test-Path -LiteralPath (Join-Path $LocalAppDataRoot 'Microsoft\WindowsApps\pwsh.exe')) {
  $ps = '%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe'; $kind = 'ExpandString'
}
else { $ps = Join-Path $SystemRootDir 'System32\WindowsPowerShell\v1.0\powershell.exe' }
if ($ps -match '\\WindowsApps\\Microsoft\.PowerShell_') {
  throw "refusing the versioned WindowsApps package path $ps -- the next PowerShell update deletes it"
}

$cmd = '"{0}" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{1}" "%1"' -f $ps, $installed
$plan = [pscustomobject]@{
  Key              = "$root\shell\open\command"
  Kind             = $kind
  Interpreter      = $ps
  Command          = $cmd
  HandlerSource    = $handler
  HandlerInstalled = $installed
}
if ($DryRun) { return $plan }

if ($PSCmdlet.ShouldProcess($root, 'Register draglint:// protocol')) {
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Copy-Item -LiteralPath $handler -Destination $installed -Force
  New-Item -Path $root -Force | Out-Null
  Set-ItemProperty -Path $root -Name '(default)'   -Value 'URL:drag-lint protocol'
  Set-ItemProperty -Path $root -Name 'URL Protocol' -Value ''
  $cmdKey = Join-Path $root 'shell\open\command'
  New-Item -Path $cmdKey -Force | Out-Null
  New-ItemProperty -Path $cmdKey -Name '(default)' -PropertyType $kind -Value $cmd -Force | Out-Null

  Write-Host "registered: $root"
  Write-Host "  handler : $installed (copied from $handler)"
  Write-Host "  command : $cmd ($kind)"
  Write-Host "  undo    : .\Register-DragLintProtocol.ps1 -Unregister"
  $plan
}
