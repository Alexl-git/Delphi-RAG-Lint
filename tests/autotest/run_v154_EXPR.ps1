<#
  run_v154_EXPR.ps1 -- 1.54 lane EXPR: duplicate-logical-operand, contradictory-condition, boolean-comparison-precedence,
  function-name-reads-itself, warnings-off-not-restored and homoglyph-identifier, on tests\fixtures\v154\EXPR.
  A fixture line that must report carries "// FIRE <rule>"; every other line must stay silent, so each rule has firing
  and silent controls in the same run. The homoglyph fixture is written here (UTF-8 and a code-page copy), because
  the repository keeps sources 7-bit ASCII.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = "$env:TEMP\drag-lint-v154-expr-$PID"
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Checks = 0
function Check($n, $ok, $d = '') {
  $script:Checks++
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Fix = (Resolve-Path "$PSScriptRoot\..\fixtures\v154\EXPR").Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $Src | Out-Null
Copy-Item "$Fix\*" $Src

# the homoglyph fixture: Cyrillic o (U+043E) and Greek alpha (U+03B1) inside Latin names
$Cyr = [string][char]0x043E
$Alpha = [string][char]0x03B1
$Imya = ([char]0x0418 + [char]0x043C + [char]0x044F)   # a whole Cyrillic word
$lines = @(
  'unit Homo;', '', 'interface', '', 'implementation', '', 'procedure P;', 'var',
  "  C${Cyr}unter: Integer; // FIRE homoglyph-identifier",
  "  ${Alpha}lpha: Integer; // FIRE homoglyph-identifier",
  '  Counter: Integer;',
  "  ${Imya}: Integer;",
  "  Edit_${Imya}: Integer;",
  'begin',
  "  Name := 'C${Cyr}unter';",
  "  // C${Cyr}unter in a comment",
  '  Exit;', 'end;', '', 'end.')
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $Src 'Homo.pas'), ($lines -join "`r`n") + "`r`n", $utf8)
# the same text in the Cyrillic code page: bytes >= $80 are letters of that page, not look-alikes
$cp = [Text.Encoding]::GetEncoding(1251)
$cpLines = @('unit HomoAnsi;', '', 'interface', '', 'implementation', '', 'procedure P;', 'var', "  C${Cyr}unter: Integer;", 'begin', '  Exit;', 'end;', '', 'end.')
[IO.File]::WriteAllText((Join-Path $Src 'HomoAnsi.pas'), ($cpLines -join "`r`n") + "`r`n", $cp)

$Db = Join-Path $WorkDir 'p.sqlite'
$Cfg = Join-Path $WorkDir 'cfg.json'
[IO.File]::WriteAllText($Cfg, '{}', [Text.Encoding]::ASCII)
& { $ErrorActionPreference = 'Continue'; & $Exe index $Src --db $Db 2>&1 | ForEach-Object { "$_" } } | Out-Null

function Get-Found([string[]]$Argv) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $Exe @Argv --json 2>$null }
  $txt = ($raw | Where-Object { $_ -is [string] }) -join "`n"
  $i = $txt.IndexOf('['); if ($i -lt 0) { return @() }
  return ,@($txt.Substring($i) | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object {
    $r = if ($_.rule_id) { $_.rule_id } else { $_.rule }
    $p = if ($_.file_path) { $_.file_path } elseif ($_.path) { $_.path } else { $_.file }
    "{0}:{1} {2}" -f (Split-Path $p -Leaf), $_.start_line, $r })
}
function Get-Wanted([string]$Rule) {
  return ,@(Get-ChildItem $Src -Filter *.pas | ForEach-Object { $f = $_; $n = 0
    [IO.File]::ReadAllLines($f.FullName, [Text.Encoding]::GetEncoding(28591)) | ForEach-Object { $n++; if ($_ -match "// FIRE $Rule\b") { "{0}:{1} {2}" -f $f.Name, $n, $Rule } } })
}
function Compare-Rule([string]$Rule) {
  $want = Get-Wanted $Rule
  $got  = Get-Found @('lint-all', '--db', $Db, '--config', $Cfg, '--rule', $Rule)
  Check "$Rule has firing controls" ($want.Count -gt 0)
  foreach ($w in $want) { Check "fires $w" ($got -contains $w) }
  $extra = @($got | Where-Object { $want -notcontains $_ })
  Check "$Rule is silent elsewhere" ($extra.Count -eq 0) ($extra -join ', ')
}

Write-Host 'THE SIX RULES' -ForegroundColor Cyan
foreach ($r in 'duplicate-logical-operand', 'contradictory-condition', 'boolean-comparison-precedence',
               'function-name-reads-itself', 'warnings-off-not-restored', 'homoglyph-identifier') { Compare-Rule $r }

Write-Host 'THE CATALOG' -ForegroundColor Cyan
$rulesTxt = (& { $ErrorActionPreference = 'Continue'; & $Exe rules --json 2>$null } | Where-Object { $_ -is [string] }) -join "`n"
foreach ($r in 'duplicate-logical-operand', 'contradictory-condition', 'boolean-comparison-precedence',
               'function-name-reads-itself', 'warnings-off-not-restored', 'homoglyph-identifier') {
  Check "rules lists $r" ($rulesTxt -match [regex]::Escape("`"$r`""))
}

Write-Host 'LINT OF ONE FILE WITHOUT THE INDEX' -ForegroundColor Cyan
$Other = Join-Path $WorkDir 'other'
New-Item -ItemType Directory $Other | Out-Null
[IO.File]::WriteAllText((Join-Path $Other 'Lone.pas'), "unit Lone;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
$OtherDb = Join-Path $WorkDir 'other.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $Other --db $OtherDb 2>&1 | ForEach-Object { "$_" } } | Out-Null
$one = Get-Found @('lint', (Join-Path $Src 'LogicCases.pas'), '--db', $OtherDb, '--config', $Cfg, '--rule', 'contradictory-condition')
Check 'the tree rules need no index' ($one.Count -eq 5) ($one -join ', ')

if ($script:Failed) { Write-Host ("FAIL ({0} checks)" -f $script:Checks) -ForegroundColor Red; exit 1 }
Write-Host ("PASS ({0} checks)" -f $script:Checks) -ForegroundColor Green
exit 0
} finally {
  if (($WorkDir -like "$env:TEMP\drag-lint-v154-expr-*") -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
