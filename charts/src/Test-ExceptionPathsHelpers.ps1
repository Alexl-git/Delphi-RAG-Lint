<#
  Test-ExceptionPathsHelpers.ps1 -- measures the INDEX-WIDE numbers behind the
  exception-paths chart (PLAN-last-four-verbs Task 1) and RETURNS them. It
  asserts nothing: Test-Emitters.ps1 pins every number with its own codes
  (A-EP0-*), the Test-Task0Helpers.ps1 precedent.

  Two populations, measured the way the chart uses them:

    * the name-filtered CANDIDATE refs (Get-ExceptionIndexStats) -- what the
      focus box prints as "approximately N raise sites / M handlers";
    * the SOURCE-ONLY rows (Get-ExceptionSourceRows) inside every INDEXED impl
      span -- bare `except`, `raise;`, `raise <var>` -- which carry no ref and so
      can only ever be `[inferred]`.

  A line belongs to its INNERMOST span (a nested routine's statements are the
  nested routine's), so each statement is counted once. Lines outside every
  span are not scanned: P6's 11 raises inside a never-defined
  `{$IFDEF M2022_REFERENCE}` sit where the index has no routine at all.

  Nothing here writes to a database.
#>
[CmdletBinding()]
param(
  [string] $DbCli  = (Join-Path $PSScriptRoot '..\scratch\db\CLIENT-Micronite2027.sqlite'),
  [string] $Engine = 'C:\Projects\Delphi-RAG-lint-wt\archify-ir\third_party\dll-win64\drag-lint.exe'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')

$DbPath = Get-CloneDb $DbCli
$res = [ordered]@{}

# ---- 1. the candidate refs (the focus box's index-wide line) ---------------------
$st = Get-ExceptionIndexStats
$res.Candidates     = $st.Candidates
$res.Raise          = $st.Raise
$res.Handle         = $st.Handle
$res.Dropped        = $st.Dropped
$res.Stale          = $st.Stale
$res.RaiseRoutines  = $st.RaiseRoutines
$res.HandleRoutines = $st.HandleRoutines

# ---- 2. the source-only rows inside every indexed impl span -----------------------
# ONE row per file (group_concat), not one per span: 11,007 spans would be 62
# paged engine calls; ~560 files is four.
$spans = Get-AllIndexRows @"
SELECT f.path AS path,
       group_concat(s.id || ':' || s.impl_start_line || ':' || s.impl_end_line, ',') AS spans,
       COUNT(*) AS n
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.impl_start_line > 0 AND s.impl_end_line >= s.impl_start_line
 GROUP BY f.path
"@ 'f.path'

$count = @{}
foreach ($k in 'bare-except', 'on-except', 'reraise', 'raise-var', 'raise-create', 'raise-other') { $count[$k] = 0 }
$bareRoutines = @{}
$spanTotal = 0; $staleFiles = 0
foreach ($f in $spans) {
  $spanTotal += [int]$f.n
  $list = @(([string]$f.spans -split ',') | ForEach-Object {
    $a = $_ -split ':'
    [pscustomobject]@{ Id = [int]$a[0]; From = [int]$a[1]; To = [int]$a[2] }
  })
  $lo = ($list | Measure-Object -Property From -Minimum).Minimum
  $hi = ($list | Measure-Object -Property To -Maximum).Maximum
  # innermost owner per line: widest spans first, narrower ones overwrite
  $owner = New-Object 'int[]' ($hi + 2)
  foreach ($s in ($list | Sort-Object @{ E = { $_.To - $_.From }; Descending = $true })) {
    for ($ln = $s.From; $ln -le $s.To; $ln++) { $owner[$ln] = $s.Id }
  }
  $scan = Get-ExceptionSourceRows ([string]$f.path) $lo $hi
  if ($scan.Stale) { $staleFiles++; continue }
  foreach ($r in $scan.Rows) {
    if ($owner[$r.Line] -eq 0) { continue }
    $count[$r.Kind]++
    if ($r.Kind -eq 'bare-except') { $bareRoutines[$owner[$r.Line]] = $true }
  }
}
$res.Spans          = $spanTotal
$res.SpanFiles      = $spans.Count
$res.SpanStaleFiles = $staleFiles
$res.BareExcept     = $count['bare-except']
$res.OnExcept       = $count['on-except']
$res.Reraise        = $count['reraise']
$res.RaiseVar       = $count['raise-var']
$res.RaiseCreate    = $count['raise-create']
$res.RaiseOther     = $count['raise-other']
$res.BareRoutines   = $bareRoutines.Count

[pscustomobject]$res
