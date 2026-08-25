<#
  run_doc_crossdb_member_callers.ps1 -- a caller that lives ONLY in an EXTRA
  store and reaches the target through a MEMBER ACCESS on a typed receiver
  (`T.DoIt`) must appear in the documented facts.

  WHAT WAS MISSING (L3 of the session-36 leftovers). The extra-store fan-out in
  TDocFactsBuilder.Build had exactly one bucket: FindUnresolvedNameCallers, a
  NAME match on the qualified name's LAST SEGMENT. That bucket is guarded by an
  ambiguity gate (the name must identify one call target in BOTH stores), and it
  only ever collects refs that have NO call_edges row.

  A dotted call on a typed receiver is the opposite case: the extra store's own
  resolver DID type the receiver and DID emit a resolved edge, so the ref is not
  in the unresolved bucket at all -- and the fact was dropped. A plain call by
  name (`Compute(21)`) came through fine, which is why this looked like it
  worked (run_doc_multidb scenario B).

  The comment at the fan-out said FindResolvedCallers "would be meaningless"
  against an extra store. That reasoning was right about the ID -- ASym.Id is a
  PRIMARY-store key and symbol ids are numbered per database -- but the answer
  is to TRANSLATE the id, not to give up the resolved edges: look the target up
  in the extra store by its FULL qualified name, and use THAT store's id.

  WHY THIS DOES NOT REOPEN THE JUNK-FACTS CHANNEL. The 2026-08-13 incident
  (dxXMLWriter / FireDAC / Spring / System.JSON written into YADF's source) came
  from LAST-SEGMENT name matches against the library index. This path requires
  (a) the FULL qualified name, (b) EXACTLY ONE symbol carrying it in that store,
  and (c) a RESOLVED call edge recorded by that store's own resolver. A leaf-name
  collision cannot satisfy (a); an ambiguous match cannot satisfy (b); a mere
  mention cannot satisfy (c). Decoy below is the standing proof of (a).

  THE FIXTURE:

    shared\thing.pas   TThing.DoIt      -- the target, indexed by BOTH sections
                       TThing.Lonely    -- called by NOBODY, anywhere
    bside\user.pas     Go calls T.DoIt  -- MEMBER ACCESS, indexed by B ONLY
    bside\other.pas    TOther.DoIt      -- same LEAF name, different qname
                       Decoy calls O.DoIt

    section A -> dbA : ["shared"]           the target's OWN db. No callers.
    section B -> dbB : ["shared", "bside"]  resolves user.Go -> thing.TThing.DoIt

  `document --qname thing.TThing.DoIt --db A --db B` makes A the primary (the
  first --db wins, ruling 2026-08-25) and B an extra. Every caller of DoIt lives
  in B, so B must contribute one or the fact is unrenderable.

  WHAT IS ASSERTED, against the APPLIED SOURCE rather than stdout: with nothing
  to render, `document` prints "doc: up to date (no change)" and emits no block,
  so a stdout assertion cannot tell "no caller found" from "nothing printed".
  The block that lands above each declaration is the artefact under test.

    2  DoIt's block names user.Go                 <- the feature (RED before)
    3  DoIt's block does NOT name Decoy           <- POSITIVE CONTROL (a)
    4  Lonely's block has NO caller list at all   <- POSITIVE CONTROL (b)

  3 AND 4 REQUIRE A NON-EMPTY BLOCK, and that is not belt-and-braces. With
  nothing to render `document` writes no block at all, so "Decoy is absent" and
  "no caller list" are both trivially true of the empty string -- both controls
  passed against the unfixed build for that reason, which is the same shape as
  a test that passes with the rule switched off. TThing.Lonely therefore calls
  a unit-local Helper: it has a Calls: fact, so a block IS written for it, and
  the absence of a caller list in that block is a real observation.

  BOTH CONTROLS ARE LOAD-BEARING. Assertion 2 alone passes if the change simply
  starts attributing every same-named call site in every open store to
  everything -- which is precisely the 2026-08-13 failure. 3 fails on a
  leaf-name match; 4 fails on an "attribute anything" implementation. They are
  checked PER DECLARATION, not over the whole file: once both blocks exist, a
  whole-file search for "Called from" would find DoIt's block while testing
  Lonely and pass for the wrong reason.

  REINDEX BETWEEN APPLIES is load-bearing: symbol line numbers come from the
  INDEX, and the first apply shifts every line below its insertion point. The
  second apply would otherwise target a stale line.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP 'draglint_crossdb_member'
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
    procedure Lonely;
  end;

implementation

procedure Helper;
begin
end;

procedure TThing.DoIt;
begin
end;

procedure TThing.Lonely;
begin
  Helper;
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

WriteAscii (Join-Path $scratch 'bside\other.pas') @'
unit other;

interface

type
  TOther = class
  public
    procedure DoIt;
  end;

procedure Decoy;

implementation

procedure TOther.DoIt;
begin
end;

procedure Decoy;
var
  O: TOther;
begin
  O := TOther.Create;
  O.DoIt;
  O.Free;
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

$dbA   = Join-Path $scratch 'out\a.sqlite'
$dbB   = Join-Path $scratch 'out\b.sqlite'
$thing = Join-Path $scratch 'shared\thing.pas'

function Reindex {
  & $exePath index --all --config $cfg --only SecA --jobs 1 2>&1 | Out-Null
  & $exePath index --all --config $cfg --only SecB --jobs 1 2>&1 | Out-Null
}

# The contiguous run of '///' lines immediately ABOVE the first line whose
# trimmed text equals $Decl. Scoping per declaration is what keeps assertion 4
# honest once DoIt's block is also in the file.
function BlockAbove([string]$Decl) {
  $lines = Get-Content $thing
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Decl) { $idx = $i; break } }
  if ($idx -lt 0) { return "<<declaration not found: $Decl>>" }
  $out = @()
  for ($j = $idx - 1; $j -ge 0; $j--) {
    if ($lines[$j].Trim().StartsWith('///')) { $out = ,$lines[$j] + $out } else { break }
  }
  return ($out -join "`n")
}

