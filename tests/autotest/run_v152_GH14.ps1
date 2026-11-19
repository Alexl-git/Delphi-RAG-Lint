<#
  run_v152_GH14.ps1 -- GitHub #14: `impact --qname` counted the callers of EVERY routine with the
  same last name segment (refs.name_text) and answered for a qname that names no symbol.
  Fixture: Shapes.TCircle.Draw / Shapes.TSquare.Draw; Painter + AnsiPainter call TCircle.Draw,
  SquarePainter calls TSquare.Draw.
  1. impact TCircle.Draw depth 1 = 2 callers in 2 units (was 3 in 3), same set as find-callers --resolved.
  2. impact TSquare.Draw depth 1 = 1 caller in 1 unit.
  3. --json levels agree (callers 2, units 2).
  4. a qname that resolves to no symbol exits 1 and says so (was "3 callers", exit 0).
  6. usages --width wide bound at a TCircle.Draw call site reports the same 2 depth-1 callers.
  5. positive control: depth 2 still walks (Painter.PaintCircle has a caller in Client).
  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl_gh14_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fx = Join-Path $work 'fx'
[void][IO.Directory]::CreateDirectory($fx)
function W($n, $t) { [IO.File]::WriteAllText((Join-Path $fx $n), ($t -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII) }
W 'Shapes.pas' @'
unit Shapes;
interface
type
  TCircle = class
  public
    procedure Draw;
  end;
  TSquare = class
  public
    procedure Draw;
  end;
implementation
procedure TCircle.Draw; begin end;
procedure TSquare.Draw; begin end;
end.
'@
W 'Painter.pas' @'
unit Painter;
interface
uses Shapes;
procedure PaintCircle(C: TCircle);
implementation
procedure PaintCircle(C: TCircle); begin C.Draw; end;
end.
'@
W 'AnsiPainter.pas' @'
unit AnsiPainter;
interface
uses Shapes;
procedure PaintAnsi(C: TCircle);
implementation
procedure PaintAnsi(C: TCircle); begin C.Draw; end;
end.
'@
W 'SquarePainter.pas' @'
unit SquarePainter;
interface
uses Shapes;
procedure PaintSquare(S: TSquare);
implementation
procedure PaintSquare(S: TSquare); begin S.Draw; end;
end.
'@
W 'Client.pas' @'
unit Client;
interface
uses Shapes, Painter;
procedure Go;
implementation
procedure Go; var C: TCircle; begin C := TCircle.Create; PaintCircle(C); end;
end.
'@
$db = Join-Path $work 'fx.sqlite'
Push-Location $work
try {
  & $exe index $fx --db $db *> $null
  Check 'fixture indexed' ($LASTEXITCODE -eq 0 -and (Test-Path $db)) "exit $LASTEXITCODE"

  $o = (& $exe impact --qname Shapes.TCircle.Draw --depth 1 --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'TCircle.Draw: 2 callers in 2 units, exit 0' (($o -match 'Depth 1:\s+2 callers in 2 units') -and $rc -eq 0) "exit $rc / $($o.Trim())"

  $o = (& $exe impact --qname Shapes.TSquare.Draw --depth 1 --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'TSquare.Draw: 1 caller in 1 unit' (($o -match 'Depth 1:\s+1 callers? in 1 units?') -and $rc -eq 0) "exit $rc / $($o.Trim())"

  $j = (& $exe impact --qname Shapes.TCircle.Draw --depth 1 --format json --db $db 2>$null | Out-String)
  $ok = $false
  try { $p = $j | ConvertFrom-Json; $ok = ($p.levels[0].callers -eq 2 -and $p.levels[0].units -eq 2) } catch { }
  Check 'json levels[0] = 2 callers / 2 units' $ok $j.Trim()

  $fc = (& $exe query find-callers --name TCircle.Draw --resolved --db $db 2>&1 | Out-String)
  Check 'agrees with find-callers --resolved (2 callers)' ($fc -match '2 callers') $fc.Trim()

  $o = (& $exe impact --qname NoSuchUnit.TNothing.Draw --depth 1 --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'unknown qname: exit 1, no caller count' ($rc -eq 1 -and $o -notmatch 'callers in' -and $o -match 'NoSuchUnit\.TNothing\.Draw') "exit $rc / $($o.Trim())"

  # 1.52 follow-up: usages --width wide bound at a call site walks the same resolved callers
  $u = (& $exe usages --name Draw --in (Join-Path $fx 'Painter.pas') --line 6 --col 46 --width wide --depth 1 --format json --db $db 2>$null | Out-String)
  $ok = $false
  try { $pu = $u | ConvertFrom-Json; $ok = ($pu.bound -match 'TCircle\.Draw' -and @($pu.impact)[0].callers -eq 2) } catch { }
  Check 'usages --width wide at TCircle.Draw: impact depth 1 = 2 callers' $ok ($u.Trim())

  $o = (& $exe impact --qname Shapes.TCircle.Draw --depth 2 --db $db 2>&1 | Out-String); $rc = $LASTEXITCODE
  Check 'positive control: depth 2 reaches Client.Go (1 caller)' ($o -match 'Depth 2:\s+1 callers? in 1 units?') "exit $rc / $($o.Trim())"
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
