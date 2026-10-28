#Requires -Version 7
<#
  run_project_context_guard.ps1 -- guard for `drag-lint project-context`.

  Writes <base>.dlcontext.json from a copy of src\cli\drag-lint.dproj (real DEBUG / RELEASE
  DCC_Define), then checks: file written, --check fresh (exit 0), touching the .dproj makes
  it stale (exit 1 + reason), platform/config change the defines (positive control: DEBUG in
  Debug and not in Release; WIN64 in Win64 and not in Win32), a .dpr without .dproj exits 2
  with the setup hint and with --platform and --config writes from built-ins.
  Never touches the user's real files: everything lives in a temp folder.

  -Exe  path of drag-lint.exe (default: the deployed engine).
#>
param(
  [string]$Exe = 'C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe'
)
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$fixture = Join-Path $repo 'src\cli\drag-lint.dproj'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("dl-pctx-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null
$fail = 0
function Check([string]$name, [bool]$ok) {
  if ($ok) { Write-Host "ok   $name" } else { Write-Host "FAIL $name"; $script:fail++ }
}
function Run([string[]]$a) {
  $out = & $Exe @a 2>&1 | Out-String
  [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function Defines([string]$file) { (Get-Content $file -Raw | ConvertFrom-Json).defines }
try {
  $dproj = Join-Path $tmp 'App.dproj'
  Copy-Item $fixture $dproj
  $ctx = Join-Path $tmp 'App.dlcontext.json'

  $r = Run @('project-context', '--project', $dproj, '--platform', 'Win64', '--config', 'Debug')
  Check 'write exits 0' ($r.Code -eq 0)
  Check 'context file exists' (Test-Path $ctx)
  $bytes = [IO.File]::ReadAllBytes($ctx)
  Check 'no BOM' ($bytes[0] -eq [byte][char]'{')
  Check 'schema 1' ((Get-Content $ctx -Raw | ConvertFrom-Json).schema -eq 1)
  Check 'Debug has DEBUG (positive control)' ((Defines $ctx) -contains 'debug')
  Check 'Win64 has WIN64' ((Defines $ctx) -contains 'win64')

  $r = Run @('project-context', '--project', $dproj, '--platform', 'Win64', '--config', 'Debug', '--check')
  Check '--check fresh exits 0' ($r.Code -eq 0)
  $r = Run @('project-context', '--project', $dproj, '--platform', 'Win64', '--config', 'Debug', '--check', '--json')
  Check '--check --json prints the context' ($r.Code -eq 0 -and $r.Out -match '"schema"')

  $r = Run @('project-context', '--project', $dproj, '--platform', 'Win64', '--config', 'Release', '--check')
  Check '--check with another config is stale (exit 1)' ($r.Code -eq 1 -and $r.Out -match 'stale')

  Run @('project-context', '--project', $dproj, '--platform', 'Win64', '--config', 'Release') | Out-Null
  Check 'Release lacks DEBUG' (-not ((Defines $ctx) -contains 'debug'))
  Check 'Release has RELEASE' ((Defines $ctx) -contains 'release')
  Run @('project-context', '--project', $dproj, '--platform', 'Win32', '--config', 'Debug') | Out-Null
  Check 'Win32 lacks WIN64' (-not ((Defines $ctx) -contains 'win64'))

  Add-Content $dproj ' '
  $r = Run @('project-context', '--project', $dproj, '--check')
  Check 'touched .dproj -> stale exit 1 with reason' ($r.Code -eq 1 -and $r.Out -match 'stale')

  $out2 = Join-Path $tmp 'other.json'
  $r = Run @('project-context', '--project', $dproj, '--out', $out2)
  Check '--out writes elsewhere' ($r.Code -eq 0 -and (Test-Path $out2))
  [IO.File]::Delete($ctx)
  $r = Run @('project-context', '--project', $dproj, '--check')
  Check 'missing file -> exit 1 saying missing' ($r.Code -eq 1 -and $r.Out -match 'missing')

  $dpr = Join-Path $tmp 'Solo.dpr'
  Set-Content $dpr 'program Solo; begin end.'
  $r = Run @('project-context', '--project', $dpr)
  Check '.dpr without .dproj exits 2 with hint' ($r.Code -eq 2 -and $r.Out -match 'no \.dproj: run dl-project-setup\.exe')
  $r = Run @('project-context', '--project', $dpr, '--platform', 'Win64', '--config', 'Debug')
  Check '.dpr with --platform/--config writes' ($r.Code -eq 0 -and (Test-Path (Join-Path $tmp 'Solo.dlcontext.json')))
  $r = Run @('project-context', '--project', $dpr, '--platform', 'Win64', '--config', 'Debug', '--check')
  Check '.dpr context never stale' ($r.Code -eq 0)
}
finally {
  [IO.Directory]::Delete($tmp, $true)
}
if ($fail) { Write-Host "project_context_guard: $fail FAIL"; exit 1 }
Write-Host 'project_context_guard: PASS'
exit 0
