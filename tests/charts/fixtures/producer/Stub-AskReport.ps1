<#
  Stub-AskReport.ps1 -- a stand-in for charts\src\Ask-Report.ps1 -Plain, for the producer tests.

  It prints the same SHAPE as the real script's plain answer: the header sentence, the
  COMMAND line, one BUNDLE line, one INDEX line, then a small body. It never touches an
  index or an engine.

    -DbPath ...stale.sqlite  without -AllowStale -> stderr "ask-report: stale index", exit 3
    -Target REFUSE                               -> stderr "ask-report: no such symbol", exit 1
    $env:STUB_VARIANT -eq 'B'                    -> the body carries one more row (so a Compare
                                                    test can force a difference)

  Parameters the real script takes but the stub ignores are accepted so a command line
  built for the real script runs unchanged.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Question,
  [Parameter(Mandatory)][string] $Target,
  [string] $To,
  [string] $In,
  [string] $Project,
  [int]    $Depth,
  [int]    $Cap,
  [int]    $SurfaceCap,
  [string] $Control,
  [string] $Mode,
  [int]    $MaxRows,
  [string] $DbPath,
  [string] $Engine,
  [switch] $Plain,
  [switch] $AllowStale
)
$ErrorActionPreference = 'Stop'
if ($Target -eq 'REFUSE') {
  [Console]::Error.WriteLine('ask-report: no such symbol')
  exit 1
}
if ($DbPath -and ($DbPath -like '*stale.sqlite') -and -not $AllowStale) {
  [Console]::Error.WriteLine('ask-report: stale index: ' + $DbPath)
  exit 3
}
$sentTarget = $(if ($To) { "$Target -> $To" } else { $Target })
$cmd = "COMMAND $Question -Target `"$Target`""
if ($To)      { $cmd += " -To `"$To`"" }
if ($Project) { $cmd += " -Project `"$Project`"" } elseif ($In) { $cmd += " -In `"$In`"" }
foreach ($n in 'Depth', 'Cap', 'SurfaceCap') { if ($PSBoundParameters.ContainsKey($n)) { $cmd += " -$n $($PSBoundParameters[$n])" } }
if ($Control) { $cmd += " -Control `"$Control`"" }
if ($Mode)    { $cmd += " -Mode $Mode" }
if ($PSBoundParameters.ContainsKey('MaxRows')) { $cmd += " -MaxRows $MaxRows" }
$index = $(if ($DbPath) { $DbPath } else { 'C:\stub\index.sqlite' })
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Who writes this field (drag-lint report $Question) for $sentTarget, asked on 2026-10-10 14:32, engine 1.27.0.")
$lines.Add($cmd)
$lines.Add('BUNDLE C:\stub\bundle')
$lines.Add("INDEX $index")
$lines.Add('Totals: 2 write sites / 2 routines.')
$lines.Add('  Unit1.TFoo.SetName (Unit1.pas:10)')
$lines.Add('  Unit1.TFoo.Load (Unit1.pas:42)')
if ($env:STUB_VARIANT -eq 'B') { $lines.Add('  Unit1.TFoo.Reset (Unit1.pas:77)') }
[Console]::Out.Write(($lines -join "`r`n") + "`r`n")
exit 0
