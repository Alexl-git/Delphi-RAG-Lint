<#
  run_init_verb.ps1 -- `drag-lint init --project <X.dproj>`: register the project, index it, find its index,
  wire Claude Code + VS Code + Cursor (XERJ item 8). Composed of existing verbs, each a child of the same exe.

  THE REAL USER FILES ARE NEVER TOUCHED. The engine under test is COPIED into a scratch install (its manifest,
  its indexes and its register-project target all live there); --home-dir and --appdata-dir always point into the
  scratch folder; CLAUDE_CONFIG_DIR is removed from this process for the run. The real ~\.claude.json,
  %APPDATA%\Code\User\mcp.json and ~\.cursor\mcp.json are fingerprinted before and after (~\.claude.json is
  rewritten by any running Claude Code session, so there only its "mcpServers" object must be identical).

  Cases
    INIT-USAGE-*    no --project / unknown flag / flag without value / missing project file: usage, exit 2
    INIT-DRY        --dry-run: exit 0, the four steps listed (1/4 .. 4/4), manifest bytes identical, no index
                    file, scratch home/appdata untouched
    INIT-RUN        the same command without --dry-run (POSITIVE CONTROL for INIT-DRY: the manifest changes, the
                    index appears, the three client files appear): exit 0; each client file's entry carries
                    --db <that index>
    INIT-IDEMPOTENT a second run: exit 0, the manifest and the client files byte-identical
    INIT-REAL       the real client files (see above)

  Exit: 0 all PASS, 1 any FAIL, 2 setup.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-init-verb-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Get-Print([string]$Path) { if (Test-Path -LiteralPath $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } else { 'absent' } }
