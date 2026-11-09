# run_cyclefix_hardcast_multiclass_dcc.ps1 -- lane 149 CYB (149-CY-12, fabcyc row 12): a member hand-over (R2) edge
# through several classes that the consumer reaches by HARD CASTS (`TX(X).M`, the C7 path) instead of `is` / `as`
# used to refuse multiple-classes (or route the other class's casts into the first class's plan). Now every class the
# edge hard-casts gets its own per-class plan, as an `is` / `as` operand does. Real dcc:
#
#   m1  Port tested with is/as + Aux only hard-cast: planned, two interfaces; --fix --apply exit 0; the applied copy
#       builds; stdout byte-identical (aux first note); consumer code names neither class; no cycle after a re-index
#                                                               (RED on 1.48.0: member-unsupported -- Note read in Port's plan)
#   m2  both classes only hard-cast (no is/as anywhere): the same                (RED on 1.48.0: not planned, manual-edit)
#   m3  one class only hard-cast (single-class C7-only edge): planned, one interface, applied, builds, identical
#   n1  control: a hard cast with no member after it (`TDemoGageAux(Part) <> nil`) still refuses type-cast
#   pc1 POSITIVE CONTROL: the applied m2 copy with Aux's Note getter returning '' builds and its stdout DIFFERS
#
# Fixture: tests\fixtures\cyclefix\memberwrite plus a class TDemoGageAux in DemoGagePort.pas; Attach / OnData
# rewritten per case. Library: a COPY of -LibraryDb in the work dir.
#
# Usage: pwsh -File run_cyclefix_hardcast_multiclass_dcc.ps1 [-Exe <drag-lint.exe>] [-WorkDir <dir>] [-LibraryDb <lib>] [-KeepWorkDir]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-hardcast-$PID",
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
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Ascii = [Text.Encoding]::ASCII

function Edit-Text([string]$Path, [string]$From, [string]$To) {
  $t = [IO.File]::ReadAllText($Path, $Ascii)
  $f = $From -replace "`r?`n", "`r`n"
  if (-not $t.Contains($f)) { throw "patch anchor not found in ${Path}: $From" }
  [IO.File]::WriteAllText($Path, $t.Replace($f, ($To -replace "`r?`n", "`r`n")), $Ascii)
}
$PortDecl  = "  /// <summary>Stand-in for the gage-port form: a channel feeding a log.</summary>"
$PortCtor  = "  FLog := TStringList.Create;`n"
$AttachOld = "procedure TDemoUIConnect.Attach;`nbegin`n  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`nend;"
$OnDataOld = "  if not (Sender is TDemoGagePort) then`n    Exit;`n  with Sender as TDemoGagePort do`n  begin`n    // Log and LastGage bind to the port; InBuf binds to Self.`n    Log.Add('data ' + InBuf);`n    Log.Add(Format('gage now %d', [LastGage]));`n    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it`n  end;"
$OnDataCast = "  if Sender.ClassName <> 'TDemoGagePort' then`n    Exit;`n  TDemoGagePort(Sender).Log.Add('data ' + InBuf);`n  TDemoGagePort(Sender).Log.Add(Format('gage now %d', [TDemoGagePort(Sender).LastGage]));`n  TDemoGagePort(Sender).LastGage := 0;"
$AuxLoop   = "  for I := 0 to Owner.ComponentCount - 1 do`n  begin`n    Part := Owner.Components[I];`n    if Part.ClassName = 'TDemoGageAux' then`n      TDemoGagePort(Owner).Log.Add('aux ' + TDemoGageAux(Part).Note);`n  end;`n"
$AttachVar = "procedure TDemoUIConnect.Attach;`nvar`n  I: Integer;`n  Part: TComponent;`nbegin`n"

