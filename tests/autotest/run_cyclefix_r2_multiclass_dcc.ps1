<#
  run_cyclefix_r2_multiclass_dcc.ps1 -- 1.42 cyc2: a member hand-over (R2) edge through MORE THAN ONE
  class is cut with one interface per class, all-or-nothing.

  ACCEPTED (planned, followed with tools\follow-cycle-plan.ps1, built, run; stdout BYTE-FOR-BYTE that
  of the untouched build):
    two   TDemoGageAux + TDemoGagePort; one consumer line names both classes; a write through Aux.
    three TDemoGageAux + its descendant TDemoGageChild + TDemoGagePort; a member Child inherits from
          Aux read through a typed local of Child; `is TDemoGageAux` must stay true for a Child.
    leaf  the two-class pair with an existing leaf declaring IDemoGagePortSurface differently: only that
          interface takes a suffix.
    nested two classes, `with Part as TDemoGageAux do with Owner as TDemoGagePort do` (1.43 CYC-C): Owner is read
          through the Aux interface (a library member, its getter GetOwnerSurface because TPersistent declares
          GetOwner); Name, on both classes, must stay the INNER one's: the stdout shows which.
    comma  the same as one head, `with Part as TDemoGageAux, Owner as TDemoGagePort do`.
    lines  the same head on two lines.
    libwrite one class; a library member read and written bare in a `with` body (Name, Tag): the consumer has
          its own Name and Tag, so a wrong binding shows in the stdout (with a second positive control).
    redecl a class(TLabel): Caption, redeclared without a type in `published`, typed in TControl.
    castlib library members through a cast, no `with` needed: `(Owner as TDemoGagePort).Name`, `.Tag :=` (the
          1.42 plan was mechanical with an interface lacking them and died in the compile gate).
  FIX PATH: `cycles --fix --apply` on the two-class pair writes the same consumer bytes as the follower
  and is verified; the cast seam (DRAGLINT_CYCLEFIX_BREAK=1) on it is repaired by E2015 through the
  ancestor of the interface concerned, which is NOT the first interface of the edge.

  DETERMINISM: the plan of one tree, planned twice from one DB and once from a fresh index, is byte-identical.
  REGRESSION: the single-class plan of the untouched fixture equals a golden frozen from the f70071d8 engine
  (tests\fixtures\cyclefix\multiclass\single-class-plan.golden, paths normalised to <ROOT>).

  REFUSED (planned only; no partial plan: no interface, no follower write):
    z1 the SECOND class is ref-counted, z2 the second class has no IInterface ancestor,
    z3 the second class's `as` has a receiver that is no plain name (receiver-unknown),
    z4 a library method in overlapping `with` bodies of two classes (with-member),
    z5 a library method in a `with` body of a class of the edge (with-member: `Free` through an interface would
       release a temporary on a freed object), z6 the same with the head on two lines,
    z7 a protected library member (with-member: whether the consumer sees it depends on its own ancestry),
    z8 an indexed library property (with-member),
    z9 a library method through a cast (class-method).
  NO-CLASS: an `is` operand that is an interface its unit keeps refuses other-ref naming the line; a private library
  name is ignored (the consumer's own FOwner stays its own, planned, not on the interface).

  POSITIVE CONTROL: the followed two-class copy with GetNote returning '' still compiles, but its stdout
  DIFFERS. The RED run is the f70071d8 engine: it refuses the accepted shapes with multiple-classes.

  The engine never opens the given library in place: -LibraryDb is copied into the scratch dir; check
  z9 compares its size + mtime. -FreezeGolden (run once, with the baseline engine) writes the golden.
#>
[CmdletBinding()]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-r2-multiclass-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$FreezeGolden
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
$Exe    = (Resolve-Path $Exe).Path
$Repo   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Fx     = Join-Path $Repo 'tests\fixtures\cyclefix\memberwrite'
$Golden = Join-Path $Repo 'tests\fixtures\cyclefix\multiclass\single-class-plan.golden'
$Follow = Join-Path $Repo 'tools\follow-cycle-plan.ps1'
$Ascii  = [Text.Encoding]::ASCII
$Handover = 'by **member hand-over through an extracted interface**'

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
# Replaces pOld by pNew in one file (CRLF); throws when nothing changed: a fixture edit that silently
# does not apply would make every check below test the wrong tree.
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  if ($n -ceq $t) { throw "fixture edit did not apply to $Path : $Old" }
  Set-Text $Path $n
}
function Get-TreeHash([string]$Dir) {
  return ((Get-ChildItem $Dir -File | Where-Object { $_.Extension -in '.pas', '.dpr', '.dproj' } | Sort-Object Name |
    ForEach-Object { '{0}={1}' -f $_.Name, (Get-FileHash $_.FullName -Algorithm SHA256).Hash }) -join ';')
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
# Runs the built program; returns its stdout as bytes (base64, for an exact compare).
function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) ('Win64\Debug\' + [IO.Path]::GetFileNameWithoutExtension($Dproj) + '.exe')
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}
function Get-Plan([string]$Db, [string]$Tag) {
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $Db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return @{ Exit = $p.ExitCode; File = $o; Text = [IO.File]::ReadAllText($o) }
}
function Get-PlanFile([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  $r = Get-Plan $db $Tag
  $r.Db = $db
  return $r
}
# The plan text with the tree, scratch and DB paths out of it, so two trees compare.
function Get-Normal([string]$Text, [string]$Dir) {
  return $Text.Replace($Dir, '<ROOT>').Replace($Dir.Replace('\', '/'), '<ROOT>').Replace($WorkDir, '<WORK>') -replace "`r`n", "`n"
}
function Invoke-Fix([string]$Dproj, [string]$Db, [string[]]$Extra, [string]$Break) {
  $o = Join-Path $WorkDir ("fix-" + (Split-Path (Split-Path $Dproj) -Leaf) + '.json')
  $e = "$o.err"
  $env:DRAGLINT_CYCLEFIX_BREAK = $Break
  try {
    $a = @('cycles', '--fix', '--project', ('"' + $Dproj + '"'), '--db', ('"' + $Db + '"'), '--library-db', ('"' + $Lib + '"'), '--format', 'json') + $Extra
    $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru -ArgumentList $a -RedirectStandardOutput $o -RedirectStandardError $e
  } finally { $env:DRAGLINT_CYCLEFIX_BREAK = '' }
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText($e) }
}

# ---------------------------------------------------------------- fixtures
$AttachOld = "procedure TDemoUIConnect.Attach;`nbegin`n  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`nend;"
$PortDecl  = "  /// <summary>Stand-in for the gage-port form: a channel feeding a log.</summary>"
$PortCtor  = "  FLog := TStringList.Create;`n"

function Add-AuxClass([string]$Gp, [string]$Extra, [string]$Create) {
  Edit-File $Gp $PortDecl ("  /// <summary>A part of a port, with a note.</summary>`n  TDemoGageAux = class(TComponent)`n  private`n    FNote: string;`n  public`n" +
    "    /// <summary>The note.</summary>`n    property Note: string read FNote write FNote;`n  end;`n`n$Extra$PortDecl")
  Edit-File $Gp $PortCtor ($PortCtor + $Create)
}
# Two classes; line `Log.Add('aux ' + ...)` names both.
$twoClass = {
  param($Dir)
  Add-AuxClass (Join-Path $Dir 'DemoGagePort.pas') '' "  TDemoGageAux.Create(Self).Note := 'first note';`n"
  Edit-File (Join-Path $Dir 'DemoUIConnect.pas') $AttachOld ("procedure TDemoUIConnect.Attach;`nvar`n  I: Integer;`n  Part: TComponent;`nbegin`n" +
    "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n" +
    "  for I := 0 to Owner.ComponentCount - 1 do`n  begin`n    Part := Owner.Components[I];`n    if Part is TDemoGageAux then`n    begin`n" +
    "      (Owner as TDemoGagePort).Log.Add('aux ' + (Part as TDemoGageAux).Note);`n      (Part as TDemoGageAux).Note := 'seen';`n" +
    "      (Owner as TDemoGagePort).Log.Add('aux now ' + (Part as TDemoGageAux).Note);`n    end;`n  end;`nend;")
}
# Three classes, Child descending from Aux; Note reached through a typed local of Child.
$threeClass = {
  param($Dir)
  Add-AuxClass (Join-Path $Dir 'DemoGagePort.pas') ("  /// <summary>A part with a level.</summary>`n  TDemoGageChild = class(TDemoGageAux)`n  private`n    FLevel: Integer;`n  public`n" +
    "    /// <summary>The level.</summary>`n    property Level: Integer read FLevel write FLevel;`n  end;`n`n") `
    ("  TDemoGageAux.Create(Self).Note := 'plain aux';`n  with TDemoGageChild.Create(Self) do`n  begin`n    Note := 'child note';`n    Level := 7;`n  end;`n")
  Edit-File (Join-Path $Dir 'DemoUIConnect.pas') $AttachOld ("procedure TDemoUIConnect.Attach;`nvar`n  I: Integer;`n  Part: TComponent;`n  Kid: TDemoGageChild; // retyped to the interface`nbegin`n" +
    "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n" +
    "  for I := 0 to Owner.ComponentCount - 1 do`n  begin`n    Part := Owner.Components[I];`n    if Part is TDemoGageAux then`n" +
    "      (Owner as TDemoGagePort).Log.Add('aux or child ' + (Part as TDemoGageAux).Note);`n    if Part is TDemoGageChild then`n    begin`n" +
    "      Kid := Part as TDemoGageChild;`n      (Owner as TDemoGagePort).Log.Add(Format('child %s level %d', [Kid.Note, Kid.Level]));`n    end;`n  end;`nend;")
}
# Port + a second class TDemoGageZed declared with pHeritage, tested through pTest.
function Set-SecondClass([string]$Dir, [string]$Heritage, [string]$Test) {
  Edit-File (Join-Path $Dir 'DemoGagePort.pas') $PortDecl ("  /// <summary>The second class.</summary>`n  TDemoGageZed = class($Heritage)`n  private`n    FTag: Integer;`n  public`n" +
    "    /// <summary>The tag.</summary>`n    property Tag2: Integer read FTag;`n  end;`n`n$PortDecl")
  Edit-File (Join-Path $Dir 'DemoUIConnect.pas') $AttachOld ("procedure TDemoUIConnect.Attach;`nvar`n  Part: TComponent;`nbegin`n" +
    "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n" +
    "  Part := Owner;`n$Test`nend;")
}

# 1.43 CYC-C: Aux and Port, named; pHead is the `with` head over both classes.
function Set-OverlapPair([string]$Dir, [string]$Head) {
  Add-AuxClass (Join-Path $Dir 'DemoGagePort.pas') '' "  Name := 'portname';`n  with TDemoGageAux.Create(Self) do`n  begin`n    Name := 'auxname';`n    Note := 'first note';`n  end;`n"
  Edit-File (Join-Path $Dir 'DemoUIConnect.pas') $AttachOld ("procedure TDemoUIConnect.Attach;`nvar`n  I: Integer;`n  Part: TComponent;`nbegin`n" +
    "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n" +
    "  for I := 0 to Owner.ComponentCount - 1 do`n  begin`n    Part := Owner.Components[I];`n    if Part is TDemoGageAux then`n$Head`n" +
    "        Log.Add('note ' + Note + ' name ' + Name);`n  end;`nend;")
}
$nested = { param($Dir) Set-OverlapPair $Dir "      with Part as TDemoGageAux do`n        with Owner as TDemoGagePort do" }
$comma  = { param($Dir) Set-OverlapPair $Dir "      with Part as TDemoGageAux, Owner as TDemoGagePort do" }
$lines  = { param($Dir) Set-OverlapPair $Dir "      with Part as TDemoGageAux,`n        Owner as TDemoGagePort do" }
$libWrite = {
  param($Dir)
  Edit-File (Join-Path $Dir 'DemoGagePort.pas') $PortCtor ("$PortCtor  Name := 'portname';`n")
  Edit-File (Join-Path $Dir 'DemoUIConnect.pas') $AttachOld ("procedure TDemoUIConnect.Attach;`nbegin`n  Name := 'uiname';`n  Tag := 3;`n" +
    "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n  begin`n    Tag := 7;`n" +
    "    Log.Add(Format('tag %d name %s', [Tag, Name]));`n  end;`n  (Owner as TDemoGagePort).Log.Add(Format('own tag %d name %s', [Self.Tag, Self.Name]));`nend;")
}
$redecl = {
  param($Dir)
  $gp = Join-Path $Dir 'DemoGagePort.pas'
  Edit-File $gp "  System.Classes;" "  System.Classes,`n  Vcl.Controls,`n  Vcl.StdCtrls;"
  Edit-File $gp $PortDecl "  /// <summary>A label of a port.</summary>`n  TDemoGageLab = class(TLabel)`n  end;`n`n$PortDecl"
  Edit-File $gp $PortCtor "$PortCtor  TDemoGageLab.Create(Self).Caption := 'first caption';`n"
  Edit-File (Join-Path $Dir 'DemoUIConnect.pas') $AttachOld ("procedure TDemoUIConnect.Attach;`nvar`n  I: Integer;`n  Part: TComponent;`nbegin`n" +
    "  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n    Log.Add(Format('ui connected (last gage %d)', [LastGage]));`n" +
    "  for I := 0 to Owner.ComponentCount - 1 do`n  begin`n    Part := Owner.Components[I];`n    if Part is TDemoGageLab then`n      with Part as TDemoGageLab do`n" +
    "      begin`n        (Owner as TDemoGagePort).Log.Add('caption ' + Caption);`n        Caption := 'second caption';`n" +
    "        (Owner as TDemoGagePort).Log.Add('caption ' + Caption);`n      end;`n  end;`nend;")
}

$castLib = {
  param($Dir)
  Edit-File (Join-Path $Dir 'DemoGagePort.pas') $PortCtor ("$PortCtor  Name := 'portname';`n")
  Edit-File (Join-Path $Dir 'DemoUIConnect.pas') $AttachOld ("procedure TDemoUIConnect.Attach;`nbegin`n  Name := 'uiname';`n" +
    "  if not (Owner is TDemoGagePort) then`n    Exit;`n  (Owner as TDemoGagePort).Tag := 9;`n" +
    "  (Owner as TDemoGagePort).Log.Add('name ' + (Owner as TDemoGagePort).Name);`n" +
    "  (Owner as TDemoGagePort).Log.Add(IntToStr((Owner as TDemoGagePort).Tag));`nend;")
}

function Test-Accepted([string]$Tag, $Prep, [string[]]$Ifaces, [string]$NoClassRegex) {
  Write-Host "== accepted: $Tag" -ForegroundColor Cyan
  $base = Join-Path $WorkDir "$Tag-base"; $edit = Join-Path $WorkDir "$Tag-edit"
  Copy-Tree $Fx $base; Copy-Tree $Fx $edit
  & $Prep $base; & $Prep $edit
  $dpB = Join-Path $base 'MemberWrite.dproj'; $dpE = Join-Path $edit 'MemberWrite.dproj'
  $b0 = Invoke-Build $dpB
  Check "$Tag-a0 the untouched copy builds" $b0.Ok $b0.Errors
  $out0 = Invoke-Program $dpB
  $plan = Get-PlanFile $dpE $Tag
  $pt = $plan.Text
  Check "$Tag-a1 planned (exit 0), cut by member hand-over" (($plan.Exit -eq 0) -and $pt.Contains($Handover)) "exit=$($plan.Exit) $(([regex]::Match($pt, 'Fix it: not available -- [\w-]+')).Value)"
  foreach ($i in $Ifaces) { Check "$Tag-a2 the plan declares $i" ($pt -match ('(?m)^\s*' + $i + ' = interface')) '' }
  $again = Get-Plan $plan.Db "$Tag-again"
  Check "$Tag-a3 a re-plan from the same DB is byte-identical" ($again.Text -ceq $pt) ''
  $db2 = Join-Path $WorkDir "$Tag-fresh.sqlite"
  & $Exe index --project $dpE --db $db2 *> (Join-Path $WorkDir "index-$Tag-fresh.log")
  $fresh = Get-Plan $db2 "$Tag-fresh"
  Check "$Tag-a4 a plan from a fresh index is byte-identical (DB name aside)" ($fresh.Text.Replace("$Tag-fresh", $Tag) -ceq $pt) ''
  $fo = & pwsh -NoProfile -File $Follow -PlanFile $plan.File -Cycle 1 -Root $edit 2>&1 | Out-String
  Check "$Tag-a5 the follower applies cycle 1 (exit 0)" ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $ut = (([IO.File]::ReadAllText((Join-Path $edit 'DemoUIConnect.pas')) -split "`r?`n") | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n"
  Check "$Tag-a6 the followed consumer code names no class of the edge" (-not ($ut -match $NoClassRegex)) ''
  $b1 = Invoke-Build $dpE
  Check "$Tag-a7 the followed copy builds (BUILD_EXITCODE=0, no error E / fatal F)" $b1.Ok $b1.Errors
  $out1 = Invoke-Program $dpE
  Check "$Tag-a8 its stdout is byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
  return @{ Out0 = $out0; Edit = $edit; Dproj = $dpE }
}

if ($FreezeGolden) {
  New-Item -ItemType Directory -Force $WorkDir | Out-Null
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  $d = Join-Path $WorkDir 'single-edit'; Copy-Tree $Fx $d
  $g = Get-PlanFile (Join-Path $d 'MemberWrite.dproj') 'single'
  New-Item -ItemType Directory -Force (Split-Path $Golden) | Out-Null
  [IO.File]::WriteAllText($Golden, (Get-Normal $g.Text $d), $Ascii)
  [IO.Directory]::Delete($WorkDir, $true)
  Write-Host "frozen: $Golden"
  exit 0
}

$Stamp0 = Get-LibStamp
New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib
  Check 's0 the platform library was copied into the scratch dir' ((Get-Item $Lib).Length -eq (Get-Item $LibraryDb).Length) $Lib

  $two = Test-Accepted 'two' $twoClass @('IDemoGageAuxSurface', 'IDemoGagePortSurface') '\bTDemoGage(Aux|Port)\b'
  $null = Test-Accepted 'three' $threeClass @('IDemoGageAuxSurface', 'IDemoGageChildSurface', 'IDemoGagePortSurface') '\bTDemoGage(Aux|Child|Port)\b'
  $nest = Test-Accepted 'nested' $nested @('IDemoGageAuxSurface', 'IDemoGagePortSurface') '\bTDemoGage(Aux|Port)\b'
  $null = Test-Accepted 'comma' $comma @('IDemoGageAuxSurface', 'IDemoGagePortSurface') '\bTDemoGage(Aux|Port)\b'
  $null = Test-Accepted 'lines' $lines @('IDemoGageAuxSurface', 'IDemoGagePortSurface') '\bTDemoGage(Aux|Port)\b'
  $lw = Test-Accepted 'libwrite' $libWrite @('IDemoGagePortSurface') '\bTDemoGagePort\b'
  $null = Test-Accepted 'redecl' $redecl @('IDemoGageLabSurface', 'IDemoGagePortSurface') '\bTDemoGage(Lab|Port)\b'
  $null = Test-Accepted 'castlib' $castLib @('IDemoGagePortSurface') '\bTDemoGagePort\b'
  $np = [IO.File]::ReadAllText((Join-Path $nest.Edit 'DemoGagePort.pas'))
  Check 'n1 Owner is carried under the free getter name: TPersistent declares GetOwner' ($np -match 'function TDemoGageAux\.GetOwnerSurface: TComponent;') ''
  Check 'n2 the nested stdout really holds the inner class''s name (the outer one''s is auxname)' ([Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($nest.Out0)) -match 'note first note name portname') ''

  Write-Host '== positive control: the followed libwrite copy with the library-name getter returning a constant' -ForegroundColor Cyan
  Edit-File (Join-Path $lw.Edit 'DemoGagePort.pas') "function TDemoGagePort.GetName: TComponentName;`nbegin`n  Result := Name;" "function TDemoGagePort.GetName: TComponentName;`nbegin`n  Result := 'constant';"
  $bl2 = Invoke-Build $lw.Dproj
  Check 'pc3 it still compiles' $bl2.Ok $bl2.Errors
  $outL = Invoke-Program $lw.Dproj
  Check 'pc4 its stdout DIFFERS from the untouched build (the libwrite compare has teeth)' (($outL -ne '<no exe>') -and ($outL -cne $lw.Out0)) ''

  Write-Host '== positive control: the followed two-class copy with the Aux getter returning an empty string' -ForegroundColor Cyan
  Edit-File (Join-Path $two.Edit 'DemoGagePort.pas') "function TDemoGageAux.GetNote: string;`nbegin`n  Result := FNote;" "function TDemoGageAux.GetNote: string;`nbegin`n  Result := '';"
  $bc = Invoke-Build $two.Dproj
  Check 'pc1 it still compiles' $bc.Ok $bc.Errors
  $outC = Invoke-Program $two.Dproj
  Check 'pc2 its stdout DIFFERS from the untouched build (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $two.Out0)) ''

  Write-Host '== existing leaf: only the interface it declares differently takes a suffix' -ForegroundColor Cyan
  $lb = Join-Path $WorkDir 'leaf-edit'; Copy-Tree $Fx $lb; & $twoClass $lb
  Set-Text (Join-Path $lb 'DemoGagePort.Untangle.pas') "unit DemoGagePort.Untangle;`n`ninterface`n`ntype`n  /// <summary>Another shape under the name.</summary>`n  IDemoGagePortSurface = interface`n    ['{11111111-2222-3333-4444-555555555555}']`n    procedure Other;`n  end;`n`nimplementation`n`nend.`n"
  Edit-File (Join-Path $lb 'MemberWrite.dpr') "  DemoGagePort in 'DemoGagePort.pas'," "  DemoGagePort.Untangle in 'DemoGagePort.Untangle.pas',`n  DemoGagePort in 'DemoGagePort.pas',"
  Edit-File (Join-Path $lb 'MemberWrite.dproj') '        <DCCReference Include="DemoGagePort.pas"/>' "        <DCCReference Include=`"DemoGagePort.Untangle.pas`"/>`n        <DCCReference Include=`"DemoGagePort.pas`"/>"
  $pl = Get-PlanFile (Join-Path $lb 'MemberWrite.dproj') 'leaf'
  Check 'l1 planned; IDemoGagePortSurface2 and IDemoGageAuxSurface' ($pl.Text.Contains($Handover) -and ($pl.Text -match '(?m)^\s*IDemoGagePortSurface2 = interface') -and ($pl.Text -match '(?m)^\s*IDemoGageAuxSurface = interface')) ''
  $fo = & pwsh -NoProfile -File $Follow -PlanFile $pl.File -Cycle 1 -Root $lb 2>&1 | Out-String
  Check 'l2 the follower applies it' ($LASTEXITCODE -eq 0) ($fo.Trim() -replace "`r?`n", ' | ')
  $bl = Invoke-Build (Join-Path $lb 'MemberWrite.dproj')
  Check 'l3 it builds' $bl.Ok $bl.Errors
  Check 'l4 its stdout is byte-identical' ((Invoke-Program (Join-Path $lb 'MemberWrite.dproj')) -ceq $two.Out0) ''

  Write-Host '== cycles --fix --apply writes what the follower wrote' -ForegroundColor Cyan
  $fxA = Join-Path $WorkDir 'fix-apply'; Copy-Tree $Fx $fxA; & $twoClass $fxA
  $folC = Join-Path $WorkDir 'fix-compare'; Copy-Tree $Fx $folC; & $twoClass $folC
  $dbA = Join-Path $WorkDir 'fix-apply.sqlite'
  & $Exe index --project (Join-Path $fxA 'MemberWrite.dproj') --db $dbA *> (Join-Path $WorkDir 'index-fix-apply.log')
  $pC = Get-PlanFile (Join-Path $folC 'MemberWrite.dproj') 'fix-compare'
  $null = & pwsh -NoProfile -File $Follow -PlanFile $pC.File -Cycle 1 -Root $folC 2>&1 | Out-String
  $r = Invoke-Fix (Join-Path $fxA 'MemberWrite.dproj') $dbA @('--apply', '--no-backup') ''
  $cy = $null; try { $cy = @(($r.Out | ConvertFrom-Json).cycles)[0] } catch { }
  Check 'f1 --fix --apply exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
  if ($r.Exit -ne 0) { Write-Host (($r.Out + $r.Err) -replace '(.{1500}).*', '$1') }
  Check 'f2 compile ok and verified' (($null -ne $cy) -and ($cy.compile.status -eq 'ok') -and ($cy.verified -eq $true)) ''
  foreach ($n in 'DemoUIConnect.pas', 'DemoGagePort.pas', 'DemoGagePort.Untangle.pas') {
    $ta = Join-Path $fxA $n; $tb = Join-Path $folC $n
    Check "f3 $n equals the follower's bytes" ((Test-Path $ta) -and (Test-Path $tb) -and ((Get-FileHash $ta).Hash -eq (Get-FileHash $tb).Hash)) ''
  }
  Check 'f4 the fixed copy runs byte-identically' ((Invoke-Program (Join-Path $fxA 'MemberWrite.dproj')) -ceq $two.Out0) ''

  Write-Host '== cycles --fix: the E2015 repair reaches the interface that is not the first of the edge' -ForegroundColor Cyan
  $fxB = Join-Path $WorkDir 'fix-break'; Copy-Tree $Fx $fxB; & $twoClass $fxB
  $dbB = Join-Path $WorkDir 'fix-break.sqlite'
  & $Exe index --project (Join-Path $fxB 'MemberWrite.dproj') --db $dbB *> (Join-Path $WorkDir 'index-fix-break.log')
  $r2 = Invoke-Fix (Join-Path $fxB 'MemberWrite.dproj') $dbB @('--apply', '--no-backup', '--no-reindex') '1'
  $cy2 = $null; try { $cy2 = @(($r2.Out | ConvertFrom-Json).cycles)[0] } catch { }
  Check 'g1 the seam is active and the run exits 0' (($r2.Exit -eq 0) -and $r2.Err.Contains('TEST BREAK active')) "exit=$($r2.Exit)"
  Check 'g2 one E2015 repair, compile ok' (($null -ne $cy2) -and ($cy2.compile.status -eq 'ok') -and (@($cy2.repairs).Count -ge 1) -and (@($cy2.repairs)[0].code -eq 'E2015')) ''
  $gu = [IO.File]::ReadAllText((Join-Path $fxB 'DemoUIConnect.pas'))
  Check 'g3 the repaired line casts through the ancestor to the second interface' ($gu -match 'TComponent\(Sender\) as IDemoGagePortSurface') ''

  Write-Host '== single-class regression: the plan equals the frozen golden' -ForegroundColor Cyan
  $sd = Join-Path $WorkDir 'single-edit'; Copy-Tree $Fx $sd
  $sp = Get-PlanFile (Join-Path $sd 'MemberWrite.dproj') 'single'
  Check 'h0 the golden exists' (Test-Path $Golden) $Golden
  if (Test-Path $Golden) {
    $nt = Get-Normal $sp.Text $sd
    Check 'h1 the single-class plan is byte-identical to the f70071d8 golden' ($nt -ceq ([IO.File]::ReadAllText($Golden) -replace "`r`n", "`n")) ''
    Check 'h2 the golden really is a member hand-over plan' ($nt.Contains($Handover)) ''
  }

  # Refused shapes: planned only.
  $refusals = @(
    @{ Tag = 'z1'; Kind = 'ref-counted'; Names = 'TDemoGageZed'; Prep = { param($Dir) Set-SecondClass $Dir 'TInterfacedObject' "  if Part is TDemoGageZed then`n    Exit;" } },
    @{ Tag = 'z2'; Kind = 'no-iinterface'; Names = 'TDemoGageZed'; Prep = { param($Dir) Set-SecondClass $Dir 'TObject' "  if Part is TDemoGageZed then`n    Exit;" } },
    @{ Tag = 'z3'; Kind = 'receiver-unknown'; Names = 'TDemoGageZed'; Prep = { param($Dir) Set-SecondClass $Dir 'TComponent' "  if (Owner.Components[0] as TDemoGageZed).Tag2 = 0 then`n    Exit;" } },
    @{ Tag = 'z4'; Kind = 'with-member'; Names = 'Free'; Prep = { param($Dir) Set-SecondClass $Dir 'TComponent' "  if Part is TDemoGageZed then`n    with Part as TDemoGageZed do`n      with Part as TDemoGagePort do`n        Free;" } },
    @{ Tag = 'z5'; Kind = 'with-member'; Names = 'TDemoGageZed.*Free'; Prep = { param($Dir) Set-SecondClass $Dir 'TComponent' "  if Part is TDemoGageZed then`n    with Part as TDemoGageZed do`n      if Tag2 = 0 then`n        Free;" } },
    @{ Tag = 'z6'; Kind = 'with-member'; Names = 'TDemoGageZed.*Free'; Prep = { param($Dir) Set-SecondClass $Dir 'TComponent' "  if Part is TDemoGageZed then`n    with`n      Part as TDemoGageZed do`n      if Tag2 = 0 then`n        Free;" } },
    @{ Tag = 'z7'; Kind = 'with-member'; Names = 'protected'; Prep = { param($Dir) Edit-File (Join-Path $Dir 'DemoGagePort.pas') "  System.Classes;" "  System.Classes,`n  Vcl.StdCtrls;"; Set-SecondClass $Dir 'TCustomLabel' "  if Part is TDemoGageZed then`n    with Part as TDemoGageZed do`n      if Text = '' then`n        Exit;" } },
    @{ Tag = 'z8'; Kind = 'with-member'; Names = 'indexed'; Prep = { param($Dir) Set-SecondClass $Dir 'TComponent' "  if Part is TDemoGageZed then`n    with Part as TDemoGageZed do`n      if Components[0] = nil then`n        Exit;" } },
    @{ Tag = 'z9'; Kind = 'class-method'; Names = 'Free'; Prep = { param($Dir) Set-SecondClass $Dir 'TComponent' "  if Part is TDemoGageZed then`n    (Part as TDemoGageZed).Free;" } }
  )
  foreach ($z in $refusals) {
    Write-Host "== refused: $($z.Kind)" -ForegroundColor Cyan
    $d = Join-Path $WorkDir "$($z.Tag)-edit"
    Copy-Tree $Fx $d
    & $z.Prep $d
    $p = Get-PlanFile (Join-Path $d 'MemberWrite.dproj') $z.Tag
    $t = $p.Text
    Check "$($z.Tag)1 not cut by member hand-over" (-not $t.Contains($Handover)) ''
    Check "$($z.Tag)2 the plan refuses $($z.Kind)" ($t -match ('Fix it: not available -- ' + [regex]::Escape($z.Kind))) ''
    Check "$($z.Tag)3 the refusal names $($z.Names)" ($t -match ('(?s)refused: ' + [regex]::Escape($z.Kind) + '.*' + $z.Names)) ''
    Check "$($z.Tag)4 no partial plan: no interface of the edge in it" (-not ($t -match 'IDemoGage(Port|Zed)Surface')) ''
    $h0 = Get-TreeHash $d
    $null = & pwsh -NoProfile -File $Follow -PlanFile $p.File -Cycle 1 -Root $d 2>&1 | Out-String
    $fx0 = $LASTEXITCODE
    Check "$($z.Tag)5 the follower writes nothing (exit $fx0)" ((Get-TreeHash $d) -ceq $h0) ''
  }

  Write-Host '== no class: the operand is an interface its unit keeps (it names a class of the unit)' -ForegroundColor Cyan
  $nc = Join-Path $WorkDir 'noclass-edit'; Copy-Tree $Fx $nc
  Edit-File (Join-Path $nc 'DemoGagePort.pas') $PortDecl ("  TDemoGagePort = class;`n`n  /// <summary>Something with a port.</summary>`n  IDemoHasPort = interface`n    ['{11111111-2222-3333-4444-555555555555}']`n    /// <summary>The port.</summary>`n    function Port: TDemoGagePort;`n  end;`n`n$PortDecl")
  Edit-File (Join-Path $nc 'DemoUIConnect.pas') $AttachOld "procedure TDemoUIConnect.Attach;`nbegin`n  if (Owner as IDemoHasPort).Port = nil then`n    Exit;`nend;"
  Edit-File (Join-Path $nc 'DemoUIConnect.pas') "  if not (Sender is TDemoGagePort) then`n    Exit;`n  with Sender as TDemoGagePort do`n  begin`n    // Log and LastGage bind to the port; InBuf binds to Self.`n    Log.Add('data ' + InBuf);`n    Log.Add(Format('gage now %d', [LastGage]));`n    LastGage := 0; // <-- a WRITE through the with: an interface of reads cannot carry it`n  end;`n" ''
  $ncp = (Get-PlanFile (Join-Path $nc 'MemberWrite.dproj') 'noclass').Text
  Check 'c1 the edge refuses other-ref, naming the interface and its line' ($ncp -match 'IDemoHasPort` \(no class\): refused: other-ref -- line \d+ tests or casts against `IDemoHasPort`') ''
  Check 'c2 the old wording is gone' (-not $ncp.Contains('names 0 classes')) ''

  Write-Host '== a name private to its library unit is not the consumer''s business' -ForegroundColor Cyan
  $pv = Join-Path $WorkDir 'private-edit'; Copy-Tree $Fx $pv
  Edit-File (Join-Path $pv 'DemoUIConnect.pas') $AttachOld "procedure TDemoUIConnect.Attach;`nvar`n  FOwner: Integer;`nbegin`n  if not (Owner is TDemoGagePort) then`n    Exit;`n  with Owner as TDemoGagePort do`n  begin`n    FOwner := LastGage;`n    Log.Add(IntToStr(FOwner));`n  end;`nend;"
  $pvp = (Get-PlanFile (Join-Path $pv 'MemberWrite.dproj') 'private').Text
  Check 'v1 planned by member hand-over (TComponent.FOwner does not refuse it)' ($pvp.Contains($Handover)) ''
  Check 'v2 FOwner is not on the interface' (-not ($pvp -match 'property FOwner')) ''
} finally {
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
$Stamp1 = Get-LibStamp
Check 'z9 the library DB given is unchanged (size + mtime)' ($Stamp0 -eq $Stamp1) "before [$Stamp0] after [$Stamp1]"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
