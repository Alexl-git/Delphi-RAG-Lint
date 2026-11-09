<#
  run_redcast_library_identity.ps1 -- lane 149 RT item 2: redundant-cast, type-not-indexed with a library.

  A cast whose target type lives in a platform LIBRARY index (not this project's) is an identity cast when the
  operand's type is that same type: the library holds exactly one distinct qualified_name of that name (a forward
  stub plus its body is ONE name). `string(X)` is an identity cast when X is typed string (an own routine, or a
  library routine whose signature returns string). Fixture: tests\fixtures\refactor\redcastlib, marked FIX /
  REFUSE <kind> / NONE per line. Plan only (dry run); every project and DB lives under %TEMP%.

  Positive controls: L1 the same project planned with --library-db none must REFUSE the library class cast
  (the library is what makes it a fix); L2 a name that two library units declare stays refused; L3 the markers
  hold a FIX, a NONE and a REFUSE; L4 a project that holds no marker line reports no fix for it.
#>
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { Write-Host "  ok   $Name" } else { $script:Failed = $true; Write-Host "  FAIL $Name $Detail" -ForegroundColor Red }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fx = (Resolve-Path "$PSScriptRoot\..\fixtures\refactor\redcastlib").Path
$Tmp = Join-Path $env:TEMP ("redcast_lib_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
[IO.Directory]::CreateDirectory($Tmp) | Out-Null

function Read-Markers([string]$Path) {
  $map = @{}
  $n = 0
  foreach ($l in [IO.File]::ReadAllLines($Path)) {
    $n++
    $m = [regex]::Match($l, '//\s*(FIX|NONE|REFUSE\s+[a-z-]+)\s*$')
    if ($m.Success) { $map[$n] = ($m.Groups[1].Value -replace '\s+', ' ') }
  }
  return $map
}
function Outcomes($Plan) {
  $map = @{}
  foreach ($f in $Plan.fixes) { $map[[int]$f.line] = 'FIX' }
  foreach ($f in $Plan.refused) { $map[[int]$f.line] = "REFUSE $($f.kind)" }
  return $map
}
function Compare-Map($Want, $Got) {
  $bad = @()
  foreach ($k in $Want.Keys) {
    $w = if ($Want[$k] -eq 'NONE') { '' } else { $Want[$k] }
    $g = if ($Got.ContainsKey($k)) { $Got[$k] } else { '' }
    if ($w -cne $g) { $bad += "line ${k}: want [$w] got [$g]" }
  }
  foreach ($k in $Got.Keys) { if (-not $Want.ContainsKey($k)) { $bad += "line ${k}: unmarked [$($Got[$k])]" } }
  return $bad
}

try {
  $d = Join-Path $Tmp 'p'
  Copy-Item $Fx $d -Recurse
  $lib = Join-Path $d 'lib.sqlite'
  $db = Join-Path $d 'p.sqlite'
  & $Exe index (Join-Path $d 'lib') --db $lib --library-db none *> (Join-Path $Tmp 'lib.index.log')
  Check 'I1 the stand-in library indexes' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  & $Exe index --project (Join-Path $d 'RcLib.dproj') --db $db --library-db $lib *> (Join-Path $Tmp 'p.index.log')
  Check 'I2 the project indexes' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
  $use = Join-Path $d 'RcLibUse.pas'
  $proj = Join-Path $d 'RcLib.dproj'
  $want = Read-Markers $use
  $flat = @($want.Values)
  Check 'L3 control: the markers hold FIX, NONE and REFUSE' (($flat -contains 'FIX') -and ($flat -contains 'NONE') -and (@($flat | Where-Object { $_ -like 'REFUSE*' }).Count -ge 2)) ($flat -join ' ')

  $o = & $Exe lint --fix --fix-rule redundant-cast --db $db --project $proj --library-db $lib --format json 2> (Join-Path $Tmp 'plan.err')
  $plan = (($o -join "`n") | ConvertFrom-Json)
  $got = Outcomes $plan
  $bad = Compare-Map $want $got
  Check 'D1 every marked line gets its outcome with the library' ($bad.Count -eq 0) ("`n    " + ($bad -join "`n    "))

  $o2 = & $Exe lint --fix --fix-rule redundant-cast --db $db --project $proj --library-db none --format json 2> (Join-Path $Tmp 'plan2.err')
  $plan2 = (($o2 -join "`n") | ConvertFrom-Json)
  $lcLine = @($want.Keys | Where-Object { $want[$_] -eq 'FIX' } | Sort-Object)[0]
  $g2 = Outcomes $plan2
  Check 'L1 control: without the library the class cast is refused type-not-indexed' ($g2[[int]$lcLine] -eq 'REFUSE type-not-indexed') "$($g2[[int]$lcLine])"
  $twinLine = @($want.Keys | Where-Object { $want[$_] -eq 'REFUSE type-not-indexed' } | Sort-Object)[0]
  Check 'L2 control: a name two library units declare stays refused' ($got[[int]$twinLine] -eq 'REFUSE type-not-indexed') "$($got[[int]$twinLine])"
  $dropped = @{}; foreach ($k in $got.Keys) { $dropped[$k] = $got[$k] }
  $dropped.Remove($lcLine)
  Check 'L4 control: the comparer sees a dropped fix' (@(Compare-Map $want $dropped).Count -gt 0)
}
finally {
  [IO.Directory]::Delete($Tmp, $true)
}
if ($script:Failed) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'PASS'
