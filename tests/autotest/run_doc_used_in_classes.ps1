<#
  run_doc_used_in_classes.ps1 --
  `Used in units:` holds UNITS only. A class name found there is moved to its
  own `Used in classes:` line, which the doc tool keeps and the checker accepts.

  THE DEFECT (owner ruling 3, 2026-10-25; backlog X-24; docs\INBOX-entryunitkey-
  strips-unit-name-suffix.md, second trigger). IParser in
  src\core\DRagLint.Core.Interfaces.pas carried
      Used in units: ..., DRagLint.Parser.Sql, TDFMParser, TFirebirdSqlParser
  from 2026-09-17 (f1016321) until a hand edit (63c4c567). HOW THEY GOT IN: v23
  of Doc.SharedFacts -- 'Implemented by:' was not in ALL_LABELS, so the flattened
  'Used in units:' slice ran on into the implementor list; the reconciler then
  kept the two names (not units, so never vouchable) as foreign entries, and a
  foreign entry is preserved forever. v23 fixed the slicing; nothing ever moved
  the residue out, so any block that caught it still carries it.

  THE FIX. A stored untagged `Used in units:` entry that this index resolves as a
  class/interface/record and NOT as a unit is moved by the writer into
  `<para>Used in classes: ...</para>`; that line is stored-only (never rendered),
  so the checker takes it out of the stored side before comparing, and the
  writer re-inserts it on every regeneration (after `Used in units:`).

  CASES:
    MOVE  an aged block (`uImpl, TThingImpl, Far.Away`) is stale + FIXABLE; the
          fix moves TThingImpl to `Used in classes:`; Far.Away (a foreign unit,
          not a class) STAYS -- negative control; uImpl stays -- positive control;
          the result is current and a second fix is byte-identical.
    KEEP  a stored `Used in classes: TForeign` (a name this index cannot see) is
          NOT drift, survives a no-op document run byte-identical, and survives a
          regeneration forced by an in-closure stale entry.

  Run from any CWD, pwsh 7. Builds its own fixture; touches no shared index.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$Exe  = (Resolve-Path $Exe).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ("dl-usedinclasses-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
$proj = Join-Path $root 'proj'
New-Item -ItemType Directory -Force -Path $proj | Out-Null
try {
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
function FactLine([string]$blk, [string]$label) {
  $m = [regex]::Match($blk, [regex]::Escape($label) + '([^<]*)</para>')
  if ($m.Success) { return $m.Groups[1].Value.Trim() } else { return $null }
}
function Reindex { $null = Run @('index','--project',$dpr,'--db',$db) }

# --- fixture ----------------------------------------------------------------
$uThing = Join-Path $proj 'uThing.pas'
WriteAscii $uThing @(
  'unit uThing;', '', 'interface', '', 'type',
  '  IThing = interface',
  '    procedure Go;',
  '  end;', '', 'implementation', '', 'end.')
WriteAscii (Join-Path $proj 'uImpl.pas') @(
  'unit uImpl;', '', 'interface', '', 'uses uThing;', '', 'type',
  '  TThingImpl = class(TInterfacedObject, IThing)',
  '  public',
  '    procedure Go;',
  '  end;', '',
  'procedure UseIt(const A: IThing);', '', 'implementation', '',
  'procedure TThingImpl.Go;', 'begin', 'end;', '',
  'procedure UseIt(const A: IThing);', 'begin', '  A.Go;', 'end;', '', 'end.')
$dpr = Join-Path $proj 'Thing.dpr'
WriteAscii $dpr @('program Thing;', 'uses', "  uThing in 'uThing.pas',", "  uImpl in 'uImpl.pas';", 'begin', 'end.')
$db = Join-Path $root 'thing.sqlite'

$r = Run @('index','--project',$dpr,'--db',$db)
Check 'setup: index built' ($r.Code -eq 0) "exit $($r.Code)"
$r = Run @('document','--unit',$uThing,'--db',$db,'--apply')
Check 'setup: fact blocks engine-written' ($r.Code -eq 0) "exit $($r.Code)"
$blk = BlockAbove $uThing 'IThing = interface'
$units0 = FactLine $blk 'Used in units:'
Check 'setup: IThing has a Used in units line naming uImpl' ($units0 -match '\buImpl\b') $blk
Check 'setup: and an Implemented by line naming TThingImpl' ((FactLine $blk 'Implemented by:') -match 'TThingImpl') $blk
Reindex
Copy-Item $uThing "$uThing.clean" -Force

# --- CASE-MOVE ----------------------------------------------------------------
# The legacy shape: a CLASS name (resolvable here) and a foreign UNIT (not in
# this closure, not a type) in the unit list.
$src = [IO.File]::ReadAllText($uThing)
$src = $src.Replace("Used in units: $units0</para>", "Used in units: $units0, TThingImpl, Far.Away</para>")
[IO.File]::WriteAllText($uThing, $src, (New-Object System.Text.ASCIIEncoding))
Check 'setup: the aged entries landed' ((FactLine (BlockAbove $uThing 'IThing = interface') 'Used in units:') -match 'TThingImpl') 'aged'
Reindex

$d = Run @('doc-drift','--qname','uThing.IThing','--db',$db)
Check 'M1 the class name in Used in units makes the block stale' ($d.Out -match 'ddFactsBlockStale') $d.Out.Trim()
Check 'M1 and the move is offered as FIXABLE' ($d.Out -match '\[FIXABLE\]') $d.Out.Trim()

$r = Run @('lint',$uThing,'--db',$db,'--project-rules','--rule','doc-drift','--fix','--apply')
$blk     = BlockAbove $uThing 'IThing = interface'
$units   = FactLine $blk 'Used in units:'
$classes = FactLine $blk 'Used in classes:'
Check 'M2 TThingImpl is gone from Used in units' ($units -notmatch 'TThingImpl') $blk
Check 'M2 TThingImpl is in Used in classes' ($classes -eq 'TThingImpl') "classes=[$classes]"
Check 'M2 POSITIVE CONTROL the real unit uImpl stays in Used in units' ($units -match '\buImpl\b') "units=[$units]"
Check 'M2 NEGATIVE CONTROL the foreign UNIT Far.Away stays in Used in units (not a class)' ($units -match 'Far\.Away') "units=[$units]"
Check 'M2 Used in classes sits directly after Used in units' ($blk -match 'Used in units:[^\n]*</para>\n\s*/// <para>Used in classes:') $blk
Check 'M2 the file is still 7-bit ASCII with CRLF' `
  ((-not ([IO.File]::ReadAllBytes($uThing) | Where-Object { $_ -gt 127 })) -and ([IO.File]::ReadAllText($uThing) -notmatch '(?<!\r)\n')) 'bytes'

Reindex
$d = Run @('doc-drift','--qname','uThing.IThing','--db',$db)
Check 'M3 checker: the moved block is current' ($d.Out -notmatch 'ddFactsBlockStale') $d.Out.Trim()
$h0 = (Get-FileHash $uThing -Algorithm MD5).Hash
$null = Run @('document','--unit',$uThing,'--db',$db,'--apply')
$null = Run @('lint',$uThing,'--db',$db,'--project-rules','--rule','doc-drift','--fix','--apply')
$h1 = (Get-FileHash $uThing -Algorithm MD5).Hash
Check 'M3 fixer: document --apply and a second --fix are byte-identical' ($h0 -eq $h1) "$h0 vs $h1"

# --- CASE-KEEP ----------------------------------------------------------------
Copy-Item "$uThing.clean" $uThing -Force
$src = [IO.File]::ReadAllText($uThing)
$src = $src.Replace("Used in units: $units0</para>", "Used in units: $units0</para>$crlf  /// <para>Used in classes: TForeign</para>")
[IO.File]::WriteAllText($uThing, $src, (New-Object System.Text.ASCIIEncoding))
Check 'setup: Used in classes injected' ((FactLine (BlockAbove $uThing 'IThing = interface') 'Used in classes:') -eq 'TForeign') 'injected'
Reindex

$d = Run @('doc-drift','--qname','uThing.IThing','--db',$db)
Check 'K1 a stored Used in classes line is not drift' ($d.Out -notmatch 'ddFactsBlockStale') $d.Out.Trim()
$h0 = (Get-FileHash $uThing -Algorithm MD5).Hash
$null = Run @('document','--unit',$uThing,'--db',$db,'--apply')
$h1 = (Get-FileHash $uThing -Algorithm MD5).Hash
Check 'K2 document --apply leaves the block byte-identical' ($h0 -eq $h1) "$h0 vs $h1"

# Force a regeneration for an unrelated, vouchable reason: uThing is indexed and
# does not use IThing, so it is a stale entry this index can reap.
$src = [IO.File]::ReadAllText($uThing)
$src = $src.Replace("Used in units: $units0</para>", "Used in units: $units0, uThing</para>")
[IO.File]::WriteAllText($uThing, $src, (New-Object System.Text.ASCIIEncoding))
Reindex
$d = Run @('doc-drift','--qname','uThing.IThing','--db',$db)
Check 'K3 CONTROL the stale uThing entry makes the block stale' ($d.Out -match 'ddFactsBlockStale') $d.Out.Trim()
$null = Run @('lint',$uThing,'--db',$db,'--project-rules','--rule','doc-drift','--fix','--apply')
$blk = BlockAbove $uThing 'IThing = interface'
Check 'K3 the fix RAN: uThing is reaped from Used in units' ((FactLine $blk 'Used in units:') -notmatch '\buThing\b') $blk
Check 'K3 Used in classes: TForeign survives the regeneration' ((FactLine $blk 'Used in classes:') -eq 'TForeign') $blk

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  if (Test-Path -LiteralPath $root) { [IO.Directory]::Delete($root, $true) }
}
