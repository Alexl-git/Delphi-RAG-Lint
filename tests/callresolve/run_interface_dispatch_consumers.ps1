<#
  run_interface_dispatch_consumers.ps1 -- the READERS (find-callers --resolved,
  impact, context, call-path) walk dispatch_edges 'implements' from an
  IMPLEMENTOR method up to its interface method.

  OWNER RULING 2026-09-16 (docs\INBOX-untypable-receivers-brainstorm.md): a call
  through `M: ICopy` is attributed to ICopy.TransferFile (resolver, shipped as
  X2); implementors stay reachable through `implements`. Until RB-5 P1 the
  READERS never climbed that edge: asking for the callers of
  TImplCopy.TransferFile answered only the class-typed sites and said nothing
  of the eight interface-typed ones that dispatch to it.

  WHAT THIS GUARD PINS (fixture tests\callresolve\fixtures\ifacedispatch)
    FC1   find-callers --resolved TransferFile: under TImplCopy.TransferFile a
          `via interface dispatch (uIfaceCopy.ICopy.TransferFile): 8 site(s)`
          block, and the same under TOtherCopy.TransferFile.
    FC2   POSITIVE CONTROL: the class-typed sites are listed DIRECTLY under
          TImplCopy and are NOT in its via block; the shadowed TOtherCopy site
          is direct under TOtherCopy.
    FC3   --json: exactly 16 rows (8 per implementor) carry `via` = the
          interface method and `via_kind` = interface; no row to the interface
          itself carries `via`.
    IM1   impact --qname ICopy.TransferFile lists BOTH implementors.
    IM2   impact --qname TImplCopy.TransferFile reports `via interface
          dispatch (uIfaceCopy.ICopy.TransferFile): 8 site(s)` (not 12).
    CX1   context --task "modify TImplCopy.TransferFile" has the section
          `Callers via interface dispatch (uIfaceCopy.ICopy.TransferFile)` with
          the 8 interface-typed lines and none of the class-typed lines.
    CP1   call-path from an interface-typed caller to TImplCopy.TransferFile
          finds ViaLocal -> ICopy.TransferFile -> TImplCopy.TransferFile.
    CP2   POSITIVE CONTROL: no path from a class-typed caller (ViaClass) to
          TOtherCopy.TransferFile.

  Usage: pwsh -File tests\callresolve\run_interface_dispatch_consumers.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\ifacedispatch')).Path
$scratch = Join-Path C:\TEMP "draglint_interface_dispatch_consumers_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db = Join-Path $scratch 'ifacedispatch.sqlite'

$lines = [System.IO.File]::ReadAllLines((Join-Path $scratch 'uIfaceUser.pas'))
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  throw "fixture line not found: $Needle"
}

$null = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

$IFACE = 'uIfaceCopy.ICopy.TransferFile'
$IMPL  = 'uIfaceCopy.TImplCopy.TransferFile'
$OTHER = 'uIfaceCopy.TOtherCopy.TransferFile'
$ifaceLines = @("M.TransferFile('local');", "P.TransferFile('param');", "D.TransferFile('derived');",
  "MakeCopy.TransferFile('free');", "MakeCopy().TransferFile('parens');", "FCopy.TransferFile('field');",
  "Copy.TransferFile('prop');", "GetCopy.TransferFile('method');") | ForEach-Object { LineOf $_ }
$classLines = @("C.TransferFile('class');", "S.TransferFile('subclass');", "MakeImpl.TransferFile('implresult');",
  "GetImpl.TransferFile('implmethod');") | ForEach-Object { LineOf $_ }
$shadowLine = LineOf "MakeCopy.TransferFile('shadow');"
$VIA = "via interface dispatch ($IFACE)"

# Split the text form into per-target blocks: header `  <qname>:` then its rows.
$txt = (& $exePath query find-callers --name TransferFile --resolved --db $db 2>$null | Out-String) -split "`r?`n"
$blocks = @{}; $cur = $null
foreach ($l in $txt) {
  if ($l -match '^  (\S+):\s*$') { $cur = $Matches[1]; $blocks[$cur] = New-Object System.Collections.ArrayList; continue }
  if ($cur) { [void]$blocks[$cur].Add($l) }
}
function ViaSection([string]$Target) {   # rows after the via header, up to the next block
  $out = @(); $on = $false
  foreach ($r in $blocks[$Target]) {
    if ($r -match '^    via ') { $on = ($r -like "*$VIA*"); continue }
    if ($on) { $out += $r }
  }
  return ,$out
}
function DirectRows([string]$Target) {
  $out = @()
  foreach ($r in $blocks[$Target]) { if ($r -match '^    via ') { break }; $out += $r }
  return ,$out
}
function LinesIn($rows) { @($rows | ForEach-Object { if ($_ -match 'uIfaceUser\.pas:(\d+)\)') { [int]$Matches[1] } }) }

