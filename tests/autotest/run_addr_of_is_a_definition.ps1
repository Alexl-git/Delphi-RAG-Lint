<#
  run_addr_of_is_a_definition.ps1 -- `@X` passed to a call is a possible WRITE of
  X, not a read of it.

  THE DEFECT THIS PINS:
    `@Buf[0]` parses as exprUnary(kAt, exprSubscript) -- verified with
    tools\dumpnode -- and in tree-sitter-delphi13 the OPERATOR is a NAMED child.
    LeftmostBaseVar descended via NamedChild(0), which was therefore `kAt`, a node
    with no identifier beneath it, so it returned -1 and the address-of produced
    no possible-def. CollectReadsAndCallDefs then fell through to its ordinary
    read walk and recorded the buffer as a READ.

    That inverts the meaning of the line. In YADFOT.Wizard.pas:

      Got := Reader.GetText(Pos, @Chunk[0], ChunkSize);   { 243 -- FILLS Chunk }
      ...
        Move(Chunk[0], Utf8Bytes[CurLen], Got);           { 247 }

    both lines were reported as "Local chunk may be used before it is assigned",
    and 243 is the very call that fills it -- so `dl:ok` there would have recorded
    something untrue, the same trap as the dangling-else defect.

    LeftmostBaseVar's own doc-comment already said `@x` was treated as a possible
    def. The intent was right; only the descent was wrong. Third instance in this
    tree of "keywords are named nodes" (the `case` arm in Analysis.Cfg names it,
    and the dangling-else exprIf fix hit it again), which is why the fix skips
    keyword nodes generically rather than special-casing kAt.

  WHAT THE PROBE ALSO SETTLED, recorded so it is not re-litigated:
    Element-wise assignment is tracked CORRECTLY -- in a loop and straight-line,
    static array and dynamic. An earlier note claimed "an array local is never
    counted as defined"; cases A1/A2/A4 below refute it, and they are kept here as
    regression coverage for the thing that was never broken.

  Assertions: only A3 changes. A1, A2 and A4 must stay silent (they always were),
  and A5 -- never assigned at all -- must still fire, or the four silences prove
  nothing.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-addr-of-def"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$FixtureBody = @'
unit uAddrOf;
interface
procedure A1;
procedure A2;
procedure A3;
procedure A4;
procedure A5;
implementation
uses Winapi.Windows, System.SysUtils;

{ Element-wise assignment in one loop, read in a later one. Never broken. }
procedure A1;
var
  Arr: array[0..2] of Integer;
  I, S: Integer;
begin
  for I := 0 to 2 do
    Arr[I] := I;
  S := 0;
  for I := 0 to 2 do
    S := S + Arr[I];
  Writeln(S);
end;

{ Straight-line element assignment. Never broken. }
procedure A2;
var
  Arr: array[0..1] of Integer;
begin
  Arr[0] := 1;
  Arr[1] := 2;
  Writeln(Arr[0] + Arr[1]);
end;

{ THE DEFECT: address-of the first element, handed to a filling API. }
procedure A3;
var
  Buf: array[0..15] of AnsiChar;
  N: Integer;
begin
  N := GetModuleFileNameA(0, @Buf[0], Length(Buf));
  Writeln(N);
  Writeln(Buf[0]);
end;

{ Dynamic array via SetLength then element-wise. Never broken. }
procedure A4;
var
  Dyn: TArray<Integer>;
  I: Integer;
begin
  SetLength(Dyn, 3);
  for I := 0 to 2 do
    Dyn[I] := I;
  Writeln(Dyn[0]);
end;

{ GENUINELY unsafe -- never assigned at all. The positive control. }
procedure A5;
var
  Arr: array[0..2] of Integer;
begin
  Writeln(Arr[0]);
end;

end.
'@
$file = Join-Path $WorkDir 'uAddrOf.pas'
$norm = ($FixtureBody -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($file, $norm, [System.Text.Encoding]::ASCII)

# Anchors derived from the fixture. Take the LAST match of each header: every
# routine is named twice (interface + implementation), and -First would put every
# anchor in the interface section, attributing every finding to the last routine.
$src = Get-Content $file
function Impl-Row([string]$Name) {
  ($src | Select-String -Pattern ("procedure {0};" -f $Name) -SimpleMatch | Select-Object -Last 1).LineNumber
}
$rows = [ordered]@{}
foreach ($n in @('A1','A2','A3','A4','A5')) { $rows[$n] = Impl-Row $n }
if (@($rows.Values | Sort-Object -Unique).Count -ne 5) {
  Write-Host "FATAL: anchors collapsed: $($rows.Values -join ',')" -ForegroundColor Red; exit 2
}
Write-Host ("  anchors: " + (($rows.Keys | ForEach-Object { "$_=$($rows[$_])" }) -join ' ')) -ForegroundColor DarkGray

$out = & $Exe lint $file 2>&1 | Out-String
$hits = @([regex]::Matches($out, 'uAddrOf\.pas:(\d+):\d+\s+\[\w+\]\s+used-before-assignment') |
          ForEach-Object { [int]$_.Groups[1].Value })
function Proc-Of([int]$Row) {
  $best = '(none)'
  foreach ($n in $rows.Keys) { if ($Row -ge $rows[$n]) { $best = $n } }
  $best
}
function Rows-In([string]$P) { ($hits | Where-Object { (Proc-Of $_) -eq $P }) -join ',' }
Write-Host ("  findings at rows: " + ($hits -join ',')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Address-of is a possible write, not a read' -ForegroundColor Cyan
Check 'A3: @Buf[0] handed to a filling API is NOT used-before-assignment' ((Rows-In 'A3') -eq '') "rows=$(Rows-In 'A3')"

Write-Host ''
Write-Host 'Element-wise assignment was never broken -- keep it that way' -ForegroundColor Cyan
Check 'A1: assigned in a for, read in a later for' ((Rows-In 'A1') -eq '') "rows=$(Rows-In 'A1')"
Check 'A2: straight-line element assignment'        ((Rows-In 'A2') -eq '') "rows=$(Rows-In 'A2')"
Check 'A4: SetLength + element-wise on a dynamic array' ((Rows-In 'A4') -eq '') "rows=$(Rows-In 'A4')"

Write-Host ''
Write-Host 'CONTROL: a genuinely unassigned array still fires' -ForegroundColor Cyan
Check 'A5: never assigned at all IS reported' ((Rows-In 'A5') -ne '') "rows=$(Rows-In 'A5')"
if ((Rows-In 'A5') -eq '') {
  Write-Host '  !! The control failed, so every silence above proves nothing --' -ForegroundColor Yellow
  Write-Host '  !! they would all pass with the rule disabled.' -ForegroundColor Yellow
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
