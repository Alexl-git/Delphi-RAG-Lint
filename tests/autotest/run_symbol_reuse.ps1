<#
  run_symbol_reuse.ps1 -- a re-parsed file keeps the ids of the declarations
  that come back, so the edges other files hold into it survive, and the scoped
  call pass still equals a whole-database pass (P2, 2026-10-14).

  WHY THIS EXISTS. A re-parse used to delete every symbol of the file and insert
  it again: new ids, every edge from another file into it gone by cascade, and
  the scoped pass widened through every name the file declared. For an edit
  inside one routine body that re-resolved refs in hundreds of files. Now
  OpenFileTx keeps the rows, UpsertSymbol claims them by natural key, and only a
  declaration that is new, gone or visibly changed widens the scope
  (SYMBOL REUSE above OpenFileTx; point 7 of ScopedResolveIsSound).

  The fixture:

      uBase1/uBase2  TBase1.Shared / TBase2.Shared        (heritage targets)
      uLib.pas       TLib = class(TBase1): Ping, Pong; Helper   (re-indexed)
      uUse1..3.pas   call Lib.Ping, Lib.Pong, Lib.Shared, Helper

  Each case edits uLib.pas and runs the SAME edit twice -- the shipping scoped
  path, and DRAGLINT_NO_SCOPED_RESOLVE=1 -- and the call edges must match.

    A  body edit         ids of uLib's symbols unchanged (RED on the exe before
                         the change, which re-inserted them); the consumer call
                         sites are NOT re-resolved (affected count is uLib's own)
    B  rename Pong       the consumers' Pong calls are re-resolved (unbound now)
    C  heritage change   TLib = class(TBase2): the pass DECLINES to the whole DB
                         naming TLib, and Lib.Shared now binds to TBase2.Shared
    D  new overload      Ping(X) added beside Ping

  Fixture size is load-bearing: the scoped pass declines at a third of the
  corpus, so one changed file needs at least 4 files in the index (6 here).

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$d){ Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int]$ok]),$n) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){ if($d){Write-Host "      $d" -ForegroundColor DarkGray}; $script:fail=$true } }

$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP "draglint_symbol_reuse_$PID"
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path $scratch | Out-Null