function Get-ServersText([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 'absent' }
  try {
    $n = [System.Text.Json.Nodes.JsonNode]::Parse([IO.File]::ReadAllText($Path))
    $s = $n['mcpServers']; if ($null -eq $s) { 'none' } else { $s.ToJsonString() }
  } catch { 'unparsable' }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$RealClaude = Join-Path $env:USERPROFILE '.claude.json'
$RealVSCode = Join-Path $env:APPDATA 'Code\User\mcp.json'
$RealCursor = Join-Path $env:USERPROFILE '.cursor\mcp.json'
$Before = @{ Claude = Get-ServersText $RealClaude; VSCode = Get-Print $RealVSCode; Cursor = Get-Print $RealCursor }
$PrevCcd = $env:CLAUDE_CONFIG_DIR
Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue

try {
  if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory $WorkDir | Out-Null
  $E64 = Join-Path $WorkDir 'third_party\dll-win64'
  New-Item -ItemType Directory -Force $E64 | Out-Null
  $Proj = Join-Path $WorkDir 'proj'
  New-Item -ItemType Directory $Proj | Out-Null
  WriteAnsi (Join-Path $Proj 'uThing.pas') "unit uThing;`ninterface`nconst`n  Answer = 42;`nimplementation`nend.`n"
  WriteAnsi (Join-Path $Proj 'Thing.dpr') "program Thing;`nuses`n  uThing in 'uThing.pas';`nbegin`nend.`n"
  $ProjFile = Join-Path $Proj 'Thing.dpr'
  $Manifest = Join-Path $E64 'drag-lint.json'
  $outDir = $WorkDir -replace '\\', '\\'
  WriteAnsi $Manifest "{`n  `"settings`": { `"defaultPlatform`": `"Win64`" },`n  `"indexes`": { `"outDir`": `"$outDir`", `"sections`": [] }`n}`n"
  Get-ChildItem (Split-Path $Exe) -File | Where-Object { $_.Extension -in '.exe', '.dll' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $E64 $_.Name) -Force }
  $Eng = Join-Path $E64 'drag-lint.exe'
  $HomeD = Join-Path $WorkDir 'home'
  $App = Join-Path $WorkDir 'appdata'
  New-Item -ItemType Directory -Force (Join-Path $HomeD '.claude'), (Join-Path $HomeD '.cursor'), (Join-Path $App 'Code\User') | Out-Null

  function Invoke-Init([string[]]$A) {
    foreach ($flag in '--home-dir', '--appdata-dir') {
      $i = [array]::IndexOf($A, $flag)
      if ($i -ge 0 -and -not ([IO.Path]::GetFullPath($A[$i + 1]).StartsWith($WorkDir, [StringComparison]::OrdinalIgnoreCase))) { throw "GUARD BUG: $flag outside scratch" }
    }
    if (($A -contains '--project') -and ($A -notcontains '--dry-run') -and ($A -notcontains '--bogus') -and ($A -notcontains '--home-dir' -or $A -notcontains '--appdata-dir') -and (Test-Path -LiteralPath $A[[array]::IndexOf($A, '--project') + 1] -ErrorAction SilentlyContinue)) {
      throw 'GUARD BUG: a real init without scratch --home-dir/--appdata-dir'
    }
    $errFile = Join-Path $WorkDir 'stderr.txt'
    Push-Location $E64
    try { $out = & $Eng init @A 2> $errFile; $code = $LASTEXITCODE } finally { Pop-Location }
    [pscustomobject]@{ Code = $code; Out = (@($out) -join "`n"); Err = [IO.File]::ReadAllText($errFile) }
  }

  Write-Host 'init verb guard' -ForegroundColor Cyan
  $r = Invoke-Init @()
  Check 'INIT-USAGE-NOPROJECT' (($r.Code -eq 2) -and ($r.Err -match 'usage:') -and ($r.Err -match '--project')) "exit=$($r.Code)"
  $r = Invoke-Init @('--project', $ProjFile, '--bogus')
  Check 'INIT-USAGE-BOGUS' (($r.Code -eq 2) -and ($r.Err -match 'unknown flag')) "exit=$($r.Code)"
  $r = Invoke-Init @('--project')
  Check 'INIT-USAGE-NOVALUE' (($r.Code -eq 2) -and ($r.Err -match 'needs a value')) "exit=$($r.Code)"
  $r = Invoke-Init @('--project', (Join-Path $Proj 'Nope.dpr'))
  Check 'INIT-USAGE-MISSING' (($r.Code -eq 2) -and ($r.Err -match 'not found')) "exit=$($r.Code)"

  # ---- INIT-DRY: writes nothing
  $mBefore = Get-Print $Manifest
  $r = Invoke-Init @('--project', $ProjFile, '--dry-run', '--home-dir', $HomeD, '--appdata-dir', $App)
  $steps = @([regex]::Matches($r.Out, '(?m)^\s+([1-4])/4\s') | ForEach-Object { $_.Groups[1].Value }) -join ','
  Check 'INIT-DRY-STEPS' (($r.Code -eq 0) -and ($steps -ceq '1,2,3,4') -and ($r.Out -match 'register-project') -and ($r.Out -match 'index --project') -and ($r.Out -match 'resolve-dbs --project') -and ($r.Out -match 'mcp-config --all')) "exit=$($r.Code) steps=$steps"
  $sq = @(Get-ChildItem -LiteralPath $WorkDir -Recurse -Filter '*.sqlite' -ErrorAction SilentlyContinue)
  $cfiles = @((Join-Path $HomeD '.cursor\mcp.json'), (Join-Path $HomeD '.claude.json'), (Join-Path $App 'Code\User\mcp.json')) | Where-Object { Test-Path -LiteralPath $_ }
  Check 'INIT-DRY-NOWRITE' (((Get-Print $Manifest) -eq $mBefore) -and ($sq.Count -eq 0) -and ($cfiles.Count -eq 0)) "manifest same, $($sq.Count) index, $($cfiles.Count) client file"

  # ---- INIT-RUN: the positive control
  $r = Invoke-Init @('--project', $ProjFile, '--home-dir', $HomeD, '--appdata-dir', $App)
  Check 'INIT-RUN-EXIT' ($r.Code -eq 0) $(if ($r.Code -ne 0) { "exit=$($r.Code) err=$($r.Err)" } else { "exit=0" })
  Check 'INIT-RUN-MANIFEST' ((Get-Print $Manifest) -ne $mBefore) 'the manifest gained the project section'
  $sq = @(Get-ChildItem -LiteralPath $WorkDir -Recurse -Filter '*.sqlite' -ErrorAction SilentlyContinue)
  Check 'INIT-RUN-INDEX' ($sq.Count -eq 1) "$($sq.Count) index file(s): $(($sq | ForEach-Object FullName) -join ';')"
  $db = $(if ($sq.Count -eq 1) { $sq[0].FullName } else { '<none>' })
  $files = [ordered]@{
    Cursor = @{ Path = (Join-Path $HomeD '.cursor\mcp.json'); Key = 'mcpServers' }
    Claude = @{ Path = (Join-Path $HomeD '.claude.json');     Key = 'mcpServers' }
    VSCode = @{ Path = (Join-Path $App 'Code\User\mcp.json'); Key = 'servers' }
  }
  foreach ($k in $files.Keys) {
    $f = $files[$k]
    $arg = $(try { ([System.Text.Json.Nodes.JsonNode]::Parse([IO.File]::ReadAllText($f.Path)))[$f.Key]['drag-lint']['args'].ToJsonString() } catch { '' })
    Check "INIT-RUN-$($k.ToUpper())" ($arg -ceq ('["serve","--db",' + ($db | ConvertTo-Json -Compress) + ']')) "args=$arg"
  }

  # ---- INIT-IDEMPOTENT
  $snap = @{ M = Get-Print $Manifest }
  foreach ($k in $files.Keys) { $snap[$k] = Get-Print $files[$k].Path }
  $r = Invoke-Init @('--project', $ProjFile, '--home-dir', $HomeD, '--appdata-dir', $App)
  $same = (Get-Print $Manifest) -eq $snap.M
  foreach ($k in $files.Keys) { $same = $same -and ((Get-Print $files[$k].Path) -eq $snap[$k]) }
  Check 'INIT-IDEMPOTENT' (($r.Code -eq 0) -and $same -and ($r.Out -match 'unchanged')) "exit=$($r.Code) same=$same"
} catch {
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  $script:Failed = $true
} finally {
  if ($null -ne $PrevCcd) { $env:CLAUDE_CONFIG_DIR = $PrevCcd }
  Check 'INIT-REAL-CLAUDE' ((Get-ServersText $RealClaude) -ceq $Before.Claude) "$RealClaude mcpServers identical"
  Check 'INIT-REAL-VSCODE' ((Get-Print $RealVSCode) -eq $Before.VSCode) "$RealVSCode byte-identical"
  Check 'INIT-REAL-CURSOR' ((Get-Print $RealCursor) -eq $Before.Cursor) "$RealCursor byte-identical"
  if (Test-Path $WorkDir) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: scratch not removed: $WorkDir" } }
}
if ($script:Failed) { Write-Host 'FAIL -- run_init_verb' -ForegroundColor Red; exit 1 }
Write-Host 'PASS -- run_init_verb' -ForegroundColor Green
exit 0
