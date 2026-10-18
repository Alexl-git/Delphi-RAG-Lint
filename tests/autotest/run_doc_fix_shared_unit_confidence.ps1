<#
  run_doc_fix_shared_unit_confidence.ps1 -- two projects that compile one unit
  and disagree on the CONFIDENCE of the same caller converge instead of
  rewriting the block past each other (B-06, 1.31.5).

  THE REPORT (docs\INBOX-docfix-shared-units-and-db-tag-leak.md, YADF
  2026-10-14): `lint --fix` previews of YADF.Options.pas differ per project DB,
  and whichever is applied the others report doc-drift "permanently".

  RE-MEASURED 2026-10-18 on a scratch copy of YADF with 1.31.4, every index
  refreshed after every apply: the differing previews are the designed one-time
  tag adoption (each project adds what IT sees; run_shared_unit_staleness pins
  that), and the union DID form -- 31 distinct entries before, 68 after, none
  lost. What did NOT converge: six blocks where YADF renders
  `YadfMain.ParseFlags (YadfMain.pas)` and YADFOT renders the same edge with
  the ' ?' uncertainty marker. The entry's IDENTITY ignores the marker, but the
  rendered text won the bare part, so every --fix from one project rewrote the
  marker the other way: 12 edits per round, round after round, with the
  checker (the same ReconcileContent) truthfully reporting drift each time.

  THE RULE NOW: confidence is MONOTONE. A project that binds the edge without
  the marker has strictly more evidence than one that could not, so once any
  project wrote the certain spelling the uncertain render keeps it. The
  reverse -- stored uncertain, fresh certain -- stays the one-time upgrade.
  Checker and fixer share ReconcileContent, so both change together.

  Fixture: uCaller calls TShared.Foo through a type alias declared in uTypes,
  which only project A compiles. A binds the receiver and renders the caller
  certain; B cannot and renders it with ' ?'. Writes are APPLIED and the file's
  bytes compared -- a dry run proves the plan, never the bytes.
  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-conf-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$proj = Join-Path $root 'proj'
New-Item -ItemType Directory -Force -Path $proj | Out-Null

$crlf = "`r`n"
function WriteAscii($path, $lines) {
  [System.IO.File]::WriteAllText($path, (($lines -join $crlf) + $crlf), (New-Object System.Text.ASCIIEncoding))
}
function Run([string[]]$xs) {
  $o = & $Exe @xs 2>&1 | Out-String
  [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE }
}
function BlockAbove([string]$path, [string]$declPat) {
  $ls = [IO.File]::ReadAllLines($path)
  $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $declPat) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) {
    if ($ls[$i] -notmatch '^\s*///') { break }
    $acc = ,$ls[$i] + $acc
  }
  return ($acc -join "`n")
}
function CalledFrom([string]$block) {
  $m = [regex]::Match($block, '<para>Called from: ([^<]*)</para>')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}

# --- fixture ----------------------------------------------------------------
$uShared = Join-Path $proj 'uShared.pas'
WriteAscii $uShared @(
  'unit uShared;   // dl:shared A, B', 'interface',
  'type', '  TShared = class', '  public', '    procedure Foo;', '  end;',
  'procedure Direct;',
  'implementation',
  'procedure TShared.Foo; begin end;',
  '// A RESOLVED caller in every project, so B''s list is MIXED: the ? marker',
  '// renders only beside a resolved anchor (a wholly-guessed list is dropped).',
  'procedure Direct;', 'var S: TShared;', 'begin', '  S:= TShared.Create;', '  S.Foo;', 'end;',
  'end.')
# uTypes lives in a folder only A.dpr names: a project index is the compile
# CLOSURE (every unit reachable through `uses`), so a sibling file in the dpr
# folder would be found by B too. In a folder B never walks it is not.
New-Item -ItemType Directory -Force -Path (Join-Path $proj 'aonly') | Out-Null
# The call site is `V.Foo` with V declared in uCaller as TLocal, an alias of
# TAlias, itself an alias of TShared declared in uTypes. A follows the chain
# and resolves the call CERTAIN. B never sees uTypes: the resolver emits no
# edge, the site falls to the by-name bucket (V is a declared VALUE, so the
# store keeps it), and V's declared type is a name this index declares as an
# ALIAS -- UNTYPABLE under the C14 foreign-receiver gate, so the entry is kept
# and marked ' ?'. Simpler shapes do not produce the asymmetry: a receiver
# whose declared type B does not declare AT ALL reads as a library type
# (FOREIGN -- dropped, not marked); an undeclared or dotted receiver fails the
# store's value filter.
WriteAscii (Join-Path $proj 'aonly\uTypes.pas') @(
  'unit uTypes;', 'interface', 'uses uShared;', 'type', '  TAlias = TShared;', 'implementation', 'end.')
