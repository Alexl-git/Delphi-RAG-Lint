<#
  run_dispatch_edges.ps1 -- dispatch_edges + classref_args, the two derived
  tables of docs\superpowers\specs\2026-10-26-extract-polymorphic-form-launches.md
  (R1-R3: DragLint.Index.DispatchResolver, TSQLiteSymbolStore.ResolveDispatch).

  WHY. A call through an interface or a virtual binds the BASE method; the
  form is opened by an override nobody calls directly, so an upward walk over
  call_edges dead-ends. dispatch_edges records base -> override/implementation;
  classref_args records which class a call site passes to a `class of` param.

  EXPECTED (fixture tests\fixtures\dispatch-forms), the EXACT set:
    override    DF.Base.TPlanBase.EditForm -> DF.Plans.TPlanA.EditForm  certain
    override    DF.Base.TPlanBase.EditForm -> DF.Plans.TPlanB.EditForm  certain
    implements  DF.Base.IPlan.EditForm     -> DF.Base.TPlanBase.EditForm certain
  NOT: TPlanR.EditForm (reintroduce, no override) -- no row of any kind.
  An interface edge goes to the method of the class that LISTS the interface;
  subclasses are reached through the override edges (a reader follows the
  edges transitively). That is the VMT truth: TPlanR's reintroduce does not
  replace the slot IPlan dispatches to.

  classref_args: exactly ONE row -- OpenChild(TfrmC) in btnOpenClick, arg 0,
  param DF.Main.TfrmMain.OpenChild.AClass, class DF.FormC.TfrmC, certain.
  OpenChild(LCls) (a variable) gets no row.

  POSITIVE CONTROL: the same fixture with `override` removed from TPlanA must
  LOSE the TPlanA edge and keep the TPlanB one -- a resolver that wrote edges
  by name alone passes the main set and fails here.

  Also pins the calls-stage `dispatch:` log line.

  Usage: pwsh -File tests\callresolve\run_dispatch_edges.ps1 [-Exe <drag-lint.exe>]
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
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures\dispatch-forms')).Path
$root    = Join-Path C:\TEMP "draglint_dispatch_edges_$PID"
if (Test-Path $root) { [System.IO.Directory]::Delete($root, $true) }
New-Item -ItemType Directory -Path $root | Out-Null

