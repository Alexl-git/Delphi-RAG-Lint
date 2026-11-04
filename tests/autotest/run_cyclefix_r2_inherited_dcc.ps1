<#
  run_cyclefix_r2_inherited_dcc.ps1 -- CYC-C (1.42 wave 2) residue (3): a member hand-over (R2) edge
  whose consumer reads a member the class INHERITS from an ancestor declared in the same unit
  (`TDemoGagePort = class(TDemoPortBase)`, `TDemoPortBase.Log`) is cut: the interface carries the
  inherited member like an own one, its getter reading the member by name (`Result := Log`).

  ACCEPTED shape (followed, built, run): tests\fixtures\cyclefix\memberwrite without its write, Log
  moved into a base class TDemoPortBase in DemoGagePort.pas; the consumer reads Log inside
  `with Owner as TDemoGagePort do` and `with Sender as TDemoGagePort do`. Build untouched, plan,
  follow (tools\follow-cycle-plan.ps1), build (BUILD_EXITCODE=0, no `error E` / `fatal F`), run,
  compare stdout BYTE-FOR-BYTE.

  REFUSED shapes (planned only): r1 an ancestor already declares `GetLog` (the getter name the
  interface needs) -> duplicate-identifier; r2 the with body reads `Tag`, a member TComponent (a
  LIBRARY ancestor) declares -> with-member stays (only same-unit ancestors are carried); r3 the
  inherited member is `strict private` in the base (no descendant method can read it) ->
  member-unsupported, or with-member when the resolver (visibility-aware) leaves the read unbound,
  which it does today: either way the edge is not cut.

  POSITIVE CONTROL: the followed copy with GetLog returning a fresh empty list still
  compiles, but its stdout must DIFFER. The RED run is the 1.42.0 engine: it refuses the accepted
  shape with member-unsupported (check a1 fails).

  The engine never opens the given library in place: -LibraryDb is copied into the $PID scratch
  dir and the copy is passed with --library-db; check z1 compares size + mtime of -LibraryDb.
#>
[CmdletBinding()]
param(
  [string]$Exe       = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-r2-inherited-dcc-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
$ErrorActionPreference = 'Stop'
$RsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $RsVars)) { Write-Host 'SKIP: RAD Studio not installed' -ForegroundColor Yellow; exit 0 }
if (-not (Test-Path $LibraryDb)) { Write-Host "SKIP: no platform library DB at $LibraryDb" -ForegroundColor Yellow; exit 0 }
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe   = (Resolve-Path $Exe).Path
$Repo  = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx    = Join-Path $Repo 'tests\fixtures\cyclefix\memberwrite'
$Ascii = [Text.Encoding]::ASCII

function Get-LibStamp {
  $i = Get-Item -LiteralPath $LibraryDb
  return ('{0}@{1:o}' -f $i.Length, $i.LastWriteTimeUtc)
}

function Copy-Tree([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force $To | Out-Null
  Get-ChildItem $From -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $To $_.Name) -Force }
}

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}

# Replaces pOld by pNew in one file of a copy (CRLF); False when nothing changed.
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  Set-Text $Path $n
  return ($n -ne $t)
}

# msbuild of pDproj (Win64 Debug); returns @{ Ok; Errors }.
function Invoke-Build([string]$Dproj) {
  $dir = Split-Path $Dproj
  $bat = Join-Path $WorkDir ('build-' + (Split-Path $dir -Leaf) + '.bat')
  $log = "$bat.log"
  $lines = @('@echo off', ('call "{0}"' -f $RsVars), ('cd /d "{0}"' -f $dir),
    ('msbuild /t:Build /p:Config=Debug /p:Platform=Win64 /v:minimal "{0}" > "{1}" 2>&1' -f $Dproj, $log),
    ('>> "{0}" echo BUILD_EXITCODE=%ERRORLEVEL%' -f $log))
  [IO.File]::WriteAllText($bat, (($lines -join "`r`n") + "`r`n"), $Ascii)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -NoNewWindow -Wait | Out-Null
  $text = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
  $errors = @([regex]::Matches($text, '(?m)^.*\b(error|fatal) [EF]\d{4}\b.*$') | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique)
  return @{ Ok = ($text -match 'BUILD_EXITCODE=0') -and ($errors.Count -eq 0); Errors = ($errors -join ' | ') }
}

