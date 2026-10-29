<#
  run_called_from_type_filter.ps1 -- item 4 (untypable receivers), spec s.5 / plan C2: the
  `Called from:` NAME bucket drops a candidate whose refs.receiver_type_text names a type that
  resolves in THIS store and is neither the target's owner nor related to it.

  Fixture called_from_type: TMine.Add is called by RealMine (certain), RealKid (certain, a
  descendant receiver), LibTyped (receiver TList<string>, a LIBRARY type this store does not
  declare: unknown is not foreign, so it stays, marked '?'), and ForeignTyped (receiver TOther,
  declared TWICE in ctf_a / ctf_b so the call stays unresolved by name; TOther is a project type
  unrelated to TMine: provably foreign, must be DROPPED -- the original defect, a fabricated caller).
  Untyped (a Variant receiver) is not asserted: the C14 gate already owns it.

  Positive control: LibTyped and RealMine are still listed (the filter must not over-drop);
  run_receiver_bucket.ps1 is the second control and must stay GREEN UNCHANGED.
  RED until the resolver lane writes refs.receiver_type_text. Run from a NEUTRAL CWD (C:\TEMP).
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path
$fixDir  = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures\called_from_type')).Path
$scratch = Join-Path C:\TEMP "draglint_cftype_$PID"
try {
  if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
  New-Item -ItemType Directory -Path $scratch | Out-Null
  Copy-Item (Join-Path $fixDir '*.pas') $scratch -Force
  $db = Join-Path $scratch 'cf.sqlite'
  Push-Location C:\TEMP
  try {
    & $exePath index $scratch --db $db 2>$null | Out-Null
    Check 'index built' ($LASTEXITCODE -eq 0)
    $doc = (& $exePath document --unit (Join-Path $scratch 'ctf.pas') --db $db 2>$null) -join "`n"
    # the Called from: line belongs to TMine.Add: the doc block that follows `TMine = class` ... find it by its callers
    $lines = @($doc -split "`n" | Where-Object { $_ -match 'Called from:' -and $_ -match 'RealMine' })
    Check 'a Called from: line naming RealMine exists' ($lines.Count -eq 1) ($lines -join ' | ')
    $cf = if ($lines.Count -ge 1) { $lines[0] } else { '' }
    Check 'REAL: RealMine listed'                         ($cf -match 'ctf\.RealMine')
    Check 'REAL: RealKid (descendant receiver) listed'    ($cf -match 'ctf\.RealKid')
    Check 'CONTROL: LibTyped (library type) KEPT, marked ?' ($cf -match 'ctf\.LibTyped \(ctf\.pas\) \?') $cf
    Check 'FABRICATED: ForeignTyped (foreign project type) DROPPED' ($cf -notmatch 'ForeignTyped') $cf
  } finally { Pop-Location }
} finally {
  if (Test-Path -LiteralPath $scratch) { [IO.Directory]::Delete($scratch, $true) }
}
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
