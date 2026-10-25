<#
  run_interface_dispatch_bind.ps1 -- an INTERFACE-dispatched call binds to the
  INTERFACE METHOD only, and a CLASS-typed call to the class's own method.

  OWNER RULING 2026-09-16 (docs\INBOX-untypable-receivers-brainstorm.md): a call
  `M.TransferFile(...)` with `M: ICopy` is attributed to ICopy.TransferFile --
  not fanned out to implementors, not dropped. Implementors stay reachable
  through `implements`.

  WHAT WAS WRONG (resolver 1.13.0-alpha, measured on this fixture):
  * CLASS receiver. LookupMethodOnType walked the class's whole heritage list,
    and a class's heritage NAMES ITS INTERFACES. `C.TransferFile` with
    `C: TImplCopy` therefore found TImplCopy.TransferFile AND ICopy.TransferFile,
    read that as two candidates, and bound 'ambiguous' -- refs.symbol_id NULL.
    An implemented interface's method is not a member of the class.
  * FUNCTION-RESULT receiver. `GetCopy.TransferFile`, `MakeCopy.TransferFile`,
    `MakeCopy().TransferFile` typed nothing: TypeReceiver had no rung for a
    receiver that names a FUNCTION, so the call stayed unbound.

  WHAT THIS GUARD PINS (target of the `call` ref on each line, and confidence)
    IF1-IF5  local / param / field / property / derived-interface receiver
             -> uIfaceCopy.ICopy.TransferFile, certain       (green before: controls)
    IF6-IF8  method result / free-function result / `F()` result
             -> uIfaceCopy.ICopy.TransferFile, certain
    NOFAN    no interface-typed site has an edge to EITHER implementor
    CLS1     class-typed local  -> TImplCopy.TransferFile, certain, refs bound
    CLS2     descendant class   -> TImplCopy.TransferFile, certain
    CLS3/4   class-typed function / method result -> TImplCopy.TransferFile
    SHADOW   a local named like the function shadows it -> TOtherCopy.TransferFile
  Two implementors declare TransferFile, so a name join cannot pass by accident.

  Usage: pwsh -File tests\callresolve\run_interface_dispatch_bind.ps1 [-Exe <drag-lint.exe>]
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
$scratch = Join-Path C:\TEMP "draglint_interface_dispatch_bind_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*.pas') $scratch
$db = Join-Path $scratch 'ifacedispatch.sqlite'

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function Sql([string]$Query) {
  $raw = (& $exePath sql --db $db --json --limit 1000 --query $Query 2>$null) -join "`n"
  $b = $raw.IndexOf('{')
  if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
  $o = $raw.Substring($b) | ConvertFrom-Json
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += $h
  }
  return ,@($out)
}

$lines = [System.IO.File]::ReadAllLines((Join-Path $scratch 'uIfaceUser.pas'))
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  throw "fixture line not found: $Needle"
}

$null = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

# The edge of the `call` ref TransferFile on the line whose trimmed text is NEEDLE.
function EdgeOf([string]$Needle) {
  $ln = LineOf $Needle
  $r = Sql ("SELECT COALESCE(t.qualified_name, '') AS q, COALESCE(e.confidence, '') AS c, " +
            "COALESCE(s.qualified_name, '') AS bound FROM refs r " +
            "LEFT JOIN call_edges e ON e.ref_id = r.id LEFT JOIN symbols t ON t.id = e.target_symbol_id " +
            "LEFT JOIN symbols s ON s.id = r.symbol_id " +
            "WHERE r.kind = 'call' AND r.name_text = 'TransferFile' AND r.start_line = $ln")
  if ($r.Count -ne 1) { return @{ q = "<$($r.Count) call refs>"; c = ''; bound = '' } }
  return $r[0]
}

$IFACE = 'uIfaceCopy.ICopy.TransferFile'
$IMPL  = 'uIfaceCopy.TImplCopy.TransferFile'
$OTHER = 'uIfaceCopy.TOtherCopy.TransferFile'

$ifaceSites = [ordered]@{
  'IF1 local M: ICopy'          = "M.TransferFile('local');"
  'IF2 param P: ICopy'          = "P.TransferFile('param');"
  'IF3 field FCopy: ICopy'      = "FCopy.TransferFile('field');"
  'IF4 property Copy: ICopy'    = "Copy.TransferFile('prop');"
  'IF5 derived D: ICopy2'       = "D.TransferFile('derived');"
  'IF6 method result GetCopy'   = "GetCopy.TransferFile('method');"
  'IF7 free result MakeCopy'    = "MakeCopy.TransferFile('free');"
  'IF8 free result MakeCopy()'  = "MakeCopy().TransferFile('parens');"
}
foreach ($k in $ifaceSites.Keys) {
  $e = EdgeOf $ifaceSites[$k]
  Check "$k -> ICopy.TransferFile, certain" (($e.q -eq $IFACE) -and ($e.c -eq 'certain') -and ($e.bound -eq $IFACE)) "edge=$($e.q) conf=$($e.c) bound=$($e.bound)"
}

# NOFAN: no edge from any interface-typed site to an implementor.
$ifaceLines = @($ifaceSites.Values | ForEach-Object { LineOf $_ }) -join ','
$fan = Sql ("SELECT COUNT(*) AS n FROM refs r JOIN call_edges e ON e.ref_id = r.id JOIN symbols t ON t.id = e.target_symbol_id " +
            "WHERE r.name_text = 'TransferFile' AND r.start_line IN ($ifaceLines) " +
            "AND t.qualified_name IN ('$IMPL', '$OTHER')")
Check 'NOFAN no interface-typed site binds an implementor' ($fan[0].n -eq 0) "edges=$($fan[0].n)"

$clsSites = [ordered]@{
  'CLS1 class local C: TImplCopy'      = @("C.TransferFile('class');", $IMPL)
  'CLS2 descendant S: TSubCopy'        = @("S.TransferFile('subclass');", $IMPL)
  'CLS3 class result MakeImpl'         = @("MakeImpl.TransferFile('implresult');", $IMPL)
  'CLS4 class method result GetImpl'   = @("GetImpl.TransferFile('implmethod');", $IMPL)
  'SHADOW local MakeCopy: TOtherCopy'  = @("MakeCopy.TransferFile('shadow');", $OTHER)
}
foreach ($k in $clsSites.Keys) {
  $e = EdgeOf $clsSites[$k][0]
  $want = $clsSites[$k][1]
  Check "$k -> $want, certain" (($e.q -eq $want) -and ($e.c -eq 'certain') -and ($e.bound -eq $want)) "edge=$($e.q) conf=$($e.c) bound=$($e.bound)"
}

# User-facing surface: find-callers by the bare name lists every site.
$fc = (& $exePath query find-callers --name TransferFile --db $db 2>$null | Out-String)
$m = [regex]::Match($fc, '(\d+) caller\(s\)')
Check 'find-callers TransferFile lists all 13 sites' ($m.Success -and [int]$m.Groups[1].Value -eq 13) "$($m.Value)"

if ($script:fail) { Write-Host 'FAIL'; exit 1 } else { Write-Host 'PASS'; exit 0 }
} finally {
  $d = Join-Path C:\TEMP "draglint_interface_dispatch_bind_$PID"
  if (Test-Path -LiteralPath $d) { [System.IO.Directory]::Delete($d, $true) }
}
