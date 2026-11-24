<#
  run_v153_AUTODOC.ps1 -- docs\INBOX-orm3-server-153.md, round 1 (autodoc) findings.

    BANNER  item 1: a line of four or more slashes is not a /// doc line. `document --apply`
            keeps every one of them, never writes slashes into a <summary>, still carries a
            genuine /// <summary> beside one, and the second pass is a no-op.
            (1.53.0: the banner above TArr was deleted and came back as a <summary>.)
    FIXER   the same rule for the fixers: deleting an unused private member keeps the banner above it.
    COMMENT item 2: unused-global -- a name that only a comment (a seealso cref, a managed fact)
            holds is still unused; one named in code, a directive or a string is not.
            (1.53.0: CDocOnly was silent.)
    DI      item 4: a type two containers register the same way renders one `Registered as:` entry.
    RESCAN  item 3: an attribute above a heading ([Inject] constructor ...) is not a tampered file; a doc
            verb's in-process rescan of a tampered file re-parses that file only, with the project's own
            build, so the index keeps its fingerprint. (1.53.0: every document run on such a unit, a dry
            run too, re-parsed it as Win32 without the project's defines; document --project force-
            reparsed the whole project per file.) Pass 2 after a reindex is a no-op.
    NOTE    item 5: a plain multi-line /// note keeps its line breaks in the <summary>, and the
            second pass is a no-op. A one-line note stays one line.
  Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = '',
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) "dl-v153-autodoc-$PID")
)
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:Failed = $false; $script:Total = 0
function Check($n, $ok, $d = '') {
  $script:Total++
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Run([string[]]$A) {
  & { $ErrorActionPreference = 'Continue'; (& $Exe @A 2>&1 | ForEach-Object { "$_" }) -join "`n" }
}
function Lines([string]$Path) { return , [IO.File]::ReadAllLines($Path) }
$Exe = (Resolve-Path $Exe).Path
[void][IO.Directory]::CreateDirectory($WorkDir)
try {
# ---------------------------------------------------------------- BANNER / NOTE
$ban = Join-Path $WorkDir 'uBanner.pas'; $db = Join-Path $WorkDir 'ban.sqlite'
$bar = '/' * 70
Write-Ascii $ban @"
unit uBanner;

interface

  $bar
  // arrays
  $bar
type
  TArr = array of Integer;

$bar
/// <summary>Genuine summary.</summary>
$bar
procedure Both;

/// <summary>Plain summary.</summary>
procedure Plain;

//////////
procedure Bare;

//// four slash prose
procedure FourSlash;

/// Sets the mode.
/// To use:
/// 1. Open the options
/// 2. Pick two themes
///
/// Then restart.
procedure NoteLines;

/// One line note.
procedure NoteOne;

implementation

procedure Both;
begin
  Plain;
end;

procedure Plain;
begin
  Bare;
end;

procedure Bare;
var
  A: TArr;
begin
  A:= nil;
  FourSlash;
end;

procedure FourSlash;
begin
  Writeln('x');
  NoteLines;
end;

procedure NoteLines;
begin
  Writeln('y');
  NoteOne;
end;

procedure NoteOne;
begin
  Writeln('z');
end;

end.
"@
$barsBefore = @((Lines $ban) | Where-Object { $_.TrimStart().StartsWith('////') })
[void](Run @('index', $ban, '--db', $db))
$o = Run @('document', '--unit', $ban, '--apply', '--no-backup', '--db', $db)
Check 'BANNER control: the apply wrote docs' ($o -match 'documented, \d+ edit') $o
$after = Lines $ban; $txt = $after -join "`n"
$barsAfter = @($after | Where-Object { $_.TrimStart().StartsWith('////') })
Check 'BANNER every four-slash line survives, in order' (($barsBefore -join "`n") -ceq ($barsAfter -join "`n")) "before=$($barsBefore.Count) after=$($barsAfter.Count)"
Check 'BANNER no slashes harvested into a summary' ($txt -notmatch '<summary>\s*/') (($after | Select-String '<summary>') -join ' | ')
Check 'BANNER TArr got its facts block' ($txt -match '(?s)type\n  /// <remarks>.{0,200}Used by: uBanner\.Bare.{0,200}TArr = array') $txt
Check 'BANNER a genuine summary between banners is kept once, with facts' (([regex]::Matches($txt, 'Genuine summary\.')).Count -eq 1 -and $txt -match '(?s)<summary>Genuine summary\.</summary>\n/// <remarks>') $txt
Check 'BANNER a genuine summary is still carried (positive control)' ($txt -match '<summary>Plain summary\.</summary>\n/// <remarks>') $txt
Check 'NOTE a multi-line note keeps its lines' ($txt -match '/// <summary>Sets the mode\.\n/// To use:\n/// 1\. Open the options\n/// 2\. Pick two themes\n///\n/// Then restart\.</summary>\n') $txt
Check 'NOTE a one-line note stays one line' ($txt -match '/// <summary>One line note\.</summary>\n') $txt
[void](Run @('index', $ban, '--db', $db))
$o2 = Run @('document', '--unit', $ban, '--db', $db)
Check 'BANNER/NOTE pass 2 is a no-op' ($o2 -match 'nothing to document') $o2

# ---------------------------------------------------------------- FIXER
$fix = Join-Path $WorkDir 'uFix.pas'; $fdb = Join-Path $WorkDir 'fix.sqlite'
Write-Ascii $fix @"
unit uFix;

interface

type
  TFix = class
  private
    $bar
    /// <summary>Dead.</summary>
    procedure Dead;
  public
    procedure Alive;
  end;

implementation

procedure TFix.Dead;
begin
end;

procedure TFix.Alive;
begin
end;

end.
"@
[void](Run @('index', $fix, '--db', $fdb))
$fo = Run @('lint-all', '--db', $fdb, '--rule', 'unused-private-member', '--fix', '--apply', '--no-compile-gate', '--library-db', 'none')
$ft = (Lines $fix) -join "`n"
Check 'FIXER control: the member and its doc were deleted' ($ft -notmatch 'Dead') "$fo || $ft"
Check 'FIXER the banner above it stays' ($ft.Contains($bar)) $ft

# ---------------------------------------------------------------- COMMENT
$src = Join-Path $WorkDir 'glob'; [void][IO.Directory]::CreateDirectory($src); $gdb = Join-Path $WorkDir 'glob.sqlite'
Write-Ascii (Join-Path $src 'uGlob.pas') @'
unit uGlob;

interface

const
  CDocOnly = 1;
  CBraceOnly = 2;
  CDirective = 3;
  CInString = 4;
  CBound = 5;
  CAfterUrl = 6;

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Used by: CDocOnly (uGlob.pas)</para>
/// <seealso cref="uGlob.CDocOnly"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure Run;

implementation

{ CBraceOnly is (* CDocOnly *) mentioned here }
(* CBraceOnly { again *)

{$IF CDirective > 1}
{$ENDIF}

procedure Run;
var
  A: array[0..CBound - 1] of Integer;
  U: string;
begin
  A[0]:= 1;
  U:= '{ http://CInString'; U:= U + 'it''s'; if Length(U) = CAfterUrl then Writeln(U, A[0]);
end;

end.
'@
[void](Run @('index', $src, '--db', $gdb))
$g = Run @('lint-all', '--db', $gdb, '--rule', 'unused-global', '--quiet')
foreach ($n in 'CDocOnly', 'CBraceOnly') { Check "COMMENT $n (comments only) is reported" ($g -match "const $n \(") $g }
foreach ($n in 'CDirective', 'CInString', 'CBound', 'CAfterUrl') { Check "COMMENT $n (code, directive or string) stays silent" ($g -notmatch "const $n \(") $g }

# ---------------------------------------------------------------- RESCAN (item 3)
$prj = Join-Path $WorkDir 'prj'; [void][IO.Directory]::CreateDirectory("$prj\_D-RAG"); $pdb = "$prj\_D-RAG\P.sqlite"
Write-Ascii "$prj\P.dpr" @'
program P;
uses
  uSvcA in 'uSvcA.pas',
  uSvcB in 'uSvcB.pas';
begin
  Go;
end.
'@
Write-Ascii "$prj\P.dproj" @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><MainSource>P.dpr</MainSource><Config Condition="'$(Config)'==''">Debug</Config><Platform Condition="'$(Platform)'==''">Win64</Platform></PropertyGroup>
  <PropertyGroup Condition="'$(Config)'=='Debug'"><DCC_Define>MYDEBUG;$(DCC_Define)</DCC_Define></PropertyGroup>
  <ItemGroup><DelphiCompile Include="P.dpr"><MainSource>MainSource</MainSource></DelphiCompile><DCCReference Include="uSvcA.pas"/><DCCReference Include="uSvcB.pas"/></ItemGroup>
</Project>
'@
Write-Ascii "$prj\uSvcA.pas" @'
unit uSvcA;

interface

type
  InjectAttribute = class(TCustomAttribute)
  end;

  ESvcOne = class(TObject);

  TSvcA = class
  private
    FName: string;
  public
    [Inject] // resolved by the container
    { a brace comment between the attribute and its heading }
    constructor Create(const AName: string);
    [Inject]
    procedure Log(const S: string);
  end;

implementation

constructor TSvcA.Create(const AName: string);
begin
  FName:= AName;
end;

procedure TSvcA.Log(const S: string);
begin
  Writeln(FName, S);
end;

end.
'@
Write-Ascii "$prj\uSvcB.pas" @'
unit uSvcB;

interface

procedure Go;
procedure Helper(const S: string);

implementation

uses
  uSvcA;

procedure Helper(const S: string);
var
  A: TSvcA;
begin
  A:= TSvcA.Create(S);
  A.Log(S);
  A.Free;
end;

procedure Go;
begin
  Helper('x');
end;

end.
'@
function Fp { (& $Exe sql --db $pdb --query "select value from schema_meta where key='indexer_fingerprint'" 2>$null | Where-Object { $_ -match '^v=' }) -join '' }
$ix = Run @('index', '--project', "$prj\P.dproj", '--db', $pdb)
$fp0 = Fp
Check 'RESCAN control: the project index carries its own build (win64, cfg)' ($fp0 -match 'plat=win64;cfg=debug;defs=') "$fp0 || $ix"
$d1 = Run @('document', '--unit', "$prj\uSvcA.pas", '--db', $pdb)
Check 'RESCAN an attribute line above a heading is not tampering (no WARN)' ($d1 -notmatch 'look unchanged by timestamp') $d1
Check 'RESCAN control: the dry run still proposes docs' ($d1 -match 'insert after line') $d1
Check 'RESCAN a dry run leaves the fingerprint of the project index alone' ((Fp) -eq $fp0) (Fp)
# pass 1 over every unit, a reindex, pass 2
foreach ($u in 'uSvcB', 'uSvcA') { [void](Run @('document', '--unit', "$prj\$u.pas", '--apply', '--no-backup', '--db', $pdb)) }
[void](Run @('index', '--project', "$prj\P.dproj", '--db', $pdb))
foreach ($u in 'uSvcB', 'uSvcA') { $o2 = Run @('document', '--unit', "$prj\$u.pas", '--db', $pdb); Check "RESCAN pass 2 of $u is a no-op after a reindex" ($o2 -match 'nothing to document') $o2 }
# a genuine same-size edit with the mtime put back
$sa = "$prj\uSvcA.pas"; $when = (Get-Item $sa).LastWriteTimeUtc
[IO.File]::WriteAllText($sa, [IO.File]::ReadAllText($sa).Replace('ESvcOne', 'ESvcTwo'), [Text.Encoding]::ASCII); (Get-Item $sa).LastWriteTimeUtc = $when
$d2 = Run @('document', '--project', "$prj\P.dproj", '--db', $pdb)
Check 'RESCAN a genuine tamper still WARNs (control)' ($d2 -match 'look unchanged by timestamp' -and $d2 -match 'uSvcA') $d2
Check 'RESCAN document --project re-parses the tampered file only' ($d2 -match 'uSvcA\.pas -> \d+ symbols' -and $d2 -notmatch 'uSvcB\.pas -> \d+ symbols') $d2
Check 'RESCAN the rescan keeps the build fingerprint (--project)' ((Fp) -eq $fp0) (Fp)
$when = (Get-Item $sa).LastWriteTimeUtc
[IO.File]::WriteAllText($sa, [IO.File]::ReadAllText($sa).Replace('ESvcTwo', 'ESvcSix'), [Text.Encoding]::ASCII); (Get-Item $sa).LastWriteTimeUtc = $when
$d3 = Run @('document', '--unit', $sa, '--db', $pdb)
Check 'RESCAN control: --unit on a genuine tamper WARNs' ($d3 -match 'look unchanged by timestamp') $d3
Check 'RESCAN the rescan keeps the build fingerprint (--unit)' ((Fp) -eq $fp0) (Fp)

# ---------------------------------------------------------------- DI
$di = Join-Path $WorkDir 'di'; [void][IO.Directory]::CreateDirectory($di); $ddb = Join-Path $WorkDir 'di.sqlite'
Write-Ascii (Join-Path $di 'uSvc.pas') @'
unit uSvc;

interface

type
  ISvc = interface
    procedure Go;
  end;

  IOther = interface
    procedure Go;
  end;

  TSvc = class(TInterfacedObject, ISvc)
  public
    procedure Go;
  end;

  TTwo = class(TInterfacedObject, ISvc, IOther)
  public
    procedure Go;
  end;

implementation

procedure TSvc.Go;
begin
  Writeln('a');
end;

procedure TTwo.Go;
begin
  Writeln('b');
end;

end.
'@
foreach ($u in 'uCfgA', 'uCfgB') {
Write-Ascii (Join-Path $di "$u.pas") @"
unit $u;

interface

procedure Setup;

implementation

uses
  Spring.Container, uSvc;

procedure Setup;
begin
  GlobalContainer.RegisterType<TSvc>.Implements<ISvc>.AsTransient;
  GlobalContainer.RegisterType<TTwo>.Implements<ISvc>.AsTransient;
  GlobalContainer.RegisterType<TTwo>.Implements<IOther>.AsTransient;
end;

end.
"@
}
[void](Run @('index', $di, '--db', $ddb))
$dout = Run @('document', '--unit', (Join-Path $di 'uSvc.pas'), '--db', $ddb)
$reg = @($dout -split "`n" | Where-Object { $_ -match 'Registered as:' } | ForEach-Object { ($_ -replace '.*Registered as: ', '') -replace '</para>.*', '' })
Check 'DI one entry for a type registered twice alike' ($reg -contains 'ISvc (transient)') ($reg -join ' | ')
Check 'DI no entry is repeated' (@($reg | Where-Object { $p = $_ -split ', '; $p.Count -ne @($p | Select-Object -Unique).Count }).Count -eq 0) ($reg -join ' | ')
Check 'DI two DIFFERENT registrations both stay (control)' (@($reg | Where-Object { $_ -match 'ISvc' -and $_ -match 'IOther' }).Count -gt 0) ($reg -join ' | ')
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { } }
}
Write-Host "checks=$script:Total"
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
