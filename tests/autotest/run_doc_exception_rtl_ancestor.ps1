<#
  run_doc_exception_rtl_ancestor.ps1 -- 149 RT item 5: C9 (library-body raises) matches an ANCESTOR cref.

  `<exception cref="Exception">` over a call into the RTL whose body raises a SUBCLASS (EInOutError ...) read as
  "never raises Exception" because C9 compared names exactly. Now a raise in a library body satisfies a cref naming
  any of its ancestors. The routine's OWN-body test stays exact (CONTROL-2 of the cref-transitive guard).

  RED on the 1.48 engine: A1Anc cref EBase over B.Go (the library body raises ESub, a descendant of EBase): REPORTED
  CONTROLS
    A2 cref EBase over B.Other (library body raises EUnrelated): still REPORTS (the ancestor must be real)
    A3 A1Anc with --library-db none: REPORTS (no library, no evidence)
    A4 cref ESub over B.Go: SILENT before and after (exact match)
  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_doc_rtl_anc_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
foreach ($d in 'lib','proj') { New-Item -ItemType Directory -Path (Join-Path $scratch $d) | Out-Null }
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $scratch 'lib\FakeAnc.pas') @'
unit FakeAnc;

interface

type
  EBase = class(TObject)
  public
    constructor Create(const A: string);
  end;
  ESub = class(EBase)
  end;
  EUnrelated = class(TObject)
  public
    constructor Create(const A: string);
  end;

  TLibA = class(TObject)
  public
    procedure Go(const A: string);
    procedure Other(const A: string);
  end;

implementation

constructor EBase.Create(const A: string); begin end;
constructor EUnrelated.Create(const A: string); begin end;

procedure TLibA.Go(const A: string);
begin
  raise ESub.Create(A);
end;

procedure TLibA.Other(const A: string);
begin
  raise EUnrelated.Create(A);
end;

end.
'@
WriteAscii (Join-Path $scratch 'proj\App.pas') @'
unit App;

interface

uses FakeAnc;

/// <summary>Library body raises a descendant.</summary>
/// <exception cref="EBase">TLibA.Go raises ESub, a descendant.</exception>
procedure A1Anc(const B: TLibA);
/// <summary>Library body raises an unrelated class.</summary>
/// <exception cref="EBase">Control: EUnrelated is no EBase.</exception>
procedure A2Unrelated(const B: TLibA);
/// <summary>Exact match.</summary>
/// <exception cref="ESub">TLibA.Go raises exactly this.</exception>
procedure A4Exact(const B: TLibA);

implementation

procedure A1Anc(const B: TLibA);
begin
  B.Go('x');
end;

procedure A2Unrelated(const B: TLibA);
begin
  B.Other('x');
end;

procedure A4Exact(const B: TLibA);
begin
  B.Go('x');
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
  Check 'A1Anc SILENT (the library body raises a descendant of the cref)' (-not $with.ContainsKey('A1Anc')) "reported: $got"
  Check 'CONTROL A2Unrelated still reports (unrelated raise)' ($with.ContainsKey('A2Unrelated')) "reported: $got"
  Check 'CONTROL A4Exact silent (exact name)' (-not $with.ContainsKey('A4Exact')) "reported: $got"
  $none = Lane-NeverRaisedIn 'none'
  Check 'CONTROL A3 A1Anc reports with --library-db none' ($none.ContainsKey('A1Anc'))
} finally { Pop-Location }

[IO.Directory]::Delete($scratch, $true)
if ($fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
} catch { Write-Host "FAIL (exception): $_"; exit 1 }
