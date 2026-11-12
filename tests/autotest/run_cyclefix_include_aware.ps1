<#
  run_cyclefix_include_aware.ps1 -- lane CYC3 (wave 152c, item 2 / M3): `cycles --plan` is include-aware. It never
  plans an edit that needs text inside an include, and never calls an include-borne use "nothing is used".

  Fixtures (tests\fixtures\cyclefix):
    incdecl  IncDeclB's interface names TIncDeclARec, declared in IncDeclTypes.inc, which IncDeclA's interface
             includes. Base engine: "could not resolve the symbol", "-> **remove**", "Delete lines", "Fix it
             (mechanical" -- a plan that deletes a NEEDED uses entry.
    incref   IncRefA's call to IncRefB's routine sits in IncRefCalls.inc, included by IncRefA's implementation.
             Base engine: "the index resolved no symbol for this edge".
  Each is checked twice:
    INC  (as committed): the use is named with the include path + line and its {$I} site; no "could not resolve",
         no "no specific symbol resolved", no remove / delete edit; `Fix it: not available -- declaration-in-include`
         / `-- reference-in-include`; the refusal names the include, its line, the {$I} site and the lint rule
         `cycle-edge-in-include`; `--causes --format json` has fix.available = false with that kind first.
    INL  POSITIVE CONTROL: the same fixture with the include inlined into the .pas (written by this guard) plans
         MECHANICALLY and `--fix --apply` passes the compile gate -- so the refusal is caused by the include, and
         the remedy the refusal names really works.
  Exit 0 all PASS, 1 any FAIL, 2 setup; SKIP (exit 0) without rsvars.bat (the compile gate of the INL rows).
#>
[CmdletBinding()]
param(
  [string]$Exe     = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe") { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" } else { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }),
  [string]$WorkDir = "$env:TEMP\drag-lint-cyclefix-incaware-$PID",
  [string]$RsVars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$NoApply,
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\HermeticEngine.ps1"
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
$Exe   = Get-HermeticEngine $Exe
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII

$Cases = @(
  @{ Tag = 'incdecl'; Name = 'IncDecl'; Host = 'IncDeclA.pas'; Inc = 'IncDeclTypes.inc'; Kind = 'declaration-in-include'
     Sym = 'TIncDeclARec'; IncLine = 2; HostLine = 8
     Why = '`incdeclb` interface uses `TIncDeclARec` (record) at `IncDeclB.pas:12`; declared in `IncDeclA` through `IncDeclTypes.inc:2` (`{$I}` at `IncDeclA.pas:8`).' },
  @{ Tag = 'incref'; Name = 'IncRef'; Host = 'IncRefA.pas'; Inc = 'IncRefCalls.inc'; Kind = 'reference-in-include'
     Sym = 'IncRefBWrite'; IncLine = 3; HostLine = 19
     Why = '`IncRefCalls.inc:3` through `{$I}` at `IncRefA.pas:19`: `IncRefBWrite`  [procedure]  -> declared in `increfb`' }
)

