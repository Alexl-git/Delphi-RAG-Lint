<#
  run_convert_book_depth.ps1 -- the `#depth N` book directive and the tree-depth
  precedence of proptree / convert-scaffold (engine 1.20.6, task T2d).

  THE CONTRACT (owner decision B, 2026-09-30):
    depth = --depth N  >  the book's `#depth N` (read via --rules FILE)  >  5.
  `#depth` takes an integer 1..10, at most one per book. Only proptree and
  convert-scaffold expand trees; convert-validate / convert-apply resolve every
  path lazily, segment by segment, so they IGNORE the value (a `#depth 1` book
  still validates a 3-segment path) -- but convert-validate still REPORTS a bad
  `#depth` as a normal `line N:` error.

  Depth is the class-recursion budget: root members are 1-segment paths and a
  K-segment path needs depth >= K-1. The fixture is a straight 7-class chain
  (TDeep.L1: TL1, TL1.L2: TL2, ... TL6.L7: TL7, each with a leaf V), so
  depth D yields paths of at most D+1 segments and the cut is exact.

  ARMS
    a  `#depth 2` + proptree --rules: 3-segment paths present, 4 absent, truncated
    b  --depth 3 beside the same --rules wins: 4-segment present, 5 absent
    c  no --rules, no --depth: exactly 5 (6-segment present, 7 absent), with a
       --depth 6 positive control that proves the chain reaches 7 segments
    d  convert-validate: `#depth 11`, `#depth x`, two `#depth` lines -> line N
       errors, exit 1; a valid `#depth 3` validates OK (control)
    e  --print-parsed lists `line L: depth 2`, never an unknown directive
    f  convert-scaffold --rules honours `#depth`; --depth still wins; the default
       (5) reaches the 4-segment leaf the book cuts off
    g  convert-validate / convert-apply ignore it: `#depth 1` still validates and
       dry-runs a 3-segment #link
    u  usage: --depth x / 0 / -1 / +3 / $A exit 2 (decimal digits only, like #depth) (proptree and convert-scaffold); a missing
       --rules file exits 2; a book whose #depth is invalid exits 2 naming the
       line; an unknown flag still exits 3

  RED 2026-09-30, the pre-change engine (33749457 copy): 9 PASS / 27 FAIL.
  `#depth` was an unknown directive, proptree / convert-scaffold ignored
  --rules, and a proptree with NO --depth ran at 3 (the global parse default),
  not the documented 6: c1 saw at most 4 segments. --depth x / 0 / -1 ran
  anyway (x -> 3, 0 and -1 -> 6). The 9 that passed are the controls and the
  arms the old default happened to satisfy (b, c4, u6 unknown flag -> 3).
  GREEN 2026-09-30, the same runner against the T2d build: 36 PASS / 0 FAIL.
  Run from a NEUTRAL CWD, pwsh 7. Every engine run passes an explicit --db.
    pwsh -File tests\autotest\run_convert_book_depth.ps1 [-Exe <engine>]
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-book-depth-$PID"
)
try {
$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false
$script:Failed = $false
$script:Pass = 0
$script:Fail = 0
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1}" -f $s, $n) -ForegroundColor $c
  if ($ok) { $script:Pass++ } else {
    $script:Fail++
    if ($d) { Write-Host "      $d" -ForegroundColor DarkGray }
    $script:Failed = $true
  }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
Write-Host ("engine : {0}" -f $Exe) -ForegroundColor Cyan

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
function P([string]$n) { return (Join-Path $WorkDir $n) }
function Book([string]$Name, [string]$Body) { Write-Ascii (P $Name) $Body; return (P $Name) }
function Json([string]$s) {
  $a = $s.IndexOf('{'); $b = $s.LastIndexOf('}')
  if ($a -lt 0 -or $b -le $a) { return $null }
  try { return ($s.Substring($a, $b - $a + 1) | ConvertFrom-Json) } catch { return $null }
}
function Segs([string]$p) { return ($p.Split('.')).Count }
function MaxSegs($paths) { $m = 0; foreach ($p in $paths) { $k = Segs $p; if ($k -gt $m) { $m = $k } }; return $m }

# ---- fixture ----------------------------------------------------------------
$fx = P 'fx'
New-Item -ItemType Directory $fx | Out-Null
Write-Ascii (Join-Path $fx 'DeepFix.pas') @'
unit DeepFix;

interface

uses
  Classes;

