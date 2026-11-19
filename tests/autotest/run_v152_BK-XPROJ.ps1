<#
  run_v152_BK-XPROJ.ps1 -- lane v152 BK-XPROJ (backlog B16, B19 + FPM member-could-be-private).

  B16: unused-global judged ONE project at a time flags an interface symbol of a unit
       that another project also compiles and uses. With no manifest section for the
       peer, the peer must still be found: (a) a DB COPY run finds peer copies beside
       --db; (b) a DB in its <project>\_D-RAG folder finds the peers its .groupproj
       lists (own folder or up to two parents) at <peer>\_D-RAG\<peer>.sqlite.
  FPM: member-could-be-private has the same cross-project false positive (a COMMON
       class method called only from the peer project): judged the same way.
  B19: lint-all --project kept findings of the project-COMPOSITION rules only when the
       file lies under the project roots; a unit the project lists from outside its
       roots lost them. They are kept now; other rules stay scoped to the roots.

  Fixture tests\lint\xproj: App1 (owns UShared, lists ..\Outside\UOut.pas), App2 (lists
  ..\App1\UShared.pas and calls UsedOnlyByApp2 + TChunkWriter.WriteChunk), Group.groupproj.
  CASES
    U1  App1 alone: unused-global fires UsedOnlyByApp2 + UsedNowhere, not UsedByApp1 (positive control)
    U2  copy mode (App2.sqlite beside --db): UsedOnlyByApp2 silent
    U3  copy mode: UsedNowhere still fires (positive control)
    U4  _D-RAG + groupproj mode: UsedOnlyByApp2 silent, UsedNowhere fires
    U5  _D-RAG mode WITHOUT the groupproj: UsedOnlyByApp2 fires again (control)
    M1  App1 alone: member-could-be-private fires WriteChunk + OnlyLocal (positive control)
    M2  copy mode: WriteChunk silent, OnlyLocal fires
    M3  _D-RAG + groupproj mode: WriteChunk silent, OnlyLocal fires
    B0  --lint-third-party: used-unit-not-resolvable reports UOut (control: the rule fires there)
    B1  default --project run: used-unit-not-resolvable on UOut (outside the roots) is kept
    B2  default --project run: no NON-composition finding on UOut leaks through
    B3  B1's message says the file lies outside the project roots

  pwsh -File tests\autotest\run_v152_BK-XPROJ.ps1 -Exe <drag-lint.exe>
#>
[CmdletBinding()]
param(
  [string]$Exe = ''
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
. "$PSScriptRoot\lib\HermeticEngine.ps1"; $Exe = Get-HermeticEngine $Exe
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}

