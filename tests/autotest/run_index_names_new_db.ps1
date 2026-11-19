<#
  run_index_names_new_db.ps1 -- an `index <folder>` with no --db that is about to CREATE a database says
  so (ORM3DB-WRITER). The `Database:` line itself is unchanged.
    a. first run, no --db, DB absent -> a "(new database: ..." line follows the Database: line
    b. second run, DB exists          -> no such line (control: the line is not printed unconditionally)
    c. explicit --db to a new file    -> no such line (the user named it)
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exeSrc = (Resolve-Path $Exe).Path; $exeSrcDir = Split-Path -Parent $exeSrc
$root = "C:\TEMP\draglint_newdb_$PID"
try {
  $eng = "$root\eng"; $src = "$root\proj\src"; $engExe = Join-Path $eng 'drag-lint.exe'
  New-Item -ItemType Directory -Path $eng,$src | Out-Null
  Copy-Item $exeSrc $engExe -Force
  Get-ChildItem $exeSrcDir -Filter '*.dll' | ForEach-Object { Copy-Item $_.FullName "$eng\$($_.Name)" -Force }
  if (Test-Path "$exeSrcDir\rules") { Copy-Item "$exeSrcDir\rules" "$eng\rules" -Recurse -Force }
  [IO.File]::WriteAllText("$src\uA.pas", "unit uA;`r`ninterface`r`nimplementation`r`nend.`r`n", [Text.Encoding]::ASCII)
  Push-Location C:\TEMP
  try {
    $a = (& { $ErrorActionPreference = 'Continue'; & $engExe index "$root\proj" 2>&1 | ForEach-Object { "$_" } } | Out-String)
    Check 'a: Database: line present' ($a -match '(?m)^Database: ') $a
    Check 'a: names the new database' ($a -match '\(new database: this file does not exist yet') $a
    $b = (& { $ErrorActionPreference = 'Continue'; & $engExe index "$root\proj" 2>&1 | ForEach-Object { "$_" } } | Out-String)
    Check 'b: second run (DB exists) does not say new' ($b -notmatch 'new database:') $b
    $c = (& { $ErrorActionPreference = 'Continue'; & $engExe index "$root\proj" --db "$root\named.sqlite" 2>&1 | ForEach-Object { "$_" } } | Out-String)
    Check 'c: explicit --db to a new file is not announced' (($c -match '(?m)^Database: ') -and ($c -notmatch 'new database:')) $c
  } finally { Pop-Location }
} finally { if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) } }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }