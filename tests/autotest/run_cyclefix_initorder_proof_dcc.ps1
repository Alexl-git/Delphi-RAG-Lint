<#
  run_cyclefix_initorder_proof_dcc.ps1 -- lane CYC3 (wave 152c, fabcyc case 3): `cycles --plan` / `--fix` prove the
  init order of a routine-call inversion from the program's uses order instead of refusing `init-order` outright.

  Fixture tests\fixtures\cyclefix\initp3 (program InitP3): IP3A impl-uses IP3C and IP3B, IP3C impl-uses IP3B, IP3B
  impl-uses IP3A; IP3A's initialization calls IP3BWrite. Only the edge IP3A -> IP3B is a routine-call inversion (the
  other edges take a routine's address). After the cut IP3A still reaches IP3B through IP3C.

  M   THE MODEL (RED-0, before any proof code). Six programs are built and RUN: the .dpr listing IP3A, IP3B or IP3C
      first, each with the cycle as written and with the IP3A -> IP3B entry removed by hand (the pointer in a leaf,
      assigned as the first statement of IP3B's initialization, as R1 writes it). The printed initialization order
      must equal the documented model (Lint.InitSections.pas header: depth-first post-order from the .dpr, interface
      uses then implementation uses, a unit already being visited is skipped), computed here from the same sources.
      The cut programs also print whether the pointer was assigned when IP3A's initialization called it.
  A   IP3A first: the plan is mechanical and carries the "init order:" line naming both positions; `--fix --apply`
      passes the compile gate; the program prints byte-identical output before and after.
  B   IP3B first / IP3C first: `init-order` refused, the text names both positions and the .dpr.
  C   A two-unit cycle (LabInit's shape): refused, the text says "whatever the .dpr order".
  D   A path uses entry inside `{$IFDEF}`: refused, naming file:line. No program in the index: refused "no program".
  G   Safety net: after the IP3A-first apply, the .dpr order is swapped by hand and the project reindexed:
      `lint-all --rule init-order-hazard` reports the pointer read in IP3A's initialization (silent before the swap).

  POSITIVE CONTROLS: A and B run on the same fixture and the same edge, only the .dpr order differs, with opposite
  verdicts; C proves the proof can say no on its own shape. For M the cut program with the pointer assignment
  removed must print "pointer nil" in every order (the run can tell an assigned pointer from a nil one).
  -Phase model runs M only (no engine needed beyond the exe path check). Needs RAD Studio; SKIPs (exit 0) without it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe") { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" } else { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-initproof-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [ValidateSet('all', 'model', 'engine')][string]$Phase = 'all',
  [switch]$KeepWorkDir
)
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
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix\initp3'
$Ascii = [Text.Encoding]::ASCII
$script:N = 0
$Units = @('IP3A', 'IP3B', 'IP3C')

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
# The .dpr uses list in the given unit order (plus any extra units at the end).
function Set-DprOrder([string]$Root, [string[]]$Order) {
  $dpr = Join-Path $Root 'InitP3.dpr'
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
    try { $null | & $Exe index --project (Join-Path $root 'InitP3.dproj') --db $db --library-db none *> "$db.log" } finally { Pop-Location }
  }
  return @{ Root = $root; Dproj = (Join-Path $root 'InitP3.dproj'); Db = $db; Name = 'InitP3' }
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
  foreach ($r in (Get-UsesOf (Join-Path $Root 'InitP3.dpr'))) { & $visit $r }
  return @($order)
}
# The by-hand cut, as R1 writes it: a leaf holds the pointer, IP3B assigns it first in its initialization,
# IP3A calls through it. -NoAssign leaves the assignment out (the positive control).
function Set-HandCut([string]$Root, [switch]$NoAssign) {
  [IO.File]::WriteAllText((Join-Path $Root 'IP3Hook.pas'), (("unit IP3Hook;`n`ninterface`n`nvar`n  IP3BWritePtr: procedure(const pText: string);`n`n" +
    "implementation`n`nend.`n") -replace "`n", "`r`n"), $Ascii)
  Edit-Text (Join-Path $Root 'IP3A.pas') "uses`n  IP3C, IP3B;" "uses`n  IP3C, IP3Hook;"
  Edit-Text (Join-Path $Root 'IP3A.pas') "  IP3BWrite('a started');" "  if Assigned(IP3BWritePtr) then IP3BWritePtr('a started') else Writeln('[a] pointer nil');"
  Edit-Text (Join-Path $Root 'IP3B.pas') "uses`n  IP3A;" "uses`n  IP3A, IP3Hook;"
  if (-not $NoAssign) { Edit-Text (Join-Path $Root 'IP3B.pas') "initialization`n  Writeln('init IP3B');" "initialization`n  IP3BWritePtr:= IP3BWrite;`n  Writeln('init IP3B');" }
}
function Get-InitLines([string]$Out) { return @([regex]::Matches($Out, '(?m)^init (\w+)') | ForEach-Object { $_.Groups[1].Value }) }
function Get-Plan($P, [switch]$NoProject) {
  $a = @('cycles', '--plan', '--db', $P.Db, '--library-db', 'none')
  if (-not $NoProject) { $a += @('--project', $P.Dproj) }
  Push-Location $WorkDir
  try { return ($null | & $Exe @a 2>$null | Out-String) } finally { Pop-Location }
}
function Get-CausesJson($P) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe cycles --causes --format json --project $P.Dproj --db $P.Db --library-db none 2>$null | Out-String) } finally { Pop-Location }
  try { return ($o | ConvertFrom-Json) } catch { return $null }
}
function Run-Fix($P, [string[]]$Extra) {
  $a = @('cycles', '--fix', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--library-db', 'none', '--format', 'json') + $Extra
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @(); $r = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += $x.kind; $r += "$($x.kind): $($x.reason)" } } }
  foreach ($x in @($j.refusals)) { if ($x) { $k += $x.kind; $r += "$($x.kind): $($x.reason)" } }
  return @{ Exit = $code; Out = $out; Kinds = $k; Reasons = ($r -join ' || ') }
}
# Reindex, then the init-order-hazard findings (lint-all --json: a bare array of findings).
function Get-Hazard($P) {
  Push-Location $WorkDir
  try {
    $null | & $Exe index --project $P.Dproj --db $P.Db --library-db none *> "$($P.Db).hzlog"
    $o = ($null | & $Exe lint-all --db $P.Db --rule init-order-hazard --json 2>$null | Out-String)
  } finally { Pop-Location }
  $j = @(); try { $j = @($o | ConvertFrom-Json) } catch { }
  return @($j | Where-Object { $_ -and $_.rule -eq 'init-order-hazard' })
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  if ($Phase -in 'all', 'model') {
    Write-Host '== M the order model, compiled and run (six programs + the nil-pointer control)' -ForegroundColor Cyan
    $script:ModelTable = @()
    foreach ($first in $Units) {
      $order = @($first) + @($Units | Where-Object { $_ -ne $first })
      foreach ($cut in @($false, $true)) {
        $P = New-Proj $order { param($r) if ($cut) { Set-HandCut $r; Set-DprOrder $r ($order + 'IP3Hook') } } -NoIndex
        $b = Invoke-Build $P
        Check ("m.build {0} first, cut={1}" -f $first, $cut) $b.Ok $b.Errors
        $out = Invoke-Program $P
        $seen = (Get-InitLines $out) -join ','
        $model = ((Get-ModelOrder $P.Root) | Where-Object { $_ -ne 'IP3Hook' }) -join ','
        $ptr = if (-not $cut) { '-' } elseif ($out -match '\[b\] a started') { 'assigned' } elseif ($out -match 'pointer nil') { 'nil' } else { '?' }
        $script:ModelTable += ("| {0} first | {1} | {2} | {3} | {4} |" -f $first, $(if ($cut) { 'cut' } else { 'cycle' }), $seen, $model, $ptr)
        Check ("m.order {0} first, cut={1}: run [{2}] = model [{3}]" -f $first, $cut, $seen, $model) (($seen -ne '') -and ($seen -eq $model)) $out
        if ($cut) {
          $bBefore = [array]::IndexOf(@($model -split ','), 'IP3B') -lt [array]::IndexOf(@($model -split ','), 'IP3A')
          Check ("m.ptr {0} first: pointer {1} iff IP3B is before IP3A in the model ({2})" -f $first, $ptr, $bBefore) (($ptr -eq 'assigned') -eq $bBefore) $out
        }
      }
    }
    $P = New-Proj @('IP3A', 'IP3B', 'IP3C') { param($r) Set-HandCut $r -NoAssign; Set-DprOrder $r @('IP3A', 'IP3B', 'IP3C', 'IP3Hook') } -NoIndex
    $null = Invoke-Build $P
    Check 'm.pc without the assignment the run prints "pointer nil" (the run tells nil from assigned)' ((Invoke-Program $P) -match 'pointer nil')
    Write-Host '  | .dpr | graph | run order | model order | pointer |' -ForegroundColor DarkGray
    $script:ModelTable | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
  }
  if ($Phase -in 'all', 'engine') {
    # 1-based model positions of the cycle as written, per .dpr order (the M table proves the model = the run)
    function Get-Pos([string]$Root, [string]$Unit) { return [array]::IndexOf(@(Get-ModelOrder $Root), $Unit) + 1 }
    $RefusedRx = '(?m)^- `ip3a -> ip3b`:.*?`IP3BWrite` \(procedure\): refused: init-order -- (.*)$'

    Write-Host '== A IP3A first: proved, planned, applied, compiled, same output' -ForegroundColor Cyan
    $P = New-Proj @('IP3A', 'IP3B', 'IP3C')
    $plan = Get-Plan $P
    $pa = Get-Pos $P.Root 'IP3A'; $pb = Get-Pos $P.Root 'IP3B'
    Check 'a.1 the plan cuts ip3a -> ip3b by routine-call inversion' ($plan -match '(?m)^- `ip3a -> ip3b`: recipe: routine-call inversion -- \*\*cut by this plan\*\*') $plan
    $want = "init order: ``IP3B`` initializes before ``IP3A`` in ``InitP3.dpr`` (position $pb before $pa; ``IP3A`` reaches ``IP3B`` through ``IP3C``)"
    Check "a.2 the step carries the proof line with the run's positions ($pb before $pa)" ($plan.Contains("- $want")) $plan
    Check 'a.3 the plan is mechanical (Fix it block, no init-order refusal)' (($plan -match 'Fix it \(mechanical') -and ($plan -notmatch 'refused: init-order')) $plan
    $j = Get-CausesJson $P
    $edge = @($j | ForEach-Object { $_.fix.edges } | Where-Object { $_.from -eq 'ip3a' -and $_.to -eq 'ip3b' })[0]
    Check 'a.4 JSON: the chosen edge carries init_order with the proof line' (($null -ne $edge) -and $edge.chosen -and ("$($edge.init_order)".StartsWith($want))) ($j | ConvertTo-Json -Depth 8 -Compress)
    $base = New-Proj @('IP3A', 'IP3B', 'IP3C') -NoIndex
    $b0 = Invoke-Build $base
    Check 'a.5 the untouched copy builds' $b0.Ok $b0.Errors
    $out0 = Invoke-Program $base
    $a = Run-Fix $P @('--apply')
    Check 'a.6 --fix --apply: exit 0, no refusal (compile gate passed)' (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons)"
    $b1 = Invoke-Build $P
    Check 'a.7 the applied copy builds (independent msbuild)' $b1.Ok $b1.Errors
    $out1 = Invoke-Program $P
    Check 'a.8 stdout byte-identical to the untouched build (the pointer was assigned in time)' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0) -and ($out0 -match '\[b\] a started')) "before=[$out0] after=[$out1]"

    Write-Host '== G safety net: the applied program with the .dpr order reversed' -ForegroundColor Cyan
    $h0 = Get-Hazard $P
    Check 'g.1 init-order-hazard is silent on the applied program as ordered (B first)' ($h0.Count -eq 0) ($h0 | ConvertTo-Json -Compress)
    $dpr = Join-Path $P.Root 'InitP3.dpr'
    $dt = [IO.File]::ReadAllText($dpr, $Ascii)
    [IO.File]::WriteAllText($dpr, [regex]::Replace($dt, "(?s)uses\r\n.*?;\r\n", "uses`r`n  IP3C in 'IP3C.pas',`r`n  IP3A in 'IP3A.pas',`r`n  IP3B in 'IP3B.pas',`r`n  IP3B.Untangle in 'IP3B.Untangle.pas';`r`n"), $Ascii)
    $h1 = Get-Hazard $P
    Check 'g.2 after the swap (IP3C first) init-order-hazard reports the pointer read in IP3A''s initialization' (@($h1 | Where-Object { $_.file_path -match 'IP3A\.pas$' -and $_.message -match 'IP3BWritePtr' }).Count -ge 1) ($h1 | ConvertTo-Json -Compress)
    $null = Invoke-Build $P
    Check 'g.3 (the run agrees) the swapped program calls the nil pointer: its output differs' ((Invoke-Program $P) -cne $out0)

    Write-Host '== B the other two orders refuse, naming both positions and the .dpr' -ForegroundColor Cyan
    foreach ($first in 'IP3B', 'IP3C') {
      $order = @($first) + @($Units | Where-Object { $_ -ne $first })
      $P = New-Proj $order
      $plan = Get-Plan $P
      $pa = Get-Pos $P.Root 'IP3A'; $pb = Get-Pos $P.Root 'IP3B'
      $m = [regex]::Match($plan, $RefusedRx)
      $want = "in ``InitP3.dpr`` ``IP3A`` (position $pa) initializes before ``IP3B`` (position $pb): list ``IP3A`` before ``$first`` in the .dpr, or cut another edge"
      Check "b.$first first: init-order refused, text names .dpr + positions $pa / $pb + the entry to reorder" ($m.Success -and $m.Groups[1].Value.Contains($want)) $plan
    }

    Write-Host '== C a two-unit cycle: never provable' -ForegroundColor Cyan
    $P = New-Proj @('IP3A', 'IP3B', 'IP3C') {
      param($r)
      Edit-Text (Join-Path $r 'IP3A.pas') "uses`n  IP3C, IP3B;" "uses`n  IP3B;"
      Edit-Text (Join-Path $r 'IP3A.pas') "  GPing:= @IP3CPing;`n" ""
      Edit-Text (Join-Path $r 'IP3A.pas') "var`n  GPing: procedure;`n`n" ""
    }
    $plan = Get-Plan $P
    $m = [regex]::Match($plan, $RefusedRx)
    Check 'c.1 ip3a -> ip3b refused: "whatever the .dpr order"' ($m.Success -and $m.Groups[1].Value.Contains('after the cut `IP3B` still uses `IP3A` and `IP3A` no longer reaches `IP3B`, so `IP3A` initializes first whatever the .dpr order')) $plan

    Write-Host '== D a conditional path entry; no program' -ForegroundColor Cyan
    $P = New-Proj @('IP3A', 'IP3B', 'IP3C') { param($r) Edit-Text (Join-Path $r 'IP3C.pas') "uses`n  IP3B;" "uses`n  {`$IFDEF MSWINDOWS}`n  IP3B`n  {`$ENDIF}`n  ;" }
    $ifLine = [array]::IndexOf(@([IO.File]::ReadAllLines((Join-Path $P.Root 'IP3C.pas'))), '  {$IFDEF MSWINDOWS}') + 1
    $plan = Get-Plan $P
    $m = [regex]::Match($plan, $RefusedRx)
    Check "d.1 refused: the order depends on a conditional uses entry (IP3C.pas:$ifLine)" ($m.Success -and $m.Groups[1].Value.Contains("conditional uses entry (``IP3C.pas:$ifLine``)")) $plan
    $P = New-Proj $null { param($r) [IO.File]::Delete((Join-Path $r 'InitP3.dpr')); [IO.File]::Delete((Join-Path $r 'InitP3.dproj')) } -NoIndex
    Push-Location $WorkDir
    try { $null | & $Exe index $P.Root --db $P.Db --library-db none *> "$($P.Db).log" } finally { Pop-Location }
    $plan = Get-Plan $P -NoProject
    $m = [regex]::Match($plan, $RefusedRx)
    Check 'd.2 no .dpr in the index: refused "no program"' ($m.Success -and $m.Groups[1].Value.Contains('no program in this index')) $plan

    Write-Host '== E Part B predicted after Part A: re-checked, then planned' -ForegroundColor Cyan
    $P = New-Proj @('IP3A', 'IP3B', 'IP3C') {
      param($r)
      Edit-Text (Join-Path $r 'IP3A.pas') "interface`n" "interface`n`nuses`n  IP3C, IP3B;`n"
      Edit-Text (Join-Path $r 'IP3A.pas') "implementation`n`nuses`n  IP3C, IP3B;`n" "implementation`n"
      Edit-Text (Join-Path $r 'IP3B.pas') "interface`n" "interface`n`nuses`n  IP3A;`n"
      Edit-Text (Join-Path $r 'IP3B.pas') "implementation`n`nuses`n  IP3A;`n" "implementation`n"
    }
    $plan = Get-Plan $P
    $m = [regex]::Match($plan, $RefusedRx)
    Check 'e.1 predicted Part B: init-order kept, "re-checked against the program order once Part A is applied"' ($m.Success -and $m.Groups[1].Value.TrimEnd().EndsWith('; re-checked against the program order once Part A is applied')) $plan
    $a = Run-Fix $P @('--part', 'a', '--apply')
    Check 'e.2 Part A applied (exit 0)' ($a.Exit -eq 0) "exit=$($a.Exit) $($a.Reasons)"
    Push-Location $WorkDir
    try { $null | & $Exe index --project $P.Dproj --db $P.Db --library-db none *> "$($P.Db).relog" } finally { Pop-Location }
    $plan = Get-Plan $P
    Check 'e.3 after Part A + reindex the same edge is planned with the proof line' (($plan -match '(?m)^- `ip3a -> ip3b`: recipe: routine-call inversion -- \*\*cut by this plan\*\*') -and $plan.Contains('- init order: `IP3B` initializes before `IP3A` in `InitP3.dpr`')) $plan
  }
} finally {
  if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("passed {0}, {1}" -f $script:Passed, $(if ($script:Failed) { 'FAILED' } else { 'all PASS' }))
if ($script:Failed) { exit 1 } else { exit 0 }
