<#
  bpl-inventory.ps1 -- HEADLESS half of the design-time package RAM audit
  (docs\INBOX-ide-lsp-ram-and-shim-todo.md, TODO 3).

  The note marks that whole item "BLOCKED: needs a running IDE". Steps 3-4 are
  not: the package REGISTRY and the on-disk BPL SIZES can be gathered right now,
  with the IDE closed, and they produce the ranked cost-vs-feature table the item
  asks for -- provisionally, from file size instead of committed memory.

  WHAT THIS CANNOT TELL YOU, stated plainly so the output is not over-read: file
  size is a PROXY for committed memory, not a measurement of it. A large BPL that
  loads once and touches little costs less than its size suggests; a small one
  that allocates heavily costs more. Only step 4 of the note -- `Get-Process bds`
  with the IDE running -- gives real ModuleMemorySize. This narrows where to
  look; it does not settle it.

  Nothing here writes to the registry or moves a file. It reads three keys and
  stats the files they name.

  Usage:  pwsh -File tools\lsp-diag\bpl-inventory.ps1 [-Top 40] [-Csv out.csv]
#>
[CmdletBinding()]
param(
  [int]$Top = 40,
  [string]$Csv = '',
  [string]$BdsVersion = '37.0'
)

$ErrorActionPreference = 'Stop'

$keys = @(
  @{ Name = 'Known Packages'    ; Path = "HKCU:\Software\Embarcadero\BDS\$BdsVersion\Known Packages"     },
  @{ Name = 'Known IDE Packages'; Path = "HKCU:\Software\Embarcadero\BDS\$BdsVersion\Known IDE Packages" },
  @{ Name = 'Known Packages x64'; Path = "HKCU:\Software\Embarcadero\BDS\$BdsVersion\Known Packages x64" }
)

$rows = New-Object System.Collections.Generic.List[object]
foreach ($k in $keys) {
  if (-not (Test-Path $k.Path)) { Write-Host ("  (absent) {0}" -f $k.Path) -ForegroundColor DarkGray; continue }
  $props = Get-ItemProperty -Path $k.Path
  foreach ($p in $props.PSObject.Properties) {
    if ($p.Name -like 'PS*') { continue }
    # value name = BPL path (may contain $(BDS)); value data = human description
    $path = $p.Name -replace '\$\(BDSBIN\)', "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion\bin" `
                    -replace '\$\(BDSCOMMONDIR\)', "$env:PUBLIC\Documents\Embarcadero\Studio\$BdsVersion" `
                    -replace '\$\(BDS\)', "C:\Program Files (x86)\Embarcadero\Studio\$BdsVersion"
    $size = $null
    if (Test-Path -LiteralPath $path) { $size = (Get-Item -LiteralPath $path).Length }
    # A LEADING '__' ON THE DESCRIPTION IS THE IDE'S OWN "DISABLED" MARKER.
    # Unchecking a package in Component > Install Packages does not delete the
    # registry value -- it prefixes the description. So a disabled entry whose
    # file is absent is the NORMAL state, not a broken install. The first draft
    # of this script reported all four such entries here as "the IDE will fail
    # to load", which would have sent the owner chasing a non-problem.
    $desc = [string]$p.Value
    $rows.Add([pscustomobject]@{
      Registry    = $k.Name
      Description = $desc
      Disabled    = $desc.StartsWith('__')
      Bpl         = Split-Path $path -Leaf
      SizeKB      = $(if ($null -ne $size) { [math]::Round($size / 1KB, 0) } else { $null })
      Found       = ($null -ne $size)
      FullPath    = $path
    })
  }
}

Write-Host ''
Write-Host ('=== design-time package inventory (BDS {0}) ===' -f $BdsVersion) -ForegroundColor Cyan
foreach ($k in $keys) {
  $sub = @($rows | Where-Object Registry -eq $k.Name)
  if ($sub.Count -eq 0) { continue }
  $missing = @($sub | Where-Object { -not $_.Found }).Count
  Write-Host ('  {0,-20} {1,4} entr(ies), {2,7} MB on disk{3}' -f `
    $k.Name, $sub.Count,
    [math]::Round((($sub | Measure-Object SizeKB -Sum).Sum) / 1KB, 1),
    $(if ($missing) { ", $missing not found on disk" } else { '' })) -ForegroundColor Cyan
}

Write-Host ''
Write-Host ("  TOP $Top BY FILE SIZE -- a shortlist to measure in a live IDE, NOT a disable list") -ForegroundColor Yellow
$rows | Where-Object Found | Sort-Object SizeKB -Descending | Select-Object -First $Top |
  Format-Table @{n='MB';e={[math]::Round($_.SizeKB/1KB,1)};a='right'}, Bpl, Registry, Description -AutoSize

$disabledMissing = @($rows | Where-Object { (-not $_.Found) -and $_.Disabled })
if ($disabledMissing.Count -gt 0) {
  Write-Host ''
  Write-Host ("  {0} DISABLED package(s) absent from disk -- expected, no action ('__' = unchecked in Install Packages):" -f $disabledMissing.Count) -ForegroundColor DarkGray
  $disabledMissing | Select-Object Bpl, Registry | Format-Table -AutoSize
}

$notFound = @($rows | Where-Object { (-not $_.Found) -and (-not $_.Disabled) })
if ($notFound.Count -gt 0) {
  Write-Host ''
  Write-Host ("  {0} ENABLED package(s) NOT found on disk -- the IDE will fail to load these:" -f $notFound.Count) -ForegroundColor Red
  $notFound | Select-Object Bpl, Registry, Description | Format-Table -AutoSize
}

if ($Csv -ne '') {
  $rows | Sort-Object SizeKB -Descending | Export-Csv -Path $Csv -NoTypeInformation -Encoding ASCII
  Write-Host ("  wrote {0}" -f $Csv) -ForegroundColor Green
}

Write-Host ''
Write-Host '  NEXT, and it needs the owner at a keyboard (see the note''s section D):' -ForegroundColor Cyan
Write-Host '    Get-Process bds | Select-Object -ExpandProperty Modules |'
Write-Host '      Sort-Object ModuleMemorySize -Descending |'
Write-Host '      Select-Object -First 60 ModuleName,ModuleMemorySize > modules.txt'
Write-Host '  Committed size is the real number; the table above only says where to look.'
