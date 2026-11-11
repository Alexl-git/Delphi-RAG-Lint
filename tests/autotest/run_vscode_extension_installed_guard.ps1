<#
  run_vscode_extension_installed_guard.ps1 -- the drag-lint VS Code extension must
  actually be INSTALLED, at the current version, in every VS Code profile.

  WHY THIS EXISTS:
    2026-11-11: the VS Code "DL" profile's extensions.json still pointed
    drag-lint.drag-lint at a deleted 1.6.0 folder, so the extension never loaded
    and nothing reported it. The release step (build\install-vsix-all-profiles.ps1,
    called by pack-lint-release.ps1) now installs the vsix everywhere; this guard
    proves the result.

  CHECKS (per run):
    1. dist\drag-lint-<package.json version>.vsix exists (missing -> FAIL).
    2. every profile (default + each userDataProfiles entry of storage.json) whose
       extensions.json lists drag-lint.drag-lint points at an EXISTING folder whose
       version is package.json's. A profile with NO entry is a NOTE (the owner may
       keep a profile extension-free); a stale or missing folder is a FAIL.
  SKIP (exit 0, with the reason) when VS Code's user dir is absent.
  SELF-TEST (always runs, builds fake dirs under %TEMP%): RED = entry pointing at a
  deleted 1.6.0 folder, GREEN = current folder, missing vsix = FAIL.

  -UserDir / -ExtRoot / -DistDir are overridable so the check runs on a fake tree;
  the real profiles are only READ, never edited.
#>
[CmdletBinding()]
param(
  [string]$Dir = "$PSScriptRoot\..\..\editors\vscode\drag-lint",
  [string]$DistDir = "$PSScriptRoot\..\..\dist",
  [string]$UserDir = "$env:APPDATA\Code\User",
  [string]$ExtRoot = "$env:USERPROFILE\.vscode\extensions"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

# Returns @{ Fails = <string[]>; Notes = <string[]> } for one tree.
function Test-InstalledTree([string]$pUserDir, [string]$pExtRoot, [string]$pDistDir, [string]$pVersion) {
  $fails = @(); $notes = @()
  $vsix = Join-Path $pDistDir "drag-lint-$pVersion.vsix"
  if (-not (Test-Path -LiteralPath $vsix)) { $fails += "vsix missing: $vsix" }
  $targets = @(@{ Name = '(default)'; Json = (Join-Path $pExtRoot 'extensions.json') })
  $st = Join-Path $pUserDir 'globalStorage\storage.json'
  if (Test-Path -LiteralPath $st) {
    $prof = (Get-Content -LiteralPath $st -Raw | ConvertFrom-Json).userDataProfiles
    foreach ($p in @($prof)) {
      $id = ([string]$p.location).Split('/')[-1]
      if ($id) { $targets += @{ Name = [string]$p.name; Json = (Join-Path $pUserDir "profiles\$id\extensions.json") } }
    }
  }
  foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.Json)) { $notes += "$($t.Name): no extensions.json"; continue }
    $e = @((Get-Content -LiteralPath $t.Json -Raw | ConvertFrom-Json) | Where-Object { $_.identifier.id -eq 'drag-lint.drag-lint' })
    if ($e.Count -eq 0) { $notes += "$($t.Name): drag-lint not installed in this profile"; continue }
    $loc = [string]$e[0].location.path
    $path = $loc.TrimStart('/')
    if (-not (Test-Path -LiteralPath $path)) { $fails += "$($t.Name): points at a missing folder $path (version $($e[0].version))" }
    elseif ([string]$e[0].version -ne $pVersion) { $fails += "$($t.Name): installed $($e[0].version), need $pVersion" }
  }
  return @{ Fails = $fails; Notes = $notes }
}

$pkgPath = Join-Path $Dir 'package.json'
if (-not (Test-Path $pkgPath)) { Write-Host "FATAL: not found: $pkgPath" -ForegroundColor Red; exit 2 }
$ver = (Get-Content $pkgPath -Raw | ConvertFrom-Json).version

Write-Host 'Self-test on a fake VS Code tree (RED / GREEN / missing-vsix controls)' -ForegroundColor Cyan
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("vsixguard-" + [Guid]::NewGuid().ToString('N'))
try {
  $u = Join-Path $tmp 'User'; $x = Join-Path $tmp 'ext'; $d = Join-Path $tmp 'dist'
  New-Item -ItemType Directory -Force -Path "$u\globalStorage", "$u\profiles\abc123", $x, $d, "$x\drag-lint.drag-lint-$ver" | Out-Null
  [IO.File]::WriteAllText("$u\globalStorage\storage.json", '{"userDataProfiles":[{"location":"abc123","name":"DL"}]}')
  [IO.File]::WriteAllText("$d\drag-lint-$ver.vsix", 'x')
  $fakeXp = $x.Replace([string][char]92, '/')
  function Write-Entry([string]$pFile, [string]$pVer) {
    $j = '[{"identifier":{"id":"drag-lint.drag-lint"},"version":"' + $pVer + '","location":{"path":"/' + $fakeXp + '/drag-lint.drag-lint-' + $pVer + '"}}]'
    [IO.File]::WriteAllText($pFile, $j)
  }
  Write-Entry "$x\extensions.json" $ver
  Write-Entry "$u\profiles\abc123\extensions.json" '1.6.0'   # the 2026-11-11 state: folder 1.6.0 was deleted
  $r = Test-InstalledTree $u $x $d $ver
  Check 'RED: profile entry pointing at a deleted 1.6.0 folder is reported' (($r.Fails -join ';') -match 'DL: points at a missing folder') ($r.Fails -join ';')
  Write-Entry "$u\profiles\abc123\extensions.json" $ver
  $r = Test-InstalledTree $u $x $d $ver
  Check 'GREEN: every profile at the current version passes' ($r.Fails.Count -eq 0) ($r.Fails -join ';')
  Write-Entry "$u\profiles\abc123\extensions.json" '1.6.0'
  New-Item -ItemType Directory -Force -Path "$x\drag-lint.drag-lint-1.6.0" | Out-Null
  $r = Test-InstalledTree $u $x $d $ver
  Check 'existing folder of an OLD version still FAILs' (($r.Fails -join ';') -match 'installed 1.6.0, need') ($r.Fails -join ';')
  Write-Entry "$u\profiles\abc123\extensions.json" $ver
  [IO.File]::Delete("$d\drag-lint-$ver.vsix")
  $r = Test-InstalledTree $u $x $d $ver
  Check 'positive control: missing vsix FAILs' (($r.Fails -join ';') -match 'vsix missing') ($r.Fails -join ';')
} finally {
  if (Test-Path $tmp) { [IO.Directory]::Delete($tmp, $true) }
}

Write-Host 'Real machine' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $UserDir)) {
  Write-Host "  [SKIP] VS Code user dir not found ($UserDir) -- VS Code is not installed here" -ForegroundColor DarkGray
} else {
  $r = Test-InstalledTree $UserDir $ExtRoot $DistDir $ver
  Check "dist vsix for $ver exists and every profile holds drag-lint $ver in an existing folder" ($r.Fails.Count -eq 0) ($r.Fails -join '; ')
  foreach ($n in $r.Notes) { Write-Host "  [NOTE] $n" -ForegroundColor DarkGray }
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