WriteAscii (Join-Path $proj 'uCaller.pas') @(
  'unit uCaller;', 'interface', 'procedure CallIt;', 'implementation', 'uses uShared, uTypes;',
  'type', '  TLocal = TAlias;',
  'var V: TLocal;',
  'procedure CallIt;', 'begin', '  V.Foo;', 'end;',
  'end.')
WriteAscii (Join-Path $proj 'A.dpr') @('program A;', "uses uShared in 'uShared.pas', uTypes in 'aonly\uTypes.pas', uCaller in 'uCaller.pas';", 'begin', 'end.')
WriteAscii (Join-Path $proj 'B.dpr') @('program B;', "uses uShared in 'uShared.pas', uCaller in 'uCaller.pas';", 'begin', 'end.')
$dbA = Join-Path $root 'A.sqlite'
$dbB = Join-Path $root 'B.sqlite'
function Reindex { $null = Run @('index','--project',(Join-Path $proj 'A.dpr'),'--db',$dbA); $null = Run @('index','--project',(Join-Path $proj 'B.dpr'),'--db',$dbB) }
function Drift($db) { $o = (Run @('lint',$uShared,'--db',$db,'--project-rules','--rule','doc-drift')).Out; $m = [regex]::Match($o, '(\d+) finding\(s\)'); if ($m.Success) { [int]$m.Groups[1].Value } else { -1 } }
function Fix($db) { $null = Run @('lint',$uShared,'--db',$db,'--project-rules','--rule','doc-drift','--fix','--apply'); Reindex }
function Hash { (Get-FileHash $uShared -Algorithm MD5).Hash }

Reindex
Check 'setup: both indexes built' ((Test-Path $dbA) -and (Test-Path $dbB))
$q = Run @('query','--name','TAlias','--db',$dbB,'--exact')
Check 'setup: B does NOT hold uTypes (so it cannot type V)' ($q.Out -notmatch 'uTypes') 'TAlias absent from B.sqlite'
$q = Run @('query','--name','TAlias','--db',$dbA,'--exact')
Check 'setup: A DOES hold uTypes.TAlias' ($q.Out -match 'uTypes') 'TAlias present in A.sqlite'

# --- B writes first: its own render is UNCERTAIN (positive control) ----------
$null = Run @('document','--unit',$uShared,'--db',$dbB,'--apply')
Reindex
$cf = CalledFrom (BlockAbove $uShared 'procedure Foo;')
Check 'CONTROL-B B renders the caller with the uncertainty marker' ($cf -match 'uCaller\.CallIt \(uCaller\.pas\) \?') $cf

# --- A upgrades it: stored uncertain, fresh certain is a one-time change ------
Check 'CONTROL-A A sees the upgrade as drift' ((Drift $dbA) -gt 0)
Fix $dbA
$cf = CalledFrom (BlockAbove $uShared 'procedure Foo;')
Check 'CONTROL-A A wrote the caller CERTAIN' (($cf -match 'uCaller\.CallIt \(uCaller\.pas\)') -and ($cf -notmatch '\?')) $cf
Check 'CONTROL-A exactly one entry for the caller (one identity)' (([regex]::Matches($cf, 'CallIt')).Count -eq 1) $cf

# --- THE FIX: B keeps the certain spelling instead of downgrading it ---------
# B's first --fix is its designed one-time tag ADOPTION (run_shared_unit_staleness
# pins that), so the block legitimately changes once: [A] becomes [A,B]. What
# must NOT change is the confidence -- before the fix this wrote
# `[A,B]uCaller.CallIt (uCaller.pas) ?`, and A then wrote it back, for ever.
Fix $dbB
$cf = CalledFrom (BlockAbove $uShared 'procedure Foo;')
Check 'CASE-B B adopted the entry under its own tag' ($cf -match '\[A,B\]uCaller\.CallIt') $cf
Check 'CASE-B ...and KEPT it certain (no downgrade to ?)' ($cf -notmatch '\?') $cf
Check 'CASE-B B reports no drift after its adoption' ((Drift $dbB) -eq 0)

# --- CONVERGENCE: two more rounds, both projects, nothing moves --------------
foreach ($round in 1, 2) {
  $h0 = Hash; Fix $dbA; Fix $dbB; $h1 = Hash
  Check "CONVERGE round $round A then B: byte-identical" ($h0 -eq $h1) "$h0 vs $h1"
  Check "CONVERGE round $round A reports 0, B reports 0" (((Drift $dbA) -eq 0) -and ((Drift $dbB) -eq 0))
}
Check 'the file is still 7-bit ASCII with CRLF' `
  ((-not ([IO.File]::ReadAllBytes($uShared) | Where-Object { $_ -gt 127 })) -and ([IO.File]::ReadAllText($uShared) -notmatch '(?<!\r)\n')) 'bytes'

Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
if ($fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
