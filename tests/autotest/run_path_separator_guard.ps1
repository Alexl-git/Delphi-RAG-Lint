<#
  run_path_separator_guard.ps1 -- a directory string concatenated with a file
  name must carry its separator.

  Why this exists
  ---------------
  2026-08-26, reported from a live IDE: "Rebuild Index for This Project" on
  C:\Projects\DataCopy\DataCopy.dproj failed with

      FATAL: Exception: Unknown argument: --platform

  --platform is a flag the CLI has accepted for months. The command was correct.
  The ENGINE was not: the plugin spawned
  third_party\dll-win32\drag-lint.exe, a 0.41.0-alpha build dated 2026-06-10
  that predates the flag entirely.

  One character caused it. DragLint.Plugin.Settings.pas expanded a bare
  'drag-lint.exe' registry value by probing the Win64 sibling first:

      var Win64Dir: string:= ExtractFilePath(...(BplDir)) + 'dll-win64';
      if FileExists(Win64Dir + Result.ExePath) then ...
      else if FileExists(BplDir + Result.ExePath) then ...

  Win64Dir had no trailing backslash, so the probe tested
  ...\third_party\dll-win64drag-lint.exe -- a path that CANNOT exist. The Win64
  branch was unreachable dead code from the day it was written, and every bare
  name fell through to whatever sat beside the BPL.

  THE SHAPE IS THE POINT. Nothing failed. The comment above those lines said
  resolution "mirrors EnsureLspClient"; EnsureLspClient bakes the separator into
  its literal ('dll-win64\') and was right, so the two surfaces disagreed on the
  same input while both looked correct in review. A fallback that ANSWERS
  WRONGLY is worse than one that fails -- nothing distinguishes a stale engine's
  answer from a current one until it happens to reject a flag.

  What is checked
  ---------------
  1. REGRESSION PIN: no source line concatenates the literal 'dll-win64' (or
     'dll-win32') without a separator or a file name inside the quotes.
  2. THE FAMILY: any <Name>Dir string variable initialised from a quoted literal
     that does not end in a separator, where <Name>Dir is later used as an
     operand of + in the same file. That is the general form of the same bug.

  A comparison (SameText(LeafDir, 'dll-win64')) is NOT a concatenation and is
  deliberately not matched -- check 1 requires a '+' immediately before.
#>
param([string]$Repo = "$PSScriptRoot\..\..")

$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

$Repo = (Resolve-Path $Repo).Path
Write-Host '== path separator guard ==' -ForegroundColor Cyan

$srcRoot = Join-Path $Repo 'src'
# -Include is SILENTLY IGNORED alongside -LiteralPath -Recurse: the first run of
# this guard scanned 1273 files -- .sqlite, -wal and -shm included -- and still
# reported PASS. Filter on the extension explicitly, and skip the per-project
# _D-RAG index folders, which are binary and locked while the IDE is open.
$exts  = @('.pas','.dpr','.inc')
$files = @(Get-ChildItem -LiteralPath $srcRoot -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } |
           Where-Object { $_.FullName -notlike '*_D-RAG*' })
Check 'source files scanned' ($files.Count -gt 0) "($($files.Count))"

# --- check 1: the regression pin -------------------------------------------
# Offender: a '+' then a quoted literal that is exactly a known platform dir
# name with no trailing separator and no file name.
$pin = [regex]"\+\s*'(dll-win64|dll-win32)'"
$pinHits = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
  $n = 0
  foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
    $n++
    if ($pin.IsMatch($line)) {
      $pinHits.Add(("{0}:{1}: {2}" -f $f.FullName.Substring($Repo.Length + 1), $n, $line.Trim()))
    }
  }
}
Check 'no platform dir literal is concatenated without its separator' ($pinHits.Count -eq 0) `
  $(if ($pinHits.Count -gt 0) { "($($pinHits.Count) offender(s))" } else { '' })
foreach ($h in $pinHits) { Write-Host ("        $h") -ForegroundColor Yellow }

# --- check 2: the family ----------------------------------------------------
# <Name>Dir := <anything> + '<literal>'  where <literal> lacks a trailing
# separator, AND <Name>Dir is later an operand of '+' in the same file.
$decl = [regex]"\b(\w*Dir)\s*:\s*string\s*:=\s*[^;]*\+\s*'([^']*)'\s*;"
$famHits = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
  $text  = [System.IO.File]::ReadAllText($f.FullName)
  $lines = [System.IO.File]::ReadAllLines($f.FullName)
  $n = 0
  foreach ($line in $lines) {
    $n++
    $m = $decl.Match($line)
    if (-not $m.Success) { continue }
    $name = $m.Groups[1].Value
    $lit  = $m.Groups[2].Value
    if ($lit.EndsWith('\') -or $lit.EndsWith('/')) { continue }   # separator present
    if ($lit -eq '') { continue }
    $useRe = [regex]("\b" + [regex]::Escape($name) + "\s*\+")
    if (-not $useRe.IsMatch($text)) { continue }                  # never concatenated
    $famHits.Add(("{0}:{1}: {2}" -f $f.FullName.Substring($Repo.Length + 1), $n, $line.Trim()))
  }
}
Check 'no directory variable is concatenated without a trailing separator' ($famHits.Count -eq 0) `
  $(if ($famHits.Count -gt 0) { "($($famHits.Count) offender(s))" } else { '' })
foreach ($h in $famHits) { Write-Host ("        $h") -ForegroundColor Yellow }
if ($famHits.Count -gt 0) {
  Write-Host '        ^ this variable names a DIRECTORY but does not end in a separator,' -ForegroundColor Yellow
  Write-Host '          and is concatenated with something. Append the separator to the' -ForegroundColor Yellow
  Write-Host '          literal, or use IncludeTrailingPathDelimiter / TPath.Combine.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'PATH SEPARATOR GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PATH SEPARATOR GUARD: PASS' -ForegroundColor Green
exit 0
