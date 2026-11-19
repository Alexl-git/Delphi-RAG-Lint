<#
  run_v152_FINCUT.ps1 -- lane FINCUT (1.52, ruling B9a): `cycles --plan` / `--fix` PLAN a routine-call inversion
  whose consumer calls the declaring unit from its FINALIZATION section when the consumer ALREADY initializes
  before the declaring unit and the cut leaves that order unchanged, in every program. The declaring unit is then
  finalized first before the cut and after it: the program's behaviour is unchanged, so the cut is planned (it used
  to refuse `finalization-order`) and the step says so.

  Fixture tests\fixtures\cyclefix\finp3 (lane FINPROOF): FP3A's finalization calls FP3BReport; FP3B's finalization
  clears the state FP3BReport prints. Only FP3A -> FP3B is a routine-call inversion.

  A   Consumer first, three units (.dpr lists FP3B first, so FP3A initializes before FP3B with the cycle as written
      and after the cut): planned, the step carries "finalization order: unchanged ...", JSON final_order holds it;
      `--fix --apply` passes the compile gate; the untouched and the applied program are built and RUN: the same
      init lines, the same fin lines, byte-identical stdout (FP3B's name already empty at FP3A's finalization).
  B   Consumer first, two units (FP3A uses only FP3B; .dpr lists FP3B first): planned the same way, applied, run,
      same output.
  C   Consumer LATER, the two-unit twin of B (.dpr lists FP3A first: FP3B initializes first today, the cut makes
      FP3A first): still refused `finalization-order`, "after the cut `FP3B` is finalized first".
  D   Consumer first but the order depends on a conditional uses entry: still refused, naming file:line.

  POSITIVE CONTROLS: B and C are the same sources, only the .dpr order differs, with opposite verdicts; in A and B
  the run shows the unchanged behaviour is the EMPTY name (the run can tell a finalized FP3B from a live one).
  Needs RAD Studio; SKIPs (exit 0) without it.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v152-fincut-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
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

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
function Set-DprOrder([string]$Root, [string[]]$Order) {
  $dpr = Join-Path $Root 'FinP3.dpr'
  $t = [IO.File]::ReadAllText($dpr, $Ascii)
  $list = ($Order | ForEach-Object { "  $_ in '$_.pas'" }) -join ",`r`n"
  $t = [regex]::Replace($t, '(?s)uses\r\n.*?;\r\n', "uses`r`n$list;`r`n")
  [IO.File]::WriteAllText($dpr, $t, $Ascii)
}
# FP3A uses FP3B only: a two-unit cycle FP3A <-> FP3B (FP3C stays in the program, outside the cycle).
function Set-TwoUnit([string]$Root) {
  Edit-Text (Join-Path $Root 'FP3A.pas') "uses`n  FP3C, FP3B;" "uses`n  FP3B;"
  Edit-Text (Join-Path $Root 'FP3A.pas') "  GPing:= @FP3CPing;`n" ""
  Edit-Text (Join-Path $Root 'FP3A.pas') "var`n  GPing: procedure;`n`n" ""
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
# The uses entries of one source file, interface first, then implementation.
function Get-UsesOf([string]$Path) {
  $t = [regex]::Replace([IO.File]::ReadAllText($Path, $Ascii), '(?m)//.*$', '')
  $r = @()
  foreach ($m in [regex]::Matches($t, '(?is)\buses\s+([^;]+);')) {
    $r += @($m.Groups[1].Value -split ',' | ForEach-Object { (($_ -split '\s+in\s+')[0]).Trim() } | Where-Object { $_ })
  }
  return $r
}
function Get-Lines([string]$Out, [string]$Word) { return @([regex]::Matches($Out, "(?m)^$Word (\w+)") | ForEach-Object { $_.Groups[1].Value }) }
function Get-Plan($P) {
  Push-Location $WorkDir
  try { return ($null | & { $ErrorActionPreference = 'Continue'; & $Exe cycles --plan --project $P.Dproj --db $P.Db --library-db none 2>$null } | Out-String) } finally { Pop-Location }
}
function Get-CausesJson($P) {
  Push-Location $WorkDir
  try { $o = ($null | & { $ErrorActionPreference = 'Continue'; & $Exe cycles --causes --format json --project $P.Dproj --db $P.Db --library-db none 2>$null } | Out-String) } finally { Pop-Location }
  try { return ($o | ConvertFrom-Json) } catch { return $null }
}
function Run-Fix($P) {
  Push-Location $WorkDir
  try { $out = ($null | & { $ErrorActionPreference = 'Continue'; & $Exe cycles --fix --apply --build-timeout 1800 --project $P.Dproj --db $P.Db --library-db none --format json 2>$null } | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @(); $r = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += $x.kind; $r += "$($x.kind): $($x.reason)" } } }
  foreach ($x in @($j.refusals)) { if ($x) { $k += $x.kind; $r += "$($x.kind): $($x.reason)" } }
  return @{ Exit = $code; Out = $out; Kinds = $k; Reasons = ($r -join ' || ') }
}

$CutRx     = '(?m)^- `fp3a -> fp3b`: recipe: routine-call inversion -- \*\*cut by this plan\*\*'
$RefusedRx = '(?m)^- `fp3a -> fp3b`:.*?`FP3BReport` \(procedure\): refused: finalization-order -- (.*)$'
$Unchanged = 'finalization order: unchanged by the cut: `FP3B` is finalized before `FP3A` with the cycle as written and after the cut'

