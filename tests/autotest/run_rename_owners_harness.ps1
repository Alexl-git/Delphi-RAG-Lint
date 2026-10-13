<#
  run_rename_owners_harness.ps1 -- pins tri-state DB membership and rename-owner
  discovery by FULL PATH (spec 2026-10-13-multi-project-rename, criteria 8a-8d).

  WHAT IT PINS
    * DbMembership answers member / notmember / unknown, and a DB it cannot
      open (garbage bytes, or no file at all) is UNKNOWN -- never "not an
      owner" (8c). The old Boolean DbContainsFile folded both into False.
    * A DB holding a DIFFERENT file with the same unit name (twin\uShared.pas)
      is not an owner (8a); a differently-cased spelling of the right path is.
    * FindRenameOwners probes EVERY manifest DB for the platform (8b), returns
      owners in plan order with the preferred DB first, keeps a library owner
      with Kind=library so the caller can refuse it (8d), and lists the DBs it
      could not read instead of dropping them (8c).

  ISOLATION: every DB is built under $env:TEMP\draglint-owners-<guid> with an
  explicit --db; the manifest is parsed from text by the harness (no manifest
  discovery). The last check proves a real project DB was not touched.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe        = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$FixtureDir = "$PSScriptRoot\fixtures\renameowners",
  [string]$WorkDir    = "$env:TEMP\draglint-owners-$([guid]::NewGuid().ToString('N'))"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAscii($path, $lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
}

