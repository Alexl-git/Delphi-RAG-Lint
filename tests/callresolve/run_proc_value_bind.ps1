<#
  run_proc_value_bind.ps1 -- a routine named as a procedure VALUE binds its
  identity (refs.symbol_id) and writes NO call edge.

  WHAT WAS WRONG (resolver at main c2c4b750, stats\draglint-gaps.log 2026-10-25
  "refs: bare FOnTouch := Touch ... symbol_id of the class method / NULL
  (unbound)", backlog GAP-CALLERS). `FOnTouch := Touch` stores a `read` ref
  named Touch. The parenless stream declined it ('not-callable': Touch is a
  procedure, or 'proc-value' for a function) and wrote nothing, so the read
  stayed NULL and find-callers listed it as a [name-only] guess -- or, for a
  free procedure, it was not even offered (the universe was function/method).

  WHAT THIS GUARD PINS
    PV1  `FOnTouch := Touch`           (own class method)   -> uPv.TPvPort.Touch
    PV2  `with pPort do FOnTouch := Touch` (with target)    -> uPv.TPvPort.Touch
    PV3  `pPort.FOnTouch := Ping`      (enclosing class)    -> uPv.TPvUser.Ping
    PV4  `FProc := Helper`             (free procedure)     -> uPv.Helper
    PV5  `FFunc := Answer`             (function, proc-typed target) -> uPv.Answer
    NOEDGE none of the five reads has a call_edges row
    PC   positive controls: `N := Answer` (a parenless CALL) still has a call
         edge to uPv.Answer, and the bare statement `Ping;` still calls Ping

  Usage: pwsh -File tests\callresolve\run_proc_value_bind.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$scratch = Join-Path C:\TEMP "draglint_proc_value_bind_$PID"
try {

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

$exePath = (Resolve-Path $Exe).Path
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
$src = @(
  'unit uPv;',
  '',
  'interface',
  '',
  'type',
  '  TNoArg = procedure of object;',
  '  TPlainProc = procedure;',
  '  TIntFunc = function: Integer;',
  '',
  '  TPvPort = class',
  '  public',
  '    FOnTouch: TNoArg;',
  '    procedure Touch;',
  '    procedure Wire;',
  '  end;',
  '',
  '  TPvUser = class',
  '  private',
  '    FProc: TPlainProc;',
  '    FFunc: TIntFunc;',
  '  public',
  '    procedure Ping;',
  '    procedure Hook(pPort: TPvPort);',
  '  end;',
  '',
  'procedure Helper;',
  'function Answer: Integer;',
  '',
  'implementation',
  '',
  'procedure Helper;',
  'begin',
  'end;',
  '',
  'function Answer: Integer;',
  'begin',
  '  Result := 42;',
  'end;',
  '',
  'procedure TPvPort.Touch;',
  'begin',
  'end;',
  '',
  'procedure TPvPort.Wire;',
  'begin',
  '  FOnTouch := Touch; { PV1 }',
  'end;',
  '',
  'procedure TPvUser.Ping;',
  'begin',
  'end;',
  '',
  'procedure TPvUser.Hook(pPort: TPvPort);',
  'var',
  '  N: Integer;',
  'begin',
  '  with pPort do',
  '    FOnTouch := Touch; { PV2 }',
  '  pPort.FOnTouch := Ping; { PV3 }',
  '  FProc := Helper; { PV4 }',
  '  FFunc := Answer; { PV5 }',
  '  N := Answer; { PC1 }',
  '  if N > 0 then',
  '    Ping; { PC2 }',
  'end;',
  '',
  'end.')
[System.IO.File]::WriteAllText((Join-Path $scratch 'uPv.pas'), (($src -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
$db = Join-Path $scratch 'pv.sqlite'

function Sql([string]$Query) {
  $raw = (& $exePath sql --db $db --json --limit 1000 --query $Query 2>$null) -join "`n"
  $b = $raw.IndexOf('{')
  if ($b -lt 0) { throw "sql returned no JSON for: $Query" }
  $o = $raw.Substring($b) | ConvertFrom-Json
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($o.rows)) {
    $h = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { $h[$names[$i]] = $r[$i] }
    $out += $h
  }
  return ,@($out)
}
function LineOf([string]$Tag) {
  for ($i = 0; $i -lt $src.Count; $i++) { if ($src[$i].Contains("{ $Tag }")) { return $i + 1 } }
  throw "fixture tag not found: $Tag"
}
# The (qualified name, call-edge count) of the ref NAME on the line tagged TAG.
function RefAt([string]$Tag, [string]$Name, [string]$Kind) {
  $ln = LineOf $Tag
  $r = Sql ("SELECT COALESCE(s.qualified_name, '') AS q, (SELECT COUNT(*) FROM call_edges ce WHERE ce.ref_id = r.id) AS e " +
            "FROM refs r LEFT JOIN symbols s ON s.id = r.symbol_id " +
            "WHERE r.kind = '$Kind' AND r.name_text = '$Name' AND r.start_line = $ln")
  if ($r.Count -ne 1) { return @{ q = "<$($r.Count) $Kind refs>"; e = -1 } }
  return $r[0]
}

$null = & $exePath index $scratch --db $db 2>&1 | Out-String
Check 'index exits 0' ($LASTEXITCODE -eq 0)

$cases = @(
  @('PV1', 'Touch',  'uPv.TPvPort.Touch'),
  @('PV2', 'Touch',  'uPv.TPvPort.Touch'),
  @('PV3', 'Ping',   'uPv.TPvUser.Ping'),
  @('PV4', 'Helper', 'uPv.Helper'),
  @('PV5', 'Answer', 'uPv.Answer'))
foreach ($c in $cases) {
  $r = RefAt $c[0] $c[1] 'read'
  Check "$($c[0]) the value read $($c[1]) binds $($c[2])" ($r.q -eq $c[2]) "bound to '$($r.q)'"
  Check "$($c[0]) NOEDGE the value read $($c[1]) has no call edge" ($r.e -eq 0) "$($r.e) edge(s)"
}
$pc1 = RefAt 'PC1' 'Answer' 'read'
Check 'PC1 POSITIVE CONTROL `N := Answer` is still a parenless CALL (bound, 1 call edge)' `
      (($pc1.q -eq 'uPv.Answer') -and ($pc1.e -eq 1)) "bound to '$($pc1.q)', $($pc1.e) edge(s)"
$pc2 = RefAt 'PC2' 'Ping' 'call'
Check 'PC2 POSITIVE CONTROL the statement `Ping;` still calls TPvUser.Ping' `
      (($pc2.q -eq 'uPv.TPvUser.Ping') -and ($pc2.e -eq 1)) "bound to '$($pc2.q)', $($pc2.e) edge(s)"

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}