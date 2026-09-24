<#
  run_doc_legacy_pure_untouched.ps1 -- a stored legacy `<para>Pure</para>` fact
  is NOT churn: `document` leaves a block byte-identical when that line is its
  ONLY difference from a fresh render, and doc-drift agrees.

  THE DEFECT (reported 2026-09-23, measured the same day on this fixture)
  --------------------------------------------------------------------------------
  Purity v2 stopped emitting `Pure` (the old render-time guess) and emits
  `Effect-free (proven)` from symbol_facts.effect_free instead. The owner
  DEFERRED migrating the stored lines: they are to be regenerated ONCE, later,
  by an explicit run. The engine did not honour that. Against the pre-fix
  build, on the fixture below:

      document --unit        -> 2 decl(s), 4 edit(s): every Pure block rewritten
      lint --project-rules   -> doc-drift "managed facts block is out of date"
                                on both, i.e. [FIXABLE] churn on untouched code

  THE CONTRACT
  --------------------------------------------------------------------------------
    * RELABEL case (stored Pure, fresh Effect-free) and RETRACT case (stored
      Pure, fresh has no purity fact) -> unchanged, not drift.
    * A block that ALSO differs in anything else is regenerated in full, and
      loses the legacy line with it (POSITIVE CONTROL: without it a checker that
      never reports anything would pass this whole file).
    * `document --migrate-pure` restores the regeneration -- the owner's runbook
      for the one-time migration depends on it.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n,$ok,$d=''){ Write-Host ("[{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n,$d) -ForegroundColor (@('Red','Green')[[int][bool]$ok]); if(-not $ok){$script:Failed=$true} }

$exePath = (Resolve-Path $Exe).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('dl-legacy-pure-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$src = Join-Path $root 'PureLegacy.pas'
$db  = Join-Path $root 'PureLegacy.sqlite'

function Write-Ascii([string]$Path, [string]$Body) {
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Run([string[]]$xs) { $o = & $exePath @xs 2>&1 | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
# The /// lines directly above a declaration: that declaration's own block.
function BlockAbove([string]$path, [string]$declPat) {
  $ls = [IO.File]::ReadAllLines($path); $d = -1
  for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match $declPat) { $d = $i; break } }
  if ($d -lt 0) { return '' }
  $acc = @()
  for ($i = $d - 1; $i -ge 0; $i--) { if ($ls[$i] -notmatch '^\s*///') { break }; $acc = ,$ls[$i] + $acc }
  return ($acc -join "`n")
}

Write-Ascii $src @'
unit PureLegacy;

interface

var
  GCount: Integer;

function Twice(X: Integer): Integer;
function Caller(Y: Integer): Integer;
procedure Bump;
procedure Kick;
function Drifted(Z: Integer): Integer;

implementation

function Twice(X: Integer): Integer;
begin
  Result:= X * 2;
end;

function Caller(Y: Integer): Integer;
begin
  Result:= Twice(Y) + 1;
end;

procedure Bump;
begin
  Inc(GCount);
end;

procedure Kick;
begin
  Bump;
end;

function Drifted(Z: Integer): Integer;
begin
  Result:= Twice(Z);
end;

end.
'@

$r = Run @('index', $root, '--db', $db);                                         Check 'setup: indexed' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('document', '--unit', $src, '--db', $db, '--apply', '--no-backup');  Check 'setup: blocks written by the current engine' ($r.Code -eq 0) "exit $($r.Code)"

# --- turn the current blocks into purity-v1 blocks ---------------------------
$t = [IO.File]::ReadAllText($src)
Check 'setup: the engine proved Twice/Caller/Drifted effect-free' (([regex]::Matches($t, 'Effect-free \(proven\)')).Count -ge 3) 'relabel case needs the v2 line to exist'
$t = $t.Replace('<para>Effect-free (proven)</para>', '<para>Pure</para>')
$ls = [Collections.ArrayList]@($t -split "`r`n")
# RETRACT: Bump writes a global, so v2 proves nothing; v1 had stamped Pure on it.
# (Kick exists only so Bump HAS a block -- a Called from: line.)
$bumpDecl = -1; for ($i = 0; $i -lt $ls.Count; $i++) { if ($ls[$i] -match '^procedure Bump;') { $bumpDecl = $i; break } }
$endAt = -1; for ($i = $bumpDecl - 1; $i -ge 0 -and $ls[$i] -match '^\s*///'; $i--) { if ($ls[$i] -match 'drag-lint:auto END') { $endAt = $i; break } }
Check 'setup: Bump carries its own managed block' ($endAt -ge 0) "END at $endAt"
if ($endAt -ge 0) { $ls.Insert($endAt, '/// <para>Pure</para>') }
# POSITIVE CONTROL: Drifted differs in a REAL fact as well as the legacy line.
$t = ($ls -join "`r`n")
$t = [regex]::Replace($t, '(?s)(<para>Calls: PureLegacy\.Twice</para>)(?=(?:(?!function ).)*function Drifted)', '<para>Calls: PureLegacy.Nothing</para>')
[IO.File]::WriteAllText($src, $t, [Text.Encoding]::ASCII)
Check 'setup: Drifted carries a stale Calls: line' ((BlockAbove $src 'function Drifted') -match 'Calls: PureLegacy\.Nothing') ''
Check 'setup: Bump carries the legacy Pure line' ((BlockAbove $src 'procedure Bump') -match '<para>Pure</para>') ''
Check 'setup: Twice carries the legacy Pure line' ((BlockAbove $src 'function Twice') -match '<para>Pure</para>') ''

$r = Run @('index', $root, '--db', $db); Check 'setup: reindexed after the edit' ($r.Code -eq 0) "exit $($r.Code)"

# --- the checker --------------------------------------------------------------
foreach ($q in 'Twice', 'Caller', 'Bump') {
  $d = (Run @('doc-drift', '--qname', "PureLegacy.$q", '--db', $db)).Out
  Check "CHECK $q (legacy Pure only) is not drift" ($d -notmatch 'ddFactsBlockStale') $d.Trim()
}
$d = (Run @('doc-drift', '--qname', 'PureLegacy.Drifted', '--db', $db)).Out
Check 'CONTROL Drifted (a real fact changed too) IS drift' ($d -match 'ddFactsBlockStale') $d.Trim()

# --- the writer ---------------------------------------------------------------
$before = @{}; foreach ($q in 'function Twice', 'function Caller', 'procedure Bump') { $before[$q] = BlockAbove $src $q }
$r = Run @('document', '--unit', $src, '--db', $db, '--apply', '--no-backup')
Check 'WRITE document --apply ran' ($r.Code -eq 0) $r.Out.Trim()
foreach ($q in 'function Twice', 'function Caller', 'procedure Bump') {
  Check "WRITE $q block is byte-identical" ((BlockAbove $src $q) -ceq $before[$q]) ''
}
$after = BlockAbove $src 'function Drifted'
Check 'CONTROL Drifted block was regenerated (stale Calls: repaired)' ($after -match 'Calls: PureLegacy\.Twice' -and $after -notmatch 'PureLegacy\.Nothing') $after
Check 'CONTROL a regenerated block carries the v2 fact, not the legacy one' ($after -match 'Effect-free \(proven\)' -and $after -notmatch '<para>Pure</para>') ''

$null = Run @('index', $root, '--db', $db)
$h1 = (Get-FileHash $src).Hash
$r = Run @('document', '--unit', $src, '--db', $db, '--apply', '--no-backup')
Check 'FIXED POINT a second run changes nothing' ((Get-FileHash $src).Hash -eq $h1) $r.Out.Trim()

# --- the explicit migration ---------------------------------------------------
$r = Run @('document', '--unit', $src, '--db', $db, '--migrate-pure')
Check 'MIGRATE --migrate-pure proposes the relabel/retract edits' ($r.Out -match '(\d+) edit\(s\)' -and [int]$Matches[1] -ge 3) $r.Out.Trim().Split("`n")[-1]
Check 'MIGRATE dry run wrote nothing' ((Get-FileHash $src).Hash -eq $h1) ''

if ($script:Failed) { Write-Host "FAIL (scratch kept: $root)" -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
