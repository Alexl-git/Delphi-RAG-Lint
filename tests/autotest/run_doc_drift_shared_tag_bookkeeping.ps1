<#
  run_doc_drift_shared_tag_bookkeeping.ps1 -- a `dl:shared A, B` unit's managed
  facts block, written from project A's DB, must NOT read as doc-drift under
  project B when the only difference is the project-tag bookkeeping.

  YADF FALSE POSITIVE #1 (docs\INBOX-yadf-false-positives-2026-11-03.md).
  ReconcileContent appends the run's own project tag to every fresh entry, so a
  stored `[A]Go` was compared against a reconciled `[A,B]Go` and read as drift;
  ReconciledDrift now compares both sides with the run's own tag stripped.

  FIXTURE: shared\thing.pas (`dl:shared SecA, SecB`, DoIt + Other);
  common\user.pas (both sections) calls DoIt; bside\only.pas (section B only)
  calls DoIt too (so the block reaches the tagged regime).

  0/1 sanity  both DBs exist; document --apply --db dbA wrote a block naming Go
  2   THE FIX  lint thing.pas --db dbB --project-rules --rule doc-drift: no
              drift for DoIt                   (RED on main effb5c97)
  CONTROLS (the rule must still fire on real differences)
  3   Other (fresh-only B caller) reports under B
  4   a hand-edited `[SecB]ghost.Go` is reported under B, silent under A
  5   after `document --apply --db dbB` both sections are silent

  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_shared_tagbk_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
foreach ($d in 'shared','common','bside') { New-Item -ItemType Directory -Path (Join-Path $scratch $d) | Out-Null }
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $scratch 'shared\thing.pas') @'
unit thing; // dl:shared SecA, SecB

interface

type
  TThing = class
  public
    procedure DoIt;
    procedure Other;
  end;

implementation

procedure TThing.DoIt;
begin
end;

procedure TThing.Other;
begin
end;

end.
'@
WriteAscii (Join-Path $scratch 'common\user.pas') @'
unit user;

interface

procedure Go;

implementation

uses
  thing;

procedure Go;
var
  T: TThing;
begin
  T := TThing.Create;
  T.DoIt;
  T.Free;
end;

end.
'@
WriteAscii (Join-Path $scratch 'bside\only.pas') @'
unit only;

interface

procedure Go2;

implementation

uses
  thing;

procedure Go2;
var
  T: TThing;
begin
  T := TThing.Create;
  T.DoIt;
  T.Free;
end;

end.
'@
$cfg = Join-Path $scratch 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "SecA", "db": "a.sqlite", "include": ["shared", "common"] },
      { "name": "SecB", "db": "b.sqlite", "include": ["shared", "common", "bside"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii
$dbA = Join-Path $scratch 'out\a.sqlite'; $dbB = Join-Path $scratch 'out\b.sqlite'
$thing = Join-Path $scratch 'shared\thing.pas'

function Reindex {
  & $exePath index --all --config $cfg --only SecA --jobs 1 2>&1 | Out-Null
  & $exePath index --all --config $cfg --only SecB --jobs 1 2>&1 | Out-Null
}
function Drift([string]$Db) {
  (& $exePath lint $thing --db $Db --project-rules --rule doc-drift 2>&1 | Out-String)
}
# The message does not name the symbol; thing.pas holds exactly one documented symbol (DoIt).
function Reports([string]$Out, [string]$Sym) { $Out -match '(?m)thing\.pas:\d+:\d+\s+\[\w+\]\s+doc-drift\b' }

Push-Location C:\TEMP
try {
  Reindex
  Check '0. sanity: both DBs exist' ((Test-Path $dbA) -and (Test-Path $dbB))
  & $exePath document --qname thing.TThing.DoIt --db $dbA --apply 2>&1 | Out-Null
  & $exePath document --qname thing.TThing.DoIt --db $dbB --apply 2>&1 | Out-Null
  Reindex
  $blk = (Get-Content $thing -Raw)
  Check '1. sanity: the block is in the TAGGED regime (carries a [b] entry)' ($blk -match '(?i)\[b\]')

  # THE FIX. user.Go is visible to both projects. The block was last written from
  # B, so it stores [b]user.Go; under A the reconciled entry is [a,b]user.Go.
  # Own-tag bookkeeping alone is not drift.
  $dA = Drift $dbA
  Write-Host (($dA -split "`n" | Select-Object -First 4) -join "`n") -ForegroundColor DarkGray
  Check '2. FIX: DoIt block written from B is silent under A' (-not (Reports $dA 'DoIt'))
  Check '2b. DoIt block written from B is silent under B' (-not (Reports (Drift $dbB) 'DoIt'))

  # CONTROL 3: a stored entry for a project that IS this run (own tag) with no
  # fresh counterpart is a ghost -> drift under B; foreign to A -> silent there.
  WriteAscii $thing ($blk -replace '(?i)Called from: ', 'Called from: [b]ghost.Go, ')
  Reindex
  Check '3a. CONTROL: ghost [b] entry is reported under B' (Reports (Drift $dbB) 'DoIt')
  Check '3b. ghost [b] entry is silent under A (foreign tag)' (-not (Reports (Drift $dbA) 'DoIt'))

  # CONTROL 4: the real caller missing from the block -> fresh-only entry -> drift.
  WriteAscii $thing ($blk -replace '(?m)^\s*///\s*<para>Called from:[^\r\n]*\r?\n', '')
  Reindex
  Check '4. CONTROL: a block lacking the real caller is reported under A' (Reports (Drift $dbA) 'DoIt')
  Check '4b. ... and under B' (Reports (Drift $dbB) 'DoIt')

  # 5 convergence
  & $exePath document --qname thing.TThing.DoIt --db $dbB --apply 2>&1 | Out-Null
  Reindex
  Check '5a. after document --apply --db B: B silent' (-not (Reports (Drift $dbB) 'DoIt'))
  Check '5b. after document --apply --db B: A silent' (-not (Reports (Drift $dbA) 'DoIt'))
} finally { Pop-Location }
if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} catch { Write-Host "ERROR: $_" -ForegroundColor Red; exit 2 }
