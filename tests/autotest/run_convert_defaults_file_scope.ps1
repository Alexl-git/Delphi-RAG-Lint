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
  and the ignored keys -- unless one of them is "db" or "project" and no --db
  was given: then it is an ERROR, exit 3 (B1c/B3; B4 is the positive control).
  Every other verb is unchanged (control C1).
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

Write-Ascii (Join-Path $subDb 'use.rules') "#use Classes`r`n"
# a project key, in its own tree
$withProj = Join-Path $WorkDir 'withproj'; $subProj = Join-Path $withProj 'sub'
New-Item -ItemType Directory $subProj -Force | Out-Null
Write-Ascii (Join-Path $withProj '.drag-lint.json') '{ "project": "C:\\nowhere\\x.dproj" }'
Copy-Item (Join-Path $subDb 'U.pas'), (Join-Path $subDb 'r.rules') $subProj
# a REAL index of U.pas for the positive control (built outside the tree with the file)
$uDb = Join-Path $WorkDir 'u.sqlite'
& $Exe index $subDb --db $uDb 2>&1 | Out-Null
function Run([string]$Cwd, [string[]]$A) {
  Push-Location $Cwd
  try { $o = (& $Exe @A 2>&1 | ForEach-Object { "$_" }) -join "`n"; $script:LastExit = $LASTEXITCODE } finally { Pop-Location }
  return $o
}

# ---- C1 CONTROL: a non-convert verb still loads the file -------------------
$ctl = Run $subDb @('--version')
Check 'C1 CONTROL a non-convert verb still loads the defaults file and says so' `
      ($ctl -match [regex]::Escape("(loaded defaults from $withDb\.drag-lint.json)")) $ctl

# ---- B1: a "db" key with NO explicit --db is an ERROR, not a silent fallback --
# Ignoring the file and auto-selecting an index could rewrite the form on a
# DIFFERENT database than the one the file names; the operator must choose.
$b1 = Run $subDb @('convert-apply', '--unit', 'U.pas', '--rules', 'r.rules')
$b1Exit = $script:LastExit
Check 'B1 convert-apply prints no "(loaded defaults" banner' (-not ($b1 -match '\(loaded defaults from')) $b1
Check 'B1b the config "db" is NOT used as an explicit --db' (-not ($b1 -match ('--db #\d+ of \d+ does not exist: ' + [regex]::Escape($cfgDb)))) $b1
Check 'B1c no --db + a "db" key in the ignored file -> exit 3' ($b1Exit -eq 3) "exit=$b1Exit`n$b1"
Check 'B1d the error names the file, the key and --db' `
      (($b1 -match [regex]::Escape("$withDb\.drag-lint.json")) -and ($b1 -match '"db"') -and ($b1 -match '--db explicitly')) $b1

# ---- B3: a "project" key is the same refusal ---------------------------------
$b3 = Run $subProj @('convert-apply', '--unit', 'U.pas', '--rules', 'r.rules')
Check 'B3 no --db + a "project" key in the ignored file -> exit 3, naming "project"' `
      (($script:LastExit -eq 3) -and ($b3 -match '"project"')) "exit=$($script:LastExit)`n$b3"

# ---- B4 POSITIVE CONTROL: with an explicit --db the same file is only a NOTE --
# and the verb runs to completion. Without this, B1c could pass because every
# convert-apply in this folder fails.
$b4 = Run $subDb @('convert-apply', '--unit', 'U.pas', '--rules', 'use.rules', '--db', $uDb)
Check 'B4 POSITIVE CONTROL explicit --db: convert-apply runs (exit 0)' ($script:LastExit -eq 0) "exit=$($script:LastExit)`n$b4"
Check 'B4b and the ignored file is named in one note' `
      ($b4 -match ('(?i)note: ignoring "db" in ' + [regex]::Escape("$withDb\.drag-lint.json"))) $b4

# ---- B5: the verb is the PARSED one -- a flag before it does not slip past ---
# The parser takes token 1 as the verb, so `--quiet convert-apply` is not a
# convert run at all: it must not convert, and must not use the config "db".
$b5 = Run $subDb @('--quiet', 'convert-apply', '--unit', 'U.pas', '--rules', 'use.rules')
Check 'B5 a leading flag does not run convert-apply on the config db' `
      ((-not ($b5 -match 'convert-apply: ')) -and (-not ($b5 -match [regex]::Escape($cfgDb)))) $b5
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
