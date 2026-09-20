<#
  run_forward_stub_is_not_a_class.ps1 -- a forward declaration is NOT a class.

  Spec: docs\superpowers\specs\2026-09-17-forward-stub-is-not-a-class-design.md
  Owner ruling 2026-09-16: "Account only for the real one and ignore the forward
  declaration. If someone hovers over the stub, show a link to the real one; if
  AI or a user searches, return the real one."

  MEASURED BEFORE THE FIX (engine 1.15.0-alpha): `query --name TFoo --exact`
  printed two identical-looking rows; `hover --qname fw.TFoo` picked the stub
  and rendered nothing but the name; ClassMetrics anchored too-many-children on
  the stub's line.

  CASES (each task of the plan adds its block; S-numbers are the spec's EARS
  criteria):
    A  query --exact --json / text    S1 S2 S3 S7 + RED CONTROL (real TFoo removed)
    B  hover --qname + LSP hover      S4
    C  lint-all too-many-children     S5
    D  outline text/json              S6

  POSITIVE CONTROLS. TOnlyStub (lone stub) and TEmpty (empty class) must each
  come back ONCE and count as classes -- the ruling's own control ("a class
  with NO full declaration in the unit is still a class"). The RED fixture
  drops the real TFoo: forward_line must then be ABSENT, which is what makes
  the S1 assertion capable of failing.

  `sql --json` rows are POSITIONAL -- this guard never reads them; every JSON it
  parses is a `query`/`outline`/`hover` object array with named fields.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_fwdstub_guard"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
