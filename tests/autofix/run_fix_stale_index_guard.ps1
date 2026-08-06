<#
  run_fix_stale_index_guard.ps1 -- REGRESSION for the HIGH-severity silent
  source corruption reported in docs\INBOX-naming-autofix-corrupts-source-on-
  stale-index.md.

  The naming autofix is STORE-backed: TRenameRefactoring.Build resolves the
  declaration and every reference site from the symbol store, whose (line, col)
  pairs are a SNAPSHOT. When the file has been edited since it was indexed those
  coordinates address unrelated text -- and TTextEditApplier.tekReplaceInLine
  clamps EndCol but NOT Col, so a column past end-of-line silently APPENDS the
  new name to whatever the line ends with. Observed in the field:
  `else` -> `elseGlyActive`, with exit code 0.

  This runner reproduces that EXACT failure mode:
    1. copy the fixture to a scratch dir and index it into a scratch db;
    2. insert ONE comment line ABOVE the use site WITHOUT reindexing, so the
       store's recorded reference line (25) now holds the bare `  else` line;
    3. run the const-casing naming autofix (opted in via config);
    4. assert the file was not corrupted.

  THE LOAD-BEARING ASSERTION is the whole-file lower-case identity check: the
  only change a pure RE-CASING fix may ever make is letter case, so the file
  lower-cased must be byte-identical before and after. Any corruption -- glued
  identifiers, eaten keywords, text written at a stale column -- breaks it,
  whether or not it happens to be syntactically invalid. (The field bug was
  caught only because it produced invalid syntax; a rename landing on a
  same-length identifier would have compiled and shipped.) The keyword
  assertions below are belt-and-braces on top of it.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

# tree-sitter Win64 DLLs must sit beside the exe (mirrors _manifest_common.ps1).
$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $exePath) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

$fixture = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\stale_index_guard.pas')).Path
$scratch = Join-Path C:\TEMP 'draglint_stale_index_guard'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
$srcDir = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $srcDir | Out-Null
$target = Join-Path $srcDir 'stale_index_guard.pas'
$db     = Join-Path $scratch 'stale.sqlite'
$cfg    = Join-Path $scratch 'drag-lint-lint.json'
Copy-Item $fixture $target -Force
'{ "autofix": ["const-casing"], "naming": { "const_case": ["UPPER_CASE"] } }' | Out-File -FilePath $cfg -Encoding ascii

Push-Location $scratch
try {
  # ---- 1. index the PRISTINE file --------------------------------------------
  & $exePath index $srcDir --db $db 2>&1 | Out-Null
  Check 'stale-guard: index exits 0' ($LASTEXITCODE -eq 0)
  Check 'stale-guard: db built' (Test-Path $db)

  # ---- 2. shift the file WITHOUT reindexing ----------------------------------
  # One comment line inserted after `Err := False;` (line 21) pushes everything
  # below down by one, so the store's reference row for glyActive (line 25,
  # col 14) now points at the bare `  else` line -- 6 characters long, i.e. the
  # recorded column is past its end. That is precisely the shape that produced
  # `elseGlyActive` in the field.
  $lines = [System.Collections.Generic.List[string]]::new()
  [IO.File]::ReadAllLines($target) | ForEach-Object { $lines.Add($_) }
  $lines.Insert(21, '  { an edit made after the file was indexed }')
  [IO.File]::WriteAllText($target, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

  $before = [IO.File]::ReadAllText($target)
  Check 'stale-guard: shifted file has `  else` at the stale reference line 25' (([IO.File]::ReadAllLines($target))[24] -eq '  else')

  # ---- 3. run the naming autofix against the STALE store ---------------------
  $out  = & $exePath lint-all --db $db --config $cfg --rule const-casing --fix --apply --quiet 2>&1
  $code = $LASTEXITCODE
  Write-Host ($out -join "`n")
  $after = [IO.File]::ReadAllText($target)

  # ---- 4. assert no corruption ------------------------------------------------
  # (a) THE load-bearing one: a re-casing fix may only change letter case.
  Check 'stale-guard: file differs from the original only in letter case (no corruption)' ($after.ToLowerInvariant() -eq $before.ToLowerInvariant())
  if ($after.ToLowerInvariant() -ne $before.ToLowerInvariant()) {
    $al = $after -split "`r`n"; $bl = $before -split "`r`n"
    for ($i = 0; $i -lt [Math]::Max($al.Count, $bl.Count); $i++) {
      $a = if ($i -lt $al.Count) { $al[$i] } else { '<eof>' }
      $b = if ($i -lt $bl.Count) { $bl[$i] } else { '<eof>' }
      if ($a.ToLowerInvariant() -ne $b.ToLowerInvariant()) { Write-Host ("  L{0}: got '{1}' want '{2}'" -f ($i+1), $a, $b) -ForegroundColor Yellow }
    }
  }

  # (b) no keyword may have an identifier glued onto it.
  foreach ($kw in @('then','else','do','begin','end')) {
    Check "stale-guard: no identifier glued onto the '$kw' keyword" (-not ($after -match "(?im)\b$kw[A-Za-z_]"))
  }

  # (c) the original keyword tokens survive verbatim.
  Check 'stale-guard: `if not Err then` still intact' ($after -match '(?m)^\s*if not Err then\s*$')
  Check 'stale-guard: bare `else` line still intact'  ($after -match '(?m)^\s*else\s*$')
  Check 'stale-guard: `end.` still intact'            ($after -match '(?m)^end\.\s*$')

  # (d) the identifier itself keeps its letters everywhere it occurred (2 sites).
  Check 'stale-guard: glyActive still present at both sites (any casing)' (([regex]::Matches($after, '(?i)glyactive')).Count -eq 2)

  # (e) the skip must be SURFACED, not silent -- an invisible skip is what made
  #     the original defect an exit-0 corruption.
  Check 'stale-guard: the stale-position skip is reported' (($out -join "`n") -match 'skipped')

  Check 'stale-guard: exit code 0' ($code -eq 0)
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
