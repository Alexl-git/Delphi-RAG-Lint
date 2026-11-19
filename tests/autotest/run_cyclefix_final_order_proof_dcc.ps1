<#
  run_cyclefix_final_order_proof_dcc.ps1 -- lane FINPROOF (wave v151, OQ19): `cycles --plan` / `--fix` prove the
  FINALIZATION order of a routine-call inversion from the program's uses order instead of refusing
  `finalization-order` whenever the declaring unit's state can be torn down.

  Fixture tests\fixtures\cyclefix\finp3 (program FinP3): FP3A impl-uses FP3C and FP3B, FP3C impl-uses FP3B, FP3B
  impl-uses FP3A; FP3A's finalization runs FP3AStop, which calls FP3BReport. FP3B's state is a string its own
  finalization clears. Only the edge FP3A -> FP3B is a routine-call inversion (the other edges take a routine's
  address). After the cut FP3A still reaches FP3B through FP3C.

  M   THE MODEL (RED-0, before any proof code). Six programs are built and RUN: the .dpr listing FP3A, FP3B or FP3C
      first, each with the cycle as written and with the FP3A -> FP3B entry removed by hand (the pointer in a leaf,
      assigned as the first statement of FP3B's initialization, as R1 writes it). Each run must print its
      initialization order equal to the documented model (Lint.InitSections.pas header), its finalization order
      equal to the exact reverse, and FP3B's state as still "alive" at FP3A's finalization exactly when the model
      puts FP3B before FP3A.
  A   FP3A first: the plan is mechanical and carries the "finalization order:" line naming both positions; JSON
      `fix.edges[].final_order` holds it; `--fix --apply` passes the compile gate; the program prints byte-identical
      output before and after (FP3B still "alive" when FP3A's finalization calls it).
  B   FP3B first / FP3C first: `finalization-order` refused; the text says FP3B MAY be finalized first and names the
      .dpr, both positions and the entry to reorder.
  C   A two-unit cycle: refused with the old certain wording ("after the cut `FP3B` is finalized first").
  D   A path uses entry inside `{$IFDEF}`: refused, naming file:line. No program in the index: refused "no program".
  E   Part B predicted after Part A: refused, "re-checked against the program order once Part A is applied".
  G   After the FP3A-first apply the .dpr order is swapped by hand and the program rebuilt and run: the output
      changes (FP3B's state is gone when FP3A's finalization calls it) -- the hazard the proof line warns about.

  POSITIVE CONTROLS: A and B run on the same fixture and the same edge, only the .dpr order differs, with opposite
  verdicts; C proves the proof can say no on its own shape; in M the FP3B-first runs print an EMPTY name (the run
  can tell a finalized FP3B from a live one).
  -Phase model runs M only. Needs RAD Studio; SKIPs (exit 0) without it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-finalproof-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [ValidateSet('all', 'model', 'engine')][string]$Phase = 'all',
  [switch]$KeepWorkDir
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe") { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" } else { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }) }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix\finp3'
$Ascii = [Text.Encoding]::ASCII
$script:N = 0
$Units = @('FP3A', 'FP3B', 'FP3C')

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
# The .dpr uses list in the given unit order.
function Set-DprOrder([string]$Root, [string[]]$Order) {
  $dpr = Join-Path $Root 'FinP3.dpr'
  $t = [IO.File]::ReadAllText($dpr, $Ascii)
  $list = ($Order | ForEach-Object { "  $_ in '$_.pas'" }) -join ",`r`n"
  $t = [regex]::Replace($t, '(?s)uses\r\n.*?;\r\n', "uses`r`n$list;`r`n")
  [IO.File]::WriteAllText($dpr, $t, $Ascii)
}
function New-Proj([string[]]$Order, [scriptblock]$Patch = $null, [switch]$NoIndex) {
  $script:N++
  $root = Join-Path $WorkDir ("p{0}" -f $script:N)
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem $Fx -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj', '.inc' } | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Order) { Set-DprOrder $root $Order }
  if ($Patch) { & $Patch $root }
  $db = "$root.sqlite"
  if (-not $NoIndex) {
    Push-Location $WorkDir
    try { $null | & { $ErrorActionPreference = 'Continue'; & $Exe index --project (Join-Path $root 'FinP3.dproj') --db $db --library-db none *> "$db.log" } } finally { Pop-Location }
  }
  return @{ Root = $root; Dproj = (Join-Path $root 'FinP3.dproj'); Db = $db; Name = 'FinP3' }
}
function Invoke-Build($P) {
  $bat = "$($P.Root).build.bat"; $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $P.Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $P.Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program($P) {
  $exeP = Join-Path $P.Root "Win64\Debug\$($P.Name).exe"
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [IO.File]::ReadAllText($o, $Ascii)
}
# The uses entries of one source file, interface first, then implementation, each in source order.
function Get-UsesOf([string]$Path) {
  $t = [regex]::Replace([IO.File]::ReadAllText($Path, $Ascii), '(?m)//.*$', '')
  $parts = [regex]::Split($t, '(?im)^\s*implementation\s*$')
  $r = @()
  foreach ($part in $parts) {
    $m = [regex]::Match($part, '(?is)\buses\s+([^;]+);')
    if ($m.Success) { $r += @($m.Groups[1].Value -split ',' | ForEach-Object { (($_ -split '\s+in\s+')[0]).Trim() } | Where-Object { $_ }) }
  }
  return $r
}
# The documented model: depth-first post-order from the .dpr uses list; a unit being visited is skipped.
function Get-ModelOrder([string]$Root) {
  $order = [Collections.Generic.List[string]]::new()
  $seen = @{}
  $visit = $null
  $visit = {
    param($u)
    $f = Join-Path $Root "$u.pas"
    if ($seen.ContainsKey($u) -or -not (Test-Path $f)) { return }
    $seen[$u] = $true
    foreach ($d in (Get-UsesOf $f)) { & $visit $d }
    $order.Add($u)
  }
  foreach ($r in (Get-UsesOf (Join-Path $Root 'FinP3.dpr'))) { & $visit $r }
  return @($order)
}
# The by-hand cut, as R1 writes it: a leaf holds the pointer, FP3B assigns it first in its initialization,
# FP3A calls through it.
function Set-HandCut([string]$Root) {
  [IO.File]::WriteAllText((Join-Path $Root 'FP3Hook.pas'), (("unit FP3Hook;`n`ninterface`n`nvar`n  FP3BReportPtr: procedure(const pText: string);`n`n" +
    "implementation`n`nend.`n") -replace "`n", "`r`n"), $Ascii)
  Edit-Text (Join-Path $Root 'FP3A.pas') "uses`n  FP3C, FP3B;" "uses`n  FP3C, FP3Hook;"
  Edit-Text (Join-Path $Root 'FP3A.pas') "  FP3BReport('a stopped');" "  FP3BReportPtr('a stopped');"
  Edit-Text (Join-Path $Root 'FP3B.pas') "uses`n  FP3A;" "uses`n  FP3A, FP3Hook;"
  Edit-Text (Join-Path $Root 'FP3B.pas') "initialization`n  GName:= 'alive';" "initialization`n  FP3BReportPtr:= FP3BReport;`n  GName:= 'alive';"
}
# Variant F (metaclass hand-over): FP3A's finalization passes the class TFP3Job of FP3B as a value to FP3Forget, a
# routine of a fourth unit outside the cycle; TFP3Job's own body takes the address of an FP3A routine, so it cannot move.
function Set-MetaclassVariant([string]$Root) {
  [IO.File]::WriteAllText((Join-Path $Root 'FP3Reg.pas'), ("unit FP3Reg;`n`ninterface`n`nprocedure FP3Forget(pClass: TClass);`n`nimplementation`n`n" +
    "procedure FP3Forget(pClass: TClass);`nbegin`n  Writeln('[reg] forget ', pClass.ClassName);`nend;`n`nend.`n" -replace "`n", "`r`n"), $Ascii)
  Edit-Text (Join-Path $Root 'FP3A.pas') "uses`n  FP3C, FP3B;" "uses`n  FP3Reg, FP3C, FP3B;"
  Edit-Text (Join-Path $Root 'FP3A.pas') "  FP3BReport('a stopped');" "  FP3Forget(TFP3Job);"
  Edit-Text (Join-Path $Root 'FP3B.pas') "interface`n`n///" ("interface`n`ntype`n  /// <summary>A class FP3A passes as a value.</summary>`n  TFP3Job = class`n" +
    "  public`n    /// <summary>Takes the address of FP3AValue.</summary>`n    procedure Kick;`n  end;`n`n///")
  Edit-Text (Join-Path $Root 'FP3B.pas') "procedure FP3BTick;`nbegin" "procedure TFP3Job.Kick;`nbegin`n  GValue:= @FP3AValue;`nend;`n`nprocedure FP3BTick;`nbegin"
  Edit-Text (Join-Path $Root 'FinP3.dpr') "  FP3C in 'FP3C.pas';" "  FP3C in 'FP3C.pas',`n  FP3Reg in 'FP3Reg.pas';"
  Edit-Text (Join-Path $Root 'FinP3.dproj') '<DCCReference Include="FP3C.pas"/>' "<DCCReference Include=`"FP3C.pas`"/>`n        <DCCReference Include=`"FP3Reg.pas`"/>"
}
# Variant H (constructor inversion): FP3A's finalization runs FP3AStop, which constructs TFP3Job of FP3B and calls a
# method that prints FP3B's state; the class's bodies use FP3B's globals, so it stays and is handed over by its constructor.
function Set-CtorVariant([string]$Root) {
  Edit-Text (Join-Path $Root 'FP3A.pas') "procedure FP3AStop;`nbegin`n  FP3BReport('a stopped');`nend;" ("procedure FP3AStop;`nvar`n  J: TFP3Job;`nbegin`n" +
    "  J:= TFP3Job.Create;`n  J.Hello('a stopped');`n  J.Free;`nend;")
  Edit-Text (Join-Path $Root 'FP3B.pas') "interface`n`n///" ("interface`n`ntype`n  /// <summary>A class FP3A constructs.</summary>`n  TFP3Job = class`n  public`n" +
    "    /// <summary>Creates the job.</summary>`n    constructor Create;`n    /// <summary>Writes one line with the unit's state.</summary>`n" +
    "    /// <param name=`"pText`">The text.</param>`n    procedure Hello(const pText: string);`n" +
    "    /// <summary>Takes the address of FP3AValue.</summary>`n    procedure Kick;`n  end;`n`n///")
  Edit-Text (Join-Path $Root 'FP3B.pas') "procedure FP3BTick;`nbegin" ("constructor TFP3Job.Create;`nbegin`n  inherited Create;`nend;`n`n" +
    "procedure TFP3Job.Hello(const pText: string);`nbegin`n  Writeln('[b] ', pText, ' name=', GName);`nend;`n`n" +
    "procedure TFP3Job.Kick;`nbegin`n  GValue:= @FP3AValue;`nend;`n`nprocedure FP3BTick;`nbegin")
}
function Get-Lines([string]$Out, [string]$Word) { return @([regex]::Matches($Out, "(?m)^$Word (\w+)") | ForEach-Object { $_.Groups[1].Value }) }
function Get-Plan($P, [switch]$NoProject) {
  $a = @('cycles', '--plan', '--db', $P.Db, '--library-db', 'none')
  if (-not $NoProject) { $a += @('--project', $P.Dproj) }
  Push-Location $WorkDir
  try { return ($null | & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>$null } | Out-String) } finally { Pop-Location }
}
function Get-CausesJson($P) {
  Push-Location $WorkDir
  try { $o = ($null | & { $ErrorActionPreference = 'Continue'; & $Exe cycles --causes --format json --project $P.Dproj --db $P.Db --library-db none 2>$null } | Out-String) } finally { Pop-Location }
  try { return ($o | ConvertFrom-Json) } catch { return $null }
}
function Run-Fix($P, [string[]]$Extra) {
  $a = @('cycles', '--fix', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--library-db', 'none', '--format', 'json') + $Extra
  Push-Location $WorkDir
  try { $out = ($null | & { $ErrorActionPreference = 'Continue'; & $Exe @a 2>$null } | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @(); $r = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += $x.kind; $r += "$($x.kind): $($x.reason)" } } }
  foreach ($x in @($j.refusals)) { if ($x) { $k += $x.kind; $r += "$($x.kind): $($x.reason)" } }
  return @{ Exit = $code; Out = $out; Kinds = $k; Reasons = ($r -join ' || ') }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  if ($Phase -in 'all', 'model') {
    Write-Host '== M the order model, compiled and run (six programs)' -ForegroundColor Cyan
    $script:ModelTable = @()
    foreach ($first in $Units) {
      $order = @($first) + @($Units | Where-Object { $_ -ne $first })
      foreach ($cut in @($false, $true)) {
        $P = New-Proj $order { param($r) if ($cut) { Set-HandCut $r; Set-DprOrder $r ($order + 'FP3Hook') } } -NoIndex
        $b = Invoke-Build $P
        Check ("m.build {0} first, cut={1}" -f $first, $cut) $b.Ok $b.Errors
        $out = Invoke-Program $P
        $init = (Get-Lines $out 'init') -join ','
        $fin = Get-Lines $out 'fin'
        [array]::Reverse($fin)
        $finRev = $fin -join ','
        $model = ((Get-ModelOrder $P.Root) | Where-Object { $_ -ne 'FP3Hook' }) -join ','
        $state = if ($out -match '\[b\] a stopped name=alive') { 'alive' } elseif ($out -match '(?m)\[b\] a stopped name=\r?$') { 'gone' } else { '?' }
        $script:ModelTable += ("| {0} first | {1} | {2} | {3} | {4} | {5} |" -f $first, $(if ($cut) { 'cut' } else { 'cycle' }), $init, ($finRev -replace ',', '<'), $model, $state)
        Check ("m.init {0} first, cut={1}: run [{2}] = model [{3}]" -f $first, $cut, $init, $model) (($init -ne '') -and ($init -eq $model)) $out
        Check ("m.fin {0} first, cut={1}: finalization is the exact reverse [{2}]" -f $first, $cut, $finRev) ($finRev -eq $init) $out
        $bBefore = [array]::IndexOf(@($model -split ','), 'FP3B') -lt [array]::IndexOf(@($model -split ','), 'FP3A')
        Check ("m.state {0} first, cut={1}: FP3B {2} at FP3A's finalization iff FP3B initializes first ({3})" -f $first, $cut, $state, $bBefore) (($state -eq 'alive') -eq $bBefore -and $state -ne '?') $out
      }
    }
    Write-Host '  | .dpr | graph | init order | fin order (reversed) | model | FP3B at FP3A fin |' -ForegroundColor DarkGray
    $script:ModelTable | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
  }
  if ($Phase -in 'all', 'engine') {
    function Get-Pos([string]$Root, [string]$Unit) { return [array]::IndexOf(@(Get-ModelOrder $Root), $Unit) + 1 }
    $RefusedRx = '(?m)^- `fp3a -> fp3b`:.*?`FP3BReport` \(procedure\): refused: finalization-order -- (.*)$'
    $Order3 = 'finalization runs in the reverse order of initialization'

    Write-Host '== A FP3A first: proved, planned, applied, compiled, same output' -ForegroundColor Cyan
    $P = New-Proj @('FP3A', 'FP3B', 'FP3C')
    $plan = Get-Plan $P
    $pa = Get-Pos $P.Root 'FP3A'; $pb = Get-Pos $P.Root 'FP3B'
    Check 'a.1 the plan cuts fp3a -> fp3b by routine-call inversion' ($plan -match '(?m)^- `fp3a -> fp3b`: recipe: routine-call inversion -- \*\*cut by this plan\*\*') $plan
    $want = "finalization order: ``FP3B`` is finalized after ``FP3A``: $Order3, and ``FP3B`` initializes before ``FP3A`` in ``FinP3.dpr`` (position $pb before $pa; ``FP3A`` reaches ``FP3B`` through ``FP3C``)"
    Check "a.2 the step carries the finalization proof line with the run's positions ($pb before $pa)" ($plan.Contains("- $want")) $plan
    Check 'a.3 the plan is mechanical (Fix it block, no finalization-order refusal)' (($plan -match 'Fix it \(mechanical') -and ($plan -notmatch 'refused: finalization-order')) $plan
    $j = Get-CausesJson $P
    $edge = @($j | ForEach-Object { $_.fix.edges } | Where-Object { $_.from -eq 'fp3a' -and $_.to -eq 'fp3b' })[0]
    Check 'a.4 JSON: the chosen edge carries final_order with the proof line, and no init_order' (($null -ne $edge) -and $edge.chosen -and ("$($edge.final_order)".StartsWith($want)) -and (-not $edge.init_order)) ($j | ConvertTo-Json -Depth 8 -Compress)
    $base = New-Proj @('FP3A', 'FP3B', 'FP3C') -NoIndex
    $b0 = Invoke-Build $base
    Check 'a.5 the untouched copy builds' $b0.Ok $b0.Errors
    $out0 = Invoke-Program $base
    $a = Run-Fix $P @('--apply')
    Check 'a.6 --fix --apply: exit 0, no refusal (compile gate passed)' (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons)"
    $b1 = Invoke-Build $P
    Check 'a.7 the applied copy builds (independent msbuild)' $b1.Ok $b1.Errors
    $out1 = Invoke-Program $P
    Check 'a.8 stdout byte-identical to the untouched build (FP3B alive at FP3A''s finalization)' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0) -and ($out0 -match '\[b\] a stopped name=alive')) "before=[$out0] after=[$out1]"

    Write-Host '== G the applied program with the .dpr order reversed: the hazard is real' -ForegroundColor Cyan
    $dpr = Join-Path $P.Root 'FinP3.dpr'
    $dt = [IO.File]::ReadAllText($dpr, $Ascii)
    $leaf = @(Get-ChildItem $P.Root -Filter 'FP3B.*.pas' | ForEach-Object { $_.BaseName })[0]
    [IO.File]::WriteAllText($dpr, [regex]::Replace($dt, "(?s)uses\r\n.*?;\r\n", "uses`r`n  FP3B in 'FP3B.pas',`r`n  FP3A in 'FP3A.pas',`r`n  FP3C in 'FP3C.pas',`r`n  $leaf in '$leaf.pas';`r`n"), $Ascii)
    $null = Invoke-Build $P
    $out2 = Invoke-Program $P
    Check 'g.1 the swapped program runs FP3A''s finalization after FP3B''s: the name is gone' (($out2 -cne $out0) -and ($out2 -match '(?m)\[b\] a stopped name=\r?$')) "leaf=$leaf out=[$out2]"

    Write-Host '== B the other two orders: FP3A already initializes first, the cut leaves the order unchanged (1.52 B9a)' -ForegroundColor Cyan
    foreach ($first in 'FP3B', 'FP3C') {
      $order = @($first) + @($Units | Where-Object { $_ -ne $first })
      $P = New-Proj $order
      $plan = Get-Plan $P
      $pa = Get-Pos $P.Root 'FP3A'; $pb = Get-Pos $P.Root 'FP3B'
      $want = "finalization order: unchanged by the cut: ``FP3B`` is finalized before ``FP3A`` with the cycle as written and after the cut: $Order3, and in ``FinP3.dpr`` ``FP3A`` (position $pa) initializes before ``FP3B`` (position $pb)"
      Check "b.$first first: planned (lane FINCUT), the step says the order is unchanged and names .dpr + positions $pa / $pb" (($plan -match '(?m)^- `fp3a -> fp3b`: recipe: routine-call inversion -- \*\*cut by this plan\*\*') -and $plan.Contains($want) -and -not [regex]::IsMatch($plan, $RefusedRx)) $plan
    }

    Write-Host '== C a two-unit cycle: never provable, the old certain wording' -ForegroundColor Cyan
    $P = New-Proj @('FP3A', 'FP3B', 'FP3C') {
      param($r)
      Edit-Text (Join-Path $r 'FP3A.pas') "uses`n  FP3C, FP3B;" "uses`n  FP3B;"
      Edit-Text (Join-Path $r 'FP3A.pas') "  GPing:= @FP3CPing;`n" ""
      Edit-Text (Join-Path $r 'FP3A.pas') "var`n  GPing: procedure;`n`n" ""
    }
    $plan = Get-Plan $P
    $m = [regex]::Match($plan, $RefusedRx)
    Check 'c.1 fp3a -> fp3b refused: "after the cut `FP3B` is finalized first"' ($m.Success -and $m.Groups[1].Value.Contains('and after the cut `FP3B` is finalized first: its finalization section (line')) $plan

    Write-Host '== D a conditional path entry; no program' -ForegroundColor Cyan
    $P = New-Proj @('FP3A', 'FP3B', 'FP3C') { param($r) Edit-Text (Join-Path $r 'FP3C.pas') "uses`n  FP3B;" "uses`n  {`$IFDEF MSWINDOWS}`n  FP3B`n  {`$ENDIF}`n  ;" }
    $ifLine = [array]::IndexOf(@([IO.File]::ReadAllLines((Join-Path $P.Root 'FP3C.pas'))), '  {$IFDEF MSWINDOWS}') + 1
    $plan = Get-Plan $P
    $m = [regex]::Match($plan, $RefusedRx)
    Check "d.1 refused: the order depends on a conditional uses entry (FP3C.pas:$ifLine)" ($m.Success -and $m.Groups[1].Value.Contains("conditional uses entry (``FP3C.pas:$ifLine``)")) $plan
    $P = New-Proj $null { param($r) [IO.File]::Delete((Join-Path $r 'FinP3.dpr')); [IO.File]::Delete((Join-Path $r 'FinP3.dproj')) } -NoIndex
    Push-Location $WorkDir
    try { $null | & { $ErrorActionPreference = 'Continue'; & $Exe index $P.Root --db $P.Db --library-db none *> "$($P.Db).log" } } finally { Pop-Location }
    $plan = Get-Plan $P -NoProject
    $m = [regex]::Match($plan, $RefusedRx)
    Check 'd.2 no .dpr in the index: refused "no program"' ($m.Success -and $m.Groups[1].Value.Contains('no program in this index')) $plan

    Write-Host '== E Part B predicted after Part A: re-checked' -ForegroundColor Cyan
    $P = New-Proj @('FP3A', 'FP3B', 'FP3C') {
      param($r)
      Edit-Text (Join-Path $r 'FP3A.pas') "interface`n" "interface`n`nuses`n  FP3C, FP3B;`n"
      Edit-Text (Join-Path $r 'FP3A.pas') "implementation`n`nuses`n  FP3C, FP3B;`n" "implementation`n"
      Edit-Text (Join-Path $r 'FP3B.pas') "interface`n" "interface`n`nuses`n  FP3A;`n"
      Edit-Text (Join-Path $r 'FP3B.pas') "implementation`n`nuses`n  FP3A;`n" "implementation`n"
    }
    $plan = Get-Plan $P
    $m = [regex]::Match($plan, $RefusedRx)
    Check 'e.1 predicted Part B: finalization-order kept, "re-checked against the program order once Part A is applied"' ($m.Success -and $m.Groups[1].Value.TrimEnd().EndsWith('; re-checked against the program order once Part A is applied')) $plan

    # F / H: the same gate on the metaclass hand-over and the constructor inversion. FP3A first: planned with the
    # proof line, applied through the compile gate, same output. FP3B first: refused finalization-order (the base
    # engine planned both: the metaclass step had no finalization check, the constructor check read only lines
    # written in the section, not the routine FP3AStop the section names).
    $Variants = @(
      @{ Tag = 'f'; Name = 'metaclass hand-over'; Patch = { param($r) Set-MetaclassVariant $r }; Recipe = 'metaclass hand-over';
         Refused = '(?m)^- `fp3a -> fp3b`:.*`TFP3Job` \(class\): refused: finalization-order -- (.*)$'; Out = '\[reg\] forget TFP3Job' },
      @{ Tag = 'h'; Name = 'constructor inversion'; Patch = { param($r) Set-CtorVariant $r }; Recipe = 'move globals';
         Refused = '(?m)^- `fp3a -> fp3b`:.*refused: ctor-inversion-surface -- `FP3A\.pas:\d+`: `TFP3Job` is constructed here, and the constructor inversion does not cover it: (.*)$'; Out = '\[b\] a stopped name=alive' }
    )
    foreach ($v in $Variants) {
      Write-Host ("== {0} {1}" -f $v.Tag.ToUpper(), $v.Name) -ForegroundColor Cyan
      $P = New-Proj @('FP3A', 'FP3B', 'FP3C') $v.Patch
      $plan = Get-Plan $P
      $pa = Get-Pos $P.Root 'FP3A'; $pb = Get-Pos $P.Root 'FP3B'
      $want = "finalization order: ``FP3B`` is finalized after ``FP3A``: $Order3, and ``FP3B`` initializes before ``FP3A`` in ``FinP3.dpr`` (position $pb before $pa;"
      Check "$($v.Tag).1 FP3A first: $($v.Name) planned with the finalization proof line ($pb before $pa)" (($plan -match ('(?m)^- `fp3a -> fp3b`: recipe: ' + $v.Recipe + ' -- \*\*cut by this plan\*\*')) -and $plan.Contains($want)) $plan
      $base = New-Proj @('FP3A', 'FP3B', 'FP3C') $v.Patch -NoIndex
      $b0 = Invoke-Build $base
      $out0 = Invoke-Program $base
      $a = Run-Fix $P @('--apply')
      $b1 = Invoke-Build $P
      $out1 = Invoke-Program $P
      Check "$($v.Tag).2 applied through the compile gate, builds, stdout byte-identical" ($b0.Ok -and ($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0) -and $b1.Ok -and ($out1 -ceq $out0) -and ($out0 -match $v.Out)) "exit=$($a.Exit) $($a.Reasons) b0=$($b0.Errors) b1=$($b1.Errors) before=[$out0] after=[$out1]"
      $P = New-Proj @('FP3B', 'FP3A', 'FP3C') $v.Patch
      $plan = Get-Plan $P
      Check "$($v.Tag).3 FP3B first: FP3A already initializes first, planned with the unchanged-order line (1.52 B9a)" ((-not [regex]::IsMatch($plan, $v.Refused)) -and ($plan -match ('(?m)^- `fp3a -> fp3b`: recipe: ' + $v.Recipe + ' -- \*\*cut by this plan\*\*')) -and $plan.Contains('finalization order: unchanged by the cut: `FP3B` is finalized before `FP3A`')) $plan
    }
  }
} finally {
  if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("passed {0}, {1}" -f $script:Passed, $(if ($script:Failed) { 'FAILED' } else { 'all PASS' }))
if ($script:Failed) { exit 1 } else { exit 0 }
