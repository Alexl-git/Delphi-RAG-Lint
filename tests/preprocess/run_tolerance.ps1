<#
  run_tolerance.ps1 -- v1.2.1 preprocessor port change #5: the dcc-tolerance
  pass (tolerance.js). Two dcc32-verified constructs where dcc silently
  imagines a terminating ';' are normalized by REPLACING one adjacent
  whitespace byte (space 32 / tab 9 / CR 13 -- NEVER LF 10) with ';' (byte 59):

    Rule A -- the FINAL routine-directive group without its ';':
        function F(...): BOOL; stdcall
      anchors: an earlier ';' on the SAME line + the next CODE line starts
      with a declaration keyword.
    Rule B -- array[..] of T as the LAST record field without its ';':
        padding: array [0 .. 83] of Byte // comment
      anchor: the next CODE line starts with 'end'.

  REPLACEMENT preserves the offset-identity invariant trivially (1 byte ->
  1 byte); a line with no eligible byte (LF-only ending, no trailing
  whitespace) is deliberately left unfixed -- offsets beat the fix.

  NOTE ON THE ORACLE (frozen, no node): unlike the older suites, this one
  does NOT call lib\render.js at run time. The expected outputs were rendered
  ONCE by the reference JS (preprocess includeMode 'off' + tolerances:true --
  matching this verb's defaults) and committed as fixtures\tolerance\
  *.pas.expected snapshots. The suite byte-compares the exe's output against
  those snapshots -- the Delphi implementation is the canonical one; the JS
  is a frozen reference. This is the de-JS test pattern going forward.

  Run from a NEUTRAL CWD (C:\TEMP) so no drag-lint-lint.json is picked up.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$tolDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\tolerance')).Path

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

function BytesEqual($a, $b) {
  if ($a.Length -ne $b.Length) { return $false }
  for ($k = 0; $k -lt $a.Length; $k++) { if ($a[$k] -ne $b[$k]) { return $false } }
  return $true
}

Push-Location C:\TEMP
try {
  $cases = @(
    @{ name = 'tol_a_spaces.pas';           edited = $true  },
    @{ name = 'tol_a_cr.pas';               edited = $true  },
    @{ name = 'tol_a_externalsym.pas';      edited = $true  },
    @{ name = 'tol_a_neg_continuation.pas'; edited = $false },
    @{ name = 'tol_b_comment.pas';          edited = $true  },
    @{ name = 'tol_b_cr.pas';               edited = $true  },
    @{ name = 'tol_b_neg_follower.pas';     edited = $false },
    @{ name = 'tol_scanner_neg.pas';        edited = $false }
  )

  foreach ($case in $cases) {
    $f        = Join-Path $tolDir $case.name
    $in       = [System.IO.File]::ReadAllBytes($f)
    $expected = [System.IO.File]::ReadAllBytes("$f.expected")
    $out      = Run-Pascal $f @('--tolerances')

    # THE offset-identity invariant, always.
    Check "$($case.name): Length(out) == Length(in) [OFFSET-IDENTITY]" ($out.Length -eq $in.Length)

    # Byte-exact match against the frozen JS-rendered snapshot.
    Check "$($case.name): byte-identical to frozen snapshot" (BytesEqual $out $expected)

    # Edited cases must differ from the input; negatives must NOT.
    if ($case.edited) {
      Check "$($case.name): a ';' replacement actually happened" (-not (BytesEqual $out $in))
    } else {
      Check "$($case.name): negative case untouched" (BytesEqual $out $in)
    }
  }

  # WITHOUT --tolerances the pass must not run: output == input for an edited
  # fixture (no directives in it, 'off' include mode => pure identity copy).
  $f   = Join-Path $tolDir 'tol_b_cr.pas'
  $in  = [System.IO.File]::ReadAllBytes($f)
  $out = Run-Pascal $f @()
  Check 'opt-in: WITHOUT --tolerances the fixture passes through untouched' (BytesEqual $out $in)

} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