# `query`/`outline` print a trailing "(loaded defaults ...)" note on stderr and
# may print a stale-index note; take stdout only and cut at the last ']'.
function ParseJsonArray([string]$raw) {
  $end = $raw.LastIndexOf(']')
  if ($end -lt 0) { return @() }
  return @($raw.Substring(0, $end + 1) | ConvertFrom-Json)
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
Write-Host ("engine: " + (& $Exe --version 2>$null | Select-Object -First 1))

if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$srcDir = Join-Path $WorkDir 'src';     New-Item -ItemType Directory $srcDir | Out-Null
$redDir = Join-Path $WorkDir 'src_red'; New-Item -ItemType Directory $redDir | Out-Null

# ---------------------------------------------------------------- fixture ----
# One unit: a class stub + real (TFoo), an interface stub + real (IFoo), a lone
# stub (TOnlyStub), an empty class (TEmpty), a consumer referencing TFoo BEFORE
# its real declaration, and 11 kids of TFoo so too-many-children (threshold 10)
# fires on exactly one class in CASE C.
$kids = (1..11 | ForEach-Object { "  TKid$_ = class(TFoo)`n  end;" }) -join "`n"
$fixture = @"
unit fwstub;

interface

type
  TFoo = class;
  IFoo = interface;
  TOnlyStub = class;
  TEmpty = class end;

  TConsumer = class
  private
    FOwner: TFoo;
  public
    property Owner: TFoo read FOwner;
  end;

  TFoo = class(TObject)
  private
    FValue: Integer;
  public
    procedure Bump;
    property Value: Integer read FValue;
  end;

  IFoo = interface
    ['{5D1B2C3E-0F47-4A8B-9C2D-1E3F4A5B6C7D}']
    procedure Ping;
  end;

$kids

implementation

procedure TFoo.Bump;
begin
  Inc(FValue);
end;

end.
"@
WriteAnsi (Join-Path $srcDir 'fwstub.pas') $fixture
# RED fixture: the real TFoo is gone (and so are its kids, which would not compile
# without it) -- the stub is now a LONE stub and must come back as a class.
$red = @"
unit fwstub;

interface

type
  TFoo = class;
  IFoo = interface;
  TOnlyStub = class;
  TEmpty = class end;

  TConsumer = class
  private
    FOwner: TFoo;
  public
    property Owner: TFoo read FOwner;
  end;

  IFoo = interface
    ['{5D1B2C3E-0F47-4A8B-9C2D-1E3F4A5B6C7D}']
    procedure Ping;
  end;

implementation

end.
"@
WriteAnsi (Join-Path $redDir 'fwstub.pas') $red

$lines = [System.IO.File]::ReadAllLines((Join-Path $srcDir 'fwstub.pas'))
function Line1Of([string]$needle) {   # 1-based line of the first line containing $needle
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($needle)) { return $i + 1 } }
  return -1
}
$stubLine     = Line1Of 'TFoo = class;'
$realLine     = Line1Of 'TFoo = class(TObject)'
$iStubLine    = Line1Of 'IFoo = interface;'
# the real interface's line is 'IFoo = interface' with NO semicolon -- a Contains()
# probe would hit the stub first, so match the trimmed line exactly
$iRealLine = -1
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq 'IFoo = interface') { $iRealLine = $i + 1; break } }
$onlyStubLine = Line1Of 'TOnlyStub = class;'
$emptyLine    = Line1Of 'TEmpty = class end;'
$consumerLine = Line1Of 'FOwner: TFoo;'
Check 'fixture anchors located' (($stubLine -gt 0) -and ($realLine -gt $stubLine) -and ($iStubLine -gt 0) -and ($iRealLine -gt $iStubLine) -and ($onlyStubLine -gt 0) -and ($emptyLine -gt 0)) `
  "stub=$stubLine real=$realLine istub=$iStubLine ireal=$iRealLine only=$onlyStubLine empty=$emptyLine"
if ($script:Failed) { Write-Host 'FAIL (fixture)' -ForegroundColor Red; exit 1 }

$db    = Join-Path $WorkDir 'fw.sqlite'
$dbRed = Join-Path $WorkDir 'fw_red.sqlite'
Push-Location $WorkDir
try {
  & $Exe index $srcDir --db $db    2>&1 | Out-Null
  & $Exe index $redDir --db $dbRed 2>&1 | Out-Null
  Check 'both indexes built' ((Test-Path $db) -and (Test-Path $dbRed))

  # ============================================================= CASE A =====
  Write-Host ''
  Write-Host 'CASE A: query --exact folds the stub into the real declaration' -ForegroundColor Cyan
  $foo = @(ParseJsonArray ((& $Exe query --name TFoo --exact --json --db $db 2>$null | Out-String)) | Where-Object { $_.qualified_name -eq 'fwstub.TFoo' })
  Check 'S1: exactly ONE fwstub.TFoo row' ($foo.Count -eq 1) "rows=$($foo.Count)"
  if ($foo.Count -ge 1) {
    Check 'S1: the row is the REAL declaration'   ($foo[0].start_line -eq $realLine) "start_line=$($foo[0].start_line) real=$realLine"
    Check 'S1: forward_line = the stub''s line'   ($foo[0].forward_line -eq $stubLine) "forward_line=$($foo[0].forward_line) stub=$stubLine"
    Check 'S1: heritage survives (it is the real row)' ($foo[0].heritage -eq 'TObject') "heritage=$($foo[0].heritage)"
  }
  $ifoo = @(ParseJsonArray ((& $Exe query --name IFoo --exact --json --db $db 2>$null | Out-String)) | Where-Object { $_.qualified_name -eq 'fwstub.IFoo' })
  Check 'S7: exactly ONE fwstub.IFoo row' ($ifoo.Count -eq 1) "rows=$($ifoo.Count)"
  if ($ifoo.Count -ge 1) {
    Check 'S7: kind interface, the real row'     (($ifoo[0].kind -eq 'interface') -and ($ifoo[0].start_line -eq $iRealLine)) "kind=$($ifoo[0].kind) start_line=$($ifoo[0].start_line)"
    Check 'S7: forward_line = the interface stub''s line' ($ifoo[0].forward_line -eq $iStubLine) "forward_line=$($ifoo[0].forward_line)"
  }
  $only = @(ParseJsonArray ((& $Exe query --name TOnlyStub --exact --json --db $db 2>$null | Out-String)))
  Check 'S2 POSITIVE CONTROL: lone TOnlyStub returned once, as a class' (($only.Count -eq 1) -and ($only[0].kind -eq 'class')) "rows=$($only.Count)"
  if ($only.Count -ge 1) { Check 'S2: no forward_line on a lone stub' (($null -eq $only[0].forward_line) -or ($only[0].forward_line -eq 0)) "forward_line=$($only[0].forward_line)" }
  $empty = @(ParseJsonArray ((& $Exe query --name TEmpty --exact --json --db $db 2>$null | Out-String)))
  Check 'S3 POSITIVE CONTROL: TEmpty returned once, as a class' (($empty.Count -eq 1) -and ($empty[0].kind -eq 'class')) "rows=$($empty.Count)"
  if ($empty.Count -ge 1) { Check 'S3: no forward_line on an empty class' (($null -eq $empty[0].forward_line) -or ($empty[0].forward_line -eq 0)) }
  # qualified-name path (hover, document, refactor use this one)
  $q = @(ParseJsonArray ((& $Exe query --qname fwstub.TFoo --exact --json --db $db 2>$null | Out-String)) | Where-Object { $_.qualified_name -eq 'fwstub.TFoo' })
  Check 'S1 via --qname: one row, the real one, forward_line set' (($q.Count -eq 1) -and ($q[0].start_line -eq $realLine) -and ($q[0].forward_line -eq $stubLine)) "rows=$($q.Count)"
  # text table
  $txt = (& $Exe query --name TFoo --exact --db $db 2>$null | Out-String)
  $fooLines = @($txt -split "`r?`n" | Where-Object { $_ -match '\bfwstub\.TFoo\b' -and $_ -notmatch 'fwstub\.TFoo\.' })
  Check 'text: one fwstub.TFoo row' ($fooLines.Count -eq 1) "rows=$($fooLines.Count)"
  if ($fooLines.Count -ge 1) { Check "text: row ends with 'forward at line $stubLine'" ($fooLines[0] -match "forward at line $stubLine\s*$") "got: [$($fooLines[0])]" }
  $txtEmpty = (& $Exe query --name TEmpty --exact --db $db 2>$null | Out-String)
  Check 'text: no forward marker on TEmpty' ($txtEmpty -notmatch 'forward at line')

  # RED CONTROL -- the real TFoo removed: the stub is now LONE and must be a class
  Write-Host ''
  Write-Host 'CASE A-red: without the real TFoo the stub is a lone stub (S2), so S1 would go red here' -ForegroundColor Cyan
  $redFoo = @(ParseJsonArray ((& $Exe query --name TFoo --exact --json --db $dbRed 2>$null | Out-String)) | Where-Object { $_.qualified_name -eq 'fwstub.TFoo' })
  Check 'red: one fwstub.TFoo row (the stub itself)' ($redFoo.Count -eq 1) "rows=$($redFoo.Count)"
  if ($redFoo.Count -ge 1) {
    Check 'red: it is the stub line'               ($redFoo[0].start_line -eq $stubLine)
    Check 'red: forward_line ABSENT (nothing to fold into)' (($null -eq $redFoo[0].forward_line) -or ($redFoo[0].forward_line -eq 0)) "forward_line=$($redFoo[0].forward_line)"
  }
}
finally { Pop-Location }

# ---- CASE B / C / D are appended by Tasks 3-5 ABOVE this footer ----
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
