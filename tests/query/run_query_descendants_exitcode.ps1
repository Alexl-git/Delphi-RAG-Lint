<#
  run_query_descendants_exitcode.ps1 --
  `query descendants` returns a full result set and exits 1.

  REPORTED BY THE CONVERTER TEAM, 2026-09-09
  (docs\INBOX-REPLY-2026-09-09-converter-two-engine-cli-findings.md item 2):

      drag-lint query descendants --of TComponent --db library-Win64.sqlite
        -> 6323 class names on stdout, EXIT 1

  Reproduced here 2026-09-14 on the same corpus, unchanged: 6323 lines, exit 1.

  THE CAUSE IS NOT A WRONG CONSTANT, IT IS A USE-AFTER-FREE. DRagLint.CLI.pas
  frees the result list in a `finally` and then reads `.Count` off the freed
  object on the NEXT line to choose the exit code:

      finally
        Names.Free;
      end;
      if Names.Count = 0 then Result:= 1 else Result:= 0;

  So the exit code is read out of released memory. "Always 1" is not guaranteed
  either -- it is whatever the memory manager left behind, which is why this must
  be pinned by a test rather than trusted to keep reproducing.

  WHY IT MATTERS MORE THAN AN ODD NUMBER. The converter team's adapter now treats
  ONLY exit 2 as failure for this verb, and says plainly that this undocumented
  workaround is the sole thing keeping their FROM/TO pickers populated. Any caller
  writing the obvious `if Code <> 0 then fail`, or chaining with `&&`, gets an
  empty picker and no explanation.

  THE EMPTY CASE IS ASSERTED TOO, and that is the half that makes this a real
  guard: "descendants found -> 0" alone would pass if someone hardcoded Exit(0),
  which would destroy the only signal a caller has for "no such ancestor".

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_query_descendants"
)
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }
function Write-Ascii($p,$t){ [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"), [System.Text.Encoding]::ASCII) }

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null

# A self-contained hierarchy, so the test does not depend on a library index
# existing on the machine that runs it.
Write-Ascii (Join-Path $src 'uShapes.pas') @'
unit uShapes;

interface

type
  TBase = class(TObject)
  end;

  TMiddle = class(TBase)
  end;

  TLeafOne = class(TMiddle)
  end;

  TLeafTwo = class(TMiddle)
  end;

implementation

end.
'@

$db  = Join-Path $WorkDir 'desc.sqlite'
$out = Join-Path $WorkDir 'o.txt'
$err = Join-Path $WorkDir 'e.txt'

& $exePath index $src --db $db 2>&1 | Out-Null

function RunDescendants([string]$Ancestor) {
  $p = Start-Process -FilePath $exePath `
        -ArgumentList @('query','descendants','--of',$Ancestor,'--db',$db) `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $lines = @(Get-Content -LiteralPath $out -ErrorAction SilentlyContinue |
             Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\(loaded defaults' })
  return @{ Code = $p.ExitCode; Lines = $lines }
}

Push-Location C:\TEMP
try {
  $hit = RunDescendants 'TBase'

  # VACUITY: if the fixture yielded no descendants the exit-code assertion below
  # would be testing the empty path while claiming to test the populated one.
  Check 'VACUITY the fixture really has descendants of TBase' `
        (($hit.Lines | Where-Object { $_ -notmatch '^\(none\)$' }).Count -gt 0) `
        ("stdout was: " + ($hit.Lines -join ' | '))

  # ---- Q1: THE DEFECT ------------------------------------------------------
  Check 'Q1 descendants found -> exit 0' `
        ($hit.Code -eq 0) `
        ("got exit $($hit.Code) alongside $($hit.Lines.Count) result line(s)" +
         " -- CLI.pas reads Names.Count AFTER Names.Free, so this is read from released memory")

  # ---- Q2: the empty case must stay distinguishable ------------------------
  $miss = RunDescendants 'TNoSuchAncestorAnywhere'
  Check 'Q2 no descendants -> exit 1 (still a usable signal)' `
        ($miss.Code -eq 1) `
        ("got exit $($miss.Code) -- if this became 0 a caller could no longer tell" +
         " 'no such ancestor' from 'found some', which is worse than the original bug")
}
finally { Pop-Location }

Write-Host ''
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