# Runs the built program of pDproj; returns its stdout as bytes (base64, for an exact compare).
function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) ('Win64\Debug\' + [IO.Path]::GetFileNameWithoutExtension($Dproj) + '.exe')
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}

function Get-PlanFile([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o }
}

# The pair without its write, Log declared in a base class of the same unit.
$inherited = {
  param($Dir)
  $null = Edit-File (Join-Path $Dir 'DemoUIConnect.pas') "    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it`n" ''
  $g = Join-Path $Dir 'DemoGagePort.pas'
  $null = Edit-File $g "  TDemoGagePort = class(TComponent)`n  private`n    FLog: TStrings;`n    FLastGage: Integer;" ("  /// <summary>What every port shares: its log.</summary>`n" +
    "  TDemoPortBase = class(TComponent)`n  private`n    FLog: TStrings;`n  public`n    /// <summary>The port's log (the real form's memo).</summary>`n" +
    "    property Log: TStrings read FLog;`n  end;`n`n  /// <summary>Stand-in for the gage-port form.</summary>`n  TDemoGagePort = class(TDemoPortBase)`n  private`n    FLastGage: Integer;")
  $null = Edit-File $g "    /// <summary>What the UI connection reads: the port's log (the real form's memo).</summary>`n    property Log: TStrings read FLog;`n" ''
}

Check 'f0 the fixture edit applies' ((& { $d = Join-Path $env:TEMP "r2in-probe-$PID"; Copy-Tree $Fx $d; & $inherited $d
  $ok = [IO.File]::ReadAllText((Join-Path $d 'DemoGagePort.pas')).Contains('TDemoGagePort = class(TDemoPortBase)'); [IO.Directory]::Delete($d, $true); $ok })) ''

