<#
  run_format_verb_guard.ps1 --
  `drag-lint format` REWRITES THE USER'S SOURCE, and until now nothing tested it.

  THE STATE THIS REPLACES (measured 2026-09-15/16).

  * `Select-String -Pattern 'TYadfFormatter|drag-lint format|yadf-path'` over
    tests\**\*.ps1 returned ZERO files. A verb that overwrites .pas files on
    disk had no coverage at all, which is how a seventeen-releases-stale YADF
    stayed wired in for months without anything going red.
  * Both hardcoded fallbacks pointed at **Win32** paths --
    C:\Projects\YADF\Win32\{Release,Debug}\EXE\YADF.exe -- and YADF has never
    been built Win32 on this box. Every real build is Win64, so both fallbacks
    were dead code that could never resolve. They also each carried a `dl:ok
    hardcoded-absolute-path` review reading "an existence-checked dev-box
    fallback, never the only source" -- a justification for the exact mechanism
    that made the defect silent.
  * **YADF EXPOSES NO `--version`.** `YADF.exe --version` exits 2 with
    "unknown option --version (run yadf --help for the flag list)". The plan
    for this work proposed spawning a version probe; that design is not
    buildable. The gate reads the exe's VERSION RESOURCE instead, which needs
    no cooperation from YADF and costs no subprocess.

  WHY THE BELOW-FLOOR CONTROL USES REAL BINARIES, NOT A STUB. A .bat stub has
  no version resource, so it cannot carry a version and cannot exercise a
  resource-based gate. This box has two real YADF builds with DIFFERENT
  versions -- Win64\Release = 1.0.17.0 (above the 1.0.6.6 floor) and
  Win64\Debug = 1.0.3.0 (below it). Using both proves the refusal keys on the
  VERSION rather than on the binary's identity, which is exactly what the
  plan's "POSITIVE CONTROL 2" asked for and what a stub could never show.
  Note the Debug build is OLDER IN VERSION but NEWER ON DISK (mtime 09-14 vs
  09-10): mtime does not order versions, so a "use the newest file" fallback
  would have picked the below-floor one.

  Those two assertions SKIP (loudly, not silently) when YADF is not installed,
  because a machine without YADF cannot answer the question either way. Every
  other assertion runs everywhere, using .bat stubs.

  WHAT AN ABSENT VERSION RESOURCE MEANS, and why it is not a refusal. A stub or
  wrapper script has no version info. Refusing everything unverifiable would
  break the `--yadf-path` escape hatch for no safety gain, because the real
  protection against a bad formatter is the POST-FORMAT VERIFICATION below,
  which runs regardless of version. Unknown version therefore proceeds WITH A
  WARNING; a known-and-too-old version is refused outright.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index and
  no file outside $WorkDir.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_format_verb"
)
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check($n,$ok,$d=''){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
function Skip($n,$why){ Write-Host ("[SKIP] {0}" -f $n) -ForegroundColor Yellow; Write-Host "      $why" -ForegroundColor DarkGray }
function Write-Ascii($p,$t){ [IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [Text.Encoding]::ASCII) }
function Sha($p){ (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir -Force | Out-Null

$SRC = @'
unit uFmt;

interface

type
  TThing = class(TObject)
  public
    function Compute(const AValue: Integer): Integer;
  end;

implementation

function TThing.Compute(const AValue: Integer): Integer;
begin
  Result := AValue * 2;
end;

end.
'@

function NewFixture([string]$Name) {
  $p = Join-Path $WorkDir $Name
  Write-Ascii $p $SRC
  return $p
}

# --- stubs -----------------------------------------------------------------
# HARMLESS: appends a trailing blank line. The file CHANGES (so a "nothing was
# written" assertion cannot pass by the formatter doing nothing) but the SYMBOL
# SET does not, so post-format verification must accept it.
$stubOk = Join-Path $WorkDir 'yadf_ok.bat'
Write-Ascii $stubOk @'
@echo off
echo.>> %1
echo stub-ok formatted %1
exit /b 0
'@

# CORRUPTING: deletes the `implementation` keyword. The file still exists and
# the stub reports success, so ONLY a post-format parse can catch this.
$stubBad = Join-Path $WorkDir 'yadf_corrupt.bat'
Write-Ascii $stubBad @'
@echo off
powershell -NoProfile -Command "$p='%1'; $t=[IO.File]::ReadAllText($p); $t=$t -replace 'implementation',''; [IO.File]::WriteAllText($p,$t,[Text.Encoding]::ASCII)"
echo stub-corrupt rewrote %1
exit /b 0
'@

# ---------------------------------------------------------------------------
# A1 POSITIVE CONTROL -- the happy path really works.
# Without this, every "refused / unchanged" assertion below would also pass
# against a build where `format` simply always fails.
# ---------------------------------------------------------------------------
$f1 = NewFixture 'ok.pas'; $h1 = Sha $f1
$o1 = (& $Exe format $f1 --yadf-path $stubOk 2>&1) -join "`n"; $e1 = $LASTEXITCODE
Check 'A1 POSITIVE CONTROL an above-board formatter run exits 0' ($e1 -eq 0) "exit=$e1`n$o1"
Check 'A1b POSITIVE CONTROL and the file really was rewritten' ((Sha $f1) -ne $h1) `
      'the file is byte-identical, so every "unchanged" assertion below proves nothing'

# ---------------------------------------------------------------------------
# A2 -- post-format verification catches a corrupting formatter and RESTORES.
# This is the assertion that would have caught the inline-var split as a defect
# instead of as a bug report.
# ---------------------------------------------------------------------------
$f2 = NewFixture 'corrupt.pas'; $h2 = Sha $f2
$o2 = (& $Exe format $f2 --yadf-path $stubBad 2>&1) -join "`n"; $e2 = $LASTEXITCODE
Check 'A2 a formatter that corrupts the file exits NON-ZERO' ($e2 -ne 0) "exit=$e2`n$o2"
Check 'A2b and the original file is RESTORED byte-for-byte' ((Sha $f2) -eq $h2) `
      "the corrupted text was left on disk -- this is the data-loss case:`n$o2"
Check 'A2c and the message says what diverged' ($o2 -match '(?i)verif|restor|symbol') `
      "the operator is told it failed but not what changed:`n$o2"

# ---------------------------------------------------------------------------
# A3 -- --dry-run resolves and reports, and writes NOTHING.
# ---------------------------------------------------------------------------
$f3 = NewFixture 'dry.pas'; $h3 = Sha $f3
$o3 = (& $Exe format $f3 --yadf-path $stubOk --dry-run 2>&1) -join "`n"; $e3 = $LASTEXITCODE
Check 'A3 --dry-run exits 0' ($e3 -eq 0) "exit=$e3`n$o3"
Check 'A3b --dry-run writes NOTHING' ((Sha $f3) -eq $h3) "the file changed under --dry-run:`n$o3"
Check 'A3c --dry-run names the binary it WOULD run' ($o3 -match [regex]::Escape('yadf_ok.bat')) `
      "the operator cannot see WHICH binary would run -- the whole point of the flag:`n$o3"

# ---------------------------------------------------------------------------
# A4 -- --diff shows the change and writes NOTHING.
# ---------------------------------------------------------------------------
$f4 = NewFixture 'diff.pas'; $h4 = Sha $f4
$o4 = (& $Exe format $f4 --yadf-path $stubOk --diff 2>&1) -join "`n"; $e4 = $LASTEXITCODE
Check 'A4 --diff exits 0' ($e4 -eq 0) "exit=$e4`n$o4"
Check 'A4b --diff writes NOTHING' ((Sha $f4) -eq $h4) "the file changed under --diff:`n$o4"
Check 'A4c --diff emits a unified-diff body' ($o4 -match '(?m)^[-+@]') `
      "no diff markers in the output:`n$o4"

# ---------------------------------------------------------------------------
# A5 ABSENCE CONTROL -- no registry value and no --yadf-path is a LOUD miss.
# This is the row that goes red if somebody reintroduces a hardcoded path.
# The registry is not touched; instead --yadf-path points at a path that does
# not exist, which exercises the same "resolved to nothing usable" branch
# without mutating the machine's HKCU.
# ---------------------------------------------------------------------------
$f5 = NewFixture 'missing.pas'; $h5 = Sha $f5
$ghost = Join-Path $WorkDir 'no_such_yadf.exe'
$o5 = (& $Exe format $f5 --yadf-path $ghost 2>&1) -join "`n"; $e5 = $LASTEXITCODE
Check 'A5 ABSENCE CONTROL an unresolvable YADF exits non-zero' ($e5 -ne 0) "exit=$e5`n$o5"
Check 'A5b ABSENCE CONTROL and writes nothing' ((Sha $f5) -eq $h5) "the file changed despite no formatter:`n$o5"
Check 'A5c ABSENCE CONTROL the message names the two real routes (--yadf-path / registry)' `
      (($o5 -match '(?i)yadf-path') -and ($o5 -match '(?i)registry')) `
      "the operator is not told how to fix it:`n$o5"
Check 'A5d ABSENCE CONTROL no hardcoded Win32 dev-box path is mentioned' `
      (-not ($o5 -match '(?i)YADF\\Win32\\')) `
      "a hardcoded fallback path has been reintroduced:`n$o5"

# ---------------------------------------------------------------------------
# A6/A7 -- the VERSION FLOOR, proved with two real binaries of different
# versions. Skipped (loudly) when YADF is not installed.
# ---------------------------------------------------------------------------
$yRel = 'C:\Projects\YADF\Win64\Release\EXE\YADF.exe'
$yDbg = 'C:\Projects\YADF\Win64\Debug\EXE\YADF.exe'
$vRel = if (Test-Path $yRel) { (Get-Item $yRel).VersionInfo.FileVersion } else { $null }
$vDbg = if (Test-Path $yDbg) { (Get-Item $yDbg).VersionInfo.FileVersion } else { $null }

if ($vDbg -and $vRel) {
  Write-Host "      [NOTE] real YADF builds: Release=$vRel  Debug=$vDbg" -ForegroundColor DarkGray

  $f6 = NewFixture 'floor.pas'; $h6 = Sha $f6
  $o6 = (& $Exe format $f6 --yadf-path $yDbg 2>&1) -join "`n"; $e6 = $LASTEXITCODE
  Check "A6 a BELOW-FLOOR YADF ($vDbg) is refused" ($e6 -ne 0) "exit=$e6`n$o6"
  Check 'A6b and nothing is written' ((Sha $f6) -eq $h6) "a below-floor formatter rewrote the file:`n$o6"
  Check 'A6c the refusal names the found version, the floor, and the path' `
        (($o6 -match [regex]::Escape($vDbg)) -and ($o6 -match '1\.0\.6\.6') -and ($o6 -match '(?i)yadf\.exe')) `
        "the operator cannot see WHICH binary was rejected or why:`n$o6"

  # POSITIVE CONTROL 2, the plan's own: the refusal must key on the VERSION,
  # not on "it was a real YADF" or "it was a Debug build".
  $f7 = NewFixture 'abovefloor.pas'; $h7 = Sha $f7
  $o7 = (& $Exe format $f7 --yadf-path $yRel 2>&1) -join "`n"; $e7 = $LASTEXITCODE
  Check "A7 POSITIVE CONTROL an ABOVE-floor YADF ($vRel) is accepted" ($e7 -eq 0) "exit=$e7`n$o7"
  Check 'A7b POSITIVE CONTROL the accepted run is not refused for version' `
        (-not ($o7 -match '(?i)below the required')) "$o7"
} else {
  Skip 'A6/A7 version-floor assertions' `
       "YADF not installed at $yRel / $yDbg -- this machine cannot answer the version question either way. Assertions NOT counted as passing."
}

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
