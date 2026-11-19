<#
  run_v152_ATLA.ps1 -- 1.52 lane ATLA acceptance runner (gap-matrix set A).

  Covers what tests\lint\run_lint_tests.ps1 cannot:
    1. rules --json: reserved-word-identifier and implicit-package-import are catalog
       rows, ON; architecture-contract-content and noreturn-returns are NOT ids (the
       first is an expansion of contract-unit-declares-class, the second is parked).
    2. contract-unit-declares-class through a drag-lint.json "contractUnits" glob
       (DRAGLINT_MANIFEST points at a private manifest): fires on the class, not on
       the exception class or the class reference (positive + control);
       a non-matching glob stays silent (control).
    3. No double report: a unit named *.Contract is reported once per class (lane
       APP's suffix check), even when a glob also names it.
    4. implicit-package-import positive control on a package laid out in a temp folder.

  Usage: pwsh -File tests\autotest\run_v152_ATLA.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe = "third_party\dll-win64\drag-lint.exe"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$exeDir  = Split-Path $exePath -Parent
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl-v152-atla-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$pass = 0; $fail = 0
function Check([bool]$ok, [string]$what) {
  if ($ok) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
function Lint([string]$file, [string]$cfg) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath lint $file --config $cfg --json 2>$null }
  $txt = ($raw -join "`n").Trim()
  if ($txt -eq '') { return }
  # lint --json is a bare array: return its ITEMS so callers' Where-Object sees findings, not one array
  return ($txt | ConvertFrom-Json)
}
function WriteAscii([string]$path, [string]$text) {
  [IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Manifest([string[]]$globs) {
  $src = Join-Path $exeDir "drag-lint.json"
  $obj = if (Test-Path $src) { Get-Content $src -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
  $obj | Add-Member -NotePropertyName contractUnits -NotePropertyValue $globs -Force
  $p = Join-Path $work ("manifest-" + [Guid]::NewGuid().ToString("N").Substring(0, 6) + ".json")
  WriteAscii $p ($obj | ConvertTo-Json -Depth 20)
  return $p
}

# 1. catalog
$rules = & { $ErrorActionPreference = 'Continue'; & $exePath rules --json 2>$null } | ConvertFrom-Json
if ($rules.rules) { $rules = $rules.rules }
$byId = @{}; foreach ($r in $rules) { $byId[$r.id] = $r }
Check ($byId.ContainsKey('reserved-word-identifier') -and $byId['reserved-word-identifier'].default_enabled) 'catalog: reserved-word-identifier is ON'
Check ($byId.ContainsKey('implicit-package-import') -and $byId['implicit-package-import'].default_enabled) 'catalog: implicit-package-import is ON'
Check (-not $byId.ContainsKey('architecture-contract-content')) 'catalog: no architecture-contract-content id (expansion of contract-unit-declares-class)'
Check (-not $byId.ContainsKey('noreturn-returns')) 'catalog: no noreturn-returns id (parked: needs an extractor fact)'

# 2. contract glob
$cfg = Join-Path $work "enable.json"
WriteAscii $cfg '{ "enabled": ["contract-unit-declares-class"] }'
$fixture = (Resolve-Path "tests\lint\architecture-contract-content.pas").Path
$saved = $env:DRAGLINT_MANIFEST
try {
  $env:DRAGLINT_MANIFEST = Manifest @('App.Orders.*')
  $f = @(Lint $fixture $cfg | Where-Object { $_.rule -eq 'contract-unit-declares-class' })
  Write-Host ("  raw lines: " + (($f | ForEach-Object { $_.start_line }) -join ','))
  Check (@($f | Where-Object { $_.start_line -eq 11 }).Count -eq 1) 'contract glob: TOrderList (line 11) reported'
  Check ($f.Count -eq 1) 'contract glob: exception class and class reference not reported'

  $env:DRAGLINT_MANIFEST = Manifest @('Other.*')
  $f = @(Lint $fixture $cfg | Where-Object { $_.rule -eq 'contract-unit-declares-class' })
  Check ($f.Count -eq 0) 'contract glob: a non-matching glob stays silent'

  # 3. no double report
  $dup = Join-Path $work "App.Orders.Contract.pas"
  WriteAscii $dup "unit App.Orders.Contract;`ninterface`ntype`n  TOrderList = class`n  end;`nimplementation`nend.`n"
  $env:DRAGLINT_MANIFEST = Manifest @('*.Contract')
  $f = @(Lint $dup $cfg | Where-Object { $_.rule -eq 'contract-unit-declares-class' })
  Check ($f.Count -eq 1) "suffix unit + matching glob: reported once (got $($f.Count))"
} finally {
  $env:DRAGLINT_MANIFEST = $saved
}

# 4. implicit-package-import in a package whose units sit one folder below the .dpk
$pkg = Join-Path $work "pkg"; $src = Join-Path $work "pkg\src"
New-Item -ItemType Directory -Path $src | Out-Null
WriteAscii (Join-Path $pkg "AtlaPkg.dpk") "package AtlaPkg;`nrequires`n  rtl;`ncontains`n  AtlaA in 'src\AtlaA.pas';`nend.`n"
WriteAscii (Join-Path $src "AtlaA.pas") "unit AtlaA;`ninterface`nuses`n  System.SysUtils,`n  AtlaB;`nimplementation`nend.`n"
WriteAscii (Join-Path $src "AtlaB.pas") "unit AtlaB;`ninterface`nimplementation`nend.`n"
$none = Join-Path $work "none.json"; WriteAscii $none '{ }'
$f = @(Lint (Join-Path $src "AtlaA.pas") $none | Where-Object { $_.rule -eq 'implicit-package-import' })
Check (($f.Count -eq 1) -and ($f[0].start_line -eq 5)) 'implicit-package-import: AtlaB (line 5) reported from the parent-folder package'
$f = @(Lint (Join-Path $src "AtlaB.pas") $none | Where-Object { $_.rule -eq 'implicit-package-import' })
Check ($f.Count -eq 0) 'implicit-package-import: a unit outside contains is not checked'

Write-Host ""
Write-Host "v152-ATLA: $pass pass / $fail fail"
if ($fail -gt 0) { exit 1 }
exit 0