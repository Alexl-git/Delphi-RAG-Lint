<#
  run_doc_overload_idempotent.ps1 -- Bug A fix (ADP1): TDocumenter.BuildFor
  resolved a decl PURELY by qualified-name text (Syms[0]), so document
  --unit's per-declaration batch loop (DRagLint.Doc.Batch.pas, DocumentUnit)
  called BuildFor(Sym.QualifiedName) for every overload row but every call
  collapsed onto the SAME first-declared symbol. Result: --apply wrote N
  stacked identical managed doc blocks above the FIRST overload's decl and
  NONE above the others, and a repeated --apply kept growing the stack
  (never idempotent). See .superpowers/sdd/adp1-bugA-brief.md and the
  DISCOVERED PRE-EXISTING BUG note in run_doc_cheap_facts.ps1 (which first
  flagged this, out of its own task's scope).

  Fix: TDocumenter.BuildForSymbol(AStore, ASym, ...) is extracted from
  BuildFor's body (operates on an ALREADY-RESOLVED TSymbol); BuildFor(AQName)
  becomes a resolve -> Syms[0] -> BuildForSymbol wrapper (--qname behavior
  unchanged); DocumentUnit's loop now calls BuildForSymbol(AStore, Sym, ...)
  with the ROW's own Sym instead of BuildFor(AStore, Sym.QualifiedName, ...).

  Fixture (uOverloadIdem.pas): TLogger has TWO overloads of Log, each with a
  distinct one-line body, both in the interface section (public, documentable):
    procedure Log(const S: string); overload;
    procedure Log(const N: Integer); overload;
  Both share the identical qualified_name (uOverloadIdem.TLogger.Log).

  Asserts (post-fix contract; pre-fix this FAILS -- see the RED evidence
  captured in the task report):
    1. After `document --unit <file> --apply --no-backup`: EXACTLY ONE
       managed '<!-- drag-lint:auto BEGIN -->' block sits directly above
       Log(const S: string)'s OWN decl line, and EXACTLY ONE sits directly
       above Log(const N: Integer)'s OWN decl line (pre-fix: 2 above the
       first, 0 above the second -- the stacking bug).
    2. A SECOND `document --unit --apply --json` run on the same file/db
       reports edits=0 (daUnchanged for both decls) AND the file is
       byte-identical before/after -- idempotent (pre-fix: --json edits > 0
       every time, the stack keeps growing).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-doc-overload-idempotent); a
  fresh copy + a TEMP db (never a real corpus db).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-doc-overload-idempotent"
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$FixtureBody = @'
unit uOverloadIdem;

interface

type
  TLogger = class
  public
    procedure Log(const S: string); overload;
    procedure Log(const N: Integer); overload;
  end;

implementation

procedure TLogger.Log(const S: string);
begin
  Writeln(S);
end;

procedure TLogger.Log(const N: Integer);
begin
  Writeln(N);
end;

end.
'@
function Write-Fixture([string]$Path) {
  $norm = $FixtureBody -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$dir  = Join-Path $WorkDir 'fx'
New-Item -ItemType Directory $dir | Out-Null
$file = Join-Path $dir 'uOverloadIdem.pas'
$db   = Join-Path $dir 'fx.sqlite'
Write-Fixture $file

& $Exe index $dir --db $db 2>&1 | Out-Null

# Finds the Nth (1-based $Occurrence) line matching $Pattern, then walks
# upward collecting the contiguous '///' block directly above it (same
# scan-upward idiom run_doc_cheap_facts.ps1 uses).
function Get-DocBlockAbove([string[]]$Lines, [string]$Pattern, [int]$Occurrence = 1) {
  $hits = @()
  for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match $Pattern) { $hits += $i } }
  if ($hits.Count -lt $Occurrence) { return $null }
  $idx = $hits[$Occurrence - 1]
  $blockLines = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($Lines[$i] -notmatch '^\s*///') { break }
    $blockLines.Insert(0, $Lines[$i])
  }
  return ([string]::Join("`n", $blockLines.ToArray()) -replace '</?para>', '')
}

function Count-Begin([string]$Block) {
  if ($null -eq $Block) { return 0 }
  return ([regex]::Matches($Block, '<!-- drag-lint:auto BEGIN -->')).Count
}

Write-Host 'First apply: document --unit --apply --no-backup' -ForegroundColor Cyan
& $Exe document --unit $file --db $db --apply --no-backup 2>&1 | Out-Null
$ec = $LASTEXITCODE
Check 'document --unit exit 0' ($ec -eq 0) "ec=$ec"

$lines = [IO.File]::ReadAllLines($file)
$blockS = Get-DocBlockAbove $lines '^\s*procedure Log\(const S: string\); overload;\s*$' 1
$blockN = Get-DocBlockAbove $lines '^\s*procedure Log\(const N: Integer\); overload;\s*$' 1
$countS = Count-Begin $blockS
$countN = Count-Begin $blockN

Check 'Log(const S: string) has EXACTLY ONE managed block (own decl, not stacked)' ($countS -eq 1) "count=$countS`n$blockS"
Check 'Log(const N: Integer) has EXACTLY ONE managed block (its OWN decl, not orphaned)' ($countN -eq 1) "count=$countN`n$blockN"

Write-Host ''
Write-Host 'Second apply: idempotent (no further edit)' -ForegroundColor Cyan
$beforeBytes = [IO.File]::ReadAllBytes($file)
# CRITICAL: re-index so the store sees the post-insert line numbers (the store
# caches file content by mtime -- a stale index hands back PRE-insert symbol
# lines, so the second apply would misplace the "existing comment" scan and
# insert a duplicate instead of recognizing daUnchanged; same requirement
# documented in run_doc_returns.ps1 Scenario C / tests\autodoc\run_doc_idempotent.ps1.
# Orthogonal to Bug A -- both overloads must independently survive this too.
& $Exe index $dir --db $db 2>&1 | Out-Null
$rj = & $Exe document --unit $file --db $db --apply --no-backup --json 2>$null | Out-String
$ecj = $LASTEXITCODE
$oj = $null; try { $oj = ($rj | ConvertFrom-Json) } catch { $oj = $null }
Check 'second apply: exit 0' ($ecj -eq 0) "ec=$ecj"
Check 'second apply: json parsed' ($null -ne $oj) $rj
Check 'second apply: edits = 0 (daUnchanged for both overloads)' `
  ($null -ne $oj -and [int]$oj.edits -eq 0) "edits=$($oj.edits)"

$afterBytes = [IO.File]::ReadAllBytes($file)
$byteIdentical = ($beforeBytes.Length -eq $afterBytes.Length) -and (-not (Compare-Object $beforeBytes $afterBytes -SyncWindow 0))
Check 'second apply: file byte-identical before/after' $byteIdentical

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
