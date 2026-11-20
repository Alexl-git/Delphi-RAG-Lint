<#
  run_v1521_smalls.ps1 -- 1.52.1 lane SMALLS (four small items).

  1  NORETURN-SHOW  the noreturn fact (symbols.directives) is shown in hover (md + json facts)
                    and in the managed autodoc facts block, through the shared 'Directives:' line.
                    GUARD ONLY: the shared FormatPhase2FactLines already carried it (measured on
                    the 1.52.0-alpha engine), so there is no RED for this item -- the test pins
                    the behaviour so a later refactor of the Directives line cannot drop it.
  2  FINDCALLEES    find-callees --name <bare> works like find-callers' bare name (exit 0, the
                    callees), and several routines sharing the bare name are each listed under
                    their own '# <qname>' header. --qname behaviour is unchanged.
  3  TEXTLIT        query --text matches ONE string literal at a time: a phrase that spans two
                    literals joined by '+' on separate lines is not found. Documented limit
                    (--help, AI-USAGE); this test pins the limit and its workaround (a phrase
                    inside one literal matches).
  4  USESFIX-TMP    uses-fix shadow-compiles in a per-process dir and removes it afterwards:
                    no draglint_usesfix* directory is left in %TEMP%.

  Usage: pwsh -File tests\autotest\run_v1521_smalls.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = '')
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]), $n) -ForegroundColor (@('Red','Green')[[int]$ok])
  if (-not $ok -and $d) { Write-Host "        $d" -ForegroundColor DarkGray }
  if (-not $ok) { $script:fail = $true }
}
function WritePas([string]$Path, [string]$Text) {
  $norm = ($Text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_smalls_$PID"
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$src = Join-Path $scratch 'src'; New-Item -ItemType Directory -Path $src | Out-Null
$tmp = Join-Path $scratch 'tmp'; New-Item -ItemType Directory -Path $tmp | Out-Null
$db = Join-Path $scratch 's.sqlite'

function Eng([string[]]$EngArgs) {
  # stdout and stderr to files, read after the exit (a pipeline once lost stdout under -Jobs 4)
  $so = Join-Path $scratch ('o_{0}.txt' -f [Guid]::NewGuid().ToString('N'))
  $se = Join-Path $scratch ('e_{0}.txt' -f [Guid]::NewGuid().ToString('N'))
  $env:TEMP = $tmp; $env:TMP = $tmp
  $q = ($EngArgs | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
  $p = Start-Process -FilePath $exePath -ArgumentList $q -NoNewWindow -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
  $null = $p.Handle
  $null = $p.WaitForExit()
  $r = [pscustomobject]@{ Out = [IO.File]::ReadAllText($so); Err = [IO.File]::ReadAllText($se); Code = $p.ExitCode }
  [IO.File]::Delete($so); [IO.File]::Delete($se)
  return $r
}

WritePas (Join-Path $src 'uNr.pas') @'
unit uNr;

interface

/// <summary>Dies.</summary>
procedure Fail(const AText: string); noreturn;

/// <summary>Plain.</summary>
procedure Plain(const AText: string);

implementation

procedure Fail(const AText: string);
begin
  raise Exception.Create(AText);
end;

procedure Plain(const AText: string);
begin
  Fail(AText);
end;

end.
'@
WritePas (Join-Path $src 'uAmb.pas') @'
unit uAmb;

interface

type
  TA = class
    procedure Run;
    procedure HelperA;
  end;
  TB = class
    procedure Run;
    procedure HelperB;
  end;

implementation

procedure TA.HelperA;
begin
end;

procedure TA.Run;
begin
  HelperA;
end;

procedure TB.HelperB;
begin
end;

procedure TB.Run;
begin
  HelperB;
end;

end.
'@
WritePas (Join-Path $src 'uMl.pas') @'
unit uMl;

interface

procedure Say;

implementation

procedure Say;
begin
  Writeln('Usage: tool --db PATH ' +
    '[--json] ' +
    '(show every row of the table)');
end;

end.
'@
# uses-fix fixture (see run_uses_fix_json_and_only.ps1): uDropMe is a REMOVE candidate, so TryEdit runs.
WritePas (Join-Path $src 'uDropMe.pas') @'
unit uDropMe;
interface
type
  TDropMe = class
    procedure Nope;
  end;
implementation
procedure TDropMe.Nope;
begin
end;
end.
'@
WritePas (Join-Path $src 'uKeepMe.pas') @'
unit uKeepMe;
interface
type
  TKeepMe = class
    procedure Stay;
  end;
implementation
procedure TKeepMe.Stay;
begin
end;
end.
'@
WritePas (Join-Path $src 'uMain.pas') @'
unit uMain;

interface

uses
  uDropMe,
  uKeepMe;

type
  TMain = class
    FKeep: TKeepMe;
    procedure Run;
  end;

implementation

procedure TMain.Run;
begin
end;

end.
'@
WritePas (Join-Path $src 'App.dproj') @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup>
    <DCCReference Include="uMain.pas"/>
    <DCCReference Include="uDropMe.pas"/>
    <DCCReference Include="uKeepMe.pas"/>
  </ItemGroup>
</Project>
'@

$null = Eng @('index', $src, '--db', $db)
Check 'fixture indexed' (Test-Path $db) $db

Write-Host '== 1 NORETURN-SHOW ==' -ForegroundColor Cyan
$h = Eng @('hover', '--qname', 'uNr.Fail', '--db', $db, '--format', 'md')
Check '1a hover md shows noreturn' ($h.Out -match 'Directives: noreturn') $h.Out
$hj = Eng @('hover', '--qname', 'uNr.Fail', '--db', $db, '--format', 'json')
Check '1b hover json facts carry noreturn' ($hj.Out -match '"facts":\[[^\]]*noreturn') $hj.Out
$hp = Eng @('hover', '--qname', 'uNr.Plain', '--db', $db, '--format', 'md')
Check '1c control: Plain has no noreturn' ($hp.Out -notmatch 'noreturn') $hp.Out
$d = Eng @('document', '--qname', 'uNr.Fail', '--db', $db)
Check '1d autodoc facts block shows noreturn' ($d.Out -match 'Directives: noreturn') $d.Out

Write-Host '== 2 find-callees --name ==' -ForegroundColor Cyan
$c = Eng @('find-callees', '--name', 'Plain', '--db', $db)
Check '2a --name Plain exit 0' ($c.Code -eq 0) "exit=$($c.Code) out=$($c.Out) err=$($c.Err)"
Check '2b --name Plain lists uNr.Fail' ($c.Out -match 'uNr\.Fail') $c.Out
$q = Eng @('find-callees', '--qname', 'uNr.Plain', '--db', $db)
Check '2c --qname unchanged: exit 0, lists uNr.Fail, no header' (($q.Code -eq 0) -and ($q.Out -match 'uNr\.Fail') -and ($q.Out -notmatch '#')) $q.Out
$a = Eng @('find-callees', '--name', 'Run', '--db', $db)
Check '2d ambiguous --name: both candidates headed' (($a.Out -match '# uAmb\.TA\.Run') -and ($a.Out -match '# uAmb\.TB\.Run')) $a.Out
Check '2e ambiguous --name: both callees listed' (($a.Out -match 'uAmb\.TA\.HelperA') -and ($a.Out -match 'uAmb\.TB\.HelperB')) $a.Out
$n = Eng @('find-callees', '--name', 'NoSuchRoutineAnywhere', '--db', $db)
Check '2f unknown --name exits 1 (not the usage error 2)' ($n.Code -eq 1) "exit=$($n.Code)"
$u = Eng @('find-callees', '--db', $db)
Check '2g neither --name nor --qname is still a usage error' ($u.Code -eq 2) "exit=$($u.Code)"
$hl = Eng @('find-callees', '--help')
Check '2h --help lists find-callees --name' ($hl.Out -match 'find-callees --qname <Foo\.Bar> \| --name') $hl.Out

Write-Host '== 3 query --text across literals ==' -ForegroundColor Cyan
$t1 = Eng @('query', '--text', 'show every row of the table', '--db', $db)
Check '3a a phrase inside ONE literal matches' ($t1.Out -match '1 match') $t1.Out
$t2 = Eng @('query', '--text', '[--json] (show every', '--db', $db)
Check '3b documented limit: a phrase spanning two literals does not match' ($t2.Out -match '0 match|^\s*$' -or $t2.Out -notmatch 'uMl\.pas') $t2.Out
$th = Eng @('--help')
Check '3c --help states the one-literal limit' ($th.Out -match 'one string literal') ''

Write-Host '== 4 uses-fix shadow dir ==' -ForegroundColor Cyan
$r = Eng @('uses-fix', (Join-Path $src 'uMain.pas'), '--project', (Join-Path $src 'App.dproj'), '--db', $db, '--remove-unused', '--format', 'json')
$left = @(Get-ChildItem $tmp -Directory -Filter 'draglint_usesfix*' -ErrorAction SilentlyContinue)
Check '4a uses-fix ran' ($r.Out -match 'uDropMe') "exit=$($r.Code) $($r.Out)"
Check '4b no draglint_usesfix* dir left in TEMP' ($left.Count -eq 0) (($left | ForEach-Object Name) -join ',')

[IO.Directory]::Delete($scratch, $true)
if ($script:fail) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL PASS' -ForegroundColor Green