type
  TL7 = class(TPersistent)
  private
    FV: Integer;
  published
    property V: Integer read FV write FV;
  end;

  TL6 = class(TPersistent)
  private
    FL7: TL7;
    FV: Integer;
  published
    property L7: TL7 read FL7 write FL7;
    property V: Integer read FV write FV;
  end;

  TL5 = class(TPersistent)
  private
    FL6: TL6;
    FV: Integer;
  published
    property L6: TL6 read FL6 write FL6;
    property V: Integer read FV write FV;
  end;

  TL4 = class(TPersistent)
  private
    FL5: TL5;
    FV: Integer;
  published
    property L5: TL5 read FL5 write FL5;
    property V: Integer read FV write FV;
  end;

  TL3 = class(TPersistent)
  private
    FL4: TL4;
    FV: Integer;
  published
    property L4: TL4 read FL4 write FL4;
    property V: Integer read FV write FV;
  end;

  TL2 = class(TPersistent)
  private
    FL3: TL3;
    FV: Integer;
  published
    property L3: TL3 read FL3 write FL3;
    property V: Integer read FV write FV;
  end;

  TL1 = class(TPersistent)
  private
    FL2: TL2;
    FV: Integer;
  published
    property L2: TL2 read FL2 write FL2;
    property V: Integer read FV write FV;
  end;

  TDeep = class(TComponent)
  private
    FL1: TL1;
  published
    property L1: TL1 read FL1 write FL1;
  end;

  TDeep2 = class(TComponent)
  private
    FL1: TL1;
  published
    property L1: TL1 read FL1 write FL1;
  end;

implementation

end.
'@

Write-Ascii (Join-Path $fx 'DeepForm.pas') @'
unit DeepForm;

interface

uses
  Classes, DeepFix;

type
  TDeepForm = class(TForm)
    d1: TDeep;
  end;

implementation

{$R *.dfm}

end.
'@

Write-Ascii (Join-Path $fx 'DeepForm.dfm') @'
object DeepForm: TDeepForm
  object d1: TDeep
  end
end
'@

$db = P 'fx.sqlite'
$idx = & $Exe index $fx --db $db 2>&1
Check 'fx the fixture index was built' (($LASTEXITCODE -eq 0) -and (Test-Path $db)) "exit=$LASTEXITCODE; $($idx -join ' | ')"

function Pt([string[]]$A) {
  $o = (& $Exe proptree --qname DeepFix.TDeep --no-write-back --json --db $db @A 2>$null) -join "`n"
  $code = $LASTEXITCODE
  $j = Json $o
  $paths = if ($j) { @($j.properties | ForEach-Object { [string]$_.path }) } else { @() }
  return [pscustomobject]@{ Code = $code; Out = $o; J = $j; Paths = $paths; Max = (MaxSegs $paths) }
}
function Run([string[]]$A) {
  $o = (& $Exe @A 2>&1) -join "`n"
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}

$d2 = Book 'd2.rules' "#depth 2`n"

# ---- a: #depth 2 via --rules -------------------------------------------------
Write-Host ''
Write-Host 'a  #depth 2 read through proptree --rules' -ForegroundColor Cyan
$r = Pt @('--rules', $d2)
Check 'a1 exit 0, JSON parsed' (($r.Code -eq 0) -and ($null -ne $r.J)) $r.Out
Check 'a2 3-segment paths present (L1.L2.V, L1.L2.L3)' (($r.Paths -contains 'L1.L2.V') -and ($r.Paths -contains 'L1.L2.L3')) ($r.Paths -join ',')
Check 'a3 no 4-segment path (max segments = 3)' ($r.Max -eq 3) "max=$($r.Max)"
Check 'a4 truncated = true' (($null -ne $r.J) -and ($r.J.truncated -eq $true)) "truncated=$(if ($r.J) { $r.J.truncated })"

# ---- b: --depth wins over #depth -----------------------------------------------
Write-Host ''
Write-Host 'b  --depth 3 beside the same --rules wins' -ForegroundColor Cyan
$r = Pt @('--rules', $d2, '--depth', '3')
Check 'b1 4-segment path present (L1.L2.L3.V)' (($r.Code -eq 0) -and ($r.Paths -contains 'L1.L2.L3.V')) ($r.Paths -join ',')
Check 'b2 no 5-segment path (max segments = 4)' ($r.Max -eq 4) "max=$($r.Max)"

