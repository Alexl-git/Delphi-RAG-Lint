# run_cyclefix_raisecast_dcc.ps1 -- lane 148 CY (fabcyc case 8): a member hand-over (R2) whose consumer handles
# EInvalidCast and casts with an UNGUARDED `as` used to refuse exception-semantics (a failed `as ISurface` raises
# EIntfCastError). Now the consumer gets a helper `AsDemoGagePortSurface(X)`: nil for nil, the interface when X
# supports it, else `raise EInvalidCast.CreateRes(@SInvalidCast)` -- what the failed class cast raised. Real dcc:
#
#   r0  the untouched copy builds; its stdout shows the EInvalidCast path ran ([ui] EInvalidCast: Invalid class typecast)
#   r1  --plan: mechanical, member hand-over, `with AsDemoGagePortSurface(Owner) do`, the Exceptions line names the helper
#                                                               (RED on 1.46.0 / 147-int: refused exception-semantics)
#   r2  --fix --apply: exit 0, no refusal; the applied copy builds; stdout byte-identical; no cycle after a re-index
#   pc1 POSITIVE CONTROL: the applied copy with the helper raising EIntfCastError instead builds, and its stdout DIFFERS
#       (the handler no longer catches it: the compare has teeth)
#
# Fixture: tests\fixtures\cyclefix\memberwrite, Attach rewritten to the unguarded try/except shape, and the .dpr
# attaching a TDemoUIConnect to a plain TComponent once. Library: a COPY of -LibraryDb in the work dir.
#
# Usage: pwsh -File run_cyclefix_raisecast_dcc.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-LibraryDb <lib>] [-KeepWorkDir]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-raisecast-$PID",
  [string]$RsVars    = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat',
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Passed = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Passed++ } else { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}
if (-not (Test-Path $RsVars)) { Write-Host "SKIP: no rsvars.bat ($RsVars)" -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII
$script:N = 0

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
function Get-SrcHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
}
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$AttachOld = "procedure TDemoUIConnect.Attach;`nbegin`n  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`nend;"
$AttachNew = "procedure TDemoUIConnect.Attach;`nbegin`n  try`n    with Owner as TDemoGagePort do`n      Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n  except`n    on E: EInvalidCast do`n      Writeln('[ui] ', E.ClassName, ': ', E.Message);`n  end;`nend;"
function New-Raise([string]$Tag) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\cyclefix\memberwrite') -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  Edit-Text (Join-Path $root 'DemoUIConnect.pas') $AttachOld $AttachNew
  Edit-Text (Join-Path $root 'MemberWrite.dpr') "uses`n  System.SysUtils," "uses`n  System.SysUtils,`n  System.Classes,"
  Edit-Text (Join-Path $root 'MemberWrite.dpr') "      GPort.ReadGage(43);" "      GPort.ReadGage(43);`n      var O := TComponent.Create(nil);`n      try`n        TDemoUIConnect.Create(O).Attach;`n      finally`n        O.Free;`n      end;"
  $db = "$root.sqlite"
  Push-Location $WorkDir
  try { $null | & $Exe index --project (Join-Path $root 'MemberWrite.dproj') --db $db --library-db $Lib *> "$db.log" } finally { Pop-Location }
  return @{ Root = $root; Dproj = (Join-Path $root 'MemberWrite.dproj'); Db = $db; Name = 'MemberWrite' }
}
function Invoke-Build($P) {
  $bat = "$($P.Root).build.bat"; $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $P.Root),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $P.Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}
function Invoke-Program($P) {
  $exeP = Join-Path $P.Root "Win64\Debug\$($P.Name).exe"
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [IO.File]::ReadAllText($o, $Ascii) + '|stderr:' + [IO.File]::ReadAllText("$exeP.stderr", $Ascii)
}
function Run-Fix($P, [string[]]$Extra) {
  $a = @('cycles', '--fix', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--library-db', $Lib, '--format', 'json') + $Extra
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @(); foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += "$($x.kind): $($x.reason)" } } }
  return @{ Exit = $code; Out = $out; Kinds = $k }
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  Write-Host '== r: an unguarded `as` under an EInvalidCast handler goes through the raise-preserving helper' -ForegroundColor Cyan
  $B = New-Raise 'base'
  $b0 = Invoke-Build $B
  Check 'r0.1 the untouched copy builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program $B
  Check 'r0.2 its stdout shows the EInvalidCast path ran' ($out0.Contains('[ui] EInvalidCast: ')) "[$out0]"
  $P = New-Raise 'edit'
  Push-Location $WorkDir
  try { $plan = ($null | & $Exe cycles --plan --project $P.Dproj --db $P.Db --library-db $Lib 2>$null | Out-String) } finally { Pop-Location }
  Check 'r1.1 the plan is mechanical, no exception-semantics refusal' (($plan -notmatch 'refused: exception-semantics') -and ($plan -match 'member hand-over through an extracted interface')) $plan
  Check 'r1.2 the cast goes through AsDemoGagePortSurface(Owner)' ($plan.Contains('with AsDemoGagePortSurface(Owner) do')) ''
  Check 'r1.3 the Exceptions line names the helper and EInvalidCast' ($plan -match 'through `AsDemoGagePortSurface\(X\)`.*EInvalidCast\.CreateRes\(@SInvalidCast\)') ''
  $a = Run-Fix $P @('--apply')
  Check 'r2.1 --apply: exit 0, no refusal' (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) $($a.Kinds -join ' || ')"
  $b1 = Invoke-Build $P
  Check 'r2.2 the applied copy builds (independent msbuild)' $b1.Ok $b1.Errors
  $out1 = Invoke-Program $P
  Check 'r2.3 stdout (and stderr) byte-identical to the untouched build' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) "before=[$out0] after=[$out1]"
  $ui = [IO.File]::ReadAllText((Join-Path $P.Root 'DemoUIConnect.pas'), $Ascii)
  Check 'r2.4 the consumer holds the helper, before Attach' ($ui -match '(?s)function AsDemoGagePortSurface\(const pX: TObject\): IDemoGagePortSurface;.*raise EInvalidCast\.CreateRes\(@SInvalidCast\);.*procedure TDemoUIConnect\.Attach;') ''
  $null | & $Exe index --project $P.Dproj --db $P.Db --library-db $Lib *> "$($P.Db).relog"
  $left = ($null | & $Exe cycles --db $P.Db --library-db none 2>$null | Out-String)
  Check 'r2.5 no cycle after a re-index' ($left -match 'No circular unit dependencies found\.') $left

  Write-Host '== pc1: the compare has teeth' -ForegroundColor Cyan
  Edit-Text (Join-Path $P.Root 'DemoUIConnect.pas') 'raise EInvalidCast.CreateRes(@SInvalidCast);' 'raise EIntfCastError.CreateRes(@SInvalidCast);'
  $bc = Invoke-Build $P
  Check 'pc1a the EIntfCastError variant compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program $P
  Check 'pc1b its output DIFFERS (EInvalidCast handler bypassed)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) "[$outC]"
} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 2 }
    }
  }
}
Write-Host ("run_cyclefix_raisecast_dcc: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }