<#
  run_tree_sites_and_confidence.ps1 -- call trees must show the call site in
  the callee direction (Gitea drag-lint#11) and must not present a guessed edge
  as a resolved one (Gitea drag-lint#13).

  #11. `reverse-calltree --direction callees` printed `"site": ""` for every
  node and the JSON gave no way to tell the direction (the children sit under
  "callers" either way), so a "call tree with call sites" had none downward.
  The site is now the parent's file and the line of its FIRST call to the
  child; `file`/`line` keep pointing at the child's declaration (the IDE
  plugin navigates there); the envelope carries "direction".

  #13. callgraph, reverse-calltree, butterfly and impact dropped the edge
  confidence. An `ambiguous` edge -- which can point at the wrong unit -- was
  drawn exactly like a certain one in trees documented as "resolved". Now the
  guessed edge is marked `[ambiguous]` (text), "confidence" (JSON), dashed
  (dot `style=dashed`, mermaid `-.->`), and impact says how many callers are
  reached only through guesses. Certain edges print exactly as before.

  The fixture makes the resolver guess: two units declare the same free
  function as `overload` and the caller uses both without qualifying it.
  (Without `overload` the uses order now decides -- Gitea drag-lint#21,
  resolver 1.20.0 -- and the edge is certain; an overload set across units is
  the case that rung still leaves ambiguous.)

  WHAT THIS ASSERTS
    0. CONTROL (fixture): find-callees reports the guessed edge [ambiguous]
    1. reverse-calltree callees json: direction=callees; Helper's site is the
       FIRST of its two call lines; confidence certain / ambiguous      <- #11 #13
    2. reverse-calltree callees text: [UMain.pas:N] site, [ambiguous] on Pick only
    3. dot: only the Pick edge is dashed; mermaid: only Pick uses -.->   <- #13
    4. callgraph text and json mark Pick, not Helper                    <- #13
    5. callgraph --direction callers from Pick marks Run [ambiguous]    <- #13
    6. impact on Pick: "of which 1 reached only through ambiguous edges",
       json ambiguous_only                                              <- #13
    7. butterfly dot: the Pick edge is dashed                           <- #13
    8. CONTROL: impact on Helper has no ambiguous line; a certain-only
       callgraph has no marker

  RED-CHECK: against the pre-fix build 1-7 FAIL; 0 and 8 pass on both.
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
function Out([string[]]$ArgList) { return ((& $Exe @ArgList 2>$null) -join "`n") }

$work = Join-Path C:\TEMP "draglint_treeconf_$PID"
if (Test-Path $work) { Get-ChildItem $work -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory $work -Force | Out-Null

$dir = Join-Path $work 'p'
Write-Ascii (Join-Path $dir 'Tree.dpr') @'
program Tree;

uses
  UA in 'UA.pas',
  UB in 'UB.pas',
  UMain in 'UMain.pas';

begin
end.
'@
Write-Ascii (Join-Path $dir 'UA.pas') @'
unit UA;

interface

function Pick(X: Integer): Integer; overload;

implementation

function Pick(X: Integer): Integer;
begin
  Result := X;
end;

end.
'@
Write-Ascii (Join-Path $dir 'UB.pas') @'
unit UB;

interface

function Pick(X: Integer): Integer; overload;

implementation

function Pick(X: Integer): Integer;
begin
  Result := X + 1;
end;

end.
'@
# Helper is called on lines 22 and 23; Pick (guessed) on line 24.
Write-Ascii (Join-Path $dir 'UMain.pas') @'
unit UMain;

interface

type
  TMain = class
  public
    procedure Helper;
    procedure Run;
  end;

implementation

uses UA, UB;

procedure TMain.Helper;
begin
end;

procedure TMain.Run;
begin
  Helper;
  Helper;
  Pick(1);
end;

end.
'@
$db = Join-Path $work 't.sqlite'
& $Exe index --project (Join-Path $dir 'Tree.dpr') --db $db *> $null
Check 'seed: index' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

$fc = Out @('find-callees', '--qname', 'UMain.TMain.Run', '--db', $db)
Write-Host $fc -ForegroundColor DarkGray
$pickQ = ''
if ($fc -match '(?m)^\s+(U[AB]\.Pick)\s+\[ambiguous\]') { $pickQ = $Matches[1] }
Check '0. CONTROL (fixture): the Pick edge is ambiguous' ($pickQ -ne '') "pick=$pickQ"
$pickRx = [regex]::Escape($pickQ)

Write-Host ''
Write-Host '=== reverse-calltree --direction callees ===' -ForegroundColor Cyan
$js = Out @('reverse-calltree', '--qname', 'UMain.TMain.Run', '--direction', 'callees', '--depth', '1', '--format', 'json', '--db', $db)
$tree = $null; try { $tree = $js | ConvertFrom-Json } catch { }
$kids = @(); if ($tree) { $kids = @($tree.root.callers) }
$helper = @($kids | Where-Object { $_.qname -eq 'UMain.TMain.Helper' })
$pick = @($kids | Where-Object { $_.qname -eq $pickQ })
Check '1. json: direction=callees, Helper site=UMain.pas:22 certain, Pick ambiguous' `
  (($null -ne $tree) -and ($tree.direction -eq 'callees') -and ($helper.Count -eq 1) -and ($helper[0].site -eq 'UMain.pas:22') `
   -and ($helper[0].confidence -eq 'certain') -and ($pick.Count -eq 1) -and ($pick[0].confidence -eq 'ambiguous') `
   -and ($helper[0].line -ge 1)) "json=$js"
$tx = Out @('reverse-calltree', '--qname', 'UMain.TMain.Run', '--direction', 'callees', '--depth', '1', '--db', $db)
Write-Host $tx -ForegroundColor DarkGray
Check '2. text: Helper [UMain.pas:22] unmarked, Pick [ambiguous]' `
  (($tx -match '(?m)^\s+UMain\.TMain\.Helper \[UMain\.pas:22\]\s*$') -and ($tx -match "(?m)^\s+$pickRx \[UMain\.pas:24\] \[ambiguous\]")) ''
$dot = Out @('reverse-calltree', '--qname', 'UMain.TMain.Run', '--direction', 'callees', '--depth', '1', '--format', 'dot', '--db', $db)
$mm = Out @('reverse-calltree', '--qname', 'UMain.TMain.Run', '--direction', 'callees', '--depth', '1', '--format', 'mermaid', '--db', $db)
Check '3. dot dashes only Pick; mermaid -.-> only for Pick' `
  (($dot -match "`"UMain\.TMain\.Run`" -> `"$pickRx`" \[style=dashed\];") -and ($dot -match '"UMain\.TMain\.Run" -> "UMain\.TMain\.Helper";') `
   -and ($mm -match '(?m)^\s*\S*Run\s+-\.->\s+\S*Pick\s*$') -and ($mm -match '(?m)^\s*\S*Run\s+-->\s+\S*Helper\s*$')) "dot=$dot mm=$mm"

Write-Host ''
Write-Host '=== callgraph ===' -ForegroundColor Cyan
$cg = Out @('callgraph', '--qname', 'UMain.TMain.Run', '--direction', 'callees', '--depth', '1', '--db', $db)
$cj = Out @('callgraph', '--qname', 'UMain.TMain.Run', '--direction', 'callees', '--depth', '1', '--json', '--db', $db)
$cjo = $null; try { $cjo = $cj | ConvertFrom-Json } catch { }
$cjPick = @(); $cjHelper = @()
if ($cjo) { $cjPick = @($cjo.children | Where-Object { $_.qname -eq $pickQ }); $cjHelper = @($cjo.children | Where-Object { $_.qname -eq 'UMain.TMain.Helper' }) }
Check '4. callgraph marks Pick [ambiguous] (text) and confidence (json), not Helper' `
  (($cg -match "(?m)^\s+$pickRx \[ambiguous\]\s*$") -and ($cg -match '(?m)^\s+UMain\.TMain\.Helper\s*$') `
   -and ($cjPick.Count -eq 1) -and ($cjPick[0].confidence -eq 'ambiguous') -and ($cjHelper[0].confidence -eq 'certain')) "text=$cg"
$cc = Out @('callgraph', '--qname', $pickQ, '--direction', 'callers', '--depth', '1', '--db', $db)
Check '5. callers of Pick: Run is [ambiguous]' ($cc -match '(?m)^\s+UMain\.TMain\.Run \[ambiguous\]\s*$') "text=$cc"

Write-Host ''
Write-Host '=== impact ===' -ForegroundColor Cyan
$im = Out @('impact', '--qname', $pickQ, '--depth', '2', '--db', $db)
$ij = Out @('impact', '--qname', $pickQ, '--depth', '2', '--format', 'json', '--db', $db)
Write-Host $im -ForegroundColor DarkGray
Check '6. impact on Pick says 1 reached only through ambiguous edges; json ambiguous_only' `
  (($im -match 'of which 1 reached only through ambiguous edges') -and ($ij -match '"ambiguous_only":\s*1')) "json=$ij"

Write-Host ''
Write-Host '=== butterfly ===' -ForegroundColor Cyan
$bf = Out @('butterfly', '--qname', 'UMain.TMain.Run', '--depth', '1', '--format', 'dot', '--db', $db)
Check '7. butterfly dot dashes the Pick edge only' `
  (($bf -match "`"UMain\.TMain\.Run`" -> `"$pickRx`" \[style=dashed\];") -and ($bf -match '"UMain\.TMain\.Run" -> "UMain\.TMain\.Helper";')) "dot=$bf"

Write-Host ''
Write-Host '=== CONTROLS ===' -ForegroundColor Cyan
$ih = Out @('impact', '--qname', 'UMain.TMain.Helper', '--depth', '2', '--db', $db)
$ch = Out @('callgraph', '--qname', 'UMain.TMain.Helper', '--direction', 'callers', '--depth', '1', '--db', $db)
Check '8. CONTROL: certain-only impact and callgraph carry no ambiguous marker' `
  (-not ($ih -match 'ambiguous') -and ($ih -match 'Total: 1 callers') -and -not ($ch -match 'ambiguous') -and ($ch -match 'UMain\.TMain\.Run')) "impact=$ih callgraph=$ch"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_treeconf_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
