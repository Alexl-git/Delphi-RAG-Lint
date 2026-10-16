<#
  run_config_as_manifest.ps1 -- `--config <root>\_D-RAG\config.json` works on
  the verbs that read --config as a manifest (E3b item 4, 2026-10-14).

  THE GAP. resolve-dbs, reconcile-project, library-drift, compile-check and
  the sibling-store resolver parse their --config with TManifestIO.ParseText,
  the OLD manifest reader. It knows "indexes" sections, not config.json's
  "projects", so naming the repository's own config.json gave a manifest with
  NO project in it: the verb answered as if the project were not configured.
  Without --config the same verbs found the project through the anchor -- so
  passing the config explicitly gave a worse answer than not passing it.

  NOW: a --config that is a repository config.json (a config.json inside a
  _D-RAG folder) is read as one -- the same manifest the anchor discovery
  builds. Any other --config is parsed as an old manifest, as before.

  CASES (run from a CWD OUTSIDE the repository, so only --config can find it):
    P   resolve-dbs --project App.dproj --config cfg -> <root>\_D-RAG\App.sqlite <- FIX
    I   resolve-dbs --in App\uMain.pas --config cfg  -> the same DB            <- FIX
    R   CONTROL: reconcile-project App.dproj --config cfg --json answers a
        well-formed document (its JSON carries no DB path, so it cannot tell
        the two readers apart -- P and I do, through the same ParseFile)
    K   CONTROL: an old manifest via --config still resolves its section
  RED-CHECK: on the pre-fix exe P and I fail; R and K pass on both.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_cfg_manifest_$PID"
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

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$root  = Join-Path $WorkDir 'repo'
$app   = Join-Path $root 'App'
$dhome = Join-Path $root '_D-RAG'
$cfg   = Join-Path $dhome 'config.json'
$db    = Join-Path $dhome 'App.sqlite'
$dproj = Join-Path $app 'App.dproj'
$cwd   = Join-Path $WorkDir 'outside'
New-Item -ItemType Directory $cwd -Force | Out-Null

Write-Ascii $dproj "<Project xmlns=`"http://schemas.microsoft.com/developer/msbuild/2003`">`n  <PropertyGroup>`n    <ProjectVersion>18.8</ProjectVersion>`n    <MainSource>App.dpr</MainSource>`n  </PropertyGroup>`n</Project>`n"
Write-Ascii (Join-Path $app 'App.dpr') @'
program App;
uses
  uMain in 'uMain.pas';
begin
  Go;
end.
'@
Write-Ascii (Join-Path $app 'uMain.pas') @'
unit uMain;
interface
procedure Go;
implementation
procedure Go;
begin
end;
end.
'@
Write-Ascii $cfg '{ "version": 1, "projects": [ { "name": "App", "dproj": "App\\App.dproj", "platform": "Win32", "delphi": "20.0" } ] }'

function Run([string[]]$argv) {
  Push-Location $cwd
  try {
    $out = & $Exe @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
  } finally { Pop-Location }
}

Write-Host ''
Write-Host 'run_config_as_manifest -- a repository config.json is a valid --config' -ForegroundColor Cyan

$ix = Run @('index', '--project', $dproj)
Check 'the fixture indexed into <root>\_D-RAG\App.sqlite' (($ix.Code -eq 0) -and (Test-Path $db)) $ix.Text
if (-not (Test-Path $db)) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
$dbRx = [regex]::Escape($db)

Write-Host ''
Write-Host 'P -- resolve-dbs --project' -ForegroundColor Cyan
$p = Run @('resolve-dbs', '--project', $dproj, '--config', $cfg)
Check 'P exit 0' ($p.Code -eq 0) $p.Text
Check 'P names the project index' ($p.Text -match $dbRx) $p.Text

Write-Host ''
Write-Host 'I -- resolve-dbs --in' -ForegroundColor Cyan
$i = Run @('resolve-dbs', '--in', (Join-Path $app 'uMain.pas'), '--config', $cfg)
Check 'I exit 0' ($i.Code -eq 0) $i.Text
Check 'I names the project index' ($i.Text -match $dbRx) $i.Text

Write-Host ''
Write-Host 'R -- CONTROL: reconcile-project' -ForegroundColor Cyan
$r = Run @('reconcile-project', $dproj, '--config', $cfg, '--json')
Check 'R exit 0' ($r.Code -eq 0) $r.Text
$rj = $null; try { $rj = $r.Text | ConvertFrom-Json } catch { }
Check 'R answers a JSON document with "missing"' (($null -ne $rj) -and ($null -ne $rj.PSObject.Properties['missing'])) $r.Text

Write-Host ''
Write-Host 'K -- CONTROL: an old manifest via --config still works' -ForegroundColor Cyan
$old = Join-Path $WorkDir 'old.drag-lint.json'
$oldDb = Join-Path $WorkDir 'old\App.sqlite'
[System.IO.File]::WriteAllText($old, ('{ "indexes": { "sections": [ { "name": "App", "db": "' + ($oldDb -replace '\\', '\\') + '", "include": ["' + ($dproj -replace '\\', '\\') + '"] } ] } }'), [System.Text.Encoding]::ASCII)
$k = Run @('resolve-dbs', '--project', $dproj, '--config', $old)
Check 'K names the old manifest''s db' ($k.Text -match [regex]::Escape($oldDb)) $k.Text

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up.
  foreach ($d23 in @("C:\TEMP\draglint_cfg_manifest_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
