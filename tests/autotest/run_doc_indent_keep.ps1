<#
  run_doc_indent_keep.ps1 -- a `///` block that sits DIRECTLY on its declaration
  (no gap) and is indented DEEPER than it keeps its own indent (1.20.6, Task 5).

  Owner ruling 2026-09-30: "when a /// block sits DIRECTLY on its declaration
  (no gap) and is indented DEEPER than it, keep the block's own first-line
  indent; every other case keeps the declaration's indent". The writer
  (Document.pas) and the checker (Drift.pas) share ONE decision
  (TDocFacts.EffectiveDocIndent), or drift never settles.

  ARMS
    K1  a column-0 `procedure KeepDirect;` with a TWO-space block directly above
        it and a caller: after document --apply every /// line of the block is
        still at exactly two spaces; cycles 2 and 3 are edits=0 / byte-identical;
        lint --rule doc-drift reports 0.
    K2  a mixed-indent block (first line at six, rest at four, declaration at
        four) is NOT a kept block: the declaration's indent wins (this is the
        run_doc_p3_indent ResidualMember pin, restated here at the unit level).
    K4  doc-drift over a LOCKED source file does not crash (fail-safe width 0).
    K3  a wrapped fact line in such a block: `type TC = class end;` at column 0
        with a two-space block directly above, 200 callers in a dl:shared unit.
        document --apply keeps the two-space indent, every physical line is
        <= 1000 characters WITH that indent, doc-drift reports 0, a second
        apply is a no-op.

  Explicit --db everywhere; scratch copies only; nothing touches a real DB.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-indent-keep-$PID"
)
$ownWorkDir = -not $PSBoundParameters.ContainsKey('WorkDir')
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
$FACT_MAX = 1000
$CALLERS  = 200

if (Test-Path $WorkDir) { Remove-Item -Recurse -Force -LiteralPath $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function Run([string[]]$xs) { $o = & $Exe @xs 2>&1 | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
function RunJson([string[]]$xs) { (& $Exe @xs 2>$null | Out-String) }
function LastLine([string]$s) { ($s.Trim() -split "`n" | Select-Object -Last 1) }
function MaxLineLen([string]$Path) {
  $m = 0; foreach ($l in [IO.File]::ReadAllLines($Path)) { if ($l.Length -gt $m) { $m = $l.Length } }; return $m
}
function Get-Indent([string]$s) { return $s.Substring(0, $s.Length - $s.TrimStart().Length) }
function DriftCount([string]$Json) {
  try { return @(ConvertFrom-Json $Json | Where-Object { $_.rule -eq 'doc-drift' }).Count } catch { return -1 }
}
# The contiguous /// run directly above the first line matching $declPattern, RAW.
function Get-Block([string[]]$lines, [string]$declPattern) {
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -cmatch $declPattern) { $idx = $i; break } }
  if ($idx -lt 0) { return @() }
  $acc = New-Object System.Collections.Generic.List[string]
  for ($i = $idx - 1; $i -ge 0; $i--) {
    if ($lines[$i] -notmatch '^\s*///') { break }
    $acc.Insert(0, $lines[$i])
  }
  return $acc.ToArray()
}
function Cycle([string]$dpr, [string]$db, [string]$unit, [string]$qname) {
  $null = Run @('index', '--project', $dpr, '--db', $db)
  $r = Run @('document', '--qname', $qname, '--db', $db, '--apply', '--no-backup', '--json')
  $a = '?'; if ($r.Out -match '"action":"(\w+)"') { $a = $Matches[1] }
  $e = -1;  if ($r.Out -match '"edits":(\d+)')    { $e = [int]$Matches[1] }
  return [pscustomobject]@{ Action = $a; Edits = $e; Code = $r.Code; Md5 = (Get-FileHash $unit -Algorithm MD5).Hash }
}

Write-Host 'indent keep (T5)' -ForegroundColor Cyan

# ------------------------------------------------------------------ K1 / K2 ---
$u1 = Join-Path $WorkDir 'Keep.pas'
$d1 = Join-Path $WorkDir 'K.dpr'
$b1 = Join-Path $WorkDir 'k.sqlite'
Write-Ascii $u1 @'
unit Keep;

