<#
  run_index_include_defines.ps1 -- {$DEFINE} inside an {$I} include must reach
  the including unit ON THE INDEX PATH.

  INBOX-parse-error-shellshock-units. run_include_modes.ps1 already proves the
  preprocessor gets this right in 'defines-only' mode; the defect was that
  TIndexer called the 2-arg Preprocess overload, whose IncludeMode is 'off' --
  includes blanked, their defines discarded. So the engine was correct and
  simply never asked for.

  Three TurboPower ShellShock units (SsShlDlg / StShlCtl / StShlDD) were the
  visible symptom: each carries a deliberate `!! Error:` compile-breaker inside
  {$IFNDEF VERSION3}, and VERSION3 is defined in SsDefine.inc. With the include
  defines dropped the branch stayed live, the breaker was parsed as code, and
  StShlCtl.pas yielded 0 symbols / 1 error instead of 1622 symbols / 11053 refs.

  Everywhere ELSE the same bug is SILENT -- a unit taking its feature defines
  from a shared .inc just gets the wrong branch indexed, with no error at all.
  That is why this suite exists at the index level and not only at preprocess
  level.

  Fixtures (fixtures\inc_defines):
    viainc.pas    RED      -- define arrives via {$I guard.inc}; must index clean.
    inlinedef.pas CONTROL+ -- same shape, define INLINE; passed before the fix
                              too. Proves nested conditionals were never the
                              problem, so a viainc failure is about the include
                              boundary specifically.
    noinc.pas     CONTROL- -- includes nothing; the breaker MUST still fire.
                              This is the one that fails if the fix is done by
                              seeding defines globally, or if one file's include
                              defines leak into the next file of the same run.
                              Without it, "viainc parses" is achievable by
                              defining everything everywhere.

  BASELINE against the UNFIXED exe (recorded 2026-08-16):
    viainc FAIL, inlinedef PASS, noinc PASS.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\inc_defines')).Path

$scratch = Join-Path C:\TEMP 'draglint_incdefines'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir '*') $scratch -Force
$db = Join-Path $scratch 'inc.sqlite'

Push-Location C:\TEMP
try {
  $out = & $exePath index $scratch --db $db 2>&1 | Out-String

  # Per-file result lines look like:  <path> -> N symbols, M refs, K errors
  function Stat($file) {
    foreach ($ln in ($out -split "`r?`n")) {
      if ($ln -match [regex]::Escape($file) + '\s*->\s*(\d+) symbols, (\d+) refs, (\d+) errors') {
        return @{ Sym = [int]$Matches[1]; Refs = [int]$Matches[2]; Err = [int]$Matches[3] }
      }
    }
    return $null
  }

  $v = Stat 'viainc.pas'
  $i = Stat 'inlinedef.pas'
  $n = Stat 'noinc.pas'

  # Sanity: all three files were actually walked. Without this the asserts below
  # could pass vacuously on a run that indexed nothing.
  Check 'SANITY: all three fixtures were indexed' (($null -ne $v) -and ($null -ne $i) -and ($null -ne $n))

  if ($null -ne $v) {
    Check 'RED: viainc.pas parses (include {$DEFINE} reached the unit)' ($v.Err -eq 0)
    Check 'RED: viainc.pas yields symbols (unit not lost)'              ($v.Sym -ge 1)
  }
  if ($null -ne $i) {
    Check 'CONTROL+: inlinedef.pas still parses (inline define unaffected)' (($i.Err -eq 0) -and ($i.Sym -ge 1))
  }
  if ($null -ne $n) {
    Check 'CONTROL-: noinc.pas STILL fails (no global seeding, no cross-file leak)' (($n.Err -ge 1) -and ($n.Sym -eq 0))
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
