<#
  run_bare_raise_no_exception.ps1 -- a bare `raise;` (a re-raise) must contribute
  NO exception class to the generated `<exception cref>` facts.

  WHY THIS EXISTS, stated honestly: it PINS behaviour that is already correct.
  `CollectRaiseClass` (src\doc\DRagLint.Doc.Facts.pas) captures the identifier
  that FOLLOWS the `raise` keyword, so `raise;` -- whose next token is `;` --
  adds nothing. That is right: a re-raise propagates the exception already in
  flight, it does not introduce a new one, and listing a class there would be a
  fabricated fact in generated documentation.

  docs\INBOX-report-exceptions-raised-and-handled.md gap 4 records exactly this
  and says: "Not yet pinned by a fixture; when this note is worked, that fixture
  is the cheapest thing in it." This is that fixture.

  A characterization test EARNS ITS PLACE ONLY THROUGH ITS CONTROLS. "No cref was
  written" also passes when the miner is switched off, when the fixture fails to
  index, and when `document` writes nothing at all -- so cases 2 and 3 assert
  that real raises ARE still mined, in the same run, from the same file.

    1. OnlyBareRaise (`raise;` only)     -> ZERO <exception cref>   <- THE PIN
    2. RaisesFoo (`raise EFoo.Create`)   -> exactly one, EFoo       <- control
    3. BareAndReal (both, in that order) -> exactly one, EBar       <- control
    4. no cref anywhere names a keyword or is empty

  Case 3 is the interesting one: a bare `raise` sitting in the same body as a
  real one must neither add a phantom class nor suppress the real one.

  RED-CHECK, run 2026-09-04 against a build with CollectRaiseClass altered to
  record a class for a `raise` whose next token is NOT an identifier. Stated as
  measured rather than as predicted -- the prediction was "case 1 fails", and
  case 3 failed too:

      crefs: OnlyBareRaise=[Exception] RaisesFoo=[EFoo] BareAndReal=[Exception,EBar]
      [FAIL] 1. a bare `raise;` contributes NO exception cref
      [PASS] 2. CONTROL: `raise EFoo.Create` IS mined, exactly once
      [FAIL] 3. CONTROL: a body with BOTH yields exactly one cref, the real one
      [PASS] 4. no cref is empty or a Pascal keyword

  Case 3 failing is the more informative half: the phantom class is prepended to
  the real one, so a body with both raises would have documented TWO exceptions
  where one is thrown. Case 2 passing in the RED run is what proves the run
  exercised a live miner rather than a dead one.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path

$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

$WorkDir = Join-Path $env:TEMP ("bare_raise_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$pas = Join-Path $WorkDir 'uRaise.pas'

[System.IO.File]::WriteAllText($pas, ((@'
unit uRaise;

interface

type
  EFoo = class(Exception)
  end;

  EBar = class(Exception)
  end;

procedure OnlyBareRaise;
procedure RaisesFoo;
procedure BareAndReal;

implementation

uses
  System.SysUtils;

// THE PIN: a re-raise propagates the exception already in flight. It introduces
// no new class, so it must contribute no <exception cref>.
procedure OnlyBareRaise;
begin
  try
    Beep;
  except
    raise;
  end;
end;

// CONTROL: a real raise MUST still be mined, or case 1 passes for the wrong
// reason (the miner being dead rather than correct).
procedure RaisesFoo;
begin
  raise EFoo.Create('boom');
end;

// CONTROL: both in one body. The bare raise must neither add a phantom class
// nor suppress the real one.
procedure BareAndReal;
begin
  try
    raise EBar.Create('boom');
  except
    raise;
  end;
end;

end.
'@ -replace "`r`n", "`n") -replace "`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))

$db = Join-Path $WorkDir 'raise.sqlite'
& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'fixture indexed' ((Test-Path $db) -and ($LASTEXITCODE -eq 0))

& $Exe document --unit $pas --db $db --apply --no-backup 2>&1 | Out-Null
Check 'document --apply exits 0' ($LASTEXITCODE -eq 0)

$lines = [System.IO.File]::ReadAllLines($pas)

# The exception facts are written as `///` lines immediately ABOVE the routine's
# INTERFACE declaration. Walk up from the declaration through the contiguous
# comment block and collect the crefs there -- reading the whole file and
# grepping would attribute any cref to any routine, which is exactly the
# confusion cases 2 and 3 exist to detect.
function CrefsAbove([string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $declPattern) { $idx = $i; break }
  }
  if ($idx -lt 0) { return $null }   # null = declaration not found, distinct from "found, zero crefs"
  $crefs = @()
  for ($j = $idx - 1; $j -ge 0; $j--) {
    if ($lines[$j] -notmatch '^\s*///') { break }
    if ($lines[$j] -match '<exception\s+cref="([^"]*)"') { $crefs += $Matches[1] }
  }
  return ,$crefs
}

$bare = CrefsAbove '^\s*procedure\s+OnlyBareRaise\s*;'
$foo  = CrefsAbove '^\s*procedure\s+RaisesFoo\s*;'
$both = CrefsAbove '^\s*procedure\s+BareAndReal\s*;'

Check 'all three declarations located' (($null -ne $bare) -and ($null -ne $foo) -and ($null -ne $both)) `
  'if a declaration is missing the assertions below would read as zero crefs and pass for the wrong reason'

Write-Host ("crefs: OnlyBareRaise=[{0}] RaisesFoo=[{1}] BareAndReal=[{2}]" -f `
  ($bare -join ','), ($foo -join ','), ($both -join ','))

# 1. THE PIN
Check '1. a bare `raise;` contributes NO exception cref' (@($bare).Count -eq 0) `
  "got: $($bare -join ', ')"

# 2/3. CONTROLS -- the miner is alive and attributes correctly
Check '2. CONTROL: `raise EFoo.Create` IS mined, exactly once' `
  ((@($foo).Count -eq 1) -and ($foo[0] -eq 'EFoo')) "got: $($foo -join ', ')"
Check '3. CONTROL: a body with BOTH yields exactly one cref, the real one' `
  ((@($both).Count -eq 1) -and ($both[0] -eq 'EBar')) "got: $($both -join ', ')"

# 4. nothing captured a keyword or an empty name
$all = @($bare) + @($foo) + @($both)
$bad = @($all | Where-Object { ($_ -eq '') -or ($_ -match '^(raise|try|except|end|begin)$') })
Check '4. no cref is empty or a Pascal keyword' ($bad.Count -eq 0) "got: $($bad -join ', ')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