# ---- c: default 5 ----------------------------------------------------------------
Write-Host ''
Write-Host 'c  no --rules, no --depth: exactly 5' -ForegroundColor Cyan
$r = Pt @()
Check 'c1 6-segment path present (L1.L2.L3.L4.L5.L6)' (($r.Code -eq 0) -and ($r.Paths -contains 'L1.L2.L3.L4.L5.L6')) ($r.Paths -join ',')
Check 'c2 no 7-segment path (max segments = 6)' ($r.Max -eq 6) "max=$($r.Max)"
Check 'c3 truncated = true' (($null -ne $r.J) -and ($r.J.truncated -eq $true)) ''
$r = Pt @('--depth', '6')
Check 'c4 CONTROL --depth 6 reaches the 7-segment path (the fixture is deep enough)' `
  (($r.Code -eq 0) -and ($r.Paths -contains 'L1.L2.L3.L4.L5.L6.L7') -and ($r.Max -eq 7)) "max=$($r.Max)"
$r = Pt @('--rules', (Book 'nodepth.rules' "#note no depth here`n"))
Check 'c5 a --rules book WITHOUT #depth falls to the default 5' (($r.Code -eq 0) -and ($r.Max -eq 6)) "max=$($r.Max)"

# ---- d: convert-validate reports a bad #depth ----------------------------------
Write-Host ''
Write-Host 'd  convert-validate reports a bad #depth as a line error' -ForegroundColor Cyan
$MSG = '#depth must be an integer 1..10'
$r = Run @('convert-validate', '--rules', (Book 'd11.rules' "#depth 11`n"), '--db', $db)
Check 'd1 #depth 11 -> line 1 error, exit 1' (($r.Code -eq 1) -and ($r.Out -match [regex]::Escape("line 1: $MSG"))) $r.Out
$r = Run @('convert-validate', '--rules', (Book 'dx.rules' "#note n`n#depth x`n"), '--db', $db)
Check 'd2 #depth x -> line 2 error, exit 1' (($r.Code -eq 1) -and ($r.Out -match [regex]::Escape("line 2: $MSG"))) $r.Out
$r = Run @('convert-validate', '--rules', (Book 'd0.rules' "#depth 0`n"), '--db', $db)
Check 'd3 #depth 0 -> line 1 error, exit 1' (($r.Code -eq 1) -and ($r.Out -match [regex]::Escape("line 1: $MSG"))) $r.Out
$r = Run @('convert-validate', '--rules', (Book 'dtwo.rules' "#depth 2`n#note n`n#depth 3`n"), '--db', $db)
Check 'd4 a second #depth -> error citing the SECOND line (3), exit 1' `
  (($r.Code -eq 1) -and ($r.Out -match 'line 3: duplicate #depth \(first on line 1\)') -and -not ($r.Out -match 'line 1: ')) $r.Out
$r = Run @('convert-validate', '--rules', (Book 'd3.rules' "#depth 3`n"), '--db', $db)
Check 'd5 CONTROL a valid #depth 3 validates OK, exit 0' (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK')) $r.Out
$r = Run @('convert-validate', '--rules', (Book 'dbare.rules' "#depth`n"), '--db', $db)
Check 'd6 a bare #depth (no value) -> line 1 error, exit 1' (($r.Code -eq 1) -and ($r.Out -match [regex]::Escape("line 1: $MSG"))) $r.Out

# ---- e: --print-parsed --------------------------------------------------------------
Write-Host ''
Write-Host 'e  --print-parsed lists #depth as a rule' -ForegroundColor Cyan
$r = Run @('convert-validate', '--rules', (Book 'pp.rules' "#note first`n#depth 2`n"), '--print-parsed', '--db', $db)
Check 'e1 "line 2: depth 2" is listed, exit 0' (($r.Code -eq 0) -and ($r.Out -match '(?m)^line 2: depth 2\r?$')) $r.Out
Check 'e2 no unknown-directive error, 2 rules parsed' ((-not ($r.Out -match 'unknown directive')) -and ($r.Out -match 'parsed 2 rule\(s\)')) $r.Out

# ---- f: convert-scaffold --------------------------------------------------------------
Write-Host ''
Write-Host 'f  convert-scaffold --rules honours #depth' -ForegroundColor Cyan
$sc = @('convert-scaffold', '--from', 'DeepFix.TDeep', '--to', 'DeepFix.TDeep2', '--db', $db)
$r = Run ($sc + @('--rules', $d2))
Check 'f1 #depth 2: the 3-segment link is emitted' (($r.Code -eq 0) -and ($r.Out -match [regex]::Escape('#link L1.L2.L3 <- L1.L2.L3'))) $r.Out
Check 'f2 #depth 2: no 4-segment path anywhere' (-not ($r.Out -match 'L1\.L2\.L3\.')) $r.Out
$r = Run $sc
Check 'f3 CONTROL no --rules (default 5): the 6-segment link is emitted, no 7-segment path' `
  (($r.Code -eq 0) -and ($r.Out -match [regex]::Escape('#link L1.L2.L3.L4.L5.L6 <- L1.L2.L3.L4.L5.L6')) -and `
   -not ($r.Out -match 'L1\.L2\.L3\.L4\.L5\.L6\.')) $r.Out
