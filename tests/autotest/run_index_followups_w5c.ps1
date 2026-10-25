<#
run_index_followups_w5c.ps1 -- two `index` defects found by the W4-cfg lane (wave 5, W5-C).

  A  `index --dry-run` must not touch the disk. It used to create the _D-RAG home and the
     DB file (and Migrate / stamp an existing one) before it reached the dry-run exit.
       A1  --db in a directory that does not exist yet: after --dry-run neither dir nor file exists
       A2  an existing DB file: SHA-256 identical after --dry-run
       A+  POSITIVE CONTROL: the same command without --dry-run DOES create the DB file
  B  a .drag-lint.json "path" key must not swallow the POSITIONAL path. The config is loaded
     first, Path was then non-empty, and the positional fell to "Unknown argument".
       B   index <positional dir> under "path": <other dir> -- positional wins (Database: names it)
       B+  POSITIVE CONTROL: index with no positional still takes the config path
       B2  --dir after a config path wins too

Usage: pwsh -NoProfile -File tests\autotest\run_index_followups_w5c.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-w5c-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) {'PASS'} else {'FAIL'}
  $color  = if ($Ok) {'Green'} else {'Red'}
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
  Write-Host "  [FAIL] engine not found: $Exe" -ForegroundColor Red
  exit 1
}
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$Ascii = [Text.Encoding]::ASCII
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), $Ascii)
}
function Invoke-Dl([string]$Cwd, [string[]]$Arguments) {
  $o = "$WorkDir\o.txt"; $e = "$WorkDir\e.txt"
  $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -WorkingDirectory $Cwd `
         -RedirectStandardOutput $o -RedirectStandardError $e
  [pscustomobject]@{
    Exit = $p.ExitCode
    Out  = [IO.File]::ReadAllText($o)
    Err  = [IO.File]::ReadAllText($e)
  }
}
try {
  New-Item -ItemType Directory -Path "$WorkDir\src", "$WorkDir\cfg\app", "$WorkDir\cfg\other" -Force | Out-Null
  Write-Ascii "$WorkDir\src\U1.pas" "unit U1;`ninterface`nimplementation`nend.`n"
  Write-Ascii "$WorkDir\cfg\app\A1.pas" "unit A1;`ninterface`nimplementation`nend.`n"
  Write-Ascii "$WorkDir\cfg\other\O1.pas" "unit O1;`ninterface`nimplementation`nend.`n"

  # --- A : dry run writes nothing -------------------------------------------
  $db1 = "$WorkDir\newhome\a1.sqlite"
  $a1 = Invoke-Dl $WorkDir @('index', "$WorkDir\src", '--db', $db1, '--dry-run')
  Check 'A1: --dry-run exits 0' ($a1.Exit -eq 0) "exit=$($a1.Exit) err='$($a1.Err.Trim())'"
  Check 'A1: --dry-run created no DB home dir' (-not (Test-Path -LiteralPath "$WorkDir\newhome"))
  Check 'A1: --dry-run created no DB file' (-not (Test-Path -LiteralPath $db1))

  $db2 = "$WorkDir\a2.sqlite"
  $null = Invoke-Dl $WorkDir @('index', "$WorkDir\src", '--db', $db2)
  Check 'A+: index without --dry-run creates the DB file' (Test-Path -LiteralPath $db2)
  $h0 = (Get-FileHash -LiteralPath $db2 -Algorithm SHA256).Hash
  Write-Ascii "$WorkDir\src\U2.pas" "unit U2;`ninterface`nimplementation`nend.`n"
  $a2 = Invoke-Dl $WorkDir @('index', "$WorkDir\src", '--db', $db2, '--dry-run')
  $h1 = (Get-FileHash -LiteralPath $db2 -Algorithm SHA256).Hash
  Check 'A2: --dry-run left an existing DB byte-identical' ($h0 -eq $h1) "exit=$($a2.Exit)"

  # --- B : positional beats the "path" defaults key --------------------------
  $esc = $WorkDir -replace '\\', '\\'
  [IO.File]::WriteAllText("$WorkDir\cfg\.drag-lint.json", ('{"path":"' + $esc + '\\cfg\\other"}'), $Ascii)
  $b = Invoke-Dl "$WorkDir\cfg" @('index', "$WorkDir\cfg\app", '--dry-run')
  Check 'B: positional dir beats config "path" -- run succeeds' ($b.Exit -eq 0) "exit=$($b.Exit) out='$($b.Out.Trim() -replace '\s+',' ')' err='$($b.Err.Trim())'"
  Check 'B: positional dir beats config "path" -- Database names app, not other' ($b.Out -match 'Database: .*\\app\\' -and $b.Out -notmatch 'Database: .*\\other\\')
  $bp = Invoke-Dl "$WorkDir\cfg" @('index', '--dry-run')
  Check 'B+: no positional -- config "path" still applies' ($bp.Out -match 'Database: .*\\other\\') "exit=$($bp.Exit) out='$($bp.Out.Trim() -replace '\s+',' ')'"
  $b2 = Invoke-Dl "$WorkDir\cfg" @('index', '--dir', "$WorkDir\cfg\app", '--dry-run')
  Check 'B2: --dir beats config "path"' ($b2.Out -match 'Database: .*\\app\\') "exit=$($b2.Exit)"
}
finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'run_index_followups_w5c: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_index_followups_w5c: PASS' -ForegroundColor Green
exit 0
