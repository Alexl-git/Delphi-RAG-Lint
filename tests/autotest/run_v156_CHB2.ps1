# Acceptance runner for lane CHB-2 (1.56): `ask control-flow` (G-44) and `ask sent-not-handled` (G-71).
#
# Usage: run_v156_CHB2.ps1 -Exe <drag-lint.exe> [-ExpectRed] [-Scratch <dir>]
#   -ExpectRed : the engine is the BASE engine; both questions must be refused as "unknown question".
#
# GREEN assertions (fixtures tests\fixtures\chb2\{flow,proj,far}, indexed into DBs under -Scratch):
#   control-flow ChbFlow.Work (if / exit, for loop, call): Nodes / Edges pinned ($Exp* below).
#   sent-not-handled project : 2 commands sent, 1 handled -> NeverHandled=1, and it is cmdTwo.
#   no --counterpart-db      : refused (exit non-zero), not an empty answer.
#   POSITIVE CONTROLS (a check that cannot fail proves nothing):
#     PC-1 a variant routine with one more `if` must raise Nodes and Edges (the counts follow the source);
#     PC-2 --cap 4 must cut the graph: HiddenNodes = TotalNodes - 4 and the dot label says "stops at 4 of";
#     PC-3 an unknown routine is refused;
#     PC-4 a counterpart that also handles cmdTwo must give NeverHandled=0 (the count follows the far index);
#     PC-5 the red node of the dot is cmdTwo, not cmdOne (the finding names the right command).
param(
  [Parameter(Mandatory)][string]$Exe,
  [switch]$ExpectRed,
  [string]$Scratch = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Scratch) { $Scratch = Join-Path $env:TEMP "chb2-run-$PID" }
[IO.Directory]::CreateDirectory($Scratch) | Out-Null
$fail = 0; $pass = 0
# pinned graph of ChbFlow.Work (entry + exit + the blocks the builder cuts) and of the one-more-if variant
$ExpNodes = 8; $ExpEdges = 9; $ExpVariantNodes = 10; $ExpVariantEdges = 12
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if ($ok) { $script:pass++; Write-Host "PASS  $name" } else { $script:fail++; Write-Host "FAIL  $name  $detail" -ForegroundColor Red }
}
function Run-Engine([string[]]$a) {
  # ProcessStartInfo with redirected streams: the engine's stderr ('loaded defaults' ...) must not become a
  # NativeCommandError under $ErrorActionPreference = 'Stop' (the way run_v156_FB1.ps1's Lane-Run does it).
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($x in $a) { $psi.ArgumentList.Add($x) }
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync(); $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Text = ($o.Result + $e.Result) }
}
function Index-Fixture([string]$dir, [string]$db) {
  if (Test-Path $db) { [IO.File]::Delete($db) }
  $r = Run-Engine @('index', $dir, '--db', $db)
  if ($r.Code -ne 0) { throw "index failed: $($r.Text)" }
}
function Ask([string]$q, [string]$target, [string]$db, [string]$out, [string[]]$more = @()) {
  Run-Engine (@('ask', $q, '--target', $target, '--db', $db, '--plain', '--out-root', $out) + $more)
}
function Emitter-Of([string]$out) {
  $m = Get-ChildItem $out -Recurse -Filter meta.json -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if (-not $m) { return $null }
  (Get-Content $m.FullName -Raw | ConvertFrom-Json | ForEach-Object { $_ }).emitter
}
function Json-Of($e) { if ($e) { $e | ConvertTo-Json -Compress } else { 'no meta' } }
function Dot-Text([string]$out) {
  $d = Get-ChildItem $out -Recurse -Filter *.dot -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
  if ($d) { Get-Content $d.FullName -Raw } else { '' }
}

$fxRoot = Join-Path $repo 'tests\fixtures\chb2'
$dbFlow = Join-Path $Scratch 'flow.sqlite'
$dbProj = Join-Path $Scratch 'proj.sqlite'
$dbFar = Join-Path $Scratch 'far.sqlite'
Index-Fixture (Join-Path $fxRoot 'flow') $dbFlow
Index-Fixture (Join-Path $fxRoot 'proj') $dbProj
Index-Fixture (Join-Path $fxRoot 'far') $dbFar

if ($ExpectRed) {
  foreach ($q in @(@('control-flow', 'ChbFlow.Work', $dbFlow), @('sent-not-handled', 'project', $dbProj))) {
    $r = Ask $q[0] $q[1] $q[2] (Join-Path $Scratch 'red') @('--counterpart-db', $dbFar)
    Check "RED $($q[0]) refused as unknown question" (($r.Code -ne 0) -and ($r.Text -match 'unknown question')) "exit=$($r.Code) $($r.Text)"
  }
  Write-Host "RED: $pass pass, $fail fail"; exit $(if ($fail) { 1 } else { 0 })
}

