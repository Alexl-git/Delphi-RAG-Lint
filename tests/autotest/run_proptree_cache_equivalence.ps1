<#
  run_proptree_cache_equivalence.ps1 -- proptree and convert-scaffold expand a
  property tree THROUGH the per-class member cache (engine 1.20.6, tree
  redesign T2c): each class is resolved ONCE, breadth-first, and the tree is
  then EMITTED depth-first from the cache. Private and strict private members
  are pruned (owner ruling 2026-09-30); the node set is otherwise the old
  walk's, in the old order, with every key identical.

  THE DEFECT. BuildPropTree was a pure tree walk: the only cycle guard was the
  per-path visited set, so the same class was re-expanded (every member
  re-resolved with SQL) on every path it recurs on -- TFDDatSTable 327 times
  at depth 3, 1,632 at depth 4 -- and proptree on FireDAC.Comp.Client.TFDQuery
  took 45 s at depth 3, 180-376 s at depth 4 and did not finish in 20 minutes
  at depth 6.

  THE CONTRACT this guard pins:
    a  FIXTURE (self-contained). A class recurring on 3 paths, a PRIVATE
       class-typed property with a public subtree, a strict private field, a
       self-referencing class, a TComponent-typed reference, and ruling R11:
       a descendant redeclaring an ancestor's PUBLISHED property as PRIVATE
       shadows it (neither appears; convert-validate warns UNREACHABLE naming TRoot -- T2h).
       The new JSON equals the OLD engine's JSON with every private node and
       every node under a private node removed -- node for node, in ORDER, in
       every key -- and truncated is equal; text mode equal line for line.
       Compared against a golden captured from the 14396852 engine, and
       against that engine LIVE when -OldExe is given (the runner is RED while
       -OldExe is the new engine, i.e. until the private prune lands).
  REAL ARMS (skipped when -LibDb is absent; pass a COPY of library-Win64.sqlite):
    b  proptree TFDQuery --depth 3 --refs-as-leaves: node set equal to the old
       depth-4 dump (-OldDumpDir) cut to <= 4 segments, minus private; < 20 s.
    c  the same at depth 4 against the whole old depth-4 dump; < 40 s.
    d  --min-visibility public / published at depth 2: equal to the old
       depth-2 dump under the same filter, minus private.
    e  convert-scaffold Bde.DBTables.TQuery -> FireDAC.Comp.Client.TFDQuery
       (--depth 2; the old engine cannot finish depth 6 on TFDQuery): text
       equal to the old engine's (-OldExe) minus the lines that name a
       private member. Times printed.
    (f -- glyph-vacuum is pinned by run_glyph_vacuum.ps1, unchanged.)

  Run from any CWD, pwsh 7. Nothing shared is touched: fixture and indexes live
  under a $PID scratch folder that is removed at the end.