$Fixture = Join-Path $PSScriptRoot '..\lint\xproj'
$Work = Join-Path ([IO.Path]::GetTempPath()) ('dl-v152-xproj-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($Work) | Out-Null
Copy-Item -Path (Join-Path $Fixture '*') -Destination $Work -Recurse
$P1 = Join-Path $Work 'App1\App1.dproj'
$P2 = Join-Path $Work 'App2\App2.dproj'

function Lint([string]$db, [string[]]$extra) {
  $raw = (& { $ErrorActionPreference = 'Continue'; & $Exe lint-all --db $db --project $P1 --json --no-stand-down @extra 2>$null }) -join "`n"
  $arr = @()
  try { $arr = @(($raw | ConvertFrom-Json) | ForEach-Object { $_ }) } catch { Write-Host ('  unparsed: ' + $raw.Substring(0, [Math]::Min(200, $raw.Length))) }
  return ,$arr
}
function Hits($findings, [string]$rule, [string]$word) {
  return @($findings | Where-Object { $_.rule -eq $rule -and ('' + $_.message) -match "\b$word\b" }).Count
}
function Index([string]$proj, [string]$db) {
  [IO.Directory]::CreateDirectory((Split-Path $db)) | Out-Null
  $o = (& { $ErrorActionPreference = 'Continue'; & $Exe index --project $proj --db $db 2>&1 | ForEach-Object { "$_" } }) -join "`n"
  if ($LASTEXITCODE -ne 0) { Write-Host $o; throw "index failed: $proj" }
}

try {
  $Solo  = Join-Path $Work 'solo\App1.sqlite'
  $Copy1 = Join-Path $Work 'copies\App1.sqlite'
  $Copy2 = Join-Path $Work 'copies\App2.sqlite'
  $Real1 = Join-Path $Work 'App1\_D-RAG\App1.sqlite'
  $Real2 = Join-Path $Work 'App2\_D-RAG\App2.sqlite'
  Index $P1 $Solo; Index $P1 $Copy1; Index $P2 $Copy2; Index $P1 $Real1; Index $P2 $Real2

  $UG = 'unused-global'; $MP = 'member-could-be-private'
  $s = Lint $Solo @('--rule', $UG)
  Check 'U1 alone: UsedOnlyByApp2 + UsedNowhere fire, UsedByApp1 silent' ((Hits $s $UG 'UsedOnlyByApp2') -eq 1 -and (Hits $s $UG 'UsedNowhere') -eq 1 -and (Hits $s $UG 'UsedByApp1') -eq 0) ("n=$($s.Count)")
  $c = Lint $Copy1 @('--rule', $UG)
  Check 'U2 copy mode: UsedOnlyByApp2 silent (App2 copy beside --db uses it)' ((Hits $c $UG 'UsedOnlyByApp2') -eq 0) ("hits=$(Hits $c $UG 'UsedOnlyByApp2')")
  Check 'U3 copy mode: UsedNowhere still fires' ((Hits $c $UG 'UsedNowhere') -eq 1) ("hits=$(Hits $c $UG 'UsedNowhere')")
  $g = Lint $Real1 @('--rule', $UG)
  Check 'U4 _D-RAG + groupproj: UsedOnlyByApp2 silent, UsedNowhere fires' ((Hits $g $UG 'UsedOnlyByApp2') -eq 0 -and (Hits $g $UG 'UsedNowhere') -eq 1) ("only=$(Hits $g $UG 'UsedOnlyByApp2') nowhere=$(Hits $g $UG 'UsedNowhere')")

  $sm = Lint $Solo @('--rule', $MP)
  Check 'M1 alone: member-could-be-private fires WriteChunk + OnlyLocal' ((Hits $sm $MP 'WriteChunk') -eq 1 -and (Hits $sm $MP 'OnlyLocal') -eq 1) ("n=$($sm.Count)")
  $cm = Lint $Copy1 @('--rule', $MP)
  Check 'M2 copy mode: WriteChunk silent, OnlyLocal fires' ((Hits $cm $MP 'WriteChunk') -eq 0 -and (Hits $cm $MP 'OnlyLocal') -eq 1) ("wc=$(Hits $cm $MP 'WriteChunk') ol=$(Hits $cm $MP 'OnlyLocal')")
  $gm = Lint $Real1 @('--rule', $MP)
  Check 'M3 _D-RAG + groupproj: WriteChunk silent, OnlyLocal fires' ((Hits $gm $MP 'WriteChunk') -eq 0 -and (Hits $gm $MP 'OnlyLocal') -eq 1) ("wc=$(Hits $gm $MP 'WriteChunk') ol=$(Hits $gm $MP 'OnlyLocal')")

  [IO.File]::Move((Join-Path $Work 'Group.groupproj'), (Join-Path $Work 'Group.groupproj.off'))
  $ng = Lint $Real1 @('--rule', $UG)
  Check 'U5 _D-RAG WITHOUT groupproj: UsedOnlyByApp2 fires again' ((Hits $ng $UG 'UsedOnlyByApp2') -eq 1) ("hits=$(Hits $ng $UG 'UsedOnlyByApp2')")
  [IO.File]::Move((Join-Path $Work 'Group.groupproj.off'), (Join-Path $Work 'Group.groupproj'))

  $UR = 'used-unit-not-resolvable'
  $onOut = { param($fs) ,@($fs | Where-Object { ('' + $_.file_path) -match 'UOut\.pas$' }) }
  $tp = Lint $Solo @('--lint-third-party')
  $tpOut = & $onOut $tp
  Check 'B0 --lint-third-party: used-unit-not-resolvable reports UOut' (@($tpOut | Where-Object { $_.rule -eq $UR }).Count -ge 1) ("rules=" + (($tpOut | ForEach-Object { $_.rule }) -join ','))
  $d = Lint $Solo @()
  $dOut = & $onOut $d
  $kept = @($dOut | Where-Object { $_.rule -eq $UR })
  Check 'B1 default --project run keeps used-unit-not-resolvable on UOut (outside the roots)' ($kept.Count -ge 1) ("rules=" + (($dOut | ForEach-Object { $_.rule }) -join ','))
  $leak = @($dOut | Where-Object { $_.rule -notin @($UR, 'unit-not-in-dpr', 'unit-used-by-no-unit', 'ancestor-not-in-project', 'unit-not-in-library', 'dependent-project-not-recompiled') })
  $tpOther = @($tpOut | Where-Object { $_.rule -ne $UR })
  Check 'B2 no non-composition finding on UOut leaks (and --lint-third-party has some)' ($leak.Count -eq 0 -and $tpOther.Count -ge 1) ("leak=" + (($leak | ForEach-Object { $_.rule }) -join ',') + " tpOther=$($tpOther.Count)")
  Check 'B3 the kept message names the project roots' (@($kept | Where-Object { ('' + $_.message) -match 'outside the project roots' }).Count -ge 1) ("msg=" + (($kept | Select-Object -First 1).message))
} finally {
  try { [IO.Directory]::Delete($Work, $true) } catch { }
}
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