$Stamp0 = Get-LibStamp
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  Check 's0 the platform library was copied into the scratch dir' ((Get-Item $Lib).Length -eq (Get-Item $LibraryDb).Length) $Lib

  Write-Host '== accepted: a member inherited from an ancestor of the same unit' -ForegroundColor Cyan
  $base = Join-Path $WorkDir 'in-base'; $edit = Join-Path $WorkDir 'in-edit'
  Copy-Tree $Fx $base; Copy-Tree $Fx $edit
  & $inherited $base; & $inherited $edit
  $b0 = Invoke-Build (Join-Path $base 'MemberWrite.dproj')
  Check 'a0 the untouched copy builds' $b0.Ok $b0.Errors
  $out0 = Invoke-Program (Join-Path $base 'MemberWrite.dproj')
  $plan = Get-PlanFile (Join-Path $edit 'MemberWrite.dproj') 'in'
  $pt = [IO.File]::ReadAllText($plan.File)
  Check 'a1 planned (exit 0), cut by member hand-over' (($plan.Exit -eq 0) -and $pt.Contains('by **member hand-over through an extracted interface**')) "exit=$($plan.Exit)"
  Check 'a2 the interface carries the inherited Log' ($pt -match 'property Log: TStrings read GetLog;') ''
  $fo = & pwsh -NoProfile -File (Join-Path $Repo 'tools\follow-cycle-plan.ps1') -PlanFile $plan.File -Cycle 1 -Root $edit 2>&1 | Out-String
  Check 'a3 the follower applies cycle 1 (exit 0)' ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $ut = (([IO.File]::ReadAllText((Join-Path $edit 'DemoUIConnect.pas')) -split "`r?`n") | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n"
  Check 'a4 the followed consumer code (comments aside) no longer names TDemoGagePort' (-not ($ut -match '\bTDemoGagePort\b')) ''
  $b1 = Invoke-Build (Join-Path $edit 'MemberWrite.dproj')
  Check 'a5 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)' $b1.Ok $b1.Errors
  $out1 = Invoke-Program (Join-Path $edit 'MemberWrite.dproj')
  Check 'a6 its stdout is byte-identical to the untouched build''s' (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''

  Write-Host '== positive control: the followed copy with GetLog returning a fresh empty list' -ForegroundColor Cyan
  $gp = Join-Path $edit 'DemoGagePort.pas'
  Check 'pc0 the getter body was changed' (Edit-File $gp "function TDemoGagePort.GetLog: TStrings;`nbegin`n  Result := Log;" "function TDemoGagePort.GetLog: TStrings;`nbegin`n  Result := TStringList.Create;") ''
  $bc = Invoke-Build (Join-Path $edit 'MemberWrite.dproj')
  Check 'pc1 it still compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program (Join-Path $edit 'MemberWrite.dproj')
  Check 'pc2 its stdout DIFFERS from the untouched build (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) ''

  # Refused shapes: planned only.
  $refusals = @(
    @{ Tag = 'r1'; Why = 'an ancestor already declares GetLog'; Kind = 'duplicate-identifier'; File = 'DemoGagePort.pas'; Line = 'function GetLog: TStrings;'
       Prep = { param($Dir) $g = Join-Path $Dir 'DemoGagePort.pas'
         $null = Edit-File $g "    property Log: TStrings read FLog;`n  end;" "    /// <summary>The log, as a function.</summary>`n    function GetLog: TStrings;`n    property Log: TStrings read FLog;`n  end;"
         $null = Edit-File $g "constructor TDemoGagePort.Create" "function TDemoPortBase.GetLog: TStrings;`nbegin`n  Result := FLog;`nend;`n`nconstructor TDemoGagePort.Create" } },
    @{ Tag = 'r2'; Why = 'the with body reads Tag, a member of a LIBRARY ancestor'; Kind = 'with-member'; File = 'DemoUIConnect.pas'; Line = 'IntToStr(Tag)'
       Prep = { param($Dir) $null = Edit-File (Join-Path $Dir 'DemoUIConnect.pas') "    Log.Add('data ' + InBuf);" "    Log.Add('data ' + InBuf + IntToStr(Tag));" } },
    @{ Tag = 'r3'; Why = 'the inherited member is strict private'; Kind = '(member-unsupported|with-member)'; File = 'DemoGagePort.pas'; Line = 'strict private'
       Prep = { param($Dir) $null = Edit-File (Join-Path $Dir 'DemoGagePort.pas') "  public`n    /// <summary>The port's log (the real form's memo).</summary>" "  strict private`n    /// <summary>The port's log (the real form's memo).</summary>" } }
  )
  foreach ($r in $refusals) {
    Write-Host "== refused: $($r.Why)" -ForegroundColor Cyan
    $d = Join-Path $WorkDir "$($r.Tag)-edit"
    Copy-Tree $Fx $d
    & $inherited $d
    & $r.Prep $d
    Check "$($r.Tag)0 the refusal variant was prepared" ([IO.File]::ReadAllText((Join-Path $d $r.File)).Contains($r.Line)) $r.Line
    $p = Get-PlanFile (Join-Path $d 'MemberWrite.dproj') $r.Tag
    $t = [IO.File]::ReadAllText($p.File)
    Check "$($r.Tag)1 not cut by member hand-over" (-not $t.Contains('by **member hand-over through an extracted interface**')) ''
    Check "$($r.Tag)2 the plan refuses $($r.Kind)" ($t -match ('Fix it: not available -- ' + $r.Kind)) ''
  }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}$Stamp1 = Get-LibStamp
Check 'z1 the library DB given is unchanged (size + mtime)' ($Stamp0 -eq $Stamp1) "before [$Stamp0] after [$Stamp1]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