#>
[CmdletBinding()]
param(
  [string]$Exe        = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$OldExe     = '',
  [string]$WorkDir    = "$env:TEMP\drag-lint-proptree-cache-eq-$PID",
  [string]$LibDb      = '',
  [string]$OldDumpDir = ''
)
try {
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if (-not $ok) { if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }; $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if ($OldExe -and -not (Test-Path $OldExe)) { Write-Host "FATAL: -OldExe not found: $OldExe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
# One node as a line carrying EVERY key, in key order.
function NodeLine($n) {
  return ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}' -f $n.path, $n.type, $n.declared_in, $n.kind, $n.is_class_typed,
    $n.visibility, $n.is_writable, $n.member_kind, $n.has_default, $n.default_value)
}
# The node-set key the real arms compare (brief T2c: path+type+kind+visibility+member_kind+has_default+default_value).
function SetLine($n) {
  return ('{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $n.path, $n.type, $n.kind, $n.visibility, $n.member_kind, $n.has_default, $n.default_value)
}
# Old output minus private: a private node, and every node under a private node, goes.
function PrunePrivate($nodes) {
  # Hashed prefixes: a node goes when it is private or any proper prefix of its
  # path is a gone node (O(nodes x depth), not O(nodes x gone)).
  $gone = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $keep = New-Object System.Collections.Generic.List[object]
  foreach ($n in $nodes) {
    $p = [string]$n.path
    $under = $false
    $k = $p.IndexOf('.')
    while ($k -ge 0) { if ($gone.Contains($p.Substring(0, $k))) { $under = $true; break }; $k = $p.IndexOf('.', $k + 1) }
    if ($under -or ($n.visibility -eq 'private')) { [void]$gone.Add($p); continue }
    $keep.Add($n)
  }
  return $keep.ToArray()
}
function Segs([string]$p) { return ($p.Split('.')).Count }
# proptree text mode rendered from a node list (the CLI's own format).
function TextOf([string]$Root, $Nodes, [bool]$Trunc) {
  $o = New-Object System.Collections.Generic.List[string]
  $o.Add(('{0}  ({1} properties{2})' -f $Root, @($Nodes).Count, $(if ($Trunc) { ', truncated' } else { '' })))
  foreach ($n in $Nodes) {
    $p = [string]$n.path; $d = (Segs $p) - 1; $leaf = $p.Substring($p.LastIndexOf('.') + 1)
    $o.Add(('{0}{1}: {2} [{3}]' -f (' ' * ($d * 2)), $leaf, $n.type, $n.kind))
  }
  return ,$o.ToArray()
}
function RunPt([string]$E, [string]$Db, [string[]]$A) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $o = (& $E proptree @A --no-write-back --db $Db 2>$null) -join "`n"
  $sw.Stop()
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o; Sec = $sw.Elapsed.TotalSeconds }
}
function FirstDiff($a, $b) {
  $n = [Math]::Max(@($a).Count, @($b).Count)
  for ($k = 0; $k -lt $n; $k++) { if ($a[$k] -cne $b[$k]) { return "at #$k`n        want: $($a[$k])`n        got : $($b[$k])" } }
  return ''
}

# ---- a: fixture -------------------------------------------------------------
$fx = P 'fx'
New-Item -ItemType Directory $fx | Out-Null
Write-Ascii (Join-Path $fx 'CacheFix.pas') @'
unit CacheFix;

interface

uses
  Classes;

type
  // Recurs on three public paths: A, Mirror and B.Shared (and on the pruned
  // Hidden.Shared).
  TShared = class(TPersistent)
  private
    FHue: Integer;
  published
    property Hue: Integer read FHue write FHue default 7;
  end;

  // Self-referencing: Next stops at the per-path cycle guard.
  TSelfRef = class(TPersistent)
  private
    FNext: TSelfRef;
    FVal: Integer;
  published
    property Next: TSelfRef read FNext write FNext;
    property Val: Integer read FVal write FVal;
  end;

  // Reached ONLY through a private property: its public subtree must vanish.
  TSecret = class(TPersistent)
  private
    FShared: TShared;
    FDeep: Integer;
  public
    property Shared: TShared read FShared write FShared;
  published
    property Deep: Integer read FDeep write FDeep;
  end;

  TMid = class(TPersistent)
  private
    FShared: TShared;
    FLoop: TSelfRef;
  published
    property Shared: TShared read FShared write FShared;
    property Loop: TSelfRef read FLoop write FLoop;
  end;

  // A referenced component: a leaf under --refs-as-leaves, expanded otherwise.
  TRef = class(TComponent)
  private
    FCaption: string;
  published
    property Caption: string read FCaption write FCaption;
  end;

  TBase = class(TComponent)
  private
    FColor: Integer;
    FSize: Integer;
  published
    property Color: Integer read FColor write FColor;
    property Size: Integer read FSize write FSize;
  end;

  TRoot = class(TBase)
  private
    FA: TShared;
    FB: TMid;
    FC: TSelfRef;
    FSecret: TSecret;
    FRef: TRef;
    FMirror: TShared;
    // A private class-typed property with a public subtree.
    property Hidden: TSecret read FSecret write FSecret;
    // Ruling R11: a PRIVATE redeclaration of the ancestor's published Color
    // SHADOWS it -- neither appears.
    property Color;
  strict private
    FStrict: Integer;
  protected
    FProt: Integer;
  public
    PubField: Integer;
  published
    property A: TShared read FA write FA;
    property B: TMid read FB write FB;
    property C: TSelfRef read FC write FC;
    property Ref: TRef read FRef write FRef;
    property Mirror: TShared read FMirror write FMirror;
  end;

  TDst = class(TPersistent)
  private
    FTitle: Integer;
  published
    property Title: Integer read FTitle write FTitle;
  end;

implementation

end.
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $fx --db $db 2>&1
Check 'a0 the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"
$oldDb = ''
if ($OldExe) {
  $oldDb = P 'fx-old.sqlite'
  & $OldExe index $fx --db $oldDb 2>&1 | Out-Null
}

# Golden: the 14396852 engine's proptree --json on CacheFix.TRoot, minus private
# (captured 2026-09-30; NodeLine format). Variant name -> truncated + lines.
$Golden = @{
  'default' = @{ Truncated = $false; Lines = @'
A|TShared|CacheFix.TRoot|class|True|published|True|property|False|
A.Hue|Integer|CacheFix.TShared|scalar|False|published|True|property|True|7
B|TMid|CacheFix.TRoot|class|True|published|True|property|False|
B.Shared|TShared|CacheFix.TMid|class|True|published|True|property|False|
B.Shared.Hue|Integer|CacheFix.TShared|scalar|False|published|True|property|True|7
B.Loop|TSelfRef|CacheFix.TMid|class|True|published|True|property|False|
B.Loop.Next|TSelfRef|CacheFix.TSelfRef|class|True|published|True|property|False|
B.Loop.Val|Integer|CacheFix.TSelfRef|scalar|False|published|True|property|False|
C|TSelfRef|CacheFix.TRoot|class|True|published|True|property|False|
C.Next|TSelfRef|CacheFix.TSelfRef|class|True|published|True|property|False|
C.Val|Integer|CacheFix.TSelfRef|scalar|False|published|True|property|False|
Ref|TRef|CacheFix.TRoot|class|True|published|True|property|False|
Ref.Caption|string|CacheFix.TRef|scalar|False|published|True|property|False|
Mirror|TShared|CacheFix.TRoot|class|True|published|True|property|False|
Mirror.Hue|Integer|CacheFix.TShared|scalar|False|published|True|property|True|7
Size|Integer|CacheFix.TBase|scalar|False|published|True|property|False|
FProt|Integer|CacheFix.TRoot|scalar|False|protected|True|field|False|
PubField|Integer|CacheFix.TRoot|scalar|False|public|True|field|False|
'@ }
  'refs' = @{ Truncated = $false; Lines = @'
A|TShared|CacheFix.TRoot|class|True|published|True|property|False|
A.Hue|Integer|CacheFix.TShared|scalar|False|published|True|property|True|7
B|TMid|CacheFix.TRoot|class|True|published|True|property|False|
B.Shared|TShared|CacheFix.TMid|class|True|published|True|property|False|
B.Shared.Hue|Integer|CacheFix.TShared|scalar|False|published|True|property|True|7
B.Loop|TSelfRef|CacheFix.TMid|class|True|published|True|property|False|
B.Loop.Next|TSelfRef|CacheFix.TSelfRef|class|True|published|True|property|False|
B.Loop.Val|Integer|CacheFix.TSelfRef|scalar|False|published|True|property|False|
C|TSelfRef|CacheFix.TRoot|class|True|published|True|property|False|
C.Next|TSelfRef|CacheFix.TSelfRef|class|True|published|True|property|False|
C.Val|Integer|CacheFix.TSelfRef|scalar|False|published|True|property|False|
Ref|TRef|CacheFix.TRoot|class|False|published|True|property|False|
Mirror|TShared|CacheFix.TRoot|class|True|published|True|property|False|
Mirror.Hue|Integer|CacheFix.TShared|scalar|False|published|True|property|True|7
Size|Integer|CacheFix.TBase|scalar|False|published|True|property|False|
FProt|Integer|CacheFix.TRoot|scalar|False|protected|True|field|False|
PubField|Integer|CacheFix.TRoot|scalar|False|public|True|field|False|
'@ }
}

$variants = [ordered]@{
  'default' = @('--qname', 'CacheFix.TRoot', '--json')
  'refs'    = @('--qname', 'CacheFix.TRoot', '--refs-as-leaves', '--json')
  'depth1'  = @('--qname', 'CacheFix.TRoot', '--depth', '1', '--json')
  'depth2r' = @('--qname', 'CacheFix.TRoot', '--depth', '2', '--refs-as-leaves', '--json')
  'self'    = @('--qname', 'CacheFix.TSelfRef', '--json')
}
foreach ($v in $variants.Keys) {
  $n = RunPt $Exe $db $variants[$v]
  $nj = Json $n.Out
  $newLines = @($nj.properties | ForEach-Object { NodeLine $_ })
  Check "a1[$v] new proptree exits 0 and has no private node" (($n.Code -eq 0) -and ($null -ne $nj) -and `
    (@($nj.properties | Where-Object { $_.visibility -eq 'private' }).Count -eq 0)) $n.Out
  if ($Golden.ContainsKey($v)) {
    $g = @($Golden[$v].Lines -split "`r?`n" | Where-Object { $_ -ne '' })
    $d = FirstDiff $g $newLines
    Check "a2[$v] equals the golden (old engine minus private): $($g.Count) nodes, order and every key; truncated equal" `
      (($d -eq '') -and ($nj.truncated -eq $Golden[$v].Truncated)) "$d truncated=$($nj.truncated)"
  }
  if ($OldExe) {
    $o = RunPt $OldExe $oldDb $variants[$v]
    $oj = Json $o.Out
    $want = @(PrunePrivate @($oj.properties) | ForEach-Object { NodeLine $_ })
    $d = FirstDiff $want $newLines
    Check "a3[$v] equals the LIVE old engine minus private: $($want.Count) nodes, order and every key; truncated equal" `
      (($null -ne $oj) -and ($d -eq '') -and ($nj.truncated -eq $oj.truncated)) "$d new.truncated=$($nj.truncated) old.truncated=$($oj.truncated)"
    if ($v -eq 'default') { Write-Host "      golden(default):`n$(@(PrunePrivate @($oj.properties) | ForEach-Object { NodeLine $_ }) -join "`n")" -ForegroundColor DarkGray }
    if ($v -eq 'refs')    { Write-Host "      golden(refs):`n$(@(PrunePrivate @($oj.properties) | ForEach-Object { NodeLine $_ }) -join "`n")" -ForegroundColor DarkGray }
    # text mode, line for line, rendered from the old JSON minus private
    $ta = @($variants[$v] | Where-Object { $_ -ne '--json' })
    $nt = @(((RunPt $Exe $db $ta).Out -split "`r?`n") | Where-Object { $_ -ne '' })
    $wt = TextOf $oj.root_type (PrunePrivate @($oj.properties)) ([bool]$oj.truncated)
    $d = FirstDiff $wt $nt
    Check "a4[$v] text mode equals the old engine's minus private, line for line ($($wt.Count) lines)" ($d -eq '') $d
  }
}

# The fixture's own shape, spelled out (independent of any golden).
$r = RunPt $Exe $db @('--qname', 'CacheFix.TRoot', '--json')
$pj = Json $r.Out
$paths = @($pj.properties | ForEach-Object { $_.path })
Check 'a5 TShared expands on all three public paths (A.Hue, Mirror.Hue, B.Shared.Hue)' `
  (($paths -contains 'A.Hue') -and ($paths -contains 'Mirror.Hue') -and ($paths -contains 'B.Shared.Hue')) ($paths -join ',')
Check 'a6 the private property Hidden and its whole public subtree are gone' `
  (-not ($paths | Where-Object { $_ -eq 'Hidden' -or $_ -like 'Hidden.*' })) ($paths -join ',')
Check 'a7 private and strict private fields are gone; protected and public fields stay' `
  ((-not ($paths -contains 'FA')) -and (-not ($paths -contains 'FStrict')) -and ($paths -contains 'FProt') -and ($paths -contains 'PubField')) ($paths -join ',')
Check 'a8 the self-reference stops at the cycle guard (C.Next is a leaf, no C.Next.*)' `
  (($paths -contains 'C.Next') -and ($paths -contains 'C.Val') -and -not ($paths | Where-Object { $_ -like 'C.Next.*' })) ($paths -join ',')
Check 'a9 R11: the private redeclaration of Color shadows the ancestor published Color (no Color node; Size kept)' `
  ((-not ($paths -contains 'Color')) -and ($paths -contains 'Size')) ($paths -join ',')
$r = RunPt $Exe $db @('--qname', 'CacheFix.TRoot', '--refs-as-leaves', '--json')
$pj = Json $r.Out
$ref = @($pj.properties | Where-Object { $_.path -eq 'Ref' })
Check 'a10 --refs-as-leaves: Ref is a reference leaf (kind=class, is_class_typed=false, no Ref.*)' `
  (($ref.Count -eq 1) -and ($ref[0].kind -eq 'class') -and ($ref[0].is_class_typed -eq $false) -and `
   -not (@($pj.properties | Where-Object { $_.path -like 'Ref.*' }).Count)) $r.Out

$bk = P 'r11.rules'
Write-Ascii $bk "#link Title <- Color`n"
$o = (& $Exe convert-validate --rules $bk --from CacheFix.TRoot --to CacheFix.TDst --db $db 2>&1) -join "`n"
# T2h (owner ruling 2026-09-30, R12): the path EXISTS but is private -- an
# unreachable WARNING naming the descendant's private redeclaration, exit 0.
Check 'a11 R11: ResolvePath on the shadowed Color is UNREACHABLE, naming TRoot''s private Color (warning, exit 0)' `
  (($LASTEXITCODE -eq 0) -and ($o -match '(?m)^line 1: warning: Color: Color is private in CacheFix\.TRoot; never applied unless a descendant class changes its visibility\r?$') -and `
   -not ($o -match 'not found')) $o
$o = (& $Exe convert-validate --rules $bk --from CacheFix.TBase --to CacheFix.TDst --db $db 2>&1) -join "`n"
Check 'a12 R11 positive control: on TBase (no redeclaration) Color resolves' (($LASTEXITCODE -eq 0) -and ($o -match '(?m)^OK')) $o

# ---- real arms --------------------------------------------------------------
if (-not $LibDb) {
  Write-Host '  (real arms b-e skipped: pass -LibDb <COPY of library-Win64.sqlite> [-OldDumpDir] [-OldExe])' -ForegroundColor DarkGray
} else {
  if (-not (Test-Path $LibDb)) { Write-Host "FATAL: -LibDb not found: $LibDb" -ForegroundColor Red; exit 2 }
  $q = 'FireDAC.Comp.Client.TFDQuery'
  $old4 = $null
  if ($OldDumpDir) {
    $f4 = Join-Path $OldDumpDir "$q.d4.json"
    if (Test-Path $f4) { $old4 = Get-Content -Raw $f4 | ConvertFrom-Json }
  }
  foreach ($depth in 3, 4) {
    $r = RunPt $Exe $LibDb @('--qname', $q, '--depth', "$depth", '--refs-as-leaves', '--json')
    $nj = Json $r.Out
    $newSet = @($nj.properties | ForEach-Object { SetLine $_ })
    Write-Host ("  proptree $q --depth $depth : {0:N1} s, {1} nodes, truncated={2}" -f $r.Sec, $newSet.Count, $nj.truncated)
    $limit = if ($depth -eq 3) { 20 } else { 40 }
    $arm = if ($depth -eq 3) { 'b' } else { 'c' }
    Check "$arm depth $depth runs in < $limit s ($([Math]::Round($r.Sec, 1)) s)" (($r.Code -eq 0) -and ($r.Sec -lt $limit)) "exit=$($r.Code)"
    if ($null -ne $old4) {
      $src = @($old4.properties | Where-Object { (Segs $_.path) -le ($depth + 1) })
      $want = @(PrunePrivate $src | ForEach-Object { SetLine $_ })
      $missing = @([Linq.Enumerable]::Except([string[]]$want, [string[]]$newSet))
      $extra   = @([Linq.Enumerable]::Except([string[]]$newSet, [string[]]$want))
      Check "$arm node set equals the old depth-4 dump cut to depth $depth, minus private ($($want.Count) nodes)" `
        (($missing.Count -eq 0) -and ($extra.Count -eq 0) -and ($want.Count -eq $newSet.Count)) `
        ("missing={0} extra={1} first missing: {2} first extra: {3}" -f $missing.Count, $extra.Count, (($missing | Select-Object -First 3) -join ' ; '), (($extra | Select-Object -First 3) -join ' ; '))
      $d = FirstDiff $want $newSet
      Check "$arm node ORDER equals the old walk's (DFS emission from the cache)" ($d -eq '') $d
      if ($depth -eq 4) { Check 'c truncated equals the old depth-4 dump' ($nj.truncated -eq $old4.truncated) "new=$($nj.truncated) old=$($old4.truncated)" }
    }
  }
  if ($OldDumpDir -and (Test-Path (Join-Path $OldDumpDir "$q.d2.json"))) {
    $old2 = Get-Content -Raw (Join-Path $OldDumpDir "$q.d2.json") | ConvertFrom-Json
    foreach ($mv in 'public', 'published') {
      $r = RunPt $Exe $LibDb @('--qname', $q, '--depth', '2', '--refs-as-leaves', '--min-visibility', $mv, '--json')
      $nj = Json $r.Out
      $newL = @($nj.properties | ForEach-Object { NodeLine $_ })
      $ok = if ($mv -eq 'published') { @('published') } else { @('published', 'public') }
      $want = @(PrunePrivate @($old2.properties) | Where-Object { ($ok -contains $_.visibility) } | ForEach-Object { NodeLine $_ })
      $d = FirstDiff $want $newL
      Check "d --min-visibility $mv (depth 2) equals the old engine's, minus private ($($want.Count) nodes, $([Math]::Round($r.Sec, 1)) s)" `
        (($r.Code -eq 0) -and ($d -eq '')) $d
    }
  }
  if ($OldExe) {
    $sa = @('convert-scaffold', '--from', 'Bde.DBTables.TQuery', '--to', $q, '--depth', '2', '--db', $LibDb)
    $sw = [Diagnostics.Stopwatch]::StartNew(); $oldT = @((& $OldExe @sa 2>$null) -split "`r?`n"); $os = $sw.Elapsed.TotalSeconds
    $sw = [Diagnostics.Stopwatch]::StartNew(); $newT = @((& $Exe @sa 2>$null) -split "`r?`n"); $ns = $sw.Elapsed.TotalSeconds
    Write-Host ("  convert-scaffold TQuery -> TFDQuery --depth 2: old {0:N1} s, new {1:N1} s; {2} / {3} lines" -f $os, $ns, $oldT.Count, $newT.Count)
    # The private members of either side, by leaf path, from the old engine's own trees.
    $priv = New-Object System.Collections.Generic.HashSet[string]
    foreach ($qq in 'Bde.DBTables.TQuery', $q) {
      $pj = Json ((& $OldExe proptree --qname $qq --depth 2 --no-write-back --json --db $LibDb 2>$null) -join "`n")
      $gone = @($pj.properties | ForEach-Object { $_.path })
      $kept = @(PrunePrivate @($pj.properties) | ForEach-Object { $_.path })
      foreach ($p in [Linq.Enumerable]::Except([string[]]$gone, [string[]]$kept)) { [void]$priv.Add($p) }
    }
    function NamesPrivate([string]$L) {
      foreach ($m in [regex]::Matches($L, '[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*')) { if ($priv.Contains($m.Value)) { return $true } }
      return $false
    }
    $wantT = @($oldT | Where-Object { -not (NamesPrivate $_) })
    $newT2 = @($newT | Where-Object { -not (NamesPrivate $_) })
    $d = FirstDiff $wantT $newT2
    Check "e convert-scaffold text equals the old engine's minus lines naming a private member ($($wantT.Count) lines; new has $($newT.Count - $newT2.Count) such lines)" `
      (($d -eq '') -and ($newT.Count -eq $newT2.Count)) $d
  }
}

if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
} finally {
  if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
}