# One consumer-first case: plan, JSON, apply through the compile gate, build both, run both, compare.
function Test-ConsumerFirst([string]$Tag, [string[]]$Order, [scriptblock]$Patch) {
  $P = New-Proj $Order $Patch
  $plan = Get-Plan $P
  Write-Host "  --- raw plan ($Tag), the fp3a -> fp3b lines:" -ForegroundColor DarkGray
  ($plan -split "`r?`n" | Where-Object { $_ -match 'fp3a -> fp3b|finalization order' }) | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
  Check "$Tag.1 the plan cuts fp3a -> fp3b (no finalization-order refusal)" (($plan -match $CutRx) -and ($plan -notmatch 'refused: finalization-order')) $plan
  Check "$Tag.2 the step says the finalization order is unchanged and names the .dpr" ($plan.Contains($Unchanged) -and $plan.Contains('in `FinP3.dpr`')) $plan
  $j = Get-CausesJson $P
  $edge = @($j | ForEach-Object { $_.fix.edges } | Where-Object { $_.from -eq 'fp3a' -and $_.to -eq 'fp3b' })[0]
  Check "$Tag.3 JSON: the chosen edge carries final_order with the unchanged line" (($null -ne $edge) -and $edge.chosen -and ("$($edge.final_order)".Contains($Unchanged))) ($j | ConvertTo-Json -Depth 8 -Compress)
  $base = New-Proj $Order $Patch -NoIndex
  $b0 = Invoke-Build $base
  Check "$Tag.4 the untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program $base
  $a = Run-Fix $P
  Check "$Tag.5 --fix --apply: exit 0, no refusal (compile gate passed)" (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) kinds=$($a.Kinds -join ',') $($a.Reasons)"
  $b1 = Invoke-Build $P
  $leaf = @(Get-ChildItem $P.Root -Filter 'FP3B.*.pas' | ForEach-Object { $_.BaseName })
  $aUses = Get-UsesOf (Join-Path $P.Root 'FP3A.pas')
  Check "$Tag.6 the cut is applied (leaf [$($leaf -join ',')], FP3A uses [$($aUses -join ',')]) and the copy builds (independent msbuild)" ($b1.Ok -and ($leaf.Count -eq 1) -and ($aUses -notcontains 'FP3B') -and ($aUses -contains $leaf[0])) $b1.Errors
  $out1 = Invoke-Program $P
  Write-Host "      untouched run: $(($out0 -split "`r?`n") -join ' / ')" -ForegroundColor DarkGray
  Write-Host "      applied run:   $(($out1 -split "`r?`n") -join ' / ')" -ForegroundColor DarkGray
  $i0 = (Get-Lines $out0 'init') -join ','; $i1 = (Get-Lines $out1 'init') -join ','
  $f0 = (Get-Lines $out0 'fin') -join ','; $f1 = (Get-Lines $out1 'fin') -join ','
  Check "$Tag.7 the applied program keeps its init order [$i1] = [$i0] and fin order [$f1] = [$f0]" (($leaf.Count -eq 1) -and ($i0 -ne '') -and ($i0 -eq $i1) -and ($f0 -eq $f1) -and ([array]::IndexOf(@($i0 -split ','), 'FP3A') -lt [array]::IndexOf(@($i0 -split ','), 'FP3B'))) "before=[$out0] after=[$out1]"
  Check "$Tag.8 stdout byte-identical; FP3B's name already empty at FP3A's finalization before and after" ($b1.Ok -and ($leaf.Count -eq 1) -and ($out0 -ne '<no exe>') -and ($out1 -ceq $out0) -and ($out0 -match '(?m)\[b\] a stopped name=\r?$')) "before=[$out0] after=[$out1]"
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  Write-Host '== A consumer first, three units (.dpr: FP3B, FP3A, FP3C)' -ForegroundColor Cyan
  Test-ConsumerFirst 'a' @('FP3B', 'FP3A', 'FP3C') $null

  Write-Host '== B consumer first, two units (.dpr: FP3B, FP3A, FP3C)' -ForegroundColor Cyan
  Test-ConsumerFirst 'b' @('FP3B', 'FP3A', 'FP3C') { param($r) Set-TwoUnit $r }

  Write-Host '== C consumer later, the two-unit twin (.dpr: FP3A, FP3B, FP3C): still refused' -ForegroundColor Cyan
  $P = New-Proj @('FP3A', 'FP3B', 'FP3C') { param($r) Set-TwoUnit $r }
  $plan = Get-Plan $P
  $m = [regex]::Match($plan, $RefusedRx)
  Check 'c.1 fp3a -> fp3b refused: "after the cut `FP3B` is finalized first"' ($m.Success -and $m.Groups[1].Value.Contains('and after the cut `FP3B` is finalized first')) $plan
  Check 'c.2 no unchanged-order line on the refused twin' (-not $plan.Contains($Unchanged)) $plan

  Write-Host '== D consumer first, a conditional path entry: still refused' -ForegroundColor Cyan
  $P = New-Proj @('FP3B', 'FP3A', 'FP3C') { param($r) Edit-Text (Join-Path $r 'FP3C.pas') "uses`n  FP3B;" "uses`n  {`$IFDEF MSWINDOWS}`n  FP3B`n  {`$ENDIF}`n  ;" }
  $ifLine = [array]::IndexOf(@([IO.File]::ReadAllLines((Join-Path $P.Root 'FP3C.pas'))), '  {$IFDEF MSWINDOWS}') + 1
  $plan = Get-Plan $P
  $m = [regex]::Match($plan, $RefusedRx)
  Check "d.1 refused: the order depends on a conditional uses entry (FP3C.pas:$ifLine)" ($m.Success -and $m.Groups[1].Value.Contains("conditional uses entry (``FP3C.pas:$ifLine``)")) $plan
} finally {
  if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("passed {0}, {1}" -f $script:Passed, $(if ($script:Failed) { 'FAILED' } else { 'all PASS' }))
if ($script:Failed) { exit 1 } else { exit 0 }