# A copy of the fixture; -Inline replaces the {$I} line by the include's text and drops the include.
function New-Proj($C, [switch]$Inline) {
  $root = Join-Path $WorkDir ($C.Tag + $(if ($Inline) { '-inl' } else { '-inc' }))
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem (Join-Path $Repo "tests\fixtures\cyclefix\$($C.Tag)") -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  if ($Inline) {
    $hostPas = Join-Path $root $C.Host
    $inc  = Join-Path $root $C.Inc
    $t = [IO.File]::ReadAllText($hostPas, $Ascii)
    $site = '{$I ' + $C.Inc + '}'
    if (-not $t.Contains($site)) { throw "no $site in $hostPas" }
    [IO.File]::WriteAllText($hostPas, $t.Replace($site, [IO.File]::ReadAllText($inc, $Ascii).TrimEnd("`r", "`n")), $Ascii)
    [IO.File]::Delete($inc)
  }
  $P = @{ Root = $root; Dproj = (Join-Path $root "$($C.Name).dproj"); Db = "$root.sqlite" }
  Push-Location $WorkDir
  try { $null | & $Exe index --project $P.Dproj --db $P.Db --library-db none *> "$($P.Db).log" } finally { Pop-Location }
  return $P
}
function Get-Plan($P) {
  Push-Location $WorkDir
  try { return ($null | & $Exe cycles --plan --project $P.Dproj --db $P.Db --library-db none 2>$null | Out-String) } finally { Pop-Location }
}
function Get-Fix($P) {
  Push-Location $WorkDir
  try { $o = ($null | & $Exe cycles --causes --format json --project $P.Dproj --db $P.Db --library-db none 2>$null | Out-String) } finally { Pop-Location }
  try { return @(($o | ConvertFrom-Json))[0].fix } catch { return $null }
}
function Run-Apply($P) {
  $a = @('cycles', '--fix', '--build-timeout', '1800', '--rsvars', $RsVars, '--project', $P.Dproj, '--db', $P.Db,
    '--library-db', 'none', '--format', 'json', '--cycle', '1', '--apply')
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @()
  foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += "$($x.kind): $($x.reason)" } } }
  foreach ($x in @($j.refusals)) { if ($x) { $k += "$($x.kind): $($x.reason)" } }
  return @{ Exit = $code; Refusals = ($k -join ' || ') }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  foreach ($c in $Cases) {
    Write-Host "== $($c.Tag) (include as committed)" -ForegroundColor Cyan
    $P = New-Proj $c
    $plan = Get-Plan $P
    Check "$($c.Tag).0 the plan is not empty" ($plan -match '(?m)^## Cycle 1:') "plan: $($plan.Length) chars"
    Check "$($c.Tag).1 no 'could not resolve' / 'no specific symbol resolved' / 'resolved no symbol'" (-not ($plan -match 'could not resolve|no specific symbol resolved|resolved no symbol'))
    Check "$($c.Tag).2 no remove / delete edit for the uses entry" (-not ($plan -match '-> \*\*remove\*\*|Delete lines'))
    Check "$($c.Tag).3 'Why it cycles' names the include and its {`$I} site" $plan.Contains($c.Why) $c.Why
    Check "$($c.Tag).4 Fix it: not available -- $($c.Kind)" ($plan -match ('(?m)^Fix it: not available -- ' + [regex]::Escape($c.Kind) + '\s*$'))
    $text = ('{0} (line {1}), which {2} includes through {{$I {0}}} at line {3}: drag-lint never edits an include' -f $c.Inc, $c.IncLine, $c.Host, $c.HostLine)
    Check "$($c.Tag).5 the refusal names the include, its line, the {`$I} site, the remedy and the rule" ($plan.Contains($text) -and $plan.Contains("into $($c.Host), then run ``cycles --plan`` again") -and $plan.Contains('`cycle-edge-in-include`')) $text
    $fix = Get-Fix $P
    Check "$($c.Tag).6 json fix.available = false, reason starts with $($c.Kind)" (($null -ne $fix) -and ($fix.available -eq $false) -and ([string]$fix.reason).StartsWith("$($c.Kind):")) "fix=$($fix | ConvertTo-Json -Compress -Depth 2)"

    Write-Host "== $($c.Tag) (include inlined: positive control)" -ForegroundColor Cyan
    $Q = New-Proj $c -Inline
    $plan = Get-Plan $Q
    Check "$($c.Tag).p1 inlined: the plan is mechanical" ($plan -match '(?m)^Fix it \(mechanical, compile-gated\):') (($plan -split "`n" | Select-String 'Fix it' | Select-Object -First 1) -join '')
    Check "$($c.Tag).p2 inlined: no include refusal" (-not ($plan -match 'declaration-in-include|reference-in-include'))
    if ($NoApply) { Write-Host "  (-NoApply: the compile-gated --apply row is skipped)" -ForegroundColor Yellow; continue }
    $r = Run-Apply $Q
    Check "$($c.Tag).p3 inlined: --fix --apply exits 0 with no refusal (compile gate passed)" (($r.Exit -eq 0) -and ($r.Refusals -eq '')) "exit=$($r.Exit) $($r.Refusals)"
  }
} finally {
  if (-not $KeepWorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host ("passed {0}{1}" -f $script:Passed, $(if ($script:Failed) { ', FAILURES' } else { ', all PASS' }))
exit $(if ($script:Failed) { 1 } else { 0 })
