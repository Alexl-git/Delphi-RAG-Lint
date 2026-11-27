# Guard for v156 lane G24R (gap G-24): member-could-be-private also proposes the tighter visibilities
#   private -> strict private, protected -> strict private / strict protected, public -> protected.
# Fixture folder tests\autotest\fixtures\v156-G24R: a line ending in { (+) } must carry a TIGHTENING finding
# (message names "strict private" / "strict protected" / "protected"), { (-) } must not.
# Controls: default OFF (silent without --rule); the old finding (UOwn / OwnFilePublic, "could be private")
# is unchanged; a fixture copy WITHOUT the descendant unit loses the descendant-only findings; run_v152_ATLB.ps1
# (the v152 guard of the existing findings) still passes.
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
function Rows-Of($findings, [string]$fileEnd) {
  return @($findings | Where-Object { $_.rule -eq 'member-could-be-private' -and ([string]$_.file_path).EndsWith($fileEnd, [StringComparison]::OrdinalIgnoreCase) })
}
function Markers([string]$path) {
  $lines = [IO.File]::ReadAllLines($path); $m = @{ plus = @(); minus = @() }
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\{ \(\+\) \}\s*$') { $m.plus += ($i + 1) }
    elseif ($lines[$i] -match '\{ \(-\) \}\s*$') { $m.minus += ($i + 1) }
  }
  return $m
}
$rule = 'member-could-be-private'
$src = Join-Path $PSScriptRoot 'fixtures\v156-G24R'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('v156-g24r-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item (Join-Path $src '*.pas') $tmp
$db = Join-Path $tmp 'a.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> (Join-Path $tmp 'index.log') }
Assert "fixture folder indexed (exit $LASTEXITCODE)" (($LASTEXITCODE -eq 0) -and (Test-Path $db))
$f = @(Get-Findings @('lint-all', '--db', $db, '--rule', $rule, '--json'))
$rows = Rows-Of $f 'UTight.pas'
$tight = @($rows | Where-Object { ([string]$_.message) -match 'strict private|strict protected|could be protected' })
$tl = @($tight | ForEach-Object { [int]$_.start_line })
$m = Markers (Join-Path $tmp 'UTight.pas')
# positive-control: tightening findings
foreach ($l in $m.plus)  { Assert "UTight.pas: tightening fires at line $l (got: $($tl -join ','))" ($tl -contains $l) }
foreach ($l in $m.minus) { Assert "UTight.pas: tightening silent at line $l" (-not ($tl -contains $l)) }
# the proposed target is the right one
function Msg-At($l) { return (@($tight | Where-Object { [int]$_.start_line -eq $l }) | Select-Object -First 1).message }
$lineOf = @{}
$all = [IO.File]::ReadAllLines((Join-Path $tmp 'UTight.pas'))
for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i] -match '^\s+(?:procedure )?(\w+)[:;].*\{ \(\+\) \}') { $lineOf[$Matches[1]] = $i + 1 } }
Assert "FOnlyOwn -> strict private" ((Msg-At $lineOf['FOnlyOwn']) -match 'strict private')
Assert "OwnProc -> strict private" ((Msg-At $lineOf['OwnProc']) -match 'strict private')
Assert "OnlyOwnProt (protected, own class only) -> strict private" ((Msg-At $lineOf['OnlyOwnProt']) -match 'strict private')
Assert "ForKids (protected, descendant only) -> strict protected" ((Msg-At $lineOf['ForKids']) -match 'strict protected')
Assert "ForKidsPublic (public, descendant only) -> protected" ((Msg-At $lineOf['ForKidsPublic']) -match 'could be protected')
# control: the old finding is unchanged -- a public member used only in its own unit still says "could be private"
$ofp = $all.IndexOf(($all | Where-Object { $_ -match 'procedure OwnFilePublic;' } | Select-Object -First 1)) + 1
$old = @($rows | Where-Object { [int]$_.start_line -eq $ofp })
Assert "control: OwnFilePublic keeps the old 'could be private' finding (line $ofp)" ($old.Count -eq 1 -and ([string]$old[0].message) -match 'Public member .* it could be private$')
Assert "control: no member gets two findings" ((@($rows | Group-Object start_line | Where-Object { $_.Count -gt 1 })).Count -eq 0)
$nf = @(Get-Findings @('lint-all', '--db', $db, '--json'))
Assert "default OFF: no $rule finding without --rule" (@($nf | Where-Object { $_.rule -eq $rule }).Count -eq 0)

# control: without the descendant unit the descendant-only members have no reference left, the tightening goes silent
[IO.File]::Delete((Join-Path $tmp 'UKid.pas'))
$db2 = Join-Path $tmp 'b.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db2 *> (Join-Path $tmp 'index2.log') }
$f2 = @(Get-Findings @('lint-all', '--db', $db2, '--rule', $rule, '--json'))
$t2 = @((Rows-Of $f2 'UTight.pas') | ForEach-Object { [int]$_.start_line })
Assert "control: ForKids silent once UKid.pas is gone" (-not ($t2 -contains $lineOf['ForKids']))
Assert "control: ForKidsPublic silent once UKid.pas is gone" (-not ($t2 -contains $lineOf['ForKidsPublic']))
Assert "control: FOnlyOwn still reported (no dependence on UKid)" ($t2 -contains $lineOf['FOnlyOwn'])

# control: the v152 guard of the existing findings still passes
$v152 = & { $ErrorActionPreference = 'Continue'; & powershell -NoProfile -File (Join-Path $PSScriptRoot 'run_v152_ATLB.ps1') -Exe $exe 2>&1 } | Out-String
Assert "control: run_v152_ATLB.ps1 (existing findings) passes" ($v152 -match 'run_v152_ATLB: all passed')

[IO.Directory]::Delete($tmp, $true)
if ($fail -gt 0) { Write-Host "run_v156_G24R: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v156_G24R: all passed"
exit 0