Push-Location C:\TEMP
try {
  Reindex
  Check '1. SANITY: both section DBs exist' ((Test-Path $dbA) -and (Test-Path $dbB))

  & $exePath document --qname 'thing.TThing.DoIt' --db $dbA --db $dbB --apply --no-backup 2>&1 | Out-Null
  Reindex
  $doItBlock = BlockAbove 'procedure DoIt;'

  Check '2. cross-DB MEMBER-ACCESS caller user.Go is rendered' `
        ($doItBlock -match '(?i)(Called from|Used by)[^\r\n]*\bGo\b') `
        'the only caller of DoIt lives in the extra store and reaches it via T.DoIt'

  Check '3. POSITIVE CONTROL (a): Decoy is NOT attributed to thing.TThing.DoIt' `
        (($doItBlock.Trim() -ne '') -and ($doItBlock -notmatch '(?i)\bDecoy\b')) `
        'NON-EMPTY block required: absence of Decoy in an absent block proves nothing'

  & $exePath document --qname 'thing.TThing.Lonely' --db $dbA --db $dbB --apply --no-backup 2>&1 | Out-Null
  $lonelyBlock = BlockAbove 'procedure Lonely;'
  Check '4. POSITIVE CONTROL (b): a symbol nothing calls gets NO caller list' `
        (($lonelyBlock.Trim() -ne '') -and ($lonelyBlock -notmatch '(?i)(Called from|Used by)')) `
        'NON-EMPTY block required (Lonely calls Helper, so it has a Calls: fact)'

  if ($fail) {
    Write-Host '      --- block above procedure DoIt; ---' -ForegroundColor DarkGray
    ($doItBlock -split "`n") | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
    Write-Host '      --- block above procedure Lonely; ---' -ForegroundColor DarkGray
    ($lonelyBlock -split "`n") | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
  }
} finally { Pop-Location }

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
