<#
  run_callee_graph_outputs.ps1 -- graph output of the callee direction must
  say what the code does, and callgraph must not ignore --format.

  Gitea drag-lint#14. `reverse-calltree --direction callees --format
  dot|mermaid` drew every arrow from the CALLEE to the root: the children of a
  callees tree sit in the same Callers field as a callers tree, and the chart
  renderer always emitted Kid -> Node. The graph claimed `Log` called
  `PublishReports`. butterfly's callees wing already turned it round.

  Gitea drag-lint#16. `callgraph --format dot|mermaid|json` was parsed and never
  read: exit 0 and the text tree, so a caller asking for a graph silently got
  something else. Now json is accepted (as --json), text is the default, and
  anything else exits 2 pointing at reverse-calltree.

  WHAT THIS ASSERTS
    1. callees dot: root -> callee, and never callee -> root          <- #14
    2. callees mermaid: same orientation                              <- #14
    3. CONTROL: callers dot keeps caller -> callee
    4. callgraph --format dot exits 2 and names reverse-calltree      <- #16
    5. callgraph --format json prints JSON                            <- #16
    6. CONTROL: callgraph default and --format text print the same tree
    7. CONTROL: find-callees lists both callees
    8-10. --help, README and AI-USAGE say find-callees is per call SITE and
       name `callgraph --depth 1` for the distinct list                 <- #9

  RED-CHECK: against the pre-fix build 1, 2, 4, 5 and 8 FAIL; 3, 6 and 7 pass
  on both builds; 9 and 10 fail against the pre-fix README/AI-USAGE.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe"
)
try {
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

function Write-Ascii([string]$path, [string]$text) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir -Force | Out-Null }
  [System.IO.File]::WriteAllText($path, ($text -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

$work = Join-Path C:\TEMP "draglint_calleegraph_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

function Run([string[]]$ArgList) {
  $out = Join-Path $work ('o-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $err = Join-Path $work ('e-{0}.log' -f [guid]::NewGuid().ToString('N').Substring(0,8))
  $quoted = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '
  cmd /c "`"$Exe`" $quoted > `"$out`" 2> `"$err`"" | Out-Null
  $code = $LASTEXITCODE
  $o = if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Raw } else { '' }
  $e = if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err -Raw } else { '' }
  if ($null -eq $o) { $o = '' }; if ($null -eq $e) { $e = '' }
  return @{ Out = $o; Err = $e; Code = $code }
}

$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Graph.dpr') @'
program Graph;

uses
  UG in 'UG.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'UG.pas') @'
unit UG;

interface

type
  TRoot = class
  public
    procedure Drive;
    procedure StepA;
    procedure StepB;
  end;

implementation

procedure TRoot.Drive;
begin
  StepA;
  StepB;
end;

procedure TRoot.StepA;
begin
end;

procedure TRoot.StepB;
begin
end;

end.
'@
$db = Join-Path $work 'g.sqlite'
$ix = Run @('index', '--project', (Join-Path $dir 'Graph.dpr'), '--db', $db)
Check 'seed: index' ($ix.Code -eq 0) "exit=$($ix.Code)"

Write-Host ''
Write-Host '=== #14: reverse-calltree --direction callees, dot / mermaid ===' -ForegroundColor Cyan
$dot = Run @('reverse-calltree', '--qname', 'UG.TRoot.Drive', '--direction', 'callees', '--format', 'dot', '--db', $db)
Write-Host $dot.Out -ForegroundColor DarkGray
Check '1. callees dot: "Drive" -> "StepA", never the reverse' `
  (($dot.Out -match '"UG\.TRoot\.Drive" -> "UG\.TRoot\.StepA"') -and -not ($dot.Out -match '"UG\.TRoot\.StepA" -> "UG\.TRoot\.Drive"')) ''
