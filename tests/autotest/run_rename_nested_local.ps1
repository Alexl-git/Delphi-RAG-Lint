<#
  run_rename_nested_local.ps1 -- wave 148 RN item 1 (146 r1 incidental): renaming a routine's local must not edit a
  NESTED routine's own same-named local, const or parameter (a different symbol that shadows it).

  RED on 1.46.0-alpha: --kind param (BuildLocal) checks only a nested routine's header args, so the nested routine's
  `var R` / `const R` and every use of them are renamed too. The program still compiles, so no gate can catch it.

  POSITIVE CONTROL: p1 -- a nested routine WITHOUT its own R uses the outer R; those uses must stay in the edit set
  (a fix that skipped every nested routine would pass n1-n3 and fail p1). p2 -- the header-arg shadowing that already
  worked keeps working.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-nestedlocal-$PID"
)
$env:DRAGLINT_RENAME_TEST_UNGATED = '1'
$ErrorActionPreference = 'Continue'
$script:Failed = $false; $script:Passed = 0; $script:FailCount = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { $script:FailCount++; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$Src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Force $Src | Out-Null
$Db = Join-Path $WorkDir 'fx.sqlite'
$Unit = @(
  'unit NlA;', '', 'interface', '', 'procedure Outer;', '', 'implementation', '',
  'procedure Outer;', 'var', '  R: Integer;', '',
  '  procedure UsesOuter;', '  begin', '    R:= R + 1;', '  end;', '',
  '  procedure OwnVar;', '  var', '    R: Integer;', '  begin', '    R:= 5;', '    Inc(R);', '  end;', '',
  '  procedure OwnConst;', '  const', '    R = 7;', '  begin', '    if R > 0 then Exit;', '  end;', '',
  '  procedure OwnArg(R: Integer);', '  begin', '    R:= 9;', '  end;', '',
  'begin', '  R:= 1;', '  UsesOuter;', '  OwnVar;', '  OwnConst;', '  OwnArg(R);', 'end;', '', 'end.', '')
$Path = Join-Path $Src 'NlA.pas'
[IO.File]::WriteAllText($Path, ($Unit -join "`r`n"), [Text.Encoding]::ASCII)
function LineOf([string]$Exact) {
  for ($i = 0; $i -lt $Unit.Count; $i++) { if ($Unit[$i] -ceq $Exact) { return $i + 1 } }; return 0
}
Push-Location $WorkDir
try {
  $null | & $Exe index $Src --db $Db --library-db none *> "$Db.log"
  $DeclLine = LineOf '  R: Integer;'
  $Outer = @((LineOf '    R:= R + 1;'), (LineOf '  R:= 1;'), (LineOf '  OwnArg(R);'), $DeclLine)
  $OwnVar = @((LineOf '    R: Integer;'), (LineOf '    R:= 5;'), (LineOf '    Inc(R);'))
  $OwnConst = @((LineOf '    R = 7;'), (LineOf '    if R > 0 then Exit;'))
  foreach ($form in @('param', 'symbol')) {
    Write-Host "rename --kind $form on the outer local R" -ForegroundColor Cyan
    if ($form -eq 'param') {
      $o = ($null | & $Exe rename --kind param --in $Path --line $DeclLine --col 3 --to RCount --db $Db --plan --json 2>$null | Out-String)
    } else {
      $o = ($null | & $Exe rename --kind symbol --name 'NlA.Outer.R' --to RCount --db $Db --library-db none --plan --json 2>$null | Out-String)
    }
    $j = $null; try { $j = $o | ConvertFrom-Json } catch { }
    $Got = @($j.edits | ForEach-Object { [int]$_.line })
    Check "$form n0 plan parsed" ($null -ne $j) $o
    $BadV = @($Got | Where-Object { $OwnVar -contains $_ })
    $BadC = @($Got | Where-Object { $OwnConst -contains $_ })
    Check "$form n1 no edit in a nested routine's own var R" ($BadV.Count -eq 0) ("edited lines " + ($BadV -join ','))
    Check "$form n2 no edit in a nested routine's own const R" ($BadC.Count -eq 0) ("edited lines " + ($BadC -join ','))
    $Miss = @($Outer | Where-Object { $Got -notcontains $_ })
    Check "$form p1 POSITIVE CONTROL: every outer R use incl. nested UsesOuter edited (5 edits)" ($Miss.Count -eq 0 -and $Got.Count -eq 5) ("missing " + ($Miss -join ',') + " got " + ($Got -join ','))
    Check "$form p2 header-arg shadowing holds (OwnArg R:= 9 untouched)" ($Got -notcontains (LineOf '    R:= 9;'))
  }
  Write-Host 'apply --kind param and read the bytes' -ForegroundColor Cyan
  $null | & $Exe rename --kind param --in $Path --line $DeclLine --col 3 --to RCount --db $Db --apply *> "$WorkDir\apply.log"
  $T = [IO.File]::ReadAllText($Path)
  Check 'a1 outer renamed' ($T -match 'RCount:= RCount \+ 1;' -and $T -match '  RCount:= 1;') (Get-Content "$WorkDir\apply.log" -Raw)
  Check 'a2 nested own R kept' ($T -match '    R:= 5;\s+Inc\(R\);' -and $T -match '    R = 7;') $T
} finally { Pop-Location }
Write-Host ("{0} passed, {1} failed" -f $script:Passed, $script:FailCount)
if ($script:Failed) { exit 1 } else { exit 0 }
