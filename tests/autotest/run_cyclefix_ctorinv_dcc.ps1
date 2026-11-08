<#
  run_cyclefix_ctorinv_dcc.ps1 -- B8 (1.44): constructor inversion. A class a consumer constructs
  (`S := TX.Create(args)`), whose bodies keep it in its unit, is handed over through the F5 base class:
  `New<TX>` in TX's unit runs the same constructor with the same arguments, a pointer in the leaf (assigned
  in TX's initialization, R1 shape) is what the consumer calls. Refused sites say `ctor-inversion-surface`
  and name the line; every plan the engine calls mechanical must compile.

  ACCEPTED (each: untouched copy built and run; `cycles --fix --apply`, the real dcc gate, on a second copy;
  cycle gone, program builds, stdout BYTE-identical to the untouched build's):
    ctor   docs\examples\cycle-lab LabCtorOwner / LabCtorChild (an own constructor, a method call, Free)
    str    LabCtorStrOwner / LabCtorStrChild: an inherited library constructor, a default parameter, no
           parentheses, a local, FreeAndNil, a nil test, two statements on a line, literals and a comment
           spelling `TX.Create` (byte-identical afterwards), a unit with no initialization section
    init   str with an initialization section already in the class's unit
    impl   ctor with an implementation-only cycle: the base class hand-over of Part B, through a typed local
  REFUSED (planned only; `Fix it: not available -- ctor-inversion-surface` and the line):
    r1 a temporary receiver `TX.Create(nil).Greet`        r2 a global of the class type
    r3 the slot passed by `var`                            r4 an overloaded constructor
    r5 the construction in the consumer's initialization   r6 the class's unit not listed in the program
    r7 a constructor parameter of a type of the cycle      r8 a property written through the slot
    r9 `Result := TX.Create` (a result of the class type)  r10 a pulled method needing a type that cannot move
  STAYS blocked-symbol: k1 `TX.ClassMethod` alone (no construction, the old refusal text).

  POSITIVE CONTROLS: (pc1) the applied `ctor` tree with the pointer assignment removed still compiles, but
  the nil call kills the run: stdout must DIFFER, so the compare can tell. The RED run is engine 1.43: 
  it refuses the `ctor` tree blocked-symbol ("uses TX. (the class itself)"), checks ctor1-ctor5 fail and the fixture edit of pc1 throws.

  The engine never opens the given library in place: -LibraryDb is copied into the $PID scratch dir.
#>
[CmdletBinding()]
param(
  [string]$Exe       = $(if (Test-Path -LiteralPath "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe") { "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" } else { "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }),
  [string]$WorkDir   = "$env:TEMP\drag-lint-cyclefix-ctorinv-$PID",
  [string]$LibraryDb = 'C:\Projects\.drag-lint\library-Win64.sqlite',
  [switch]$KeepWorkDir
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
$Lab   = Join-Path $Repo 'docs\examples\cycle-lab'
$Ascii = [Text.Encoding]::ASCII

function Set-Text([string]$Path, [string]$Text) {
  [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $Ascii)
}
function Edit-File([string]$Path, [string]$Old, [string]$New) {
  $t = [IO.File]::ReadAllText($Path)
  $n = $t.Replace(($Old -replace "`r?`n", "`r`n"), ($New -replace "`r?`n", "`r`n"))
  if ($n -ceq $t) { throw "fixture edit did not apply in $Path : $Old" }
  Set-Text $Path $n
}

$DprCtor = @'
program CtorLab;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  LabCtorOwner in 'LabCtorOwner.pas',
  LabCtorChild in 'LabCtorChild.pas';
var
  O: TLabCtorOwner;
begin
  try
    O := TLabCtorOwner.Create;
    try
      O.Poke;
    finally
      O.Free;
    end;
  except
    on E: Exception do Writeln('died: ', E.ClassName);
  end;
end.
'@
$DprStr = @'
program CtorLab;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  LabCtorStrOwner in 'LabCtorStrOwner.pas',
  LabCtorStrChild in 'LabCtorStrChild.pas';
var
  O: TLabCtorStrOwner;
begin
  try
    O := TLabCtorStrOwner.Create;
    try
      O.Run;
    finally
      O.Free;
    end;
  except
    on E: Exception do Writeln('died: ', E.ClassName);
  end;
end.
'@

function New-Tree([string]$Dir, [string]$Dpr, [string[]]$Units) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  foreach ($u in $Units) { Copy-Item (Join-Path $Lab "$u.pas") (Join-Path $Dir "$u.pas") -Force }
  Set-Text (Join-Path $Dir 'CtorLab.dpr') $Dpr
  $pj = [IO.File]::ReadAllText((Join-Path $Repo 'tests\fixtures\cyclefix\r1extend\R1Extend.dproj'))
  $pj = $pj.Replace('R1Extend', 'CtorLab').Replace('{5A1C7E94-2B6D-4F03-8C9A-7E3B1D0F2A85}', '{7C3E9AB6-4D8F-4125-AEBC-905D3F2B4CA7}')
  $pj = [regex]::Replace($pj, '(?m)^\s*<DCCReference Include="[^"]+"/>\r?\n', '')
  $refs = ($Units | ForEach-Object { "<DCCReference Include=`"$_.pas`"/>" }) -join "`r`n        "
  $pj = $pj.Replace('<DelphiCompile Include="$(MainSource)">', "<DelphiCompile Include=`"`$(MainSource)`">")
  $pj = $pj.Replace('</DelphiCompile>', "</DelphiCompile>`r`n        $refs")
  Set-Text (Join-Path $Dir 'CtorLab.dproj') $pj
}
function New-Ctor([string]$Dir) { New-Tree $Dir $DprCtor @('LabCtorOwner', 'LabCtorChild') }
function New-Str([string]$Dir)  { New-Tree $Dir $DprStr @('LabCtorStrOwner', 'LabCtorStrChild') }

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
function Invoke-Program([string]$Dproj) {
  $exeP = Join-Path (Split-Path $Dproj) ('Win64\Debug\' + [IO.Path]::GetFileNameWithoutExtension($Dproj) + '.exe')
  if (-not (Test-Path $exeP)) { return '<no exe>' }
  $o = "$exeP.stdout"
  Start-Process -FilePath $exeP -WorkingDirectory (Split-Path $exeP) -NoNewWindow -Wait `
    -RedirectStandardOutput $o -RedirectStandardError "$exeP.stderr" | Out-Null
  return [Convert]::ToBase64String([IO.File]::ReadAllBytes($o))
}
function Invoke-Index([string]$Dproj, [string]$Tag) {
  $db = Join-Path $WorkDir "$Tag.sqlite"
  & $Exe index --project $Dproj --db $db *> (Join-Path $WorkDir "index-$Tag.log")
  return $db
}
function Get-Plan([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  $o = Join-Path $WorkDir "plan-$Tag.out"
  $null = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--db', ('"' + $db + '"'), '--plan', '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "plan-$Tag.err")
  return [IO.File]::ReadAllText($o)
}
function Invoke-Apply([string]$Dproj, [string]$Tag) {
  $db = Invoke-Index $Dproj $Tag
  $o = Join-Path $WorkDir "apply-$Tag.out"
  $p = Start-Process -FilePath $Exe -WorkingDirectory $WorkDir -NoNewWindow -Wait -PassThru `
    -ArgumentList @('cycles', '--fix', '--apply', '--no-backup', '--build-timeout', '600', '--cycle', '1', '--project', ('"' + $Dproj + '"'),
      '--db', ('"' + $db + '"'), '--library-db', ('"' + $Lib + '"')) `
    -RedirectStandardOutput $o -RedirectStandardError (Join-Path $WorkDir "apply-$Tag.err")
  return @{ Exit = $p.ExitCode; Out = [IO.File]::ReadAllText($o); Err = [IO.File]::ReadAllText((Join-Path $WorkDir "apply-$Tag.err")); Db = $db }
}
function Get-CyclesText([string]$Db, [string]$Dproj, [string]$Tag) {
  $null = Invoke-Index $Dproj $Tag
  return ((& $Exe cycles --db (Join-Path $WorkDir "$Tag.sqlite") 2>&1) | Out-String)
}

New-Item -ItemType Directory -Force $WorkDir | Out-Null
try {
  $Lib = Join-Path $WorkDir 'library-copy.sqlite'
  Copy-Item $LibraryDb $Lib

  $accepted = @(
    @{ Tag = 'ctor'; New = { param($d) New-Ctor $d }; Prep = $null; Ptr = 'NewTLabCtorChildPtr(Self)'; File = 'LabCtorOwner.pas'; Keep = @() },
    @{ Tag = 'str'; New = { param($d) New-Str $d }; Prep = $null; Ptr = 'NewTLabCtorStrChildPtr(nil)'; File = 'LabCtorStrOwner.pas'
       Keep = @("FChild.Configure('TLabCtorStrChild.Create(nil)', 1);", "NewTLabCtorStrArgPtr('TLabCtorStrArg.Create', 2);", 'NewTLabCtorStrBarePtr();', '// TLabCtorStrArg.Create in a comment') },
    @{ Tag = 'init'; New = { param($d) New-Str $d }; Ptr = 'NewTLabCtorStrChildPtr(nil)'; File = 'LabCtorStrOwner.pas'; Keep = @()
       Prep = { param($d) Edit-File (Join-Path $d 'LabCtorStrChild.pas') "Writeln('[bare] ping of ', TLabCtorStrOwner.Label_);`nend;`n" "Writeln('[bare] ping of ', TLabCtorStrOwner.Label_);`nend;`n`ninitialization`n  Writeln('[child] init');`n" } },
    @{ Tag = 'impl'; New = { param($d) New-Ctor $d }; Ptr = 'NewTLabCtorChildPtr(Self)'; File = 'LabCtorOwner.pas'; Keep = @()
       Prep = { param($d)
         $u = Join-Path $d 'LabCtorOwner.pas'
         Edit-File $u "interface`n`nuses`n  LabCtorChild;`n`ntype" "interface`n`ntype"
         Edit-File $u "  private`n    FChild: TLabCtorChild;`n  public`n    constructor Create;`n    destructor Destroy; override;`n" "  public`n"
         Edit-File $u "implementation`n`nconstructor TLabCtorOwner.Create;`nbegin`n  inherited Create;`n  FChild := TLabCtorChild.Create(Self);`nend;`n`ndestructor TLabCtorOwner.Destroy;`nbegin`n  FChild.Free;`n  inherited;`nend;`n" "implementation`n`nuses`n  LabCtorChild;`n"
         Edit-File $u "procedure TLabCtorOwner.Poke;`nbegin`n  FChild.Touch;`nend;" "procedure TLabCtorOwner.Poke;`nvar`n  Child: TLabCtorChild;`nbegin`n  Child := TLabCtorChild.Create(Self);`n  try`n    Child.Touch;`n  finally`n    Child.Free;`n  end;`nend;"
         # keep the hard cast off the R2 route: Child -> Owner carries a method through a class-level call
         Edit-File (Join-Path $d 'LabCtorChild.pas') "Writeln('[ctor] touched by ', TLabCtorOwner(FOwner).Title);" "Writeln('[ctor] touched by ', TLabCtorOwner.ClassName, ' ', TLabCtorOwner(FOwner).Title);" } }
  )
  foreach ($c in $accepted) {
    $t = $c.Tag
    Write-Host "== accepted: $t" -ForegroundColor Cyan
    $base = Join-Path $WorkDir "$t-base"; $edit = Join-Path $WorkDir "$t-edit"
    foreach ($d in $base, $edit) { & $c.New $d; if ($c.Prep) { & $c.Prep $d } }
    $b0 = Invoke-Build (Join-Path $base 'CtorLab.dproj')
    Check "${t}0 the untouched copy builds" $b0.Ok $b0.Errors
    $out0 = Invoke-Program (Join-Path $base 'CtorLab.dproj')
    $pt = Get-Plan (Join-Path $edit 'CtorLab.dproj') "$t-plan"
    Check "${t}1 the plan says mechanical, by constructor inversion" ($pt.Contains('**Constructor inversion:**') -and -not $pt.Contains('Fix it: not available')) ''
    $ap = Invoke-Apply (Join-Path $edit 'CtorLab.dproj') "$t-apply"
    Check "${t}2 --fix --apply passes the dcc gate (exit 0)" ($ap.Exit -eq 0) ("exit=$($ap.Exit) " + (($ap.Out + $ap.Err).Trim() -split "`r?`n" | Select-Object -Last 4) -join ' | ')
    $ft = [IO.File]::ReadAllText((Join-Path $edit $c.File))
    Check "${t}3 the consumer calls the pointer" ($ft.Contains($c.Ptr)) $c.Ptr
    foreach ($k in $c.Keep) { Check "${t}3b text in the applied consumer: $k" ($ft.Contains($k)) '' }
    $code = (($ft -split "`r?`n") | ForEach-Object { $_ -replace "//.*$", '' -replace "'[^']*'", "''" }) -join "`n"
    Check "${t}4 the consumer's code no longer names the unit of the class" (-not ($code -match '\buses\b[^;]*\bLab(CtorChild|CtorStrChild)\b(?!\.)')) ''
    $cy = Get-CyclesText '' (Join-Path $edit 'CtorLab.dproj') "$t-after"
    Check "${t}5 the cycle is gone" ($cy -match 'No circular|0 circular|no circular') (($cy.Trim() -split "`r?`n" | Select-Object -First 2) -join ' | ')
    $b1 = Invoke-Build (Join-Path $edit 'CtorLab.dproj')
    Check "${t}6 the applied copy builds" $b1.Ok $b1.Errors
    $out1 = Invoke-Program (Join-Path $edit 'CtorLab.dproj')
    Check "${t}7 stdout byte-identical to the untouched build's" (($out0 -ne '<no exe>') -and ($out1 -ceq $out0)) ''
    if ($t -eq 'ctor') {
      Write-Host '== positive control: the applied tree with the pointer assignment removed' -ForegroundColor Cyan
      Edit-File (Join-Path $edit 'LabCtorChild.pas') '  NewTLabCtorChildPtr := NewTLabCtorChild;' ''
      $bc = Invoke-Build (Join-Path $edit 'CtorLab.dproj')
      Check 'pc1a it still compiles' $bc.Ok $bc.Errors
      $outC = Invoke-Program (Join-Path $edit 'CtorLab.dproj')
      Check 'pc1b its stdout DIFFERS (the compare has teeth)' (($outC -ne '<no exe>') -and ($outC -cne $out0)) ''
    }
  }

  $own = 'LabCtorStrOwner.pas'; $kid = 'LabCtorStrChild.pas'
  $refused = @(
    @{ Tag = 'r1'; Why = 'a temporary receiver'; Line = "LabCtorStrOwner.pas:"
       Prep = { param($d) Edit-File (Join-Path $d $own) '  FBare.Ping;' "  FBare.Ping;`n  TLabCtorStrChild.Create(nil).Greet;" } },
    @{ Tag = 'r2'; Why = 'a global of the class type'; Line = "LabCtorStrOwner.pas:"
       Prep = { param($d) Edit-File (Join-Path $d $own) "  System.SysUtils;`n`nconstructor" "  System.SysUtils;`n`nvar`n  GArg: TLabCtorStrArg;`n`nconstructor"
                Edit-File (Join-Path $d $own) '  FBare.Ping;' "  FBare.Ping;`n  GArg := TLabCtorStrArg.Create('g');`n  GArg.Free;" } },
    @{ Tag = 'r3'; Why = 'the slot passed by var'; Line = "LabCtorStrOwner.pas:"
       Prep = { param($d) Edit-File (Join-Path $d $own) "  System.SysUtils;`n`nconstructor" "  System.SysUtils;`n`nprocedure Fill(var pArg: TLabCtorStrArg);`nbegin`n  pArg := nil;`nend;`n`nconstructor"
                Edit-File (Join-Path $d $own) '  FBare.Ping;' "  FBare.Ping;`n  Fill(FArg);" } },
    @{ Tag = 'r4'; Why = 'an overloaded constructor'; Line = "overloaded"
       Prep = { param($d) Edit-File (Join-Path $d $kid) '    constructor Create(const pText: string; pId: Integer = 7);' "    constructor Create(const pText: string; pId: Integer = 7); overload;`n    constructor Create(pId: Integer); overload;"
                Edit-File (Join-Path $d $kid) "procedure TLabCtorStrArg.Show;" "constructor TLabCtorStrArg.Create(pId: Integer);`nbegin`n  inherited Create;`n  FText := IntToStr(pId);`nend;`n`nprocedure TLabCtorStrArg.Show;" } },
    @{ Tag = 'r5'; Why = 'the consumer''s initialization runs the routine that constructs'; Line = "in the initialization section"
       Prep = { param($d) Edit-File (Join-Path $d $own) "  Result := 'owner';`nend;`n" "  Result := 'owner';`nend;`n`ninitialization`n  TLabCtorStrOwner.Create.Free;`n" } },
    @{ Tag = 'r6'; Why = 'the class''s unit not listed in the program'; Line = "does not list"
       Prep = { param($d) Edit-File (Join-Path $d 'CtorLab.dpr') "  LabCtorStrChild in 'LabCtorStrChild.pas';" "  System.Classes;" } },
    @{ Tag = 'r7'; Why = 'a constructor parameter of a type of the cycle'; Line = "of this cycle"
       Prep = { param($d) Edit-File (Join-Path $d $kid) "    constructor Create;`n" "    constructor Create(pOwner: TLabCtorStrArg);`n"
                Edit-File (Join-Path $d $kid) "constructor TLabCtorStrBare.Create;" "constructor TLabCtorStrBare.Create(pOwner: TLabCtorStrArg);"
                Edit-File (Join-Path $d $own) "FBare := TLabCtorStrBare.Create;" "FBare := TLabCtorStrBare.Create(nil);" } },
    @{ Tag = 'r8'; Why = 'a property written through the slot'; Line = "LabCtorStrOwner.pas:"
       Prep = { param($d) Edit-File (Join-Path $d $own) '  FChild.Greet;' "  FChild.Name := 'x';`n  FChild.Greet;" } },
    @{ Tag = 'r9'; Why = 'a result of the class type'; Line = "LabCtorStrOwner.pas:"
       Prep = { param($d) Edit-File (Join-Path $d $own) "    procedure Run;`n" "    procedure Run;`n    /// <summary>Makes one.</summary>`n    /// <returns>A new child.</returns>`n    function Make: TLabCtorStrBare;`n"
                Edit-File (Join-Path $d $own) "class function TLabCtorStrOwner.Label_: string;" "function TLabCtorStrOwner.Make: TLabCtorStrBare;`nbegin`n  Result := TLabCtorStrBare.Create;`nend;`n`nclass function TLabCtorStrOwner.Label_: string;" } },
    @{ Tag = 'r10'; Why = 'a pulled method that needs a type which cannot move'; Line = "cannot move"
       Prep = { param($d) Edit-File (Join-Path $d $kid) "    procedure Greet;`n" "    procedure Greet;`n    /// <summary>Takes an argument object.</summary>`n    /// <param name=`"pArg`">Ignored.</param>`n    procedure Attach(pArg: TObject; pBare: TLabCtorStrBare);`n"
                Edit-File (Join-Path $d $kid) "procedure TLabCtorStrChild.Greet;" "procedure TLabCtorStrChild.Attach(pArg: TObject; pBare: TLabCtorStrBare);`nbegin`nend;`n`nprocedure TLabCtorStrChild.Greet;"
                Edit-File (Join-Path $d $kid) "  TLabCtorStrChild = class(TComponent)" "  TLabCtorStrBare = class;`n`n  TLabCtorStrChild = class(TComponent)"
                Edit-File (Join-Path $d $own) '  FChild.Greet;' "  FChild.Attach(nil, nil);`n  FChild.Greet;" } }
  )
  foreach ($r in $refused) {
    Write-Host "== refused: $($r.Why)" -ForegroundColor Cyan
    $d = Join-Path $WorkDir "$($r.Tag)-edit"
    New-Str $d
    & $r.Prep $d
    $pt = Get-Plan (Join-Path $d 'CtorLab.dproj') $r.Tag
    Check "$($r.Tag)1 the plan refuses ctor-inversion-surface" ($pt -match 'refused: ctor-inversion-surface -- ') (([regex]::Match($pt, '(?m)^.*refused:.*$').Value) -replace '^(.{0,220}).*$', '$1')
    Check "$($r.Tag)2 it names the site ($($r.Line))" ($pt.Contains($r.Line) -and ($pt -match 'ctor-inversion-surface -- .*' + [regex]::Escape($r.Line))) ''
    Check "$($r.Tag)3 the cycle's verdict is that refusal" ($pt.Contains('Fix it: not available -- ctor-inversion-surface')) ''
  }

  Write-Host '== stays: a class-level use that is no construction' -ForegroundColor Cyan
  $d = Join-Path $WorkDir 'k1-edit'
  New-Str $d
  Edit-File (Join-Path $d $own) "FBare := TLabCtorStrBare.Create;" "FBare := nil;`n  Writeln(TLabCtorStrBare.ClassName);"
  $pt = Get-Plan (Join-Path $d 'CtorLab.dproj') 'k1'
  Check 'k1 `TX.ClassName` keeps the old text, not the new kind' ($pt.Contains('(the class itself, not an instance)') -and -not ($pt -match 'ctor-inversion-surface.*TLabCtorStrBare')) ''
} finally {
  if ((-not $KeepWorkDir) -and (Test-Path -LiteralPath $WorkDir)) { [IO.Directory]::Delete($WorkDir, $true) }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