function Sql([string]$Db, [string]$Query) {
  $raw = (& $exePath sql --db $Db --json --limit 1000 --query $Query 2>$null) -join "`n"
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
function IndexCopy([string]$Name, [scriptblock]$Mutate) {
  $dir = Join-Path $root $Name
  New-Item -ItemType Directory -Path $dir | Out-Null
  Copy-Item (Join-Path $fixDir '*') $dir
  if ($Mutate) { & $Mutate $dir }
  $db = Join-Path $dir "$Name.sqlite"
  $log = & $exePath index $dir --db $db 2>&1
  Check "$Name index exits 0" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  return @{ Db = $db; Log = @($log | ForEach-Object { "$_" }) }
}
function EdgeSet([string]$Db) {
  $rows = Sql $Db ("SELECT b.qualified_name AS b, i.qualified_name AS i, d.kind AS k, d.confidence AS c " +
                   "FROM dispatch_edges d JOIN symbols b ON b.id = d.base_symbol_id JOIN symbols i ON i.id = d.impl_symbol_id")
  return ,@($rows | ForEach-Object { "$($_.k) $($_.b) -> $($_.i) $($_.c)" } | Sort-Object)
}

# ---- main fixture ---------------------------------------------------------
$m = IndexCopy 'main' $null
$want = @(
  'implements DF.Base.IPlan.EditForm -> DF.Base.TPlanBase.EditForm certain',
  'override DF.Base.TPlanBase.EditForm -> DF.Plans.TPlanA.EditForm certain',
  'override DF.Base.TPlanBase.EditForm -> DF.Plans.TPlanB.EditForm certain') | Sort-Object
$got = EdgeSet $m.Db
Check 'dispatch_edges is exactly the expected set' ((($got -join '|') -ceq ($want -join '|'))) ("got=[" + ($got -join '; ') + "]")
Check 'no edge names TPlanR (reintroduce)' (@($got | Where-Object { $_ -match 'TPlanR' }).Count -eq 0)

$ca = Sql $m.Db ("SELECT c.arg_index AS ai, p.qualified_name AS p, k.qualified_name AS k, c.confidence AS c, r.name_text AS n, e.qualified_name AS e " +
                 "FROM classref_args c JOIN symbols p ON p.id = c.param_symbol_id JOIN symbols k ON k.id = c.class_symbol_id " +
                 "JOIN refs r ON r.id = c.ref_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id")
Check 'classref_args has exactly one row' ($ca.Count -eq 1) "rows=$($ca.Count)"
if ($ca.Count -eq 1) {
  $r = $ca[0]
  Check 'CA site is OpenChild in btnOpenClick' (($r.n -eq 'OpenChild') -and ($r.e -eq 'DF.Main.TfrmMain.btnOpenClick')) "n=$($r.n) e=$($r.e)"
  Check 'CA arg 0 -> param AClass' (([int]$r.ai -eq 0) -and ($r.p -eq 'DF.Main.TfrmMain.OpenChild.AClass')) "ai=$($r.ai) p=$($r.p)"
  Check 'CA class DF.FormC.TfrmC certain' (($r.k -eq 'DF.FormC.TfrmC') -and ($r.c -eq 'certain')) "k=$($r.k) c=$($r.c)"
}
$line = @($m.Log | Where-Object { $_ -match 'dispatch: overrides=(\d+) implements=(\d+) classref-args=(\d+)' })
Check 'calls-stage dispatch: line present once' ($line.Count -eq 1) "lines=$($line.Count)"
if ($line.Count -eq 1) {
  $null = $line[0] -match 'overrides=(\d+) implements=(\d+) classref-args=(\d+)'
  Check 'dispatch: line counts 2/1/1' (($Matches[1] -eq '2') -and ($Matches[2] -eq '1') -and ($Matches[3] -eq '1')) $line[0].Trim()
  Check 'dispatch: line counts the variable argument as indirect' ($line[0] -match 'indirect=1\b') $line[0].Trim()
}

# ---- resolve-only rebuilds the same set (wipe + rewrite, no duplicates) ----
& $exePath index (Split-Path $m.Db) --db $m.Db --resolve-only 2>&1 | Out-Null
Check 'resolve-only exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
$got2 = EdgeSet $m.Db
Check 'resolve-only rebuilds the identical set' ((($got2 -join '|') -ceq ($want -join '|'))) ("got=[" + ($got2 -join '; ') + "]")

# ---- positive control: no `override` on TPlanA -> its edge vanishes ------
$pc = IndexCopy 'nooverride' {
  param($dir)
  $p = Join-Path $dir 'DF.Plans.pas'
  $t = [IO.File]::ReadAllText($p)
  $t2 = $t.Replace("  TPlanA = class(TPlanBase)`r`n  public`r`n    procedure EditForm; override;", "  TPlanA = class(TPlanBase)`r`n  public`r`n    procedure EditForm;")
  if ($t2 -eq $t) { throw 'positive-control mutation did not apply' }
  [IO.File]::WriteAllText($p, $t2, [Text.Encoding]::ASCII)
}
$gotPc = EdgeSet $pc.Db
Check 'PC: TPlanA edge is gone' (@($gotPc | Where-Object { $_ -match 'TPlanA' }).Count -eq 0) ("got=[" + ($gotPc -join '; ') + "]")
Check 'PC: TPlanB edge stays' (@($gotPc | Where-Object { $_ -match 'override .*TPlanB\.EditForm' }).Count -eq 1)

if ($script:fail) { Write-Host 'run_dispatch_edges: FAIL'; exit 1 }
Write-Host 'run_dispatch_edges: PASS'
exit 0
} catch {
  Write-Host "FATAL: $_"
  exit 2
}
