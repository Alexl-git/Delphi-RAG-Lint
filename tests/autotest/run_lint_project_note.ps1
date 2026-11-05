<#
  run_lint_project_note.ps1 --
  `lint --project X.dpr --rule unit-not-in-dpr` must not claim "no index covers this file" (1.44).

  THE STATE IT REPLACES (gate note 2026-11-05). A project-level lint names no file, yet its
  footer said "no index covers this file, so the store-backed and project rules did NOT run" --
  while unit-not-in-dpr DID run and reported. The note now says what happened.

  POSITIVE CONTROL: the run reports the finding (the rule ran), so the absence of
  the false claim is not a vacuous pass.

  Usage: pwsh -NoProfile -File tests\autotest\run_lint_project_note.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint-lint-project-note-$PID"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
try {
  $exePath = (Resolve-Path $Exe).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
  Write-Ascii "$WorkDir\uA.pas" "unit uA;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n"
  Write-Ascii "$WorkDir\uOrphan.pas" "unit uOrphan;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n"
  Write-Ascii "$WorkDir\App.dpr" "program App;`r`n`r`nuses`r`n  uA in 'uA.pas';`r`n`r`nbegin`r`nend.`r`n"
  $o = "$WorkDir\o.txt"; $e = "$WorkDir\e.txt"
  $p = Start-Process -FilePath $exePath -ArgumentList @('lint', '--project', "$WorkDir\App.dpr", '--rule', 'unit-not-in-dpr') -NoNewWindow -Wait -PassThru `
         -WorkingDirectory $WorkDir -RedirectStandardOutput $o -RedirectStandardError $e
  $out = [IO.File]::ReadAllText($o); $err = [IO.File]::ReadAllText($e)
  Check 'V2 POSITIVE CONTROL the rule ran and reported a unit-not-in-dpr finding' ($out -match 'unit-not-in-dpr:') ("stdout=" + $out.Trim())
  Check 'no false "no index covers this file" claim' ($err -notmatch 'no index covers this file') ("stderr=" + $err.Trim())
  Check 'the note says it was a project-level run' ($err -match 'project-level run') ("stderr=" + $err.Trim())
} finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
if ($script:fail) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 } else { Write-Host 'ALL PASS' -ForegroundColor Green; exit 0 }
