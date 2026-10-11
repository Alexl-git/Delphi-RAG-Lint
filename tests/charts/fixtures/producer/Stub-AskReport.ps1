<#
  Stub-AskReport.ps1 -- a stand-in for charts\src\Ask-Report.ps1 -Plain, for the producer tests.

  It prints the same SHAPE as the real script's plain answer: the header sentence, the
  COMMAND line, one BUNDLE line, one INDEX line, then a small body. It never touches an
  index or an engine.

    -DbPath ...stale.sqlite  without -AllowStale -> stderr "ask-report: stale index", exit 3
    -Project ...stale.dproj  without -AllowStale -> stderr "ask-report: stale index", exit 3 (the NEW-run
                                                    stale case of a Compare test, no -DbPath)
    -Target REFUSE                               -> stderr "ask-report: no such symbol", exit 1
    $env:STUB_VARIANT -eq 'B'                    -> the body carries one more row (so a Compare
                                                    test can force a difference)
    $env:STUB_BUNDLE = <folder>                 -> writes graph.dot (nodes StubA, StubB and the edge between them, in the emitters'
                                                    dialect: bare ids, HTML-table labels) and graph.svg
                                                    (<svg>NEW</svg>) into that folder and names it on
                                                    the BUNDLE line, overwriting what is there (so a
                                                    Compare test sees a rerun rewrite the old bundle)

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
if ($Project -and ($Project -like '*stale.dproj') -and -not $AllowStale) {
  [Console]::Error.WriteLine('ask-report: stale index for ' + $Project)
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
$bundle = 'C:\stub\bundle'
if ($env:STUB_BUNDLE) {
  $bundle = $env:STUB_BUNDLE
  New-Item -ItemType Directory -Force -Path $bundle | Out-Null
  $dot = @"
digraph stub {
  node  [shape=plaintext, fontname="Consolas", fontsize=14];
  sa [label=<<TABLE BORDER="0" CELLBORDER="0"><TR><TD PORT="p1" ALIGN="LEFT" HREF="draglint://open?file=Unit1.pas&amp;line=10" TITLE="1 write site: 10:3"><FONT COLOR="#1F2933">StubA</FONT></TD></TR></TABLE>>];
  sb [label=<<TABLE BORDER="0" CELLBORDER="0"><TR><TD PORT="p1" ALIGN="LEFT" HREF="draglint://open?file=Unit1.pas&amp;line=42" TITLE="1 write site: 42:3"><FONT COLOR="#1F2933">StubB</FONT></TD></TR></TABLE>>];
  sa:p1 -> sb:p1 [color="#8A94A6"];
}

"@
  [IO.File]::WriteAllText((Join-Path $bundle 'graph.dot'), $dot, [Text.Encoding]::ASCII)
  [IO.File]::WriteAllText((Join-Path $bundle 'graph.svg'), '<svg>NEW</svg>', [Text.Encoding]::ASCII)
}
$lines.Add("BUNDLE $bundle")
$lines.Add("INDEX $index")
$lines.Add('Totals: 2 write sites / 2 routines.')
$lines.Add('  Unit1.TFoo.SetName (Unit1.pas:10)')
$lines.Add('  Unit1.TFoo.Load (Unit1.pas:42)')
if ($env:STUB_VARIANT -eq 'B') { $lines.Add('  Unit1.TFoo.Reset (Unit1.pas:77)') }
[Console]::Out.Write(($lines -join "`r`n") + "`r`n")
exit 0
