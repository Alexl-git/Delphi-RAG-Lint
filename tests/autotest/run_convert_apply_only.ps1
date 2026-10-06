<#
  run_convert_apply_only.ps1 -- the convert-apply --only contract (C13, the
  converter's C12 asks N3 and N4; 1.23.0).

  N3. --only takes instance names. A name is matched case-insensitively (the
  IDE's spelling may differ from the .dfm's after a hand edit). A name that
  names no .dfm object of a #convert From type is IGNORED -- no error, exit
  unchanged -- and reported: apply/1 carries only_matched[] and
  only_unmatched[] (strings, spelled as given, in --only order; ALWAYS present,
  [] without --only), and text mode prints one '--only: no #convert instance
  named <names> (ignored)' line.

  N4. With --only, a #unuse / #useswap removal that would strand ONLY instances
  --only left out is skipped rather than refusing the unit (uses[] action
  'skipped'); info --json advertises capabilities.only_skips_unit_rules. The
  detailed R26 arms live in run_convert_apply_unit_rules.ps1; this suite pins
  the converter's own acceptance shape: --only btnOne --apply converts btnOne,
  leaves btnTwo and the LibA uses entry, exit 0; without --only both convert
  and LibA goes.

  Fixtures: tests\autotest\fixtures\unitrules (R26Form: btnOne, btnTwo, both
  TSrcBtn, declared in LibA), COPIED to a $PID scratch folder.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_apply_only_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures\unitrules\*') $WorkDir

$db = Join-Path $WorkDir 'fx.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'V the fixture index was built' (Test-Path $db)

function P([string]$n) { return (Join-Path $WorkDir $n) }
function Text([string]$n) { return [IO.File]::ReadAllText((P $n)) }
function Apply([string]$Unit, [string]$Rules, [string[]]$Extra = @()) {
  $o = (& $Exe @(@('convert-apply', '--unit', (P $Unit), '--rules', (P $Rules), '--db', $db) + $Extra) 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Arr($v) { return ((@($v) | ForEach-Object { [string]$_ }) -join ',') }

# ---- N3 -----------------------------------------------------------------------
$r = Apply 'R26Form.pas' 'r26convert.rules' @('--only', 'btnOne', '--format', 'json')
$j = Json $r.Out
Check 'N3a --only btnOne: exit 0, one instance converted, only_matched = [btnOne], only_unmatched = []' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 1) -and ((Arr $j.only_matched) -eq 'btnOne') -and `
   ($j.PSObject.Properties.Name -contains 'only_unmatched') -and (@($j.only_unmatched).Count -eq 0)) $r.Out
$r = Apply 'R26Form.pas' 'r26convert.rules' @('--only', 'btnOne,Nope', '--format', 'json')
$j = Json $r.Out
Check 'N3b --only btnOne,Nope: exit 0, one converted, only_matched = [btnOne], only_unmatched = [Nope]' `
  (($r.Code -eq 0) -and ($null -ne $j) -and $j.ok -and (@($j.converted).Count -eq 1) -and ((Arr $j.only_matched) -eq 'btnOne') -and ((Arr $j.only_unmatched) -eq 'Nope')) $r.Out
$r = Apply 'R26Form.pas' 'r26convert.rules' @('--only', 'BTNONE', '--format', 'json')
$j = Json $r.Out
Check 'N3c --only BTNONE (case differs): btnOne converts; matched spelled as given' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 1) -and ($j.converted[0] -match 'btnOne') -and ((Arr $j.only_matched) -eq 'BTNONE')) $r.Out
$r = Apply 'R26Form.pas' 'r26convert.rules' @('--format', 'json')
$j = Json $r.Out
Check 'N3d no --only: both keys present and [], both instances converted' `
  (($r.Code -eq 0) -and ($null -ne $j) -and ($j.PSObject.Properties.Name -contains 'only_matched') -and (@($j.only_matched).Count -eq 0) -and `
   (@($j.only_unmatched).Count -eq 0) -and (@($j.converted).Count -eq 2)) $r.Out
$r = Apply 'R26Form.pas' 'r26convert.rules' @('--only', 'btnOne,Nope,Zip')
Check 'N3e text: one "--only: no #convert instance named Nope, Zip (ignored)" line, exit 0' `
  (($r.Code -eq 0) -and ($r.Out -match '(?m)^--only: no #convert instance named Nope, Zip \(ignored\)\r?$')) $r.Out
$r = Apply 'R26Form.pas' 'r26convert.rules' @('--only', 'Nope', '--format', 'json')
$j = Json $r.Out
Check 'N3f --only naming nothing at all: only_unmatched = [Nope], only_matched = [] (the exit is the zero-instance one, unchanged)' `
  (($null -ne $j) -and (@($j.only_matched).Count -eq 0) -and ((Arr $j.only_unmatched) -eq 'Nope')) $r.Out

# ---- N4 -----------------------------------------------------------------------
$j = Json ((& $Exe info --json 2>&1) -join "`n")
Check 'N4a info --json: capabilities.only_skips_unit_rules is JSON true' `
  (($null -ne $j) -and ($j.capabilities.only_skips_unit_rules -is [bool]) -and ($j.capabilities.only_skips_unit_rules -eq $true)) `
  "capabilities = $(if ($j) { $j.capabilities | ConvertTo-Json -Compress } else { '<no json>' })"
# control FIRST (dry run, file untouched): without --only both convert and the
# #unuse LibA removal is planned -- no skip
$r = Apply 'R26Form.pas' 'r26unuse.rules' @('--format', 'json')
$j = Json $r.Out
Check 'N4e control, no --only: both converted, the LibA removal planned, no skipped row' `
  (($r.Code -eq 0) -and ($null -ne $j) -and (@($j.converted).Count -eq 2) -and ($j.uses_removed -eq 1) -and `
   (@($j.uses | Where-Object { ($_.action -eq 'remove') -and ($_.unit -eq 'LibA') }).Count -eq 1) -and `
   (@($j.uses | Where-Object { $_.action -eq 'skipped' }).Count -eq 0)) $r.Out
$r = Apply 'R26Form.pas' 'r26unuse.rules' @('--only', 'btnOne', '--apply', '--no-backup', '--format', 'json')
$j = Json $r.Out
$t = Text 'R26Form.pas'
Check 'N4b --only btnOne --apply + #unuse LibA: exit 0, btnOne converted, btnTwo and LibA left' `
  (($r.Code -eq 0) -and ($t -match 'btnOne: TDstBtn;') -and ($t -match 'btnTwo: TSrcBtn;') -and ($t -match '\bLibA\b') -and ($t -match '\bLibB\b')) ($r.Out + "`n" + $t)
Check 'N4c ... uses[] carries {action skipped, unit LibA, rule #unuse LibA, reason}' `
  (($null -ne $j) -and (@($j.uses | Where-Object { ($_.action -eq 'skipped') -and ($_.unit -eq 'LibA') -and ($_.rule -eq '#unuse LibA') -and `
     ($_.reason -eq 'would leave 1 unconverted instance(s) of TSrcBtn') }).Count -eq 1)) $r.Out
Check 'N4d ... and a "line 3: warning:" line in warnings[]' `
  (($null -ne $j) -and (@($j.warnings | Where-Object { $_ -match '^line 3: warning: #unuse LibA skipped' }).Count -eq 1)) $r.Out

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_apply_only_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
