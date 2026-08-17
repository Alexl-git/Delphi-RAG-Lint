<#
  PENDING -- deliberately named `pending_*` so the battery's `run_*.ps1`
  discovery does NOT pick it up. It is the fixture for work that is not
  implemented (INBOX-buildfor-defaulted-args, the AExtraStores residue), and a
  test for an unbuilt feature belongs outside the battery, not inside it as a
  standing red.

  STATUS 2026-08-17: written, and it does NOT yet demonstrate the defect.
  Against the current build it reports:

      1 document --db A --db B wrote the block naming B's caller      PASS
      2 lint-all --db A --db B --fix KEPT the entry                   PASS
      3 no ping-pong                                                  PASS
      4 POSITIVE CONTROL: lint-all --db A alone DOES strip it         FAIL

  Step 4 failing is the whole point of having it: with only dbA open the entry
  is unaccountable and SHOULD be reported stale, and it is not. `lint-all --db A`
  on the fixture emits only `empty-procedure-body` -- no facts-block-stale
  finding at all. So either the fixture does not put the decl into doc-drift's
  population (the generated block carries only <remarks>, no <summary> -- check
  what DocumentedPublicDecls actually requires), or the drift signal is narrower
  than the note assumes.

  DO NOT rename this to run_* until step 4 goes RED for the right reason.
  Until then steps 1-3 passing means nothing: they would pass on an engine that
  never reports drift at all.

  NEXT DIAGNOSTIC (unrun -- needs a quiet machine):
      DRAGLINT_PROFILE=1 drag-lint lint-all --db <a.sqlite> --quiet
  and read the DOC-DRIFT BREAKDOWN decl count. Zero documented decls means the
  fixture, not the engine.

  ---

  run_doc_drift_extra_stores.ps1 -- a cross-DB inbound fact must survive
  `lint-all --fix`.

  INBOX-buildfor-defaulted-args-diverge-between-entry-points, the one residue
  that is real: AExtraStores.

  `document --qname X --db A --db B` mines inbound facts from BOTH stores and
  writes them into the source. The doc-drift CHECKER then rebuilds the same block
  to compare -- but TDocDrift.Analyze hardcodes {AExtraStores=}nil, so it renders
  Fresh from the PRIMARY store only, sees an entry it cannot account for, calls
  the block stale, and `--fix` deletes it. Run `document` again and it is re-added.
  A ping-pong, and the source file changes on every alternation.

  THE FIXTURE, and why it is shaped this way:

    shared\thing.pas   TThing.DoIt          -- indexed by BOTH sections
    bside\user.pas     calls TThing.DoIt    -- indexed by section B ONLY

    section A -> dbA : ["shared"]            so dbA has NO caller for DoIt
    section B -> dbB : ["shared", "bside"]   so dbB RESOLVES user.Go -> DoIt

  The call is a RESOLVED edge in B, not a name match, so this exercises the
  cross-store fan-out rather than the ambiguity-gated name path.

    1  document --db A --db B --apply   -> the block names a caller from B
    2  lint-all --db A --db B --fix     -> the entry MUST SURVIVE   <-- the bug
    3  document --db A --db B --apply   -> reports nothing to do
                                          (the ping-pong's other half: if 2
                                           stripped it, this re-adds it)

  POSITIVE CONTROL (step 4): `lint-all --db A --fix` ALONE -- one store, no
  extra -- SHOULD still strip it, because with only dbA open the entry genuinely
  is unaccountable. Without this, a fix that simply stopped ever removing
  inbound entries would pass steps 1-3 while destroying the drift signal.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_c1_extrastores'
if (Test-Path $scratch) { Remove-Item $scratch -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $scratch 'shared') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratch 'bside')  | Out-Null

function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}

WriteAscii (Join-Path $scratch 'shared\thing.pas') @'
unit thing;

interface

type
  TThing = class
  public
    procedure DoIt;
  end;

implementation

procedure TThing.DoIt;
begin
end;

end.
'@

WriteAscii (Join-Path $scratch 'bside\user.pas') @'
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

$cfg = Join-Path $scratch 'manifest.drag-lint.json'
@"
{
  "settings": { "defaultPlatform": "Win64", "sizeGuardMB": 1500, "enginePath": "auto", "maxJobs": 1 },
  "indexes": {
    "outDir": "out",
    "sections": [
      { "name": "SecA", "db": "a.sqlite", "include": ["shared"] },
      { "name": "SecB", "db": "b.sqlite", "include": ["shared", "bside"] }
    ]
  }
}
"@ | Set-Content $cfg -Encoding ascii

$dbA    = Join-Path $scratch 'out\a.sqlite'
$dbB    = Join-Path $scratch 'out\b.sqlite'
$thing  = Join-Path $scratch 'shared\thing.pas'
$QNAME  = 'thing.TThing.DoIt'

function BlockHasCaller { (Get-Content $thing -Raw) -match '(?i)(Called from|Used by)[^\r\n]*Go' }

Push-Location C:\TEMP
try {
  & $exePath index --all --config $cfg --only SecA --jobs 1 2>&1 | Out-Null
  & $exePath index --all --config $cfg --only SecB --jobs 1 2>&1 | Out-Null
  Check 'SANITY: both section DBs exist' ((Test-Path $dbA) -and (Test-Path $dbB))

  # --- 1. document with BOTH stores -----------------------------------------
  $d1 = (& $exePath document --qname $QNAME --db $dbA --db $dbB --apply 2>&1 | Out-String)
  Check '1. document --db A --db B wrote a managed block naming B''s caller' `
        (BlockHasCaller) `
        $(($d1 -split "`n" | Select-Object -Last 2) -join ' / ')

  # --- 2. THE BUG: lint-all --fix with the SAME two stores must not strip it --
  & $exePath lint-all --db $dbA --db $dbB --fix --quiet 2>&1 | Out-Null
  Check '2. lint-all --db A --db B --fix KEPT the cross-DB inbound entry' `
        (BlockHasCaller) `
        'the checker renders Fresh single-store and deletes what document wrote'

  # --- 3. and document has nothing left to do (the ping-pong''s other half) ---
  $d3 = (& $exePath document --qname $QNAME --db $dbA --db $dbB --apply 2>&1 | Out-String)
  Check '3. a second document --apply re-adds nothing (no ping-pong)' `
        ($d3 -notmatch '(?i)\b1 (file|decl|symbol)s? (changed|updated|written)') `
        $(($d3 -split "`n" | Where-Object { $_ -match '(?i)nothing|changed|updated' } | Select-Object -First 1))

  # --- 4. POSITIVE CONTROL: with ONE store the entry is genuinely stale ------
  & $exePath lint-all --db $dbA --fix --quiet 2>&1 | Out-Null
  Check '4. positive control: lint-all --db A alone DOES strip it' `
        (-not (BlockHasCaller)) `
        'single-store drift detection must still work, or the fix is just "never remove"'
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
