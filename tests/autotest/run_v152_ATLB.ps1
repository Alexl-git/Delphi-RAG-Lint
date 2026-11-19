# Guard for v152 lane ATLB (1.52.0-alpha).
#  1. hides-ancestor-virtual on a COMPONENT constructor without override. The new id
#     component-create-without-override stays REFUSED (exact dcc W1010 duplicate, owner
#     ruling 2026-11-17); this proves the host rule covers the shape. Fixture:
#     tests\lint\hides-ancestor-virtual-component-ctor.pas. Positive control: --disable.
#  2. member-could-be-private (project-wide, default OFF) over the fixture folder
#     tests\autotest\fixtures\v152-ATLB: a line ending in { (+) } must carry the finding,
#     { (-) } must not. Controls: the rule is silent when not requested (default OFF);
#     UShared.pas carries a dl:shared header naming a second project (its index is not
#     open here) and is silent, while a copy WITHOUT the header is reported; a unit
#     referenced from a second file (UsedElsewhere) stays silent, its caller removed it fires.
# debug-display-placeholder landed in 1.52 BK-ATTRRULES (B48): tests\autotest\run_v152_BK-ATTRRULES.ps1.
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$exe = (Resolve-Path $Exe).Path
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}
function Get-Findings([string[]]$ArgList) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exe @ArgList 2>$null }
  $text = ($raw -join "`n").Trim()
  if ($text -eq '') { return @() }
  try { $j = $text | ConvertFrom-Json | ForEach-Object { $_ } } catch { return @() }
  if ($null -eq $j) { return @() }
  return @($j)
}
function Lines-Of($findings, [string]$rule, [string]$fileEnd) {
  return @($findings | Where-Object { $_.rule -eq $rule -and ([string]$_.file_path).EndsWith($fileEnd, [StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { [int]$_.start_line })
}
function Markers([string]$path) {
  $lines = [IO.File]::ReadAllLines($path); $m = @{ plus = @(); minus = @() }
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\{ \(\+\) \}\s*$') { $m.plus += ($i + 1) }
    elseif ($lines[$i] -match '\{ \(-\) \}\s*$') { $m.minus += ($i + 1) }
  }
  return $m
}

# ---- 1. component constructor ----
$ctor = 'tests\lint\hides-ancestor-virtual-component-ctor.pas'
$mk = Markers $ctor
$got = @(Lines-Of (@(Get-Findings @('lint', $ctor, '--rule', 'hides-ancestor-virtual', '--json'))) 'hides-ancestor-virtual' 'component-ctor.pas')
foreach ($l in $mk.plus) { Assert "component ctor: hides-ancestor-virtual fires at line $l (got: $($got -join ','))" ($got -contains $l) }
$off = @(Lines-Of (@(Get-Findings @('lint', $ctor, '--rule', 'hides-ancestor-virtual', '--disable', 'hides-ancestor-virtual', '--json'))) 'hides-ancestor-virtual' 'component-ctor.pas')
Assert "component ctor: positive control -- rule disabled, no finding" ($off.Count -eq 0)
$cat = & { $ErrorActionPreference = 'Continue'; & $exe rules --json 2>$null } | Out-String
Assert "component-create-without-override is NOT a catalog id (refused duplicate)" ($cat -notmatch 'component-create-without-override')
Assert "debug-display-placeholder is a catalog id (1.52 BK-ATTRRULES, on the attributes fact; run_v152_BK-ATTRRULES.ps1)" ($cat -match 'debug-display-placeholder')

# ---- 2. member-could-be-private ----
$rule = 'member-could-be-private'
$src = Join-Path $PSScriptRoot 'fixtures\v152-ATLB'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('v152-atlb-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item (Join-Path $src '*.pas') $tmp
$db = Join-Path $tmp 'a.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> (Join-Path $tmp 'index.log') }
Assert "fixture folder indexed (exit $LASTEXITCODE)" (($LASTEXITCODE -eq 0) -and (Test-Path $db))
$f = @(Get-Findings @('lint-all', '--db', $db, '--rule', $rule, '--json'))
foreach ($u in 'UOwn.pas', 'UShared.pas') {
  $m = Markers (Join-Path $tmp $u); $g = @(Lines-Of $f $rule $u)
  # positive-control: member-could-be-private
  foreach ($l in $m.plus)  { Assert "$u`: $rule fires at line $l (got: $($g -join ','))" ($g -contains $l) }
  foreach ($l in $m.minus) { Assert "$u`: $rule silent at line $l" (-not ($g -contains $l)) }
}
$all = @(Get-Findings @('lint-all', '--db', $db, '--json'))
Assert "default OFF: no $rule finding without --rule" (@($all | Where-Object { $_.rule -eq $rule }).Count -eq 0)

# control: UShared without the header is reported (the silence above is the marker's doing)
$ush = Join-Path $tmp 'UShared.pas'
$t = [IO.File]::ReadAllText($ush) -replace '//\s*dl:shared[^\r\n]*', ''
[IO.File]::WriteAllText($ush, $t)
$db = Join-Path $tmp 'b.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> (Join-Path $tmp "index2.log") }
$f2 = @(Get-Findings @('lint-all', '--db', $db, '--rule', $rule, '--json'))
$sharedLine = (Markers (Join-Path $src 'UShared.pas')).minus[0]
Assert "control: UShared without dl:shared is reported at line $sharedLine" ((@(Lines-Of $f2 $rule 'UShared.pas')) -contains $sharedLine)

# control: drop the second file's call -> UsedElsewhere now fires
[IO.File]::Delete((Join-Path $tmp "UOther.pas"))
$own = Join-Path $tmp 'UOwn.pas'
$ownLine = ([IO.File]::ReadAllLines($own) | Select-String 'procedure UsedElsewhere;' | Select-Object -First 1).LineNumber
[IO.File]::WriteAllText($own, ([IO.File]::ReadAllText($own) -replace "procedure TOwn.Run;\r?\nbegin", "procedure TOwn.Run;`r`nbegin`r`n  UsedElsewhere;"))
$db = Join-Path $tmp 'c.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> (Join-Path $tmp "index3.log") }
$f3 = @(Get-Findings @('lint-all', '--db', $db, '--rule', $rule, '--json'))
Assert "control: UsedElsewhere reported once no other file references it (line $ownLine)" ((@(Lines-Of $f3 $rule 'UOwn.pas')) -contains $ownLine)

[IO.Directory]::Delete($tmp, $true)
if ($fail -gt 0) { Write-Host "run_v152_ATLB: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v152_ATLB: all passed"
exit 0