interface

  /// <summary>Two-space block directly above a column-0 declaration.</summary>
procedure KeepDirect;

type
  TMixed = class
  public
      /// <value>Mixed block: first line deeper than the rest.</value>
    /// <summary>Declaration indent wins for a mixed block.</summary>
    procedure MixedMember;
  end;

procedure CallsKeep;

implementation

procedure KeepDirect;
begin
end;

procedure TMixed.MixedMember;
begin
end;

procedure CallsKeep;
var M: TMixed;
begin
  KeepDirect;
  M.MixedMember;
end;

end.
'@
Write-Ascii $d1 "program K;`n`n{`$APPTYPE CONSOLE}`n`nuses Keep in 'Keep.pas';`n`nbegin`nend.`n"
$c = @(); foreach ($i in 1..3) { $c += Cycle $d1 $b1 $u1 'Keep.KeepDirect' }
Check 'K1: document --apply exits 0 on every cycle' ((@($c | Where-Object { $_.Code -ne 0 }).Count) -eq 0) (($c | ForEach-Object { "$($_.Action)/$($_.Edits)" }) -join ' ')
$blk = Get-Block ([IO.File]::ReadAllLines($u1)) '^procedure KeepDirect;'
Check 'K1: POSITIVE CONTROL -- the block is still there and was written by the engine' (($blk.Count -ge 2) -and (($blk -join "`n") -match 'drag-lint:auto')) ($blk -join ' | ')
$bad = @($blk | Where-Object { (Get-Indent $_) -cne '  ' })
Check 'K1: EVERY /// line of the block sits at exactly two spaces' (($blk.Count -gt 0) -and ($bad.Count -eq 0)) ($blk -join ' | ')
Check 'K1: cycles 2 and 3 are edits=0 and byte-identical to cycle 1' (($c[1].Edits -eq 0) -and ($c[2].Edits -eq 0) -and ($c[1].Md5 -eq $c[0].Md5) -and ($c[2].Md5 -eq $c[0].Md5)) (($c | ForEach-Object { "$($_.Action)/$($_.Edits)" }) -join ' ')
$null = Run @('index', '--project', $d1, '--db', $b1)
Check 'K1: lint --rule doc-drift reports 0' ((DriftCount (RunJson @('lint', $u1, '--db', $b1, '--rule', 'doc-drift', '--project-rules', '--json'))) -eq 0)

$cm = @(); foreach ($i in 1..2) { $cm += Cycle $d1 $b1 $u1 'Keep.TMixed.MixedMember' }
$blkm = Get-Block ([IO.File]::ReadAllLines($u1)) '^    procedure MixedMember;'
$badm = @($blkm | Where-Object { (Get-Indent $_) -cne '    ' })
Check 'K2: a mixed-indent block lands at the DECLARATION indent (four spaces)' (($blkm.Count -gt 0) -and ($badm.Count -eq 0)) ($blkm -join ' | ')
Check 'K2: the next cycle is a no-op' ($cm[1].Edits -eq 0) "$($cm[1].Action)/$($cm[1].Edits)"

