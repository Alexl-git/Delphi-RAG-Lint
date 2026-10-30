<#
  run_file_lookup_8dot3.ps1 -- a file indexed under one spelling of its path
  must be found under another (Gitea drag-lint#26, #23).

  THE DEFECT. Windows names a file by its long path and by 8.3 short
  components (C:\Users\JONATH~1.SIL\... for C:\Users\jonathas.silva\...), and a
  path can MIX them. An index stores paths as the run that built it was given
  -- %TEMP% hands out a short first component on some machines -- and a later
  lookup arrives in another mix (a process CWD is reported long).
  FindFileIdByPath compared text, so the two never matched: convert-apply said
  "MyForm.pas is not covered by any supplied --db" about a file the --db held,
  converted nothing, wrote no backup and exited 0 (run_convert_apply,
  run_convert_apply_multidb), and `lint --db` ran store-free on it.

  The fixture lives in a folder with a LONG name and is indexed through its
  8.3 SHORT spelling; the lookups use the long spelling.

  WHAT THIS ASSERTS
    1. the database holds the short spelling (the premise -- else nothing below
       tests anything)
    2. lint <long path> --db: the store-backed rules ran ("project rules ran"),
       not "no index covers this file"                                <- THE FIX
    3. CONTROL: lint <short path> --db (the stored spelling) -- the same
    4. CONTROL: a path the database does NOT hold still is not covered

  SKIP (exit 77) when the volume does not generate 8.3 names: no short
  spelling exists, so the defect cannot occur there.
  RED-CHECK: against the pre-fix build 2 FAILS; 1, 3 and 4 pass on both.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

# A long folder name, so 8.3 generation (when enabled) gives it a short alias.
$longDir = Join-Path C:\TEMP ("draglint lookup long folder name $PID")
New-Item -ItemType Directory $longDir -Force | Out-Null
$shortDir = (cmd /c "for %I in (`"$longDir`") do @echo %~sI").Trim()
if (($shortDir -eq '') -or ($shortDir -ieq $longDir) -or ($shortDir -notmatch '~')) {
  Write-Host "SKIP: no 8.3 short name for $longDir (8.3 generation is off on this volume) -- the defect cannot occur here" -ForegroundColor Yellow
  exit 77
}
Write-Host "long : $longDir" -ForegroundColor DarkGray
Write-Host "short: $shortDir" -ForegroundColor DarkGray

Write-Ascii (Join-Path $longDir 'L.dpr') @'
program L;

uses
  ULook in 'ULook.pas';

begin
end.
'@
Write-Ascii (Join-Path $longDir 'ULook.pas') @'
unit ULook;

interface

procedure Look;

implementation

procedure Look;
begin
end;

end.
'@
$db = Join-Path $longDir 'l.sqlite'
& $Exe index --project (Join-Path $shortDir 'L.dpr') --db $db *> $null
Check 'seed: index through the short spelling' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$stored = (& $Exe sql --db $db --query "select path from files where path like '%ULook.pas'" 2>$null) -join "`n"
Check '1. the database holds the SHORT spelling (premise)' ($stored -match '~') $stored

function NoteFor([string]$file) { return ((& $Exe lint $file --db $db 2>&1) -join "`n") }
$long = NoteFor (Join-Path $longDir 'ULook.pas')
Check '2. lint <long path> --db runs store-backed ("project rules ran")' `
  (($long -match 'project rules ran for this file') -and -not ($long -match 'no index covers this file')) ''
$short = NoteFor (Join-Path $shortDir 'ULook.pas')
Check '3. CONTROL: lint <short path> --db runs store-backed too' ($short -match 'project rules ran for this file') ''
$other = Join-Path $longDir 'Unindexed.pas'
Write-Ascii $other "unit Unindexed;`n`ninterface`n`nimplementation`n`nend.`n"
$o4 = NoteFor $other
Check '4. CONTROL: a file the database does not hold is still not covered' ($o4 -match 'no index covers this file') ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @(Join-Path C:\TEMP ("draglint lookup long folder name $PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