foreach ($t in @($IMPL, $OTHER)) {
  $hdr = @($blocks[$t] | Where-Object { $_ -eq "    ${VIA}: 8 site(s)" })
  Check "FC1 $t has '${VIA}: 8 site(s)'" ($hdr.Count -eq 1) "rows=$(@($blocks[$t]).Count)"
  $vl = @(LinesIn (ViaSection $t) | Sort-Object)
  Check "FC1 $t via sites are the 8 interface-typed lines" (($vl -join ',') -eq (($ifaceLines | Sort-Object) -join ',')) "got=$($vl -join ',')"
}
$dl = @(LinesIn (DirectRows $IMPL) | Sort-Object)
Check 'FC2 TImplCopy direct rows = the 4 class-typed lines' (($dl -join ',') -eq (($classLines | Sort-Object) -join ',')) "got=$($dl -join ',')"
$vlImpl = @(LinesIn (ViaSection $IMPL))
Check 'FC2 control: no class-typed line is in the via block' (@($vlImpl | Where-Object { $classLines -contains $_ }).Count -eq 0)
$dlO = @(LinesIn (DirectRows $OTHER))
Check 'FC2 TOtherCopy direct = the shadowed site only' (($dlO -join ',') -eq "$shadowLine") "got=$($dlO -join ',')"

$jraw = (& $exePath query find-callers --name TransferFile --resolved --json --db $db 2>$null) -join "`n"
$j = @($jraw.Substring($jraw.IndexOf('[')) | ConvertFrom-Json)
$withVia = @($j | Where-Object { $_.PSObject.Properties.Name -contains 'via' })
Check 'FC3 json: 16 via rows (8 per implementor)' ($withVia.Count -eq 16) "n=$($withVia.Count)"
Check 'FC3 json: every via row names the interface method, kind interface' (@($withVia | Where-Object { $_.via -ne $IFACE -or $_.via_kind -ne 'interface' }).Count -eq 0)
Check 'FC3 json: no row to the interface itself carries via' (@($j | Where-Object { $_.target_qname -eq $IFACE -and ($_.PSObject.Properties.Name -contains 'via') }).Count -eq 0)

$imI = (& $exePath impact --qname $IFACE --db $db 2>&1 | Out-String)
Check 'IM1 impact on the interface method lists both implementors' (($imI -match [regex]::Escape($IMPL)) -and ($imI -match [regex]::Escape($OTHER)) -and ($imI -match 'implementor')) $imI.Trim()
$imC = (& $exePath impact --qname $IMPL --db $db 2>&1 | Out-String)
Check 'IM2 impact on an implementor: via interface dispatch, 8 site(s)' ($imC -like "*${VIA}: 8 site(s)*") $imC.Trim()
$imJ = (& $exePath impact --qname $IFACE --format json --db $db 2>&1 | Out-String)
Check 'IM1 json carries an implementors array' ($imJ -match '"implementors"')

$cx = (& $exePath context --task "modify TImplCopy.TransferFile" --db $db --format markdown --max-callers 20 2>$null | Out-String)
$ix = $cx.IndexOf("Callers via interface dispatch ($IFACE)")
Check 'CX1 context has the via section' ($ix -ge 0)
if ($ix -ge 0) {
  $sec = $cx.Substring($ix)
  $nx = $sec.IndexOf("`n## ", 5); if ($nx -gt 0) { $sec = $sec.Substring(0, $nx) }
  $got = @([regex]::Matches($sec, 'uIfaceUser\.pas:(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique)
  Check 'CX1 via section = the 8 interface-typed lines' (($got -join ',') -eq (($ifaceLines | Sort-Object) -join ',')) "got=$($got -join ',')"
  Check 'CX1 control: no class-typed line in the via section' (@($got | Where-Object { $classLines -contains $_ }).Count -eq 0)
}

$cx5 = (& $exePath context --task "modify TImplCopy.TransferFile" --db $db --format markdown 2>$null | Out-String)
Check 'CX2 default cap (5): header still reports the true 8 site(s)' ($cx5 -like "*Callers via interface dispatch (${IFACE}): 8 site(s)*")
$cp = (& $exePath call-path --from uIfaceUser.ViaLocal --to $IMPL --db $db 2>$null | Out-String).Trim()
Check 'CP1 interface-typed caller reaches the implementor' ($LASTEXITCODE -eq 0 -and $cp -eq "uIfaceUser.ViaLocal -> $IFACE -> $IMPL") $cp
$cp2 = (& $exePath call-path --from uIfaceUser.ViaClass --to $OTHER --db $db 2>$null | Out-String).Trim()
Check 'CP2 control: class-typed caller does NOT reach the other implementor' ($LASTEXITCODE -eq 1) $cp2

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  $d = Join-Path C:\TEMP "draglint_interface_dispatch_consumers_$PID"
  if (Test-Path -LiteralPath $d) { [System.IO.Directory]::Delete($d, $true) }
}