$RealDb = 'C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite'
$realBefore = if (Test-Path $RealDb) { $i = Get-Item $RealDb; "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' }

Write-Host '== Rename owners: tri-state membership + discovery by full path ==' -ForegroundColor Cyan
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory $WorkDir | Out-Null
foreach ($d in 'shared', 'twin', 'A', 'T') { New-Item -ItemType Directory "$WorkDir\$d" | Out-Null }

# --- fixture sources: one unit name, two different files ---
$unit = @('unit uShared;', '', 'interface', '', 'const', '  My_Const = 1;', '', 'implementation', '', 'end.')
WriteAscii "$WorkDir\shared\uShared.pas" $unit
WriteAscii "$WorkDir\twin\uShared.pas"   $unit
WriteAscii "$WorkDir\A\A.dpr" @('program A;', '', 'uses', "  uShared in '..\shared\uShared.pas';", '', 'begin', 'end.')
WriteAscii "$WorkDir\T\T.dpr" @('program T;', '', 'uses', "  uShared in '..\twin\uShared.pas';", '', 'begin', 'end.')

# --- fixture DBs, each with an explicit --db, cwd inside the work folder ---
Push-Location $WorkDir
try {
  $null = & $Exe index --project "$WorkDir\A\A.dpr" --db "$WorkDir\A.sqlite" 2>&1
  Check 'F1 indexed A.dpr' ($LASTEXITCODE -eq 0 -and (Test-Path "$WorkDir\A.sqlite")) "exit=$LASTEXITCODE"
  $null = & $Exe index --project "$WorkDir\T\T.dpr" --db "$WorkDir\T.sqlite" 2>&1
  Check 'F2 indexed T.dpr' ($LASTEXITCODE -eq 0 -and (Test-Path "$WorkDir\T.sqlite")) "exit=$LASTEXITCODE"
  # a LIBRARY-type DB: a folder target is valid for a library DB (never for a project DB)
  $null = & $Exe index "$WorkDir\shared" --db "$WorkDir\LIB.sqlite" 2>&1
  Check 'F3 indexed shared\ as a library DB' ($LASTEXITCODE -eq 0 -and (Test-Path "$WorkDir\LIB.sqlite")) "exit=$LASTEXITCODE"
} finally { Pop-Location }
[System.IO.File]::WriteAllBytes("$WorkDir\bad.sqlite", [byte[]](,0xFF * 64))

# --- manifests, parsed from text by the harness ---
$j = ($WorkDir -replace '\\', '\\')
WriteAscii "$WorkDir\owners.json" @(
  '{ "indexes": { "sections": ['
  "  { `"name`": `"A`",   `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$j\\A.sqlite`" },"
  "  { `"name`": `"T`",   `"include`": [`"$j\\T\\T.dpr`"], `"db`": `"$j\\T.sqlite`" },"
  "  { `"name`": `"LIB`", `"source`": `"registry-libraries`", `"platforms`": [`"Win64`"], `"db`": `"$j\\LIB.sqlite`" }"
  ']}}')
WriteAscii "$WorkDir\unknown.json" @(
  '{ "indexes": { "sections": ['
  "  { `"name`": `"A`",   `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$j\\A.sqlite`" },"
  "  { `"name`": `"A2`",  `"include`": [`"$j\\A\\A.dpr`"], `"db`": `"$($j.ToUpper())\\A.SQLITE`" },"
  "  { `"name`": `"BAD`", `"include`": [`"$j\\T\\T.dpr`"], `"db`": `"$j\\bad.sqlite`" }"
  ']}}')

# --- build the harness (bare .dpr: dcc64 with the CLI dproj's search path) ---
$rsvars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
. (Join-Path $PSScriptRoot 'lib\CliBuildPaths.ps1')
$uArgs  = (Get-CliDcc64Args).Args
$outDir = "$FixtureDir\Win64\Debug"
New-Item -ItemType Directory -Force $outDir | Out-Null
$batPath = "$WorkDir\build_harness.bat"
$logPath = "$WorkDir\build_harness.log"
WriteAscii $batPath @(
  '@echo off'
  "call `"$rsvars`""
  "cd /d `"$FixtureDir`""
  "dcc64 -CC $uArgs -E`"$outDir`" -N0`"$outDir`" RenameOwnersHarness.dpr"
  'echo BUILD_EXITCODE=%ERRORLEVEL%')
$null = Start-Process cmd.exe -ArgumentList "/c", "`"$batPath`"" `
          -RedirectStandardOutput $logPath -RedirectStandardError "$logPath.err" -NoNewWindow -Wait -PassThru
$log = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
$buildOk = ($log -match 'BUILD_EXITCODE=0') -and ($log -notmatch 'Error:')
$errLines = ($log -split "`r?`n" | Where-Object { $_ -match 'Error|Fatal' } | Select-Object -First 4) -join ' | '
Check 'B1 RenameOwnersHarness.dpr builds (Win64 Debug)' $buildOk $errLines
$hx = "$outDir\RenameOwnersHarness.exe"
if (-not $buildOk -or -not (Test-Path $hx)) { [System.IO.Directory]::Delete($WorkDir, $true); Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$out = & $hx $WorkDir 2>&1 | Out-String
$kv = @{}
foreach ($line in ($out -split "`r?`n")) { if ($line -match '^([A-Za-z0-9_.]+)=(.*)$') { $kv[$matches[1]] = $matches[2] } }
Check 'H1 harness ran to completion' ($out -match '(?m)^DONE') ($kv['EXCEPTION'])

Write-Host '-- DbMembership (8a, 8c)' -ForegroundColor Cyan
Check 'M1 the DB whose closure holds the file is a member'           ($kv['A'] -eq 'member')          "got: $($kv['A']) $($kv['A.reason'])"
Check 'M2 ... also when the caller spells the path in another case' ($kv['A_upper'] -eq 'member')    "got: $($kv['A_upper'])"
Check 'M3 same unit NAME at another path is not a member'           ($kv['T'] -eq 'notmember')       "got: $($kv['T'])"
Check 'M4 an unopenable DB is unknown, not notmember'               ($kv['bad'] -eq 'unknown')       "got: $($kv['bad'])"
Check 'M5 ... and says why'                                        ($kv['bad.reason'] -ne '')        "got: $($kv['bad.reason'])"
Check 'M6 a DB file that does not exist is unknown'                ($kv['missing'] -eq 'unknown')   "got: $($kv['missing'])"
Check 'M7 ... with reason "db file not found"'                     ($kv['missing.reason'] -eq 'db file not found') "got: $($kv['missing.reason'])"
Check 'M8 a definite answer carries no reason'                     (($kv['A.reason'] -eq '') -and ($kv['T.reason'] -eq '')) ''

Write-Host '-- FindRenameOwners (8a, 8b, 8c, 8d)' -ForegroundColor Cyan
Check 'O1 every manifest DB for the platform is probed'             ($kv['probed'] -eq '3')                  "got: $($kv['probed'])"
Check 'O2 owners by full path, plan order (twin T excluded)'        ($kv['owners'] -eq 'A,LIB')              "got: $($kv['owners'])"
Check 'O3 a library owner is kept and marked library'               ($kv['owner_kinds'] -eq 'project,library') "got: $($kv['owner_kinds'])"
Check 'O4 the project owner carries its project file'               ($kv['owner_projfile.0'] -eq "$WorkDir\A\A.dpr") "got: $($kv['owner_projfile.0'])"
Check 'O5 a library owner has no project file'                      ($kv['owner_projfile.1'] -eq '')         "got: $($kv['owner_projfile.1'])"
Check 'O6 nothing unknown when every DB opened'                     ($kv['unknown_count'] -eq '0')           "got: $($kv['unknown_count'])"
Check 'O7 the preferred DB is listed first'                         ($kv['owners_pref'] -eq 'LIB,A')         "got: $($kv['owners_pref'])"
Check 'O8 the same DB under two spellings is probed once'           ($kv['u.probed'] -eq '2')                "got: $($kv['u.probed'])"
Check 'O9 ... and owns once'                                        ($kv['u.owners'] -eq 'A')                "got: $($kv['u.owners'])"
Check 'O10 an unreadable DB is reported unknown, not dropped'       ($kv['u.unknown_count'] -eq '1')         "got: $($kv['u.unknown_count'])"
Check 'O11 ... as "dbpath: reason"' ($kv['u.unknown.0'] -like "$WorkDir\bad.sqlite: ?*") "got: $($kv['u.unknown.0'])"

$realAfter = if (Test-Path $RealDb) { $i = Get-Item $RealDb; "$($i.Length)|$($i.LastWriteTimeUtc.Ticks)" } else { 'absent' }
Check 'Z1 a real project DB was not touched (size+mtime)' ($realBefore -eq $realAfter) "$realBefore -> $realAfter"

[System.IO.Directory]::Delete($WorkDir, $true)
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
