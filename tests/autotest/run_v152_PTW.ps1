<#
  run_v152_PTW.ps1 -- lane v152 PTW (ruling B7): parameter-type-too-wide ships ON with an autofix.

  Fixture: tests\lint\parameter-type-too-wide.project (app\PtwDemo.dproj + lib\PtwLib.pas on the search path).
  Every routine body there uses only pP.MidOp on a TLeaf parameter, so each could take TMid; the trailing marker
  says FIRE <type> or SILENT <skip class>. The fixture is copied to a scratch folder and indexed into
  app\_D-RAG\PtwDemo.sqlite, so the index has a project anchor and library code (lib\) lies outside its roots.

    A1  lint-all --rule: exactly the FIRE lines fire; one check per SILENT twin (virtual, override, interface method,
        method pointer, procedural value, published handler, dfm-bound handler, library code)
    A2  lint-project --rule: the same set (library code silent there too)
    A3  POSITIVE CONTROL for the library skip: the same index at an ad-hoc path (no anchor) reports PtwLib
    A4  plain lint-all (no --rule): the rule is ON by default
    A5  plain lint-project (no --rule): ON there too
    A6  rules --json: the row is default ON, severity warning, fixable
    B1  lint <PtwUse.pas> --fix --fix-rule --fix-line <ViaMid> --apply --compile-gate: both headers say TMid, PtwBase
        joins the uses clause, the gate built it
    B2  only that finding was fixed (FreeMid keeps TLeaf)
    B3  an independent msbuild of the fixed project succeeds
    B4  after a reindex: ViaMid no longer fires, FreeMid and PubFree still do, every SILENT twin stays silent
    B5  a fix asked on a SILENT line (a virtual method) writes nothing
    B6  fix-all on PtwUse.pas (no --fix-line): FreeMid narrowed too, project still builds

  B* need dcc (rsvars.bat); without it they print SKIP, never PASS.
  RED: run against an engine without the lane (1.51.x / lane/v152-int).

  Usage: pwsh -File tests\autotest\run_v152_PTW.ps1 [-Exe <drag-lint.exe>] [-RsVars <rsvars.bat>]
#>
param(
  [string]$Exe    = "third_party\dll-win64\drag-lint.exe",
  [string]$RsVars = "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$Rule    = 'parameter-type-too-wide'
$fx      = Join-Path $repo 'tests\lint\parameter-type-too-wide.project'
$scratch = Join-Path ([IO.Path]::GetTempPath()) "draglint_v152ptw_$PID"
$HaveDcc = Test-Path $RsVars
$script:pass = 0; $script:fail = 0; $script:skip = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++; $tag = 'PASS' } else { $script:fail++; $tag = 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
}
function Skip([string]$Name, [string]$Why) { $script:skip++; Write-Host "[SKIP] $Name  ($Why)" }

