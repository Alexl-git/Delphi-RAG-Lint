<#
  run_flow_typeref_not_a_read.ps1 -- a TYPE ANNOTATION is not a variable read.

  THE DEFECT THIS PINS (shape E of INBOX-used-before-assignment-false-positives,
  undiagnosed there, bisected 2026-08-27):

      var ProxyOpt: DRagLint.LSP.Proxy.TLspProxyOptions;   <- DRagLint.CLI.pas:21160

  reported `Local "lsp" is used before it is assigned` at ERROR severity, on a
  line that assigns nothing and reads nothing. The same routine happens to
  declare a local `LSP` twenty lines further down, and the MIDDLE COMPONENT of
  the qualified type name was counted as a read of it.

  Mechanism, from tools\dumptree (not from the grammar comments -- this repo has
  been wrong about node names five separate times):

      var Opt: A.B.C.TThing
        -> varDef(kVar, identifier, type: (type (typeref (typerefDot ...))))

  typerefDot, NOT exprDot. CollectReadsAndCallDefs suppresses the rhs of an
  exprDot; a typerefDot fell through to the generic "walk every named child"
  arm, which treats each component as a bare identifier read.

  WHY THE FIX IS GAP-FREE, which matters more here than usual: this rule's
  author refused two wider suppressions IN WRITING because any gap in them would
  hide a true positive. There is no gap in this one -- nothing inside a Delphi
  type annotation can read a local. Array bounds and generic arguments are
  constant expressions, and an initialiser is a SIBLING of the type node, not a
  child of it.

  THE PAIRS (each shape gets one that must go silent and one that must fire):
    K1  MUST FIRE   -- a genuinely unassigned local of that name, no type in sight
    K2  MUST FIRE   -- the type annotation is present AND a real read precedes
                       the assignment; the real read must survive the fix
    K3  MUST BE SILENT after the fix -- only the type annotation names it
    K4  MUST FIRE   -- an unassigned local read from inside an initialiser on the
                       very same inline declaration, i.e. the sibling the fix
                       must not have swallowed along with the type

  RUN RED FIRST: against the pre-fix engine K3 fires (line 41) and so does the
  type-annotation line inside K2 (line 26), while K1, K2's real read and K4 all
  fire as they should. Measured exactly that way on 2026-08-27.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-typeref-not-a-read"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null

# The qualified type's MIDDLE component is deliberately the same identifier as
# the local. That collision is the whole defect; a fixture whose type name does
# not contain the local's name measures nothing, and the first draft of this
# fixture made exactly that mistake and read as green.
$src = @'
unit TypeRefProbe;

interface

implementation

uses A.LSP.C;

function K1: Integer;
var
  LSP: Integer;
begin
  Result := LSP + 1;
end;

function K2: Integer;
var
  LSP: Integer;
begin
  Result := 0;
  if Result = 0 then
  begin
    var Opt: A.LSP.C.TThing;
    Opt.X := 1;
  end;
  Result := LSP;
  LSP := 3;
end;

function K3: Integer;
var
  LSP: Integer;
begin
  Result := 0;
  if Result = 0 then
  begin
    var Opt: A.LSP.C.TThing;
    Opt.X := 1;
  end;
  LSP := 3;
  Result := LSP;
end;

function K4: Integer;
var
  LSP: Integer;
begin
  Result := 0;
  var Seed: Integer := LSP + 1;
  Result := Seed;
  LSP := 2;
end;

end.
'@
$file = Join-Path $WorkDir 'TypeRefProbe.pas'
WriteAnsi $file $src

$lines = $src -split "`r?`n"
function LineOf([string]$Pattern) {
  return [Array]::FindIndex($lines, [Predicate[string]]{ param($x) $x -like $Pattern }) + 1
}
$k1Read   = LineOf '*Result := LSP + 1;*'
$k2Type   = ([Array]::FindAll($lines, [Predicate[string]]{ param($x) $x -like '*var Opt: A.LSP.C.TThing;*' }) | Measure-Object).Count
$typeLines = @()
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -like '*var Opt: A.LSP.C.TThing;*') { $typeLines += ($i + 1) } }
$k2RealRead = LineOf '*Result := LSP;*'
$k4Read     = LineOf '*var Seed: Integer := LSP + 1;*'
Check 'located the probe lines' `
  (($k1Read -gt 0) -and ($typeLines.Count -eq 2) -and ($k2RealRead -gt 0) -and ($k4Read -gt 0)) `
  "k1=$k1Read types=$($typeLines -join ',') k2read=$k2RealRead k4=$k4Read"

$raw = & $Exe lint $file --json 2>$null
$all = @($raw | ConvertFrom-Json)
$uba = @($all | Where-Object { $_.rule -eq 'used-before-assignment' })
$hit = @($uba | ForEach-Object { $_.start_line })
Write-Host ("  fired on lines: {0}" -f ($hit -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'MUST FIRE -- genuine reads, unaffected by the fix' -ForegroundColor Cyan
Check "K1 unassigned read at line $k1Read"        ($hit -contains $k1Read)
Check "K2 real read at line $k2RealRead"          ($hit -contains $k2RealRead)
Check "K4 read inside an initialiser at line $k4Read" ($hit -contains $k4Read) `
  'the initialiser is a SIBLING of the type node; the fix must not swallow it'

Write-Host ''
Write-Host 'MUST BE SILENT -- the type annotation is not a read' -ForegroundColor Cyan
foreach ($tl in $typeLines) {
  Check "no finding on the type annotation at line $tl" (-not ($hit -contains $tl))
}

Write-Host ''
Write-Host 'VACUITY -- the rule is switched on at all' -ForegroundColor Cyan
Check 'the rule produced findings on this file' ($uba.Count -gt 0) "count=$($uba.Count)"
Check 'and exactly the three genuine ones' ($uba.Count -eq 3) "count=$($uba.Count) lines=$($hit -join ',')"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