# ---- control-flow ----
$o1 = Join-Path $Scratch 'cf1'
$r = Ask 'control-flow' 'ChbFlow.Work' $dbFlow $o1
Check 'control-flow exits 0' ($r.Code -eq 0) $r.Text
$e = Emitter-Of $o1
Check "control-flow: $ExpNodes nodes" ($e -and $e.Nodes -eq $ExpNodes -and $e.TotalNodes -eq $ExpNodes) (Json-Of $e)
Check "control-flow: $ExpEdges edges" ($e -and $e.Edges -eq $ExpEdges -and $e.TotalEdges -eq $ExpEdges) (Json-Of $e)
Check 'control-flow: nothing hidden, no cap label' ($e -and $e.HiddenNodes -eq 0 -and -not ((Dot-Text $o1) -match 'stops at')) (Json-Of $e)

# PC-1: one more `if` raises both counts
$fxv = Join-Path $Scratch 'flowv'; [IO.Directory]::CreateDirectory($fxv) | Out-Null
$src = [IO.File]::ReadAllText((Join-Path $fxRoot 'flow\ChbFlow.pas'))
$src = $src.Replace("  Writeln(pCount);", "  if pCount > 5 then`r`n    Inc(pCount);`r`n  Writeln(pCount);")
[IO.File]::WriteAllText((Join-Path $fxv 'ChbFlow.pas'), $src, [Text.Encoding]::ASCII)
$dbv = Join-Path $Scratch 'flowv.sqlite'
Index-Fixture $fxv $dbv
$o2 = Join-Path $Scratch 'cf2'
$r = Ask 'control-flow' 'ChbFlow.Work' $dbv $o2
$e = Emitter-Of $o2
Check "PC-1 variant with one more if: $ExpVariantNodes nodes, $ExpVariantEdges edges" ($e -and $e.Nodes -eq $ExpVariantNodes -and $e.Edges -eq $ExpVariantEdges) (Json-Of $e)

# PC-2: the cap says where it stops
$o3 = Join-Path $Scratch 'cf3'
$r = Ask 'control-flow' 'ChbFlow.Work' $dbFlow $o3 @('--cap', '4')
$e = Emitter-Of $o3
Check 'PC-2 --cap 4: 4 nodes drawn, the rest counted as hidden' ($e -and $e.Nodes -eq 4 -and $e.HiddenNodes -eq ($ExpNodes - 4)) (Json-Of $e)
Check 'PC-2 --cap 4: the dot label names the cut' ((Dot-Text $o3) -match "stops at 4 of $ExpNodes blocks \(cap 4\)") (Dot-Text $o3)

# PC-3
$r = Ask 'control-flow' 'ChbFlow.NoSuchRoutine' $dbFlow (Join-Path $Scratch 'cf4')
Check 'PC-3 unknown routine is refused' ($r.Code -ne 0) $r.Text

# ---- sent-not-handled ----
$o5 = Join-Path $Scratch 'snh1'
$r = Ask 'sent-not-handled' 'project' $dbProj $o5 @('--counterpart-db', $dbFar)
Check 'sent-not-handled exits 0' ($r.Code -eq 0) $r.Text
$e = Emitter-Of $o5
Check '2 commands sent, 1 handled -> 1 never handled' ($e -and $e.Sent -eq 2 -and $e.Handled -eq 1 -and $e.NeverHandled -eq 1) (Json-Of $e)
$dot = Dot-Text $o5
Check 'PC-5 the red node is cmdTwo, the green one cmdOne' (($dot -match 'label="cmdTwo[^"]*", fillcolor="#FDE8E8"') -and ($dot -match 'label="cmdOne[^"]*", fillcolor="#E2F1EF"')) $dot

$r = Ask 'sent-not-handled' 'project' $dbProj (Join-Path $Scratch 'snh2')
Check 'no counterpart db: refused, says what is missing' (($r.Code -ne 0) -and ($r.Text -match 'counterpart-db')) "exit=$($r.Code) $($r.Text)"

# PC-4: a far side that handles cmdTwo too
$fxf = Join-Path $Scratch 'farv'; [IO.Directory]::CreateDirectory($fxf) | Out-Null
Copy-Item (Join-Path $fxRoot 'far\ChbCmds.pas') $fxf
$h = [IO.File]::ReadAllText((Join-Path $fxRoot 'far\ChbHandler.pas')).Replace("    cmdOne: Writeln('one');", "    cmdOne: Writeln('one');`r`n    cmdTwo: Writeln('two');")
[IO.File]::WriteAllText((Join-Path $fxf 'ChbHandler.pas'), $h, [Text.Encoding]::ASCII)
$dbfv = Join-Path $Scratch 'farv.sqlite'
Index-Fixture $fxf $dbfv
$o6 = Join-Path $Scratch 'snh3'
$r = Ask 'sent-not-handled' 'project' $dbProj $o6 @('--counterpart-db', $dbfv)
$e = Emitter-Of $o6
Check 'PC-4 far side handles both: NeverHandled=0' ($e -and $e.Sent -eq 2 -and $e.NeverHandled -eq 0) (Json-Of $e)

Write-Host "CHB-2: $pass pass, $fail fail"
exit $(if ($fail) { 1 } else { 0 })