$mm = Run @('reverse-calltree', '--qname', 'UG.TRoot.Drive', '--direction', 'callees', '--format', 'mermaid', '--db', $db)
Write-Host $mm.Out -ForegroundColor DarkGray
Check '2. callees mermaid: Drive --> StepB, never the reverse' `
  (($mm.Out -match '(?m)^\s*\S*Drive\S*\s+-->\s+\S*StepB\S*\s*$') -and -not ($mm.Out -match '(?m)^\s*\S*StepB\S*\s+-->\s+\S*Drive\S*\s*$')) ''
$cdot = Run @('reverse-calltree', '--qname', 'UG.TRoot.StepA', '--direction', 'callers', '--format', 'dot', '--db', $db)
Check '3. CONTROL: callers dot keeps "Drive" -> "StepA"' ($cdot.Out -match '"UG\.TRoot\.Drive" -> "UG\.TRoot\.StepA"') ''

Write-Host ''
Write-Host '=== #16: callgraph --format ===' -ForegroundColor Cyan
$cg = Run @('callgraph', '--qname', 'UG.TRoot.Drive', '--direction', 'callees', '--format', 'dot', '--db', $db)
Check '4. callgraph --format dot exits 2 and names reverse-calltree' `
  (($cg.Code -eq 2) -and (($cg.Out + $cg.Err) -match 'reverse-calltree')) "exit=$($cg.Code) out=$($cg.Out.Trim()) err=$($cg.Err.Trim())"
$cj = Run @('callgraph', '--qname', 'UG.TRoot.Drive', '--direction', 'callees', '--format', 'json', '--db', $db)
$parsed = $null
try { $parsed = $cj.Out | ConvertFrom-Json } catch { }
Check '5. callgraph --format json prints JSON naming the root' `
  (($cj.Code -eq 0) -and ($null -ne $parsed) -and ($parsed.qname -eq 'UG.TRoot.Drive')) "exit=$($cj.Code)"
$cd = Run @('callgraph', '--qname', 'UG.TRoot.Drive', '--direction', 'callees', '--db', $db)
$ct = Run @('callgraph', '--qname', 'UG.TRoot.Drive', '--direction', 'callees', '--format', 'text', '--db', $db)
Check '6. CONTROL: default and --format text print the same tree' `
  (($cd.Code -eq 0) -and ($ct.Code -eq 0) -and ($cd.Out -eq $ct.Out) -and ($cd.Out -match 'StepA')) ''

Write-Host ''
Write-Host '=== #9: find-callees is per call SITE, and the docs say so ===' -ForegroundColor Cyan
# Gitea drag-lint#9: find-callees prints one line per call site, so a helper
# called 24 times was listed 24 times, and nothing in --help/README/AI-USAGE
# said so or named the verb that lists each callee once. The behaviour is kept
# (scripts count its JSON lines); what must not regress is the documentation.
$fc = Run @('find-callees', '--qname', 'UG.TRoot.Drive', '--db', $db)
Check '7. CONTROL: find-callees lists both callees' (($fc.Out -match 'StepA') -and ($fc.Out -match 'StepB')) ''
$root = Join-Path $PSScriptRoot '..\..'
$help = (& $Exe --help 2>$null) -join "`n"
$helpLine = @($help -split "`n" | Where-Object { $_ -match '^\s*drag-lint find-callees ' })
Check '8. --help: find-callees says per call site and names callgraph --depth 1' `
  (($helpLine.Count -eq 1) -and ($helpLine[0] -match 'call SITE') -and ($helpLine[0] -match 'callgraph .*--depth 1')) "line=$($helpLine -join ' | ')"
$readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
Check '9. README: find-callees row says per call site and names callgraph' `
  ($readme -match '(?m)^\| \[`find-callees`\].*call site.*callgraph --qname <X> --direction callees --depth 1') ''
$ai = Get-Content -LiteralPath (Join-Path $root 'docs\AI-USAGE.md') -Raw
Check '10. AI-USAGE: find-callees row says per call SITE and names callgraph' `
  ($ai -match '(?m)^\| `find-callees --qname U\.T\.M[^`]*` \|.*call SITE.*callgraph --qname U\.T\.M --direction callees --depth 1') ''

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_calleegraph_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