$r = Run ($sc + @('--rules', $d2, '--depth', '3'))
Check 'f4 --depth 3 beside #depth 2 wins: the 4-segment link is emitted, no 5-segment path' `
  (($r.Code -eq 0) -and ($r.Out -match [regex]::Escape('#link L1.L2.L3.L4 <- L1.L2.L3.L4')) -and -not ($r.Out -match 'L1\.L2\.L3\.L4\.')) $r.Out

# ---- g: validation and conversion ignore #depth ------------------------------------
Write-Host ''
Write-Host 'g  convert-validate / convert-apply ignore #depth (lazy resolution)' -ForegroundColor Cyan
$g = Book 'g.rules' "#depth 1`n#convert DeepFix.TDeep -> DeepFix.TDeep2, DeepFix`n#link L1.L2.V <- L1.L2.V`n"
$r = Run @('convert-validate', '--rules', $g, '--from', 'DeepFix.TDeep', '--to', 'DeepFix.TDeep2', '--db', $db)
Check 'g1 convert-validate: #depth 1 still validates a 3-segment #link, exit 0' `
  (($r.Code -eq 0) -and ($r.Out -match '(?m)^OK') -and -not ($r.Out -match 'not found')) $r.Out
$o = (& $Exe convert-apply --unit (Join-Path $fx 'DeepForm.pas') --rules $g --db $db --format json 2>$null) -join "`n"
$code = $LASTEXITCODE
$j = Json $o
Check 'g2 convert-apply dry run: #depth 1 book with a 3-segment #link is ok, exit 0' `
  (($code -eq 0) -and ($null -ne $j) -and $j.ok -and -not ($o -match 'not found')) $o

# ---- u: usage errors ------------------------------------------------------------------
Write-Host ''
Write-Host 'u  usage errors' -ForegroundColor Cyan
foreach ($v in @('x', '0', '-1', '+3', '$A')) {
  $r = Run @('proptree', '--qname', 'DeepFix.TDeep', '--no-write-back', '--depth', $v, '--db', $db)
  Check "u1 proptree --depth $v -> exit 2 naming --depth" (($r.Code -eq 2) -and ($r.Out -match '--depth')) "exit=$($r.Code) $($r.Out)"
  $r = Run ($sc + @('--depth', $v))
  Check "u2 convert-scaffold --depth $v -> exit 2 naming --depth" (($r.Code -eq 2) -and ($r.Out -match '--depth')) "exit=$($r.Code) $($r.Out)"
}
$r = Run @('proptree', '--qname', 'DeepFix.TDeep', '--no-write-back', '--rules', (P 'no-such.rules'), '--db', $db)
Check 'u3 proptree --rules <missing file> -> exit 2' (($r.Code -eq 2) -and ($r.Out -match 'rules file not found')) "exit=$($r.Code) $($r.Out)"
$r = Run @('proptree', '--qname', 'DeepFix.TDeep', '--no-write-back', '--rules', (P 'd11.rules'), '--db', $db)
Check 'u4 proptree --rules <book with #depth 11> -> exit 2 naming the line' `
  (($r.Code -eq 2) -and ($r.Out -match [regex]::Escape("line 1: $MSG"))) "exit=$($r.Code) $($r.Out)"
$r = Run ($sc + @('--rules', (P 'dtwo.rules')))
Check 'u5 convert-scaffold --rules <book with two #depth> -> exit 2 naming line 3' `
  (($r.Code -eq 2) -and ($r.Out -match 'line 3: duplicate #depth')) "exit=$($r.Code) $($r.Out)"
$r = Run @('proptree', '--qname', 'DeepFix.TDeep', '--no-write-back', '--bogus-flag', '--db', $db)
Check 'u6 an unknown flag still exits 3' ($r.Code -eq 3) "exit=$($r.Code)"

Write-Host ''
Write-Host ("{0} PASS / {1} FAIL" -f $script:Pass, $script:Fail)
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; $rc = 1 } else { Write-Host 'PASS' -ForegroundColor Green; $rc = 0 }
} finally {
  try { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
exit $rc
