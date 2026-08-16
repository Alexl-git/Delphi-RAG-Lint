<#
  run_receiver_qualified_cross_unit.ps1 -- `OtherUnit.TType.Create(...)` resolves
  ACROSS units.

  INBOX-qualified-type-receiver-does-not-resolve. That note, and a later
  re-diagnosis banner on it, were BOTH out of date -- measured 2026-08-16:

    * the note said `call_edges` held only the unqualified caller (1 edge);
    * the banner said no `Create` ref was emitted for the qualified form at all.

  Neither is true of current code. `receiver_bucket.pas` resolves both callers as
  [certain], and `run_receiver_bucket.ps1` already asserts exactly that. The note
  had simply never been closed.

  What was genuinely NOT covered is this file's subject: receiver_bucket.pas
  qualifies with its OWN unit name, which is the easy case. Delphi forces
  qualification when two USED units export the same type name -- i.e. across
  units -- so that is the shape a developer actually writes, and nothing pinned
  it. This suite pins it.

    MakePlain     unqualified            -> resolves [certain]   (positive control:
                                            if this fails the harness is broken and
                                            the MakeQualified result means nothing)
    MakeQualified qual_decl.TOnlyOnce    -> resolves [certain]   (the subject)
    NoiseUnknown  uNotIndexed.TStranger  -> must NOT resolve     (negative control:
                                            keeps the resolver honest; a resolver
                                            that matched every leaf name would pass
                                            the first two and fail this one)

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures')).Path

$scratch = Join-Path C:\TEMP 'draglint_qualcross'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $fixDir 'qual_decl.pas') $scratch -Force
Copy-Item (Join-Path $fixDir 'qual_call.pas') $scratch -Force
$db = Join-Path $scratch 'qual.sqlite'

Push-Location C:\TEMP
try {
  $idx = & $exePath index $scratch --db $db 2>&1 | Out-String
  Check 'SANITY: both fixture units indexed with no errors' `
        (($idx -match 'qual_decl\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors') -and
         ($idx -match 'qual_call\.pas\s*->\s*\d+ symbols, \d+ refs, 0 errors')) $idx

  $res = & $exePath query find-callers --name Create --resolved --db $db 2>&1 | Out-String

  Check 'the constructor is the resolved target' `
        ($res -match 'qual_decl\.TOnlyOnce\.Create') $res
  Check 'POSITIVE CONTROL: MakePlain (unqualified) resolves [certain]' `
        ($res -match 'qual_call\.MakePlain\b[^\r\n]*\[certain\]') $res
  Check 'SUBJECT: MakeQualified (qual_decl.TOnlyOnce.Create) resolves [certain]' `
        ($res -match 'qual_call\.MakeQualified\b[^\r\n]*\[certain\]') $res
  Check 'NEGATIVE CONTROL: NoiseUnknown does NOT resolve' `
        ($res -notmatch 'qual_call\.NoiseUnknown') $res
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
