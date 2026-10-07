<#
  run_convert_defaults_file_scope.ps1 --
  convert-* verbs do NOT read a `.drag-lint.json` defaults file (1.26.2).

  THE DEFECT (converter team): every run of a STAGED, PINNED engine copy printed
  `(loaded defaults from C:\Projects\.drag-lint.json)`. The defaults file is
  found by walking up from the CWD, not from the exe, so a pin in C:\TEMP run
  from a project folder under C:\Projects picked up the machine-wide file. That
  one happens to contribute nothing; a "db" key in it would have become an
  EXPLICIT --db for convert-apply (a config "db" counts as explicit), so a
  shared file could silently choose the index a conversion rewrites a form on.

  THE RULE: a convert-* verb takes its databases, rules and units from its own
  command line only. A defaults file above the CWD is not loaded; when it holds
  a key the defaults reader would have applied, one stderr note names the file
  and the ignored keys. Every other verb is unchanged (control C1).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_convert_defaults_scope_$PID"
)
try {
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }

# withdb\.drag-lint.json carries a "db"; inert\.drag-lint.json carries nothing
# the defaults reader applies -- the shape of the real C:\Projects one.
$withDb = Join-Path $WorkDir 'withdb'; $inert = Join-Path $WorkDir 'inert'
$subDb = Join-Path $withDb 'sub'; $subInert = Join-Path $inert 'sub'
foreach ($d in @($subDb, $subInert)) { New-Item -ItemType Directory $d -Force | Out-Null }
$cfgDb = Join-Path $withDb 'from-config.sqlite'
Write-Ascii (Join-Path $withDb '.drag-lint.json') ('{ "db": "' + ($cfgDb -replace '\\','\\') + '" }')
Write-Ascii (Join-Path $inert '.drag-lint.json') '{ "_comment": ["nothing the defaults reader applies"], "scan": { "library": true } }'
Write-Ascii (Join-Path $subDb 'U.pas') "unit U;`r`ninterface`r`nimplementation`r`nend.`r`n"
Write-Ascii (Join-Path $subDb 'r.rules') "#convert TA -> TB, UB`r`n"

function Run([string]$Cwd, [string[]]$A) {
  Push-Location $Cwd
  try { $o = (& $Exe @A 2>&1 | ForEach-Object { "$_" }) -join "`n" } finally { Pop-Location }
  return $o
}

# ---- C1 CONTROL: a non-convert verb still loads the file -------------------
$ctl = Run $subDb @('--version')
Check 'C1 CONTROL a non-convert verb still loads the defaults file and says so' `
      ($ctl -match [regex]::Escape("(loaded defaults from $withDb\.drag-lint.json)")) $ctl

# ---- B1: a "db" key does NOT become convert-apply's --db --------------------
$b1 = Run $subDb @('convert-apply', '--unit', 'U.pas', '--rules', 'r.rules')
Check 'B1 convert-apply prints no "(loaded defaults" banner' (-not ($b1 -match '\(loaded defaults from')) $b1
Check 'B1b the config "db" is NOT used as an explicit --db' (-not ($b1 -match ('--db #\d+ of \d+ does not exist: ' + [regex]::Escape($cfgDb)))) $b1
Check 'B1c one note names the file and the ignored key' `
      ($b1 -match ('(?i)ignor[^\n]*' + [regex]::Escape("$withDb\.drag-lint.json") + '[^\n]*\bdb\b')) $b1

# ---- B2: a file contributing nothing is silent for convert-* ----------------
$b2 = Run $subInert @('convert-validate', '--rules', 'nosuch.rules', '--db', 'nosuch.sqlite')
Check 'B2 an inert defaults file is silent for convert-validate (no banner, no note)' `
      (-not ($b2 -match '\(loaded defaults from|drag-lint\.json')) $b2

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  foreach ($d23 in @("C:\TEMP\draglint_convert_defaults_scope_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
