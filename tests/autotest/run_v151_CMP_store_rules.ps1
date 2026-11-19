# Guard for the v151 lane CMP rules that need an index or a compiled resource
# (1.51.0-alpha). The plain fixtures run index-free in tests\lint; these cases
# cannot:
#   * interface-holder-of-non-refcounted, CMP widening: Supports(X, IID, Intf) where X's
#     static type descends from TComponent through a class of another unit (USupports);
#   * hides-ancestor-virtual on `constructor Create(AOwner: TComponent)` without override,
#     ancestor in another unit (UCtor) -- the refused gap #16 is covered by the host rule;
#   * component-missing-free-notification with the ancestry known only to the index
#     (UFreeNotify);
#   * component-palette-icon reading a COMPILED .dcr (UPalette; the runner writes it).
# Expectations are the markers in the fixtures: a line ending in { (+) } must carry the
# finding, { (-) } must not. Positive control: every (+) line is re-run with the rule
# disabled (--disable) and must then be ABSENT, so an assertion that cannot fail is caught.
# The fixture folder is copied to a temp directory and indexed into a temp DB there.
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
[Environment]::CurrentDirectory = $repo
$exe = (Resolve-Path $Exe).Path
$fail = 0
function Assert($name, $cond) {
  if ($cond) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:fail++ }
}

$src = Join-Path $PSScriptRoot 'fixtures\v151-CMP\store'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('v151-cmp-store-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
Copy-Item (Join-Path $src '*.pas') $tmp

# UPalette.dcr: an empty header entry, then one RT_BITMAP entry named TPALOK.
function New-ResEntry([int]$type, [string]$name, [byte[]]$data) {
  $ms = New-Object IO.MemoryStream
  $bw = New-Object IO.BinaryWriter($ms)
  $nameBytes = [Text.Encoding]::Unicode.GetBytes($name + [char]0)
  $hdr = 8 + 4 + $nameBytes.Length
  if ($hdr % 4 -ne 0) { $hdr += 4 - ($hdr % 4) }
  $hdr += 16
  $bw.Write([uint32]$data.Length); $bw.Write([uint32]$hdr)
  $bw.Write([uint16]0xFFFF); $bw.Write([uint16]$type)
  $bw.Write($nameBytes)
  while ($ms.Length % 4 -ne 0) { $bw.Write([byte]0) }
  $bw.Write([uint32]0); $bw.Write([uint16]0x1030); $bw.Write([uint16]0x0409); $bw.Write([uint32]0); $bw.Write([uint32]0)
  $bw.Write($data)
  while ($ms.Length % 4 -ne 0) { $bw.Write([byte]0) }
  $bw.Flush()
  return ,$ms.ToArray()
}
$empty = [byte[]](0,0,0,0, 32,0,0,0, 0xFF,0xFF,0,0, 0xFF,0xFF,0,0, 0,0,0,0, 0,0, 0,0, 0,0,0,0, 0,0,0,0)
$bmp = New-ResEntry 2 'TPALOK' ([byte[]](1,2,3,4))
[IO.File]::WriteAllBytes((Join-Path $tmp 'UPalette.dcr'), [byte[]]($empty + $bmp))

$db = Join-Path $tmp 'store.sqlite'
& { $ErrorActionPreference = 'Continue'; & $exe index $tmp --db $db *> (Join-Path $tmp 'index.log') }
Assert "fixture folder indexed into a temp DB (exit $LASTEXITCODE)" (($LASTEXITCODE -eq 0) -and (Test-Path $db))

function Lint-Lines([string]$unit, [string]$rule, [string[]]$extra) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exe lint (Join-Path $tmp $unit) --db $db --rule $rule --json @extra 2>$null }
  $arr = @()
  try { $arr = @((($raw -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { $arr = @() }
  return @($arr | Where-Object { $_.rule -eq $rule } | ForEach-Object { [int]$_.start_line })
}

$cases = @(
  @{ Unit = 'USupports.pas';   Rule = 'interface-holder-of-non-refcounted' },
  @{ Unit = 'UCtor.pas';       Rule = 'hides-ancestor-virtual' },
  @{ Unit = 'UFreeNotify.pas'; Rule = 'component-missing-free-notification' },
  @{ Unit = 'UPalette.pas';    Rule = 'component-palette-icon' }
)
foreach ($c in $cases) {
  $lines = [IO.File]::ReadAllLines((Join-Path $tmp $c.Unit))
  $must = @(); $mustNot = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '\{ \(\+\) \}\s*$') { $must += ($i + 1) }
    elseif ($lines[$i] -match '\{ \(-\) \}\s*$') { $mustNot += ($i + 1) }
  }
  $got = @(Lint-Lines $c.Unit $c.Rule @())
  foreach ($l in $must) { Assert "$($c.Unit): $($c.Rule) fires at line $l (got: $($got -join ','))" ($got -contains $l) }
  foreach ($l in $mustNot) { Assert "$($c.Unit): $($c.Rule) silent at line $l" (-not ($got -contains $l)) }
  $off = @(Lint-Lines $c.Unit $c.Rule @('--disable', $c.Rule))
  foreach ($l in $must) { Assert "$($c.Unit): positive control -- with --disable $($c.Rule) line $l is gone" (-not ($off -contains $l)) }
}

[IO.Directory]::Delete($tmp, $true)
if ($fail -gt 0) { Write-Host "run_v151_CMP_store_rules: $fail FAILED" -ForegroundColor Red; exit 1 }
Write-Host "run_v151_CMP_store_rules: all passed"
exit 0