# lint --json / lint-all --json print a bare array of findings (start_line, file_path, rule, severity).
function Parse-Findings([string[]]$Raw) {
  $txt = ($Raw -join "`n"); $b = $txt.IndexOf('[')
  $out = @(); if ($b -ge 0) { try { $out = @(($txt.Substring($b) | ConvertFrom-Json | ForEach-Object { $_ }) | ForEach-Object { $_ }) } catch { $out = @() } }
  return ,@($out)
}
function RuleHits([string]$Verb, [string]$Db, [string[]]$Extra) {
  $raw = & { $ErrorActionPreference = 'Continue'; & $exePath $Verb --db $Db --library-db none --format json @Extra 2>$null }
  return ,@((Parse-Findings $raw) | Where-Object { $_.rule -eq $Rule } |
    ForEach-Object { '{0}:{1}' -f [IO.Path]::GetFileName($_.file_path), [int]$_.start_line } | Sort-Object)
}
# file:line of each line carrying the marker regex, over the fixture's .pas files
function Markers([string]$Root, [string]$Pattern) {
  $out = @()
  foreach ($f in Get-ChildItem $Root -Recurse -Filter '*.pas') {
    $n = 0
    foreach ($l in [IO.File]::ReadAllLines($f.FullName)) {
      $n++
      if ($l -match $Pattern) { $out += [pscustomobject]@{ Key = ('{0}:{1}' -f $f.Name, $n); Tag = $Matches[1] } }
    }
  }
  return ,@($out)
}
function Build([string]$Dir, [string]$Tag) {
  $bat = Join-Path $scratch "build_$Tag.bat"; $log = Join-Path $scratch "build_$Tag.log"
  [IO.File]::WriteAllText($bat, "@echo off`r`ncall `"$RsVars`"`r`ncd /D `"$Dir`"`r`nmsbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal PtwDemo.dproj`r`necho BUILD_EXITCODE=%ERRORLEVEL%`r`n", [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -Wait -WindowStyle Hidden
  return ([IO.File]::ReadAllText($log) -match 'BUILD_EXITCODE=0')
}
function Fix([string]$Unit, [string[]]$Extra) {
  $a = @('lint', $Unit, '--db', $db, '--library-db', 'none', '--rule', $Rule, '--fix', '--fix-rule', $Rule, '--apply',
         '--project', $proj, '--no-backup', '--rsvars', $RsVars) + $Extra
  return (& { $ErrorActionPreference = 'Continue'; & $exePath @a 2>&1 | ForEach-Object { "$_" } } | Out-String)
}
function Reindex { & { $ErrorActionPreference = 'Continue'; & $exePath index --project $proj --db $db --library-db none 2>&1 | ForEach-Object { "$_" } } | Out-Null }

try {
  [void](New-Item -ItemType Directory -Force -Path $scratch)
  $root = Join-Path $scratch 'fx'
  Copy-Item $fx $root -Recurse
  $app  = Join-Path $root 'app'
  $proj = Join-Path $app 'PtwDemo.dproj'
  $use  = Join-Path $app 'PtwUse.pas'
  $db   = Join-Path $app '_D-RAG\PtwDemo.sqlite'
  Reindex

  $fire   = Markers $root '//\s*FIRE (\w+)\s*$'
  $silent = Markers $root '//\s*SILENT ([a-z-]+)\s*$'
  $want   = @($fire | ForEach-Object Key | Sort-Object)
  Check 'C0 control: the fixture holds FIRE and SILENT twins' (($fire.Count -ge 3) -and ($silent.Count -ge 8)) "fire=$($fire.Count) silent=$($silent.Count)"
  Check 'C1 control: the index exists' (Test-Path $db) $db

  # A1 / A2: the rule asked by name
  foreach ($verb in 'lint-all', 'lint-project') {
    $tag = if ($verb -eq 'lint-all') { 'A1' } else { 'A2' }
    $got = RuleHits $verb $db @('--rule', $Rule)
    Check "$tag $verb --rule: exactly the FIRE lines" (($got -join ',') -eq ($want -join ',')) "got [$($got -join ',')] want [$($want -join ',')]"
    foreach ($s in $silent) {
      Check "$tag $verb silent: $($s.Tag) twin $($s.Key)" (-not ($got -contains $s.Key)) ''
    }
  }

  # A3: positive control -- an unanchored copy is linted unscoped, so library code fires
  $adhoc = Join-Path $scratch 'adhoc.sqlite'
  Copy-Item $db $adhoc
  $un = RuleHits 'lint-all' $adhoc @('--rule', $Rule)
  Check 'A3 control: an ad-hoc (unanchored) index reports PtwLib' ($un -contains 'PtwLib.pas:12') "got [$($un -join ',')]"

  # A4 / A5: default ON
  $on = RuleHits 'lint-all' $db @()
  Check 'A4 plain lint-all: ON by default' (($on -join ',') -eq ($want -join ',')) "got [$($on -join ',')]"
  $onp = RuleHits 'lint-project' $db @()
  Check 'A5 plain lint-project: ON by default' (($onp -join ',') -eq ($want -join ',')) "got [$($onp -join ',')]"

  # A6: catalog row
  $rj = (& { $ErrorActionPreference = 'Continue'; & $exePath rules --json 2>$null } | Out-String)
  $row = $null
  try { $row = @(($rj | ConvertFrom-Json | ForEach-Object { $_ }).rules | Where-Object { $_.id -eq $Rule }) | Select-Object -First 1 } catch { $row = $null }
  if ($null -eq $row) { try { $row = @(($rj | ConvertFrom-Json | ForEach-Object { $_ }) | Where-Object { $_.id -eq $Rule }) | Select-Object -First 1 } catch { $row = $null } }
  Check 'A6 rules --json has the row' ($null -ne $row) ''
  if ($null -ne $row) {
    Write-Host ("  row: " + ($row | ConvertTo-Json -Compress -Depth 3))
    Check 'A6 default ON' (($row.default_enabled -eq $true) -or ($row.enabled -eq $true)) ''
    Check 'A6 severity warning' ($row.default_severity -eq 'warning') "$($row.default_severity)"
    Check 'A6 fixable' ($row.fixable -eq $true) ''
  }
  $sev = @((Parse-Findings (& { $ErrorActionPreference = 'Continue'; & $exePath lint-all --db $db --library-db none --format json --rule $Rule 2>$null })) | Where-Object { $_.rule -eq $Rule } | ForEach-Object severity | Sort-Object -Unique)
  Check 'A7 findings are warnings' (($sev -join ',') -eq 'warning') "[$($sev -join ',')]"

  # B: the fix
  if (-not $HaveDcc) {
    'B1', 'B2', 'B3', 'B4', 'B5', 'B6' | ForEach-Object { Skip $_ 'no rsvars.bat' }
  } else {
    $viaMid  = @($fire | Where-Object { $_.Key -like 'PtwUse.pas:*' } | Select-Object -First 1)[0].Key.Split(':')[1]
    $before  = [IO.File]::ReadAllText($use)
    $out = Fix $use @('--fix-line', $viaMid, '--compile-gate')
    Write-Host ($out.Trim() -split "`n" | Select-Object -Last 6 | ForEach-Object { "  | $_" } | Out-String).TrimEnd()
    $after = [IO.File]::ReadAllText($use)
    Check 'B1 the declaration says TMid' ($after -match 'procedure ViaMid\(pP: TMid\); // FIRE TMid') ''
    Check 'B1 the implementation header says TMid' ($after -match 'procedure THost\.ViaMid\(pP: TMid\);') ''
    Check 'B1 PtwBase joins the uses clause' ($after -match '(?s)interface.*?uses[^;]*\bPtwBase\b[^;]*;.*?type') ''
    Check 'B1 the gate did not refuse' ($out -notmatch 'REFUSED|rolled back') ''
    Check 'B2 only that finding: FreeMid keeps TLeaf' ($after -match 'procedure FreeMid\(pP: TLeaf\); // FIRE TMid') ''
    Check 'B2 the file changed at all' ($after -ne $before) ''
    Check 'B3 independent msbuild of the fixed project' (Build $app 'b3') ''

    Reindex
    # the uses edit shifted lines: re-read the markers from the edited copy
    $fire   = Markers $root '//\s*FIRE (\w+)\s*$'
    $silent = Markers $root '//\s*SILENT ([a-z-]+)\s*$'
    $viaNow = @(Markers $root '(procedure ViaMid)\(')[0].Key
    $got = RuleHits 'lint-all' $db @('--rule', $Rule)
    Check 'B4 ViaMid no longer fires' (-not ($got -contains $viaNow)) "ViaMid at $viaNow; got [$($got -join ',')]"
    $rest = @($fire | ForEach-Object Key | Where-Object { $_ -ne $viaNow } | Sort-Object)
    Check 'B4 control: FreeMid and PubFree still fire' (($rest -join ',') -eq ($got -join ',')) "got [$($got -join ',')] want [$($rest -join ',')]"
    Check 'B4 every SILENT twin stays silent' (@($silent | Where-Object { $got -contains $_.Key }).Count -eq 0) ''

    $virt = @($silent | Where-Object { ($_.Tag -eq 'virtual-routine') -and ($_.Key -like 'PtwUse.pas:*') } | Select-Object -First 1)[0].Key.Split(':')[1]
    $snap = [IO.File]::ReadAllBytes($use)
    $out5 = Fix $use @('--fix-line', $virt, '--compile-gate')
    Check 'B5 a fix on a SILENT line (virtual) writes nothing' ([Convert]::ToBase64String($snap) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($use))) ''

    $out6 = Fix $use @('--compile-gate')
    Write-Host ($out6.Trim() -split "`n" | Select-Object -Last 4 | ForEach-Object { "  | $_" } | Out-String).TrimEnd()
    $t6 = [IO.File]::ReadAllText($use)
    Check 'B6 fix-all: FreeMid narrowed too' ($t6 -match 'procedure FreeMid\(pP: TMid\);') ''
    Check 'B6 fix-all: the virtual twin untouched' ($t6 -match 'procedure Handle\(pP: TLeaf\); virtual;') ''
    Check 'B6 fix-all: PtwBase named once in the interface uses' (([regex]::Matches($t6, '\bPtwBase\b')).Count -eq 1) "$(([regex]::Matches($t6, '\bPtwBase\b')).Count)"
    Check 'B6 the project still builds' (Build $app 'b6') ''
  }
} finally {
  if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}
Write-Host ("SUMMARY pass={0} fail={1} skip={2}" -f $script:pass, $script:fail, $script:skip)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