function Write-Ascii($p,$t) {
  [System.IO.File]::WriteAllText($p, (($t -replace "`r`n","`n") -replace "`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false)))
}

$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src | Out-Null

foreach ($b in 1..2) {
Write-Ascii (Join-Path $src "uBase$b.pas") @"
unit uBase$b;

interface

type
  TBase$b = class
  public
    procedure Shared;
  end;

implementation

procedure TBase$b.Shared;
begin
end;

end.
"@
}

function Write-Lib([string]$Base = 'TBase1', [string]$PongName = 'Pong', [string]$Body = '  Inc(N);', [switch]$Overload) {
  $ovDecl = ''; $ovImpl = ''; $ovMark = ''
  if ($Overload) {
    $ovMark = ' overload;'
    $ovDecl = "    procedure Ping(X: Integer); overload;`r`n"
    $ovImpl = "procedure TLib.Ping(X: Integer);`r`nbegin`r`nend;`r`n`r`n"
  }
  Write-Ascii (Join-Path $src 'uLib.pas') @"
unit uLib;

interface

uses
  uBase1, uBase2;

type
  TLib = class($Base)
  public
    procedure Ping;$ovMark
$ovDecl    procedure $PongName;
  end;

procedure Helper;

implementation

procedure TLib.Ping;
var
  N: Integer;
begin
  N := 0;
$Body
end;

$($ovImpl)procedure TLib.$PongName;
begin
end;

procedure Helper;
begin
end;

end.
"@
}
Write-Lib

foreach ($n in 1..3) {
Write-Ascii (Join-Path $src "uUse$n.pas") @"
unit uUse$n;

interface

uses
  uLib;

procedure Run$n;

implementation

procedure Run$n;
var
  Lib: TLib;
begin
  Lib := TLib.Create;
  Lib.Ping;
  Lib.Pong;
  Lib.Shared;
  Helper;
end;

end.
"@
}

$py = @'
import sqlite3, sys, os
c = sqlite3.connect(sys.argv[2])
if sys.argv[1] == 'edges':
    for x in c.execute("""
        SELECT f.path, r.start_line, r.start_col, r.name_text,
               COALESCE(s.qualified_name,'?'), COALESCE(e.confidence,'')
        FROM call_edges e
        JOIN refs r ON r.id = e.ref_id
        JOIN files f ON f.id = r.file_id
        LEFT JOIN symbols s ON s.id = e.target_symbol_id
        ORDER BY f.path, r.start_line, r.start_col, r.name_text""").fetchall():
        row = list(x); row[0] = os.path.basename(row[0])
        print('EDGE|' + '|'.join(str(i) for i in row))
elif sys.argv[1] == 'ids':
    for x in c.execute("""SELECT s.kind, s.qualified_name, s.signature, s.id FROM symbols s
                          JOIN files f ON f.id = s.file_id WHERE f.path LIKE '%uLib.pas'
                          AND s.kind NOT IN ('param','local_var')
                          ORDER BY s.kind, s.qualified_name, s.signature""").fetchall():
        print('ID|' + '|'.join(str(i) for i in x))
'@
$pyf = Join-Path $scratch 'dump.py'
Write-Ascii $pyf $py

function RunIndex([string]$Db, [string]$NoScoped) {
  Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE -ErrorAction SilentlyContinue
  if ($NoScoped) { $env:DRAGLINT_NO_SCOPED_RESOLVE = $NoScoped }
  try   { return (& $exePath index $src --db $Db 2>&1 | Out-String) }
  finally { Remove-Item Env:\DRAGLINT_NO_SCOPED_RESOLVE -ErrorAction SilentlyContinue }
}
function Affected([string]$Out) {
  if ($Out -match 'from (\d+) affected call-site ref\(s\)') { return [int]$Matches[1] }
  return -1
}
function Dump([string]$What, [string]$Db) { return (& python $pyf $What $Db 2>&1 | Out-String) }

# One case: copy the current base DB twice, apply the edit, index scoped and
# whole, compare the edges. The scoped DB becomes the next case's base.
$script:base = Join-Path $scratch 'base0.sqlite'
function RunCase([string]$Tag, [scriptblock]$Edit) {
  $s = Join-Path $scratch "$Tag.scoped.sqlite"; $w = Join-Path $scratch "$Tag.whole.sqlite"
  Copy-Item $script:base $s -Force; Copy-Item $script:base $w -Force
  & $Edit
  $outS = RunIndex $s ''
  $outW = RunIndex $w '1'
  $eS = Dump 'edges' $s; $eW = Dump 'edges' $w
  Check "$($Tag): scoped edges equal the whole-DB edges" ($eS -ceq $eW) "scoped=$($eS.Length) whole=$($eW.Length)"
  if ($eS -cne $eW) {
    $a = ($eS -split "`r?`n" | Where-Object { $_ }); $b = ($eW -split "`r?`n" | Where-Object { $_ })
    $b | Where-Object { $a -notcontains $_ } | Select-Object -First 6 | ForEach-Object { Write-Host "        whole only: $_" -ForegroundColor DarkGray }
    $a | Where-Object { $b -notcontains $_ } | Select-Object -First 6 | ForEach-Object { Write-Host "        scoped only: $_" -ForegroundColor DarkGray }
  }
  $script:base = $s
  return [pscustomobject]@{ Out = $outS; Edges = $eS; Db = $s }
}

Push-Location C:\TEMP
try {
  & $exePath index $src --db $script:base 2>&1 | Out-Null
  $idsBefore = Dump 'ids' $script:base
  $e0 = Dump 'edges' $script:base
  Check 'CONTROL: the consumers bind Lib.Ping, Lib.Pong, Lib.Shared and Helper' `
        (($e0 -match 'uUse1\.pas\|\d+\|\d+\|Ping\|uLib\.TLib\.Ping') -and ($e0 -match 'uUse1\.pas\|\d+\|\d+\|Pong\|uLib\.TLib\.Pong') -and
         ($e0 -match 'uUse1\.pas\|\d+\|\d+\|Shared\|uBase1\.TBase1\.Shared') -and ($e0 -match 'uUse1\.pas\|\d+\|\d+\|Helper\|uLib\.Helper')) `
        (($e0 -split "`r?`n" | Select-Object -First 12) -join "`n")

  # A. body edit
  $A = RunCase 'A' { Write-Lib -Body "  Inc(N);`r`n  Inc(N, 2);" }
  $idsAfter = Dump 'ids' $A.Db
  Check 'A: a body edit keeps every declaration''s id' ($idsBefore -ceq $idsAfter) `
        "before:`n$idsBefore`nafter:`n$idsAfter"
  $nA = Affected $A.Out
  Check 'A: the run is scoped and leaves the 12 consumer call sites alone' (($nA -ge 0) -and ($nA -lt 12)) "affected=$nA"

  # B. rename a method
  $B = RunCase 'B' { Write-Lib -Body "  Inc(N);`r`n  Inc(N, 2);" -PongName 'Pang' }
  $nB = Affected $B.Out
  Check 'B: renaming Pong re-resolves its 3 consumer calls' ($nB -ge 3) "affected=$nB"
  Check 'B: the consumers'' Pong calls are no longer bound to uLib' (-not ($B.Edges -match '\|Pong\|uLib\.TLib\.Pong')) $B.Edges

  # C. heritage change under the same type name
  $C = RunCase 'C' { Write-Lib -Body "  Inc(N);`r`n  Inc(N, 2);" -PongName 'Pang' -Base 'TBase2' }
  Check 'C: a heritage change declines to the whole database, naming the type' `
        (($C.Out -match 'WHOLE DB') -and ($C.Out -match 'heritage of TLib changed')) ($C.Out -split "`r?`n" | Select-String 'calls' | Out-String)
  Check 'C: Lib.Shared now binds to TBase2.Shared' ($C.Edges -match 'uUse1\.pas\|\d+\|\d+\|Shared\|uBase2\.TBase2\.Shared') $C.Edges

  # D. a new overload beside an existing routine
  $D = RunCase 'D' { Write-Lib -Body "  Inc(N);`r`n  Inc(N, 2);" -PongName 'Pang' -Base 'TBase2' -Overload }
  Check 'D: the consumers still bind Lib.Ping after an overload is added' ($D.Edges -match 'uUse1\.pas\|\d+\|\d+\|Ping\|uLib\.TLib\.Ping') $D.Edges
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @((Join-Path C:\TEMP "draglint_symbol_reuse_$PID"))) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