# --------------------------------------------------------------------- K3 -----
$db3 = Join-Path $WorkDir 'k3.sqlite'
$u3  = Join-Path $WorkDir 'S2.pas'
$d3  = Join-Path $WorkDir 'K3.dpr'
Write-Ascii $u3 "unit S2;   // dl:shared ProjA, ProjB`n`ninterface`n`n  /// <summary>Two-space block, column-0 type.</summary>`ntype TC = class end;`n`nimplementation`n`nend.`n"
$decls = (1..$CALLERS | ForEach-Object { 'procedure Pqqqqqqq{0:D3};' -f $_ }) -join "`n"
$impls = (1..$CALLERS | ForEach-Object { 'procedure Pqqqqqqq{0:D3}; var L: TC; begin L:= nil; L.Free; end;' -f $_ }) -join "`n"
Write-Ascii (Join-Path $WorkDir 'Caller2.pas') "unit Caller2;`n`ninterface`n`n$decls`n`nimplementation`n`nuses S2;`n`n$impls`n`nend.`n"
Write-Ascii $d3 "program K3;`n`n{`$APPTYPE CONSOLE}`n`nuses S2 in 'S2.pas', Caller2 in 'Caller2.pas';`n`nbegin`nend.`n"
$null = Run @('index', '--project', $d3, '--db', $db3)
$r = Run @('document', '--unit', $u3, '--db', $db3, '--apply', '--no-backup')
$l3 = [IO.File]::ReadAllLines($u3)
$blk3 = Get-Block $l3 '^type TC = class end;'
$bad3 = @($blk3 | Where-Object { (Get-Indent $_) -cne '  ' })
Check 'K3: POSITIVE CONTROL -- the block is wrapped over several lines' ($blk3.Count -gt 4) "$($blk3.Count) lines; $(LastLine $r.Out)"
Check 'K3: EVERY /// line keeps two spaces' (($blk3.Count -gt 0) -and ($bad3.Count -eq 0)) ($blk3 -join ' | ').Substring(0, [Math]::Min(200, ($blk3 -join ' | ').Length))
$m3 = MaxLineLen $u3
Check "K3: every physical line (kept indent included) is <= $FACT_MAX" ($m3 -le $FACT_MAX) "max $m3"
$null = Run @('index', '--project', $d3, '--db', $db3)
Check 'K3: lint --rule doc-drift reports 0' ((DriftCount (RunJson @('lint', $u3, '--db', $db3, '--rule', 'doc-drift', '--project-rules', '--json'))) -eq 0)
$h = (Get-FileHash $u3).Hash
$null = Run @('document', '--unit', $u3, '--db', $db3, '--apply', '--no-backup')
Check 'K3: a second document --apply is a no-op' ((Get-FileHash $u3).Hash -eq $h)

# --------------------------------------------------------------------- K4 -----
# An unreadable source file must never crash drift (fail-safe: no indent to
# measure -> width 0). HONEST SCOPE: lint opens the file itself before drift
# runs, so over the CLI a LOCKED file stops lint with the engine's own clean
# FATAL line (exit 3, the engine's own top-level handler) and the catch in Drift.FileLinesCached is not reached; what
# this arm pins is that neither a locked nor a vanished unit takes the process
# down with an unhandled exception. The catch itself is a plain `except` (every
# exception class), matching the pre-1.20.6 ReadDeclLineRaw.
$null = Run @('index', '--project', $d1, '--db', $b1)
$fs = [System.IO.File]::Open($u1, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
try {
  $r4 = Run @('lint-all', '--db', $b1, '--rule', 'doc-drift', '--project-rules', '--json')
} finally { $fs.Dispose() }
Check 'K4: doc-drift over a LOCKED source file ends cleanly (exit 0, 1 or the engine error 3)' (@(0, 1, 3) -contains $r4.Code) "exit $($r4.Code); $(LastLine $r4.Out)"
Check 'K4: ...with no unhandled exception text' ($r4.Out -notmatch 'Access violation|Unhandled|Runtime error') (LastLine $r4.Out)
$moved = "$u1.moved"
Move-Item -LiteralPath $u1 -Destination $moved
try {
  $r4b = Run @('lint-all', '--db', $b1, '--rule', 'doc-drift', '--project-rules', '--json')
} finally { Move-Item -LiteralPath $moved -Destination $u1 }
Check 'K4b: doc-drift over a VANISHED source file ends cleanly' ((@(0, 1, 3) -contains $r4b.Code) -and ($r4b.Out -notmatch 'Access violation|Unhandled|Runtime error')) "exit $($r4b.Code); $(LastLine $r4b.Out)"
Write-Host ''
if ($script:Failed) { Write-Host 'run_doc_indent_keep: FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'run_doc_indent_keep: OK' -ForegroundColor Green
exit 0
} finally {
  if ($ownWorkDir -and (Test-Path -LiteralPath $WorkDir)) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
