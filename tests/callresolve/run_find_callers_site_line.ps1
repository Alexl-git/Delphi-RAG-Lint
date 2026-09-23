<#
  run_find_callers_site_line.ps1 -- every `query find-callers --resolved` row
  reports the CALL SITE in `line`, whichever arm produced it.

  THE DEFECT (C1, 2026-09-23). The rows built from call_edges -- a routine
  call, a property/field access, an enum-value read and a parenless call --
  reported the CALLER ROUTINE's declaration line in `line`, while the callback
  arm reported the site. One key, two meanings, chosen by which arm happened to
  produce the row; the parenless-call implementer tripped over it the day that
  arm shipped. The text form printed no line at all for those rows, so text and
  JSON could not even be compared.

  THE CONTRACT PINNED HERE
    * `line`        = the line of the call/access/read ITSELF, on every row.
    * `caller_line` = the enclosing routine's declaration line, when the
                      enclosing routine is known -- a separate key, so nothing
                      that wants the routine has to recover it from `line`.
    * the text form prints `(<file>:<site line>)` on every row, so the two
      forms name the same line.

  THE CONTROL. Every caller in the fixture is DECLARED on a line that is not its
  call site (checked first), so a renderer that prints either line for both
  keys fails at least one assertion. Line numbers are read from the fixture's
  own `// SITE-*` / `// DECL-*` markers, never hard-coded.

  Usage: pwsh -File tests\callresolve\run_find_callers_site_line.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\draglint_find_callers_site_line"
)
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe"; exit 2 }
$exePath = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory -Path $src | Out-Null

$fixture = @"
unit uSiteLine;

interface

type
  TColourX = (clRedX, clGreenX);
  TPickPred = function(const AItem: string): Boolean;

  TBox = class
  private
    FCount: Integer;
  public
    property Count: Integer read FCount write FCount;
  end;

implementation

procedure Target(A: Integer);
begin
  Writeln(A);
end;

function NextId: Integer;
begin
  Result := 1;
end;

function Pred(const AItem: string): Boolean;
begin
  Result := AItem <> '';
end;

procedure Choose(P: TPickPred);
begin
  if Assigned(P) then Writeln('chosen');
end;

procedure CallIt; // DECL-CALL
var
  I: Integer;
begin
  I := 2;
  Writeln(I);
  Target(I); // SITE-CALL
end;

procedure ReadProp(B: TBox); // DECL-PROP
var
  N: Integer;
begin
  N := 0;
  N := B.Count; // SITE-PROP
  Writeln(N);
end;

procedure UseEnum; // DECL-ENUM
var
  C: TColourX;
begin
  Writeln('x');
  C := clGreenX; // SITE-ENUM
  Writeln(Ord(C));
end;

procedure UseParenless; // DECL-PARENLESS
var
  N: Integer;
begin
  Writeln('x');
  N := NextId; // SITE-PARENLESS
  Writeln(N);
end;

procedure PassCb; // DECL-CB
begin
  Writeln('x');
  Choose(Pred); // SITE-CB
end;

end.
"@
$unit = Join-Path $src 'uSiteLine.pas'
[IO.File]::WriteAllText($unit, (($fixture -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII)

function LineOf([string]$Marker) {
  $m = @(Select-String -LiteralPath $unit -SimpleMatch -Pattern "// $Marker")
  if ($m.Count -ne 1) { throw "marker '$Marker' found $($m.Count) times in the fixture" }
  return [int]$m[0].LineNumber
}

$db = Join-Path $WorkDir 'siteline.sqlite'
Push-Location $WorkDir
try {
  & $exePath index $src --db $db 2>&1 | Out-Null
  if (-not (Test-Path $db)) { Write-Host 'FATAL: index produced no DB'; exit 2 }

  # One arm per case: the target name to ask for, the caller that reaches it,
  # and the confidence/mode the arm is expected to carry (so a row from the
  # WRONG arm cannot satisfy the case).
  $cases = @(
    @{ Arm = 'call';      Name = 'Target'; Caller = 'CallIt';       Tag = 'CALL';      Conf = 'certain';  Mode = $null  },
    @{ Arm = 'property';  Name = 'Count';  Caller = 'ReadProp';     Tag = 'PROP';      Conf = $null;      Mode = 'read' },
    @{ Arm = 'enum';      Name = 'clGreenX'; Caller = 'UseEnum';    Tag = 'ENUM';      Conf = $null;      Mode = 'read' },
    @{ Arm = 'parenless'; Name = 'NextId'; Caller = 'UseParenless'; Tag = 'PARENLESS'; Conf = 'certain';  Mode = $null  },
    @{ Arm = 'callback';  Name = 'Pred';   Caller = 'PassCb';       Tag = 'CB';        Conf = 'callback'; Mode = $null  })

  foreach ($c in $cases) {
    $site = LineOf ("SITE-" + $c.Tag)
    $decl = LineOf ("DECL-" + $c.Tag)
    Check ("fixture control [{0}]: declaration line {1} is not the site line {2}" -f $c.Arm, $decl, $site) ($site -ne $decl)

    $raw = (& $exePath query find-callers --name $c.Name --resolved --json --db $db 2>$null) -join "`n"
    $b = $raw.IndexOf('[')
    $rows = @(); if ($b -ge 0) { $rows = @($raw.Substring($b) | ConvertFrom-Json) }
    $mine = @($rows | Where-Object {
      ([string]$_.caller_qname).EndsWith($c.Caller) -and
      (($null -eq $c.Conf) -or ($_.confidence -eq $c.Conf)) -and
      (($null -eq $c.Mode) -or ($_.mode -eq $c.Mode)) })
    Check ("json [{0}]: exactly one {1} row for {2}" -f $c.Arm, $c.Caller, $c.Name) ($mine.Count -eq 1) `
      ("rows=" + (($rows | ForEach-Object { "$($_.caller_qname)/$($_.confidence)/$($_.mode)/line=$($_.line)" }) -join '; '))
    if ($mine.Count -eq 1) {
      Check ("json [{0}]: line is the SITE ({1})" -f $c.Arm, $site) ($mine[0].line -eq $site) "line=$($mine[0].line) decl=$decl"
      Check ("json [{0}]: caller_line is the caller's DECLARATION ({1})" -f $c.Arm, $decl) ($mine[0].caller_line -eq $decl) `
        "caller_line=$($mine[0].caller_line)"
    }

    $txt = (& $exePath query find-callers --name $c.Name --resolved --db $db 2>$null) -join "`n"
    $pat = [regex]::Escape($c.Caller) + '\s+\(uSiteLine\.pas:' + $site + '\)'
    Check ("text [{0}]: the row prints the SITE line, agreeing with json" -f $c.Arm) ($txt -match $pat) "got: $($txt.Trim())"
  }
}
finally {
  Pop-Location
}

if ($script:fail) { Write-Host 'FAIL  run_find_callers_site_line'; exit 1 }
Write-Host 'PASS  run_find_callers_site_line'
exit 0