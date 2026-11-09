<#
  run_doc_exception_rtl_callee_scope.ps1 -- 148 DX, the two C9 (1.44) limits named in
  lanes\144\drift\REPORT.md deviation 5:

  a) A BARE call matched a free routine of that name in ANY library unit, so a same-named
     routine in a unit the caller does not use silenced a finding. Only units in the
     calling file's uses clause (plus System / SysInit, implicit) may answer; a used name
     may be a unit-scope short form (`Scoped` for `Fake.Scoped`).
  b) A VIRTUAL member reached through a non-abstract base read the base body only; a
     descendant's override is a dispatch target and its raise is plausible.

  RED on the 1.46 engine:
    S1 App uses FakeRtl only; FakeRtl.Twin is quiet, FakeOther.Twin raises EScope: REPORT
    V1 B: TLibV; B.Go is virtual (quiet body), TLibV2.Go override raises EVirt: SILENT
  CONTROLS
    S2 App2 uses FakeOther: the same bare call is SILENT (the used unit raises)
    S3 App3 uses `Scoped` (unit-scope short form of Fake.Scoped, which raises): SILENT
    V2 B.Stat is STATIC; TLibV2.Stat hides it and raises: still REPORTS (no dispatch)
    C5 V1 with --library-db none: REPORTS (no library, no evidence)
  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_doc_rtl_scope_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
foreach ($d in 'lib','proj') { New-Item -ItemType Directory -Path (Join-Path $scratch $d) | Out-Null }
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $scratch 'lib\FakeRtl.pas') @'
unit FakeRtl;

interface

type
  EScope = class(TObject)
  public
    constructor Create(const A: string);
  end;
  EVirt = class(TObject)
  public
    constructor Create(const A: string);
  end;
  EStat = class(TObject)
  public
    constructor Create(const A: string);
  end;

  TLibV = class(TObject)
  public
    procedure Go(const A: string); virtual;
    procedure Stat(const A: string);
  end;

  TLibV2 = class(TLibV)
  public
    procedure Go(const A: string); override;
    procedure Stat(const A: string);
  end;

procedure Twin(const A: string);

implementation

constructor EScope.Create(const A: string); begin end;
constructor EVirt.Create(const A: string); begin end;
constructor EStat.Create(const A: string); begin end;

procedure TLibV.Go(const A: string);
begin
end;

procedure TLibV.Stat(const A: string);
begin
end;

procedure TLibV2.Go(const A: string);
begin
  raise EVirt.Create(A);
end;

procedure TLibV2.Stat(const A: string);
begin
  raise EStat.Create(A);
end;

procedure Twin(const A: string);
begin
end;

end.
'@
WriteAscii (Join-Path $scratch 'lib\FakeOther.pas') @'
unit FakeOther;

interface

uses FakeRtl;

procedure Twin(const A: string);

implementation

procedure Twin(const A: string);
begin
  raise EScope.Create(A);
end;

end.
'@
WriteAscii (Join-Path $scratch 'lib\Fake.Scoped.pas') @'
unit Fake.Scoped;

interface

uses FakeRtl;

procedure Twin3(const A: string);

implementation

procedure Twin3(const A: string);
begin
  raise EScope.Create(A);
end;

end.
'@
WriteAscii (Join-Path $scratch 'proj\App.pas') @'
unit App;

interface

uses FakeRtl;

/// <summary>Bare call, unused unit raises.</summary>
/// <exception cref="EScope">Only FakeOther.Twin raises it.</exception>
procedure S1Twin;
/// <summary>Virtual through the base.</summary>
/// <exception cref="EVirt">An override raises it.</exception>
procedure V1Virtual(const B: TLibV);
/// <summary>Static through the base.</summary>
/// <exception cref="EStat">Control: a hiding static member is no dispatch target.</exception>
procedure V2Static(const B: TLibV);

implementation

procedure S1Twin;
begin
  Twin('x');
end;

procedure V1Virtual(const B: TLibV);
begin
  B.Go('x');
end;

procedure V2Static(const B: TLibV);
begin
  B.Stat('x');
end;

end.
'@
WriteAscii (Join-Path $scratch 'proj\App2.pas') @'
unit App2;

interface

uses FakeRtl, FakeOther;

/// <summary>Bare call, used unit raises.</summary>
/// <exception cref="EScope">FakeOther.Twin raises it.</exception>
procedure S2Twin;

implementation

procedure S2Twin;
begin
  Twin('x');
end;

end.
'@
WriteAscii (Join-Path $scratch 'proj\App3.pas') @'
unit App3;

interface

uses FakeRtl, Scoped;

/// <summary>Bare call through a unit-scope short name.</summary>
/// <exception cref="EScope">Fake.Scoped.Twin3 raises it.</exception>
procedure S3Twin;

implementation

procedure S3Twin;
begin
  Twin3('x');
end;

end.
'@

$libDb = Join-Path $scratch 'lib.sqlite'
$projDb = Join-Path $scratch 'proj.sqlite'
Push-Location $scratch
try {
  $null = & $exePath index (Join-Path $scratch 'lib') --db $libDb --library-db none 2>&1 | Out-String
  $null = & $exePath index (Join-Path $scratch 'proj') --db $projDb --library-db none 2>&1 | Out-String

  function Lane-NeverRaisedIn([string]$LibArg) {
    $raw = (& $exePath lint-all --db $projDb --rule doc-drift --library-db $LibArg --json 2>$null | Out-String)
    $rows = @($raw | ConvertFrom-Json)
    $names = @{}
    foreach ($r in $rows) {
      if ($r.message -notmatch 'never raises') { continue }
      $src = [IO.File]::ReadAllLines($r.file_path)
      for ($i = $r.start_line - 1; $i -lt $src.Length; $i++) {
        if ($src[$i] -match '^procedure (\w+)') { $names[$Matches[1]] = $true; break }
      }
    }
    return ,$names
  }

  $with = Lane-NeverRaisedIn $libDb
  $got = ($with.Keys | Sort-Object) -join ','
  Check '0. sanity: the fixture produced findings at all' ($with.Count -gt 0) "reported: $got"
  Check 'S1Twin REPORTS (only an unused unit raises)' ($with.ContainsKey('S1Twin')) "reported: $got"
  Check 'V1Virtual SILENT (an override raises)' (-not $with.ContainsKey('V1Virtual')) "reported: $got"
  Check 'CONTROL S2Twin silent (the used unit raises)' (-not $with.ContainsKey('S2Twin')) "reported: $got"
  Check 'CONTROL S3Twin silent (unit-scope short name)' (-not $with.ContainsKey('S3Twin')) "reported: $got"
  Check 'CONTROL V2Static still reports (static hide)' ($with.ContainsKey('V2Static')) "reported: $got"
  $none = Lane-NeverRaisedIn 'none'
  Check 'CONTROL C5 V1Virtual reports with --library-db none' ($none.ContainsKey('V1Virtual'))
} finally { Pop-Location }

[IO.Directory]::Delete($scratch, $true)
if ($fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
} catch { Write-Host "FAIL (exception): $_"; exit 1 }
