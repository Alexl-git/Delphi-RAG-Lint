<#
  run_include_resolve.ps1 -- v1.2.1 preprocessor port change #2: nearest-first
  {$I} filename resolution beyond the current directory.

  resolveInclude (preprocess.js:116-136) widens the search past baseDir +
  includePaths: baseDir's immediate subdirs, then each parent (up to searchLevels
  = 3 hops) and that parent's immediate subdirs -- nearest first. subdirsOf is a
  cached readdir. nearSearch:false restores strict same-dir-only resolution.

  Layout (mirrors preprocessor/test-include-resolve.js), under fixtures/incres:
    incres/
      defs.inc                     <- grandparent-level include (ROOT_OK)
      shadow.inc                   <- FAR shadow copy (ShadowFar)
      Common/ELDefs.inc            <- sibling-subdir include (CPU_OK)
      Source/
        shadow.inc                 <- NEAR shadow copy (ShadowNear) -- must win
        uses_eldefs.pas            <- {$I ELDefs.inc}  -> ../Common (parent's subdir)
        uses_shadow.pas            <- {$I shadow.inc}  -> nearest (Source) wins
        Sub/
          uses_defs.pas            <- {$I defs.inc}    -> ../../ (2 levels up)
          uses_missing.pas         <- unresolvable, stays blanked 1:1

  Each case is oracle-diffed byte-for-byte against v1.2.1 preprocess() via
  lib\render.js (which uses baseDir = dirname(file), nearSearch default true),
  plus a content assertion that the {$IFDEF <SYM>}-guarded var survived.

  These cases FAIL on the strict (pre-#2) resolver -- ELDefs.inc / defs.inc do
  not sit in the file's own dir, so the include blanks and the guarded var is
  absent. #2 makes them resolve.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath  = (Resolve-Path $Exe).Path
$fixDir   = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures')).Path
$renderJs = (Resolve-Path (Join-Path $PSScriptRoot 'lib\render.js')).Path

function Q([string]$s) { return '"' + $s + '"' }
function Run-Redirected([string[]]$tokens) {
  $tmp = [System.IO.Path]::GetTempFileName()
  $line = ($tokens -join ' ') + ' > ' + (Q $tmp)
  Start-Process cmd.exe -ArgumentList '/c', ('"' + $line + '"') -NoNewWindow -Wait | Out-Null
  $bytes = [System.IO.File]::ReadAllBytes($tmp)
  Remove-Item $tmp -Force
  return ,$bytes
}
function Run-Pascal([string]$fixture, [string[]]$verbArgs) {
  return ,(Run-Redirected (@((Q $exePath), 'preprocess-file', '--file', (Q $fixture)) + $verbArgs))
}
function Run-Oracle([string]$fixture, [string[]]$oracleArgs) {
  $nodeExe = (Get-Command node).Source
  return ,(Run-Redirected (@((Q $nodeExe), (Q $renderJs), (Q $fixture)) + $oracleArgs))
}
function BytesEqual($a, $b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($k = 0; $k -lt $a.Length; $k++) { if ($a[$k] -ne $b[$k]) { return $false } }
  return $true
}
function AsciiOf($bytes) { return [System.Text.Encoding]::ASCII.GetString($bytes, 0, $bytes.Length) }

# Run one fixture in defines-only mode; return @{ Pas; Orc; In }.
function RunCase([string]$rel) {
  $f = Join-Path $fixDir $rel
  return @{
    In  = [System.IO.File]::ReadAllBytes($f)
    Pas = (Run-Pascal $f @('--include-mode', 'defines-only'))
    Orc = (Run-Oracle $f @('--include-mode', 'defines-only'))
  }
}

Push-Location C:\TEMP
try {
  # 1. Parent's subdir (Source -> ../Common/ELDefs.inc).
  $c = RunCase 'incres\Source\uses_eldefs.pas'
  Check 'resolve: parent subdir Common/ found (var ok survives)' ((AsciiOf $c.Pas).Contains('var ok'))
  Check 'resolve: uses_eldefs Length invariant' ($c.Pas.Length -eq $c.In.Length)
  Check 'resolve: uses_eldefs ORACLE-DIFF Pascal === JS' (BytesEqual $c.Pas $c.Orc)

  # 2. Two levels up (Source/Sub -> ../../defs.inc).
  $c = RunCase 'incres\Source\Sub\uses_defs.pas'
  Check 'resolve: two levels up found (var ok2 survives)' ((AsciiOf $c.Pas).Contains('var ok2'))
  Check 'resolve: uses_defs Length invariant' ($c.Pas.Length -eq $c.In.Length)
  Check 'resolve: uses_defs ORACLE-DIFF Pascal === JS' (BytesEqual $c.Pas $c.Orc)

  # 3. Nearest-first: Source/shadow.inc (defines SHADOW_NEAR) must win over
  #    root/shadow.inc (defines SHADOW_FAR). The two copies DEFINE DIFFERENT
  #    symbols so nearest-first is provable even in defines-only mode (the body
  #    is discarded, but the DEFINE it applied is not): after {$I shadow.inc},
  #    {$IFDEF SHADOW_NEAR} must take THEN (usednear survives) and
  #    {$IFDEF SHADOW_FAR} must not (usedfar absent).
  $c = RunCase 'incres\Source\uses_shadow.pas'
  Check 'resolve: nearest-first picks NEAR copy (usednear survives)' ((AsciiOf $c.Pas).Contains('var usednear'))
  Check 'resolve: nearest-first does NOT pick FAR copy (usedfar absent)' (-not (AsciiOf $c.Pas).Contains('var usedfar'))
  Check 'resolve: shadow Length invariant' ($c.Pas.Length -eq $c.In.Length)
  Check 'resolve: shadow nearest-first ORACLE-DIFF Pascal === JS' (BytesEqual $c.Pas $c.Orc)

  # 4. Unresolvable include stays blanked 1:1 (no throw, no offset shift).
  $c = RunCase 'incres\Source\Sub\uses_missing.pas'
  Check 'resolve: unresolvable blanked 1:1 (Length invariant, no throw)' ($c.Pas.Length -eq $c.In.Length)
  Check 'resolve: unresolvable ORACLE-DIFF Pascal === JS' (BytesEqual $c.Pas $c.Orc)

  # 5. --no-near-search restores strict BaseDir-only resolution: ELDefs.inc lives
  #    in ../Common, NOT in the file's own dir, so with the widened search OFF it
  #    does NOT resolve -> CPU_OK stays undefined -> var ok is BLANKED. (Proves
  #    the opt-out flag is real -- the exact same file resolved fine in case 1.)
  $f5 = Join-Path $fixDir 'incres\Source\uses_eldefs.pas'
  $strict = Run-Pascal $f5 @('--include-mode', 'defines-only', '--no-near-search')
  Check 'resolve: --no-near-search does NOT find ../Common (var ok absent)' (-not (AsciiOf $strict).Contains('var ok'))
  Check 'resolve: --no-near-search Length invariant' ($strict.Length -eq ([System.IO.File]::ReadAllBytes($f5)).Length)

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
