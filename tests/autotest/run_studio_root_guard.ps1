<#
  run_studio_root_guard.ps1 -- there is exactly ONE RAD Studio path literal in
  this repository, and everything else is composed from it.

  WHY THIS EXISTS. Eight sites across four units named the Studio installation
  and disagreed about how to find it: CLI's check-unit read $BDS then fell back
  to a literal, LSP.Proxy read the registry then fell back to a literal,
  CompileCheck and Project.Resolver used a literal outright. FOUR of the eight
  stored `<root>\bin\rsvars.bat` separately from the root, so a machine with
  Studio installed elsewhere resolved the right root and the wrong rsvars.

  Nothing failed when they drifted apart. They were simply all correct on the
  author's box -- which is exactly the condition under which a hardcoded path
  survives review. `hardcoded-absolute-path` reported them, and this guard is
  what stops the count creeping back up.

  Owner ruling, 2026-09-02: the single fallback SURVIVES, but only when the
  directory actually exists; otherwise a missing Studio is a hard error rather
  than a wrong path handed to dcc.

  THREE THINGS ARE CHECKED, and the split matters:
    * BEHAVIOUR -- `selftest studio-root`, run against the shipping binary, so
      precedence and composition are tested as users get them, not as a
      re-implementation in PowerShell.
    * SOURCE    -- exactly one Studio literal, in DRagLint.Core.StudioEnv.pas.
      A behaviour test alone cannot catch a SECOND literal added elsewhere,
      because the second literal is usually right on this machine too.
    * ROUTING   -- no other unit reads $BDS or names rsvars.bat directly. This
      is the check that catches "I'll just read the env var here as well",
      which is how the eight sites came to exist in the first place.

  RED-CHECKED 2026-09-02: with RsvarsBat returning its own literal instead of
  composing from Root, the behaviour check fails
  ("got C:\Program Files (x86)\...\rsvars.bat, expected C:\SelfTestStudio\...")
  and the source check reports 2 literals. Both were confirmed to go red before
  the fix was restored.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$Src = "$PSScriptRoot\..\..\src",
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  if ($Quiet) { if (-not $ok) { $script:fail = $true }; return }
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int]$ok]), $n) -ForegroundColor (@('Red', 'Green')[[int]$ok])
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (-not (Test-Path $Src)) { Write-Host "FATAL: src not found: $Src" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Src = (Resolve-Path $Src).Path

# The one unit allowed to name a Studio path -- and, deliberately, the one unit
# holding the assertions about it, so that no exemption is needed here.
$OWNER = 'DRagLint.Core.StudioEnv.pas'

<#
  Every string literal in a Pascal file, with its 1-based line number.

  IT MUST BE COMMENT-AWARE. Scanning quotes line by line reported three false
  positives on the first run: a `{ }` block comment in AstChecks.pas documenting
  the very `GetEnvironmentVariable('BDS')` pattern this change removed, and two
  path examples in comments. This repo has a standing record of text scanners
  mistaking comment text for code, and of brace depth tracked as a per-line
  local -- so the state machine below runs over the WHOLE file, not per line.

  Pascal has three comment forms and one string form, and inside a string a
  brace is just a brace. A doubled quote ('') inside a literal is an escaped
  quote, not a terminator -- which matters here because it merely ends the
  literal early and could split one path across two reported literals.
#>
function Get-PascalStringLiterals([string]$Path) {
  $text = [System.IO.File]::ReadAllText($Path)
  $lit = New-Object System.Collections.Generic.List[object]
  $i = 0; $line = 1; $n = $text.Length
  $sb = $null; $startLine = 0
  while ($i -lt $n) {
    $c = $text[$i]
    if ($c -eq "`n") { $line++; $i++; continue }
    if ($null -ne $sb) {
      if ($c -eq "'") {
        if (($i + 1 -lt $n) -and ($text[$i + 1] -eq "'")) { [void]$sb.Append("''"); $i += 2; continue }
        $lit.Add([pscustomobject]@{ Line = $startLine; Text = $sb.ToString() }); $sb = $null; $i++; continue
      }
      [void]$sb.Append($c); $i++; continue
    }
    if ($c -eq "'") { $sb = New-Object System.Text.StringBuilder; $startLine = $line; $i++; continue }
    if (($c -eq '/') -and ($i + 1 -lt $n) -and ($text[$i + 1] -eq '/')) {
      while (($i -lt $n) -and ($text[$i] -ne "`n")) { $i++ }
      continue
    }
    if ($c -eq '{') {
      while (($i -lt $n) -and ($text[$i] -ne '}')) { if ($text[$i] -eq "`n") { $line++ }; $i++ }
      $i++; continue
    }
    if (($c -eq '(') -and ($i + 1 -lt $n) -and ($text[$i + 1] -eq '*')) {
      $i += 2
      while ($i + 1 -lt $n) {
        if ($text[$i] -eq "`n") { $line++ }
        if (($text[$i] -eq '*') -and ($text[$i + 1] -eq ')')) { break }
        $i++
      }
      $i += 2; continue
    }
    $i++
  }
  return $lit
}

# ---------------------------------------------------------------------------
# 1. BEHAVIOUR -- precedence, normalisation, composition.
# ---------------------------------------------------------------------------
$out = (& $Exe selftest studio-root 2>&1 | Out-String).Trim()
$rc = $LASTEXITCODE
Check 'selftest studio-root passes' (($rc -eq 0) -and ($out -match 'STUDIOROOT-OK')) "exit=$rc, output: $out"

# ---------------------------------------------------------------------------
# 2. SOURCE -- exactly one Studio literal, and it lives in the owning unit.
#
# ANCHORED AT A DRIVE ROOT, deliberately. The registry KEY
# (Software\Embarcadero\BDS\37.0) is not a filesystem path and several units
# legitimately name it, and CompileCheck matches the SEARCH NEEDLE
# '\embarcadero\studio\37.0\' against library entries -- a needle, not a path
# the program uses. What must stay unique is an absolute path that hardcodes
# where Studio lives.
# ---------------------------------------------------------------------------
$pas = Get-ChildItem -Path $Src -Recurse -Filter *.pas -File
$literals = @{}
foreach ($f in $pas) { $literals[$f.FullName] = Get-PascalStringLiterals $f.FullName }

$literalHits = @()
foreach ($f in $pas) {
  foreach ($l in $literals[$f.FullName]) {
    if ($l.Text -match '(?i)^[A-Z]:\\.*Embarcadero\\Studio\\') {
      $literalHits += [pscustomobject]@{ File = $f.Name; Line = $l.Line; Text = $l.Text }
    }
  }
}
Check 'exactly one Studio path literal in src' ($literalHits.Count -eq 1) `
  ("found $($literalHits.Count): " + (($literalHits | ForEach-Object { "$($_.File):$($_.Line)" }) -join ', '))
Check 'the one literal lives in the owning unit' `
  (($literalHits.Count -eq 1) -and ($literalHits[0].File -eq $OWNER)) `
  ("expected $OWNER, found " + (($literalHits | ForEach-Object { $_.File }) -join ', '))

# ---------------------------------------------------------------------------
# 3. ROUTING -- nobody else reads $BDS or names rsvars.bat.
#
# These are the two moves that recreated the problem: an extra env read that
# silently disagrees about the fallback, and an rsvars path stored rather than
# composed.
# ---------------------------------------------------------------------------
$bdsReaders = @()
$rsvarsNamers = @()
foreach ($f in $pas) {
  if ($f.Name -eq $OWNER) { continue }
  foreach ($l in $literals[$f.FullName]) {
    if ($l.Text -ceq 'BDS') { $bdsReaders += "$($f.Name):$($l.Line)" }
    if ($l.Text -match '(?i)rsvars\.bat') { $rsvarsNamers += "$($f.Name):$($l.Line)" }
  }
}
Check 'no other unit reads the BDS environment variable' ($bdsReaders.Count -eq 0) `
  ($bdsReaders -join ', ')
Check 'no other unit names rsvars.bat' ($rsvarsNamers.Count -eq 0) `
  ($rsvarsNamers -join ', ')

if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