function Add-Aux([string]$Root) {
  $gp = Join-Path $Root 'DemoGagePort.pas'
  Edit-Text $gp $PortDecl ("  /// <summary>A part of a port, with a note.</summary>`n  TDemoGageAux = class(TComponent)`n  private`n    FNote: string;`n  public`n" +
    "    /// <summary>The note.</summary>`n    property Note: string read FNote write FNote;`n  end;`n`n$PortDecl")
  Edit-Text $gp $PortCtor ($PortCtor + "  TDemoGageAux.Create(Self).Note := 'first note';`n")
}
$Cases = @{
  m1 = { param($r) Add-Aux $r
    Edit-Text (Join-Path $r 'DemoUIConnect.pas') $AttachOld ($AttachVar + "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n" +
      "    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n$AuxLoop" + 'end;') }
  m2 = { param($r) Add-Aux $r
    Edit-Text (Join-Path $r 'DemoUIConnect.pas') $AttachOld ($AttachVar + "  if Owner.ClassName <> 'TDemoGagePort' then`n    Exit;`n" +
      "  TDemoGagePort(Owner).Log.Add(Format('ui connected (last gage %d)', [TDemoGagePort(Owner).LastGage]));`n$AuxLoop" + 'end;')
    Edit-Text (Join-Path $r 'DemoUIConnect.pas') $OnDataOld $OnDataCast }
  m3 = { param($r)
    Edit-Text (Join-Path $r 'DemoUIConnect.pas') $AttachOld ("procedure TDemoUIConnect.Attach;`nbegin`n  if Owner.ClassName <> 'TDemoGagePort' then`n    Exit;`n" +
      "  TDemoGagePort(Owner).Log.Add(Format('ui connected (last gage %d)', [TDemoGagePort(Owner).LastGage]));`nend;")
    Edit-Text (Join-Path $r 'DemoUIConnect.pas') $OnDataOld $OnDataCast }
  n1 = { param($r) Add-Aux $r
    Edit-Text (Join-Path $r 'DemoUIConnect.pas') $AttachOld ($AttachVar + "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n" +
      "    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n  for I := 0 to Owner.ComponentCount - 1 do`n  begin`n    Part := Owner.Components[I];`n" +
      "    if TDemoGageAux(Part) <> nil then`n      (Owner as TDemoGagePort).Log.Add('part');`n  end;`nend;") }
}
function New-Case([string]$Tag, [string]$Case) {
  $root = Join-Path $WorkDir $Tag
  New-Item -ItemType Directory -Force $root | Out-Null
  Get-ChildItem (Join-Path $Repo 'tests\fixtures\cyclefix\memberwrite') -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $root $_.Name) }
  & $Cases[$Case] $root
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
function Get-Plan($P) {
  Push-Location $WorkDir
  try { return ($null | & $Exe cycles --plan --project $P.Dproj --db $P.Db --library-db $Lib 2>$null | Out-String) } finally { Pop-Location }
}
function Run-Fix($P) {
  $a = @('cycles', '--fix', '--apply', '--build-timeout', '1800', '--project', $P.Dproj, '--db', $P.Db, '--library-db', $Lib, '--format', 'json')
  Push-Location $WorkDir
  try { $out = ($null | & $Exe @a 2>$null | Out-String); $code = $LASTEXITCODE } finally { Pop-Location }
  $j = $null; try { $j = $out | ConvertFrom-Json } catch { }
  $k = @(); foreach ($c in @($j.cycles)) { foreach ($x in @($c.refusals)) { if ($x) { $k += "$($x.kind): $($x.reason)" } } }
  return @{ Exit = $code; Out = $out; Kinds = $k }
}
function Test-Accepted([string]$Tag, [string[]]$Ifaces, [string]$NoClass, [string]$Expect) {
  Write-Host "== $Tag" -ForegroundColor Cyan
  $B = New-Case "$Tag-base" $Tag
  $b0 = Invoke-Build $B
  $out0 = Invoke-Program $B
  Check "$Tag.0 the untouched copy builds, its stdout shows the case ran" ($b0.Ok -and $out0.Contains($Expect)) "$($b0.Errors) [$out0]"
  $P = New-Case "$Tag-edit" $Tag
  $plan = Get-Plan $P
  $all = $true; foreach ($i in $Ifaces) { if ($plan -notmatch ('(?m)^\s*' + $i + ' = interface')) { $all = $false } }
  Check "$Tag.1 planned by member hand-over, interfaces $($Ifaces -join ' + '), no refusal" ($all -and ($plan -match 'member hand-over through an extracted interface') -and ($plan -notmatch 'Fix it: not available')) $plan
  $a = Run-Fix $P
  Check "$Tag.2 --fix --apply: exit 0, no refusal" (($a.Exit -eq 0) -and ($a.Kinds.Count -eq 0)) "exit=$($a.Exit) $($a.Kinds -join ' || ')"
  $b1 = Invoke-Build $P
  $out1 = Invoke-Program $P
  Check "$Tag.3 the applied copy builds (independent msbuild); stdout + stderr byte-identical" ($b1.Ok -and ($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) "$($b1.Errors) before=[$out0] after=[$out1]"
  $ui = (([IO.File]::ReadAllText((Join-Path $P.Root 'DemoUIConnect.pas'), $Ascii) -split "`r?`n") | ForEach-Object { $_ -replace '//.*$', '' -replace "'[^']*'", "''" }) -join "`n"
  Check "$Tag.4 the consumer code names no class of the edge" ($ui -notmatch $NoClass) $ui
  $null | & $Exe index --project $P.Dproj --db $P.Db --library-db $Lib *> "$($P.Db).relog"
  $left = ($null | & $Exe cycles --db $P.Db --library-db none 2>$null | Out-String)
  Check "$Tag.5 no cycle after a re-index" ($left -match 'No circular unit dependencies found\.') $left
  return $P
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  $null = Test-Accepted 'm1' @('IDemoGageAuxSurface', 'IDemoGagePortSurface') '\bTDemoGage(Aux|Port)\b' 'aux first note'
  $P2 = Test-Accepted 'm2' @('IDemoGageAuxSurface', 'IDemoGagePortSurface') '\bTDemoGage(Aux|Port)\b' 'aux first note'
  $null = Test-Accepted 'm3' @('IDemoGagePortSurface') '\bTDemoGagePort\b' 'ui connected'
  Write-Host '== n1: control' -ForegroundColor Cyan
  $N = New-Case 'n1' 'n1'
  $np = Get-Plan $N
  Check 'n1 a hard cast with no member after it still refuses (type-cast), nothing planned' (($np -match 'refused: type-cast') -and ($np -match 'Fix it: not available')) $np
  Write-Host '== pc1: the compare has teeth' -ForegroundColor Cyan
  $out0 = Invoke-Program $P2
  $gp = Join-Path $P2.Root 'DemoGagePort.pas'
  $gt = [IO.File]::ReadAllText($gp, $Ascii)
  $m = [regex]::Match($gt, '(?s)function TDemoGageAux\.\w*Note\w*: string;\r\nbegin\r\n  Result := [^;]+;')
  Check 'pc1a the applied copy holds an Aux Note getter' $m.Success ''
  if ($m.Success) {
    [IO.File]::WriteAllText($gp, $gt.Replace($m.Value, ($m.Value -replace 'Result := [^;]+;', "Result := '';")), $Ascii)
    $bc = Invoke-Build $P2
    $outC = Invoke-Program $P2
    Check 'pc1b the broken getter builds and its stdout DIFFERS' ($bc.Ok -and ($outC -ne '<no exe>') -and ($outC -cne $out0)) "$($bc.Errors) [$outC]"
  }
} finally {
  if (-not $KeepWorkDir) {
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $WorkDir); $i++) {
      try { [IO.Directory]::Delete($WorkDir, $true) } catch { Start-Sleep -Seconds 2 }
    }
  }
}
Write-Host ("run_cyclefix_hardcast_multiclass_dcc: {0} ({1} checks)" -f ($(if ($script:Failed) { 'FAIL' } else { 'PASS' })), $script:Passed)
if ($script:Failed) { exit 1 } else { exit 0 }
