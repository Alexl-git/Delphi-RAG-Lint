<#
  run_unwith.ps1 -- lane 144 unwith: `unwith` removes a with block only when it can prove every binding.

  Needs dcc: SKIPs when rsvars.bat or the platform library is missing. The fixture is copied under %TEMP%; the library is
  opened read-only.
  (a) usage: neither --plan nor --apply, --apply without --project, --line without --in -> exit 2.
  (b) tests\fixtures\refactor\unwith\UwRefused.pas: the comment before each with names the refusal kind; each must be that
      kind, with a detail, and none may be a candidate. --plan writes nothing.
      UW_HIDDEN is set for builds and NOT for the index: THiddenBase is an unresolved ancestor the compiler sees.
  (c) UwCases.pas: the candidates, and the plan's binding table on the silent-rebind case: Count / Value / Tag prefixed,
      each bound to the member, not to the local of the same name.
  (d) POSITIVE CONTROL for the closure: --library-db none: TObject's members are unknown, so a class target refuses
      unresolved-ancestor; a record target stays a candidate.
  (e) THE SILENT REBIND. Test seam DRAGLINT_UNWITH_TEST_SKIP_PREFIX=Count leaves `Count` bare where the closure says prefix.
      That text COMPILES (the gate's after build passes) and reads the local: exit 1, refusal rebind-after naming
      TBase.Count -> the local, the file restored byte-identically. This is what the gate alone can never see.
  (f) a gate failure: the same seam over the whole file does not compile -> compile-error, rolled back byte-identically; a
      project that does not build -> dirty-baseline, nothing written.
  (g) a real --apply: exit 0, proof points > 0, no with left but the outer of the nested pair, ASCII + CRLF kept, and the
      PROGRAM'S OUTPUT identical to the untouched program's (silent-rebind prints member values, not the locals).
  (h) second pass after a reindex: the outer with is a candidate now; apply; output still identical; no with left.
  (i) stale-file: a file edited after the index refuses.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-unwith-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [string]$Rsvars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [switch]$KeepScratch
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$script:Passed = 0
function Check($n, $ok, $d = '') {
  if ($ok) { Write-Host "  [PASS] $n" -ForegroundColor Green; $script:Passed++ }
  else { Write-Host "  [FAIL] $n" -ForegroundColor Red; if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $Rsvars)) { Write-Host "SKIP: no rsvars.bat ($Rsvars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library ($LibraryDb)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fixture = Join-Path $Repo 'tests\fixtures\refactor\unwith'

function New-Copy([string]$Name) {
  $d = Join-Path $WorkDir $Name
  [IO.Directory]::CreateDirectory($d) | Out-Null
  Copy-Item "$Fixture\*" $d -Recurse -Force
  return $d
}
function Hash-Of([string]$Path) { return (Get-FileHash $Path -Algorithm SHA256).Hash }
function Invoke-Index([string]$Dir) {
  $env:UW_HIDDEN = ''
  $null = & $Exe index --project "$Dir\UwDemo.dproj" --db "$Dir\uw.sqlite" 2>&1
  $env:UW_HIDDEN = 'hidden'
  if ($LASTEXITCODE -ne 0) { throw "index failed in $Dir" }
}
function Invoke-Plan([string]$Dir, [string]$File, [string[]]$Extra = @('--library-db', $LibraryDb)) {
  $o = & $Exe unwith --db "$Dir\uw.sqlite" --in "$Dir\$File" --plan --json @Extra 2>$null
  return ($o | Where-Object { $_ -like '{*' } | Select-Object -Last 1) | ConvertFrom-Json
}
function Invoke-Apply([string]$Dir, [string]$File, [int]$Line = 0) {
  $LineArgs = if ($Line -gt 0) { @('--line', "$Line") } else { @() }
  $o = & $Exe unwith --db "$Dir\uw.sqlite" --library-db $LibraryDb --in "$Dir\$File" @LineArgs --apply --project "$Dir\UwDemo.dproj" --json 2>$null
  $script:ApplyCode = $LASTEXITCODE
  return ($o | Where-Object { $_ -like '{*' } | Select-Object -Last 1) | ConvertFrom-Json
}
function Build-And-Run([string]$Dir) {
  $bat = Join-Path $Dir '_b.bat'
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$Rsvars`"`r`ncd /d `"$Dir`"`r`nset UW_HIDDEN=hidden`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal UwDemo.dproj`r`n")
  $log = Join-Path $Dir '_b.log'
  Start-Process cmd.exe -ArgumentList '/c', $bat -RedirectStandardOutput $log -NoNewWindow -Wait
  $found = Get-ChildItem "$Dir\Win64\Debug\UwDemo.exe" -ErrorAction SilentlyContinue
  if (-not $found) { throw "the fixture did not build in $Dir, see $log" }
  return (& $found.FullName | Out-String)
}

try {
  [IO.Directory]::CreateDirectory($WorkDir) | Out-Null
  $env:UW_HIDDEN = 'hidden'

  # the untouched program's output: what every rewrite must reproduce
  $Base = New-Copy 'base'
  $Golden = Build-And-Run $Base
  Check 'baseline program runs' ($Golden -match 'silent-rebind 7 tag 0' -and $Golden -match 'locals 1000 2000') $Golden

  # (a) usage
  $D = New-Copy 'plan'
  Invoke-Index $D
  $null = & $Exe unwith --db "$D\uw.sqlite" 2>$null; Check '(a) neither --plan nor --apply -> exit 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  $null = & $Exe unwith --db "$D\uw.sqlite" --apply 2>$null; Check '(a) --apply without --project -> exit 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"
  $null = & $Exe unwith --db "$D\uw.sqlite" --plan --line 3 2>$null; Check '(a) --line without --in -> exit 2' ($LASTEXITCODE -eq 2) "exit $LASTEXITCODE"

  # (b) every refusal, by the comment before it
  $Before = Hash-Of "$D\UwRefused.pas"
  $Plan = Invoke-Plan $D 'UwRefused.pas'
  Check '(b) schema unwith/1' ($Plan.schema -eq 'unwith/1')
  Check '(b) no candidate in UwRefused' ($Plan.candidates -eq 0) (($Plan.sites | Where-Object { $_.refusal -eq '' } | ForEach-Object { "$($_.line): $($_.target)" }) -join '; ')
  $Lines = [IO.File]::ReadAllLines("$D\UwRefused.pas")
  $Pending = ''
  $Expected = 0
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match '^\{ ([a-z-]+)[ :]') { $Pending = $Matches[1] }
    elseif ($Pending -and $Lines[$i] -match '^\s*with\b') {
      $Site = $Plan.sites | Where-Object { $_.line -eq ($i + 1) }
      $Expected++
      Check "(b) line $($i + 1) refuses $Pending" (($Site.refusal -eq $Pending) -and ($Site.detail -ne '')) "got '$($Site.refusal)': $($Site.detail)"
      $Pending = ''
    }
  }
  Check '(b) the fixture states at least 20 refusals (the parse of its comments did not go vacuous)' ($Expected -ge 20) "$Expected"
  $Kinds = @($Plan.sites | ForEach-Object { $_.refusal } | Sort-Object -Unique)
  Check '(b) at least 17 distinct kinds' ($Kinds.Count -ge 17) ($Kinds -join ',')
  Check '(b) --plan writes nothing' ((Hash-Of "$D\UwRefused.pas") -eq $Before)

  # (c) the candidates and the binding table
  $Plan = Invoke-Plan $D 'UwCases.pas'
  Check '(c) candidates: all but the outer of the nested pair' (($Plan.candidates -ge 11) -and ($Plan.refused -eq 1)) "cand $($Plan.candidates) ref $($Plan.refused)"
  Check '(c) the one refusal is inner-with-first' (($Plan.sites | Where-Object { $_.refusal -ne '' }).refusal -eq 'inner-with-first')
  $Src = [IO.File]::ReadAllLines("$D\UwCases.pas")
  $RebindLine = 0
  for ($i = 0; $i -lt $Src.Count; $i++) { if ($Src[$i] -match "silent-rebind '") { $RebindLine = $i + 1 } }
  $Site = $Plan.sites | Where-Object { $_.line -eq ($RebindLine - 1) }
  $Bs = $Site.bindings
  $Count = $Bs | Where-Object { $_.name -eq 'Count' }
  $Value = $Bs | Where-Object { $_.name -eq 'Value' }
  $Tag = $Bs | Where-Object { $_.name -eq 'Tag' }
  Check '(c) Count prefixed, member of the ANCESTOR, not the local' ($Count.prefixed -and ($Count.before -like 'UwTypes.TBase.Count*')) ($Count | ConvertTo-Json -Compress)
  Check '(c) Value prefixed, member, not the local' ($Value.prefixed -and ($Value.before -like 'UwTypes.TMid.Value*')) ($Value | ConvertTo-Json -Compress)
  Check '(c) Tag prefixed (a property of the ancestor)' ($Tag.prefixed -and ($Tag.before -like 'UwTypes.TBase.Tag*')) ($Tag | ConvertTo-Json -Compress)
  Check '(c) Writeln stays bare' (-not ($Bs | Where-Object { $_.name -eq 'Writeln' }).prefixed)
  # a library member: Free comes from TObject through the bridge; a variant-part field and a helper's member are members too
  $AllB = @($Plan.sites | ForEach-Object { $_.bindings })
  Check '(c) TObject.Free through the library is prefixed' (($AllB | Where-Object { $_.name -eq 'Free' }).prefixed -contains $true)
  Check '(c) a helper''s member is prefixed' (($AllB | Where-Object { $_.name -eq 'HelperOnly' }).prefixed -contains $true)
  Check '(c) a variant-part field is prefixed' (($AllB | Where-Object { $_.name -eq 'AsInt' }).prefixed -contains $true)

  # (d) positive control: no library, no closure, no candidate on a class
  $Plan = Invoke-Plan $D 'UwCases.pas' @('--library-db', 'none')
  $ClassSites = @($Plan.sites | Where-Object { $_.target -in 'pMid', 'Mid', 'H' })
  Check '(d) --library-db none: class targets refuse unresolved-ancestor' (($ClassSites.Count -ge 3) -and (@($ClassSites | Where-Object { $_.refusal -ne 'unresolved-ancestor' }).Count -eq 0)) (($ClassSites | ForEach-Object { "$($_.target)=$($_.refusal)" }) -join ';')
  Check '(d) --library-db none: a record target stays a candidate' ((($Plan.sites | Where-Object { $_.target -eq 'FPt' }).refusal) -eq '')

  # (e) the silent rebind the build cannot see
  $D = New-Copy 'seam'
  Invoke-Index $D
  $Before = Hash-Of "$D\UwCases.pas"
  $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = 'Count'
  try { $Res = Invoke-Apply $D 'UwCases.pas' ($RebindLine - 1) } finally { $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = '' }
  Check '(e) under-prefixed: exit 1' ($script:ApplyCode -eq 1) "exit $script:ApplyCode"
  Check '(e) refusal rebind-after (the build passed: the proof caught it)' ($Res.apply.refusal -eq 'rebind-after') "$($Res.apply.refusal): $($Res.apply.detail)"
  $Rb = @($Res.apply.rebinds | Where-Object { $_ -match 'Count: UwTypes\.TBase\.Count.* -> UwCases\.CaseSilentRebind\.Count' })
  Check '(e) names the member -> the local' ($Rb.Count -ge 1) (($Res.apply.rebinds | Select-Object -First 4) -join ' || ')
  Check '(e) restored byte-identically' ((Hash-Of "$D\UwCases.pas") -eq $Before)
  # rebind-after is reached only when the gate's after build PASSED: the under-prefixed text compiles, and would print 1000 + 4.
  $Cmp = [IO.File]::ReadAllText("$D\UwCases.pas").Replace("with M do`r`n      Writeln('silent-rebind ', Count + Value, ' tag ', Tag);", "Writeln('silent-rebind ', Count + M.Value, ' tag ', M.Tag);")
  [IO.File]::WriteAllText("$D\UwCases.pas", $Cmp)
  Check '(e) control: the under-prefixed text builds and prints another number' ((Build-And-Run $D) -match 'silent-rebind 1004 tag 0') 'expected 1004'

  # (f) the gate
  $D = New-Copy 'gate'
  Invoke-Index $D
  $Before = Hash-Of "$D\UwCases.pas"
  # The same seam on the whole file: elsewhere a bare Count has no local to fall back on (E2003).
  $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = 'Count'
  try { $Res = Invoke-Apply $D 'UwCases.pas' } finally { $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = '' }
  Check '(f) a rewrite that does not compile: compile-error, exit 1' (($script:ApplyCode -eq 1) -and ($Res.apply.refusal -eq 'compile-error')) "exit $script:ApplyCode $($Res.apply.refusal): $($Res.apply.detail)"
  Check '(f) rolled back byte-identically' ((Hash-Of "$D\UwCases.pas") -eq $Before)
  $D = New-Copy 'dirty'
  Invoke-Index $D
  $Before = Hash-Of "$D\UwCases.pas"
  $T = [IO.File]::ReadAllText("$D\UwRefused.pas").Replace('unit UwRefused;', 'unit UwRefusedX;')
  [IO.File]::WriteAllText("$D\UwRefused.pas", $T)
  $Res = Invoke-Apply $D 'UwCases.pas'
  Check '(f) a project that does not build: dirty-baseline, nothing written' (($Res.apply.refusal -eq 'dirty-baseline') -and ((Hash-Of "$D\UwCases.pas") -eq $Before)) "$($Res.apply.refusal)"

  # (g) the real thing
  $D = New-Copy 'apply'
  Invoke-Index $D
  $Res = Invoke-Apply $D 'UwCases.pas'
  Check '(g) applied, exit 0' (($script:ApplyCode -eq 0) -and $Res.apply.applied) "exit $script:ApplyCode $($Res.apply.refusal): $($Res.apply.detail)"
  Check '(g) no copy of the DB outlives the run' (@(Get-ChildItem 'C:\TEMP\draglint_cyclefix_*_unwith\after-proof.sqlite*' -ErrorAction SilentlyContinue).Count -eq 0)
  Check '(g) the after-proof compared refs' ($Res.apply.proof_points -gt 30) "$($Res.apply.proof_points)"
  $Text = [IO.File]::ReadAllBytes("$D\UwCases.pas")
  Check '(g) 7-bit ASCII' (@($Text | Where-Object { $_ -gt 127 }).Count -eq 0)
  $S = [Text.Encoding]::ASCII.GetString($Text)
  Check '(g) CRLF only' (-not ($S -replace "`r`n", '').Contains("`n"))
  $Left = [regex]::Matches($S, '(?m)^\s*with\s')
  Check '(g) one with left: the outer of the nested pair' ($Left.Count -eq 1) "$($Left.Count)"
  Check '(g) a silent-rebind name carries its prefix' ($S -match "M\.Count \+ M\.Value") 'not found'
  Check '(g) as-cast prefix has its parentheses' ($S -match '\(pO as TMid\)\.Value:= 5') 'not found'
  Check '(g) the then-branch kept its begin..end' ($S -match "(?s)if pFlag then\s+begin\s+S\.AsInt:= 70000") 'not found'
  Check '(g) a block in a statement list is unwrapped' ($S -match "FPt\.X:= 1;\r\n  FPt\.Y:= FPt\.X \+ 1;") 'not found'
  $Out = Build-And-Run $D
  Check '(g) the program prints exactly what it printed' ($Out -ceq $Golden) "--- golden`n$Golden--- now`n$Out"

  # (h) second pass
  $null = & $Exe index --project "$D\UwDemo.dproj" --db "$D\uw.sqlite" 2>&1
  $Res = Invoke-Apply $D 'UwCases.pas'
  Check '(h) the outer with applies after a reindex' (($script:ApplyCode -eq 0) -and $Res.apply.applied) "exit $script:ApplyCode $($Res.apply.refusal): $($Res.apply.detail)"
  $S = [IO.File]::ReadAllText("$D\UwCases.pas")
  Check '(h) no with left' ([regex]::Matches($S, '(?m)^\s*with\s').Count -eq 0)
  Check '(h) outer prefix on the name the inner left bare' ($S -match 'B\.Count:= B\.Value \+ A\.X') 'not found'
  $Out = Build-And-Run $D
  Check '(h) the program still prints exactly what it printed' ($Out -ceq $Golden) "--- golden`n$Golden--- now`n$Out"

  # (i) stale
  [IO.File]::AppendAllText("$D\UwRefused.pas", "`r`n{ edited after the index }`r`n")
  $Plan = Invoke-Plan $D 'UwRefused.pas'
  Check '(i) a file edited after the index refuses stale-file' (@($Plan.sites | Where-Object { $_.refusal -ne 'stale-file' }).Count -eq 0 -and $Plan.sites.Count -gt 0) "$($Plan.refused)"
}
finally {
  $env:UW_HIDDEN = ''
  $env:DRAGLINT_UNWITH_TEST_SKIP_PREFIX = ''
  Set-Location -LiteralPath $env:TEMP
  if (-not ($script:Failed -and $KeepScratch) -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
  elseif ($script:Failed) { Write-Host "scratch kept: $WorkDir" -ForegroundColor Yellow }
}
if ($script:Failed) { Write-Host "run_unwith: FAILED ($script:Passed passed)" -ForegroundColor Red; exit 1 }
Write-Host "run_unwith: ALL $script:Passed PASSED" -ForegroundColor Green
exit 0
