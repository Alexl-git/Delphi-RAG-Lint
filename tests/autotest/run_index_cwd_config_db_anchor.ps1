<#
  run_index_cwd_config_db_anchor.ps1 -- INBOX-2026-09-29 item 4b-1.

  A `.drag-lint.json {"db": "<other.sqlite>"}` in the directory the operator
  happens to stand in must NEVER redirect an `index` WRITE. Only the lint
  anchor was guarded (run_lint_all_config_db_anchor.ps1); the index verb writes
  a database, so a redirect there corrupts or widens a DB that belongs to
  another project.

  A1  `index <dir> --db <scratch>` from that cwd: the write lands in <scratch>,
      <other> is untouched (sha256 + size + mtime).
  A2  `index --project <x.dproj>` (no --db) from that cwd: the write lands in
      the project's own <proj>\_D-RAG\<x>.sqlite, <other> untouched.

  POSITIVE CONTROL: -Inject makes A1 assert the OPPOSITE target (the write
  must land in <other>); it must FAIL against a correct engine, proving the
  arms can fail. Run from a neutral CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_idx_cfg_db_anchor_$PID",
  [switch]$Inject
)
try {
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function Stamp($p) {
  if (-not (Test-Path -LiteralPath $p)) { return 'absent' }
  $i = Get-Item -LiteralPath $p
  '{0}|{1}|{2}' -f $i.Length, $i.LastWriteTimeUtc.Ticks, (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
function Invoke-Engine([string]$Cwd, [string[]]$Argv) {
  $o = Join-Path $WorkDir 'out.txt'; $e = Join-Path $WorkDir 'err.txt'
  $q = @($Argv | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
  $p = Start-Process $exePath -ArgumentList $q -WorkingDirectory $Cwd -PassThru -NoNewWindow -RedirectStandardOutput $o -RedirectStandardError $e
  if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch { }; return 'TIMEOUT' }
  return ([string](Get-Content $o -Raw -ErrorAction SilentlyContinue)) + "`n" + ([string](Get-Content $e -Raw -ErrorAction SilentlyContinue))
}

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$cwd  = Join-Path $WorkDir 'cwd';  $src = Join-Path $WorkDir 'src'; $proj = Join-Path $WorkDir 'proj'
foreach ($d in $cwd, $src, $proj) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

$unit = "unit uAnchor;`ninterface`nfunction Twice(pN: Integer): Integer;`nimplementation`nfunction Twice(pN: Integer): Integer;`nbegin`n  Result:= pN * 2;`nend;`nend.`n"
Write-Ascii (Join-Path $src 'uAnchor.pas') $unit
Write-Ascii (Join-Path $proj 'uAnchor.pas') $unit
Write-Ascii (Join-Path $proj 'Anchor.dpr') "program Anchor;`nuses uAnchor in 'uAnchor.pas';`nbegin`nend.`n"
Write-Ascii (Join-Path $proj 'Anchor.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>Anchor.dpr</MainSource></PropertyGroup>
  <ItemGroup><DCCReference Include="uAnchor.pas"/></ItemGroup>
</Project>
'@

# <other> is a REAL index made first, so "untouched" means something.
$other = Join-Path $WorkDir 'other.sqlite'
$null = Invoke-Engine $WorkDir @('index', $src, '--db', $other)
Check 'setup: other.sqlite exists' (Test-Path $other)
$before = Stamp $other
Start-Sleep -Milliseconds 1200   # a rewrite must be visible in mtime
Write-Ascii (Join-Path $cwd '.drag-lint.json') ('{"db": "' + $other.Replace('\', '/') + '"}')

# A1
$scratch = Join-Path $WorkDir 'scratch.sqlite'
$null = Invoke-Engine $cwd @('index', $src, '--db', $scratch)
if ($Inject) {
  Check 'A1 (INJECTED opposite) write landed in the config db' ((Stamp $other) -ne $before)
} else {
  Check 'A1 index <dir> --db: write landed in the named db' (Test-Path $scratch)
  Check 'A1 index <dir> --db: config db untouched' ((Stamp $other) -eq $before) ((Stamp $other))
}

# A2
$owned = Join-Path $proj '_D-RAG\Anchor.sqlite'
$null = Invoke-Engine $cwd @('index', '--project', (Join-Path $proj 'Anchor.dproj'))
Check 'A2 index --project (no --db): write landed in the project-owned db' (Test-Path $owned)
Check 'A2 index --project (no --db): config db untouched' ((Stamp $other) -eq $before) ((Stamp $other))

# A3 positive control for the fix: a "db" key whose folder CONTAINS the target is still honoured.
$honoured = Join-Path $WorkDir 'honoured.sqlite'
Write-Ascii (Join-Path $src '.drag-lint.json') ('{"db": "' + $honoured.Replace([string][char]92, '/') + '"}')
$null = Invoke-Engine $src @('index', $src)
Check 'A3 config db in a folder above the target is still honoured' (Test-Path $honoured)

} finally { }
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
