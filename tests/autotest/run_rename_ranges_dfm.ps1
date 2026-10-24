<#
  run_rename_ranges_dfm.ps1 -- two rename defects from the LSP review (2026-10-23).

  (1) RANGES. `rename --kind symbol --json` must report every edit AT the
      identifier it replaces: for each edit, the text at (line, col) of length
      len(old) in the named file IS `old`. The declaration edit used to carry
      the column of the `function`/`procedure`/`property` keyword (Sym.StartCol),
      so a client (CLI --json, MCP rename_symbol, LSP) got a wrong range; only
      Apply's forward scan hid it on disk. Covered shapes: global function
      (interface decl + impl header), method decl + `TFoo.Bar` impl header,
      property, field, type.

  (2) DFM EVENT BINDING (rename spec 2.2). Renaming an event handler method
      (TForm1.Button1Click) also rewrites `OnClick = Button1Click` in the
      form's text .dfm. Positive control: a NON-handler method rename leaves
      the .dfm byte-identical. A form whose .dfm is BINARY and binds the name is
      refused (exit 2, reason names the .dfm and says binary), sources unchanged.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-ranges-dfm-$PID"
)
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

$dllSrc = "$PSScriptRoot\..\..\third_party\dll-win64"
if (Test-Path $dllSrc) {
  Get-ChildItem "$dllSrc\*.dll" | ForEach-Object {
    $dst = Join-Path (Split-Path $Exe) $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
  }
}

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

$Unit1 = @'
unit Unit1;

interface

uses
  Classes;

type
  TShape1 = class
  end;

  TForm1 = class(TComponent)
  private
    FCount: Integer;
  published
    procedure Button1Click(Sender: TObject);
    procedure Helper;
    property Count: Integer read FCount;
  end;

function Compute(A: Integer): Integer;

implementation

function Compute(A: Integer): Integer;
begin
  Result:= A;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  S: TShape1;
begin
  S:= nil;
  Helper;
  FCount:= Compute(FCount) + Count;
end;

procedure TForm1.Helper;
begin
end;

end.
'@

$Dfm1 = @'
object Form1: TForm1
  Left = 0
  Top = 0
  object Button1: TButton
    Left = 8
    OnClick = Button1Click
  end
end
'@

$Unit2 = @'
unit Unit2;

interface

uses
  Classes;

type
  TForm2 = class(TComponent)
  published
    procedure Button2Click(Sender: TObject);
  end;

implementation

procedure TForm2.Button2Click(Sender: TObject);
begin
end;

end.
'@

function New-Fixture([string]$Name) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  Write-Ascii (Join-Path $src 'Unit1.pas') $Unit1
  Write-Ascii (Join-Path $src 'Unit1.dfm') $Dfm1
  Write-Ascii (Join-Path $src 'Unit2.pas') $Unit2
  # A BINARY dfm (resource header + TPF0 stream) whose OnClick binds Button2Click.
  $ms = New-Object System.IO.MemoryStream
  $w  = New-Object System.IO.BinaryWriter($ms)
  $w.Write([byte[]](0xFF, 0x0A, 0x00)); $w.Write([Text.Encoding]::ASCII.GetBytes("TFORM2")); $w.Write([byte]0)
  $w.Write([byte[]](0x30, 0x10)); $w.Write([int32]0)
  $w.Write([Text.Encoding]::ASCII.GetBytes('TPF0'))
  $w.Write([byte]6); $w.Write([Text.Encoding]::ASCII.GetBytes('TForm2'))
  $w.Write([byte]5); $w.Write([Text.Encoding]::ASCII.GetBytes('Form2'))
  $w.Write([byte]7); $w.Write([Text.Encoding]::ASCII.GetBytes('OnClick'))
  $w.Write([byte]7); $w.Write([byte]12); $w.Write([Text.Encoding]::ASCII.GetBytes('Button2Click'))
  $w.Write([byte[]](0, 0)); $w.Flush()
  [IO.File]::WriteAllBytes((Join-Path $src 'Unit2.dfm'), $ms.ToArray())
  $db = Join-Path $dir 'idx.sqlite'
  Push-Location $dir
  try { & $Exe index $src --db $db 2>&1 | Out-Null } finally { Pop-Location }
  Check "$Name index exits 0" ($LASTEXITCODE -eq 0)
  [pscustomobject]@{ Dir = $dir; Src = $src; Db = $db }
}

function Snapshot($fx) {
  (Get-ChildItem $fx.Src -File | Where-Object { $_.Extension -ne '.bak' } | Sort-Object Name |
    ForEach-Object { $_.Name + '=' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName)) }) -join '|'
}

function Run-Rename($fx, [string[]]$RenameArgs) {
  Push-Location $fx.Dir
  try { $o = & $Exe rename @RenameArgs --db $fx.Db 2>&1 } finally { Pop-Location }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($o -join "`n") }
}

# Every edit's (line, col, len(old)) slice of its file must BE old.
function Check-Ranges([string]$Label, $Out) {
  $edits = $null
  try { $edits = @($Out | ConvertFrom-Json) } catch { }
  Check "$Label --json parses to edits" ($null -ne $edits -and $edits.Count -gt 0) "count=$(@($edits).Count)"
  if ($null -eq $edits) { return @() }
  foreach ($e in $edits) {
    $lines = [IO.File]::ReadAllLines($e.file, [Text.Encoding]::ASCII)
    $txt = ''
    if ($e.line -ge 1 -and $e.line -le $lines.Count) {
      $ln = $lines[$e.line - 1]
      if ($e.col -ge 1 -and ($e.col - 1 + $e.old.Length) -le $ln.Length) { $txt = $ln.Substring($e.col - 1, $e.old.Length) }
    }
    Check ("$Label range {0}:{1}:{2} replaces '{3}'" -f (Split-Path -Leaf $e.file), $e.line, $e.col, $e.old) ($txt -ceq $e.old) "found='$txt'"
  }
  return $edits
}

# ---------------- (1) ranges ----------------
Write-Host 'Fixture R: --json ranges equal the name token' -ForegroundColor Cyan
$r1 = New-Fixture 'R'
$cases = @(
  @{ Q = 'Unit1.Compute';        To = 'Compute2'; MinEdits = 3 },  # iface decl + impl header + call
  @{ Q = 'Unit1.TForm1.Helper';  To = 'Helper2';  MinEdits = 3 },  # decl + impl header + call
  @{ Q = 'Unit1.TForm1.Count';   To = 'Count2';   MinEdits = 2 },  # property decl + use
  @{ Q = 'Unit1.TForm1.FCount';  To = 'FCount2';  MinEdits = 2 },  # field decl + uses
  @{ Q = 'Unit1.TShape1';        To = 'TShape2';  MinEdits = 2 }   # type decl + var use
)
foreach ($c in $cases) {
  $r = Run-Rename $r1 @('--kind', 'symbol', '--name', $c.Q, '--to', $c.To, '--json')
  Check "$($c.Q) --json exits 0" ($r.Exit -eq 0) "exit=$($r.Exit)"
  $ed = Check-Ranges $c.Q $r.Out
  Check "$($c.Q) has >= $($c.MinEdits) edits" (@($ed).Count -ge $c.MinEdits) "count=$(@($ed).Count)"
}

# ---------------- (2) dfm handler rename ----------------
Write-Host 'Fixture H: handler rename rewrites the text .dfm binding' -ForegroundColor Cyan
$h = New-Fixture 'H'
$r = Run-Rename $h @('--kind', 'symbol', '--name', 'Unit1.TForm1.Button1Click', '--to', 'OkClick', '--json')
Check 'handler --json exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
$ed = Check-Ranges 'handler' $r.Out
Check 'handler --json carries a Unit1.dfm edit' (@($ed | Where-Object { $_.file -like '*Unit1.dfm' }).Count -eq 1)
$r = Run-Rename $h @('--kind', 'symbol', '--name', 'Unit1.TForm1.Button1Click', '--to', 'OkClick', '--apply', '--no-backup')
Check 'handler --apply exits 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
$dfm = Get-Content -Raw (Join-Path $h.Src 'Unit1.dfm')
$pas = Get-Content -Raw (Join-Path $h.Src 'Unit1.pas')
Check 'dfm binding is OnClick = OkClick'       ($dfm -cmatch 'OnClick = OkClick\r\n')
Check 'no stale Button1Click in dfm'           (-not ($dfm -cmatch 'Button1Click'))
Check 'pas decl renamed'                       ($pas -cmatch 'procedure OkClick\(Sender: TObject\);')
Check 'pas impl header renamed'                ($pas -cmatch 'procedure TForm1\.OkClick\(Sender: TObject\);')
Check 'dfm still CRLF, no lone LF'             (-not ($dfm -match '[^\r]\n'))

Write-Host 'Fixture N: non-handler rename leaves the .dfm untouched (positive control)' -ForegroundColor Cyan
$n = New-Fixture 'N'
$dfmBefore = [IO.File]::ReadAllBytes((Join-Path $n.Src 'Unit1.dfm'))
$r = Run-Rename $n @('--kind', 'symbol', '--name', 'Unit1.TForm1.Helper', '--to', 'Helper2', '--apply', '--no-backup')
Check 'non-handler --apply exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
$dfmAfter = [IO.File]::ReadAllBytes((Join-Path $n.Src 'Unit1.dfm'))
Check 'dfm byte-identical' ([Convert]::ToBase64String($dfmBefore) -ceq [Convert]::ToBase64String($dfmAfter))
Check 'pas Helper renamed' ((Get-Content -Raw (Join-Path $n.Src 'Unit1.pas')) -cmatch 'procedure TForm1\.Helper2;')

Write-Host 'Fixture B: handler bound in a BINARY .dfm is refused' -ForegroundColor Cyan
$b = New-Fixture 'B'
$before = Snapshot $b
foreach ($f in @(
    @{ N = '--kind symbol --json';  A = @('--kind', 'symbol', '--name', 'Unit2.TForm2.Button2Click', '--to', 'GoClick', '--json') },
    @{ N = '--kind symbol --apply'; A = @('--kind', 'symbol', '--name', 'Unit2.TForm2.Button2Click', '--to', 'GoClick', '--apply') },
    @{ N = 'legacy --qname';        A = @('--qname', 'Unit2.TForm2.Button2Click', '--to', 'GoClick') })) {
  $r = Run-Rename $b $f.A
  Check "B $($f.N) exits 2"         ($r.Exit -eq 2)                "exit=$($r.Exit)"
  Check "B $($f.N) names Unit2.dfm" ($r.Out -match 'Unit2\.dfm')   ($r.Out -split "`n" | Select-Object -Last 1)
  Check "B $($f.N) says binary"     ($r.Out -match '(?i)binary')
}
Check 'B sources unchanged' ((Snapshot $b) -ceq $before)
# Positive control: a method of the same unit the binary dfm does NOT bind is not refused.
$r = Run-Rename $b @('--kind', 'symbol', '--name', 'Unit1.TForm1.Helper', '--to', 'Helper2', '--json')
Check 'B unrelated rename not refused' ($r.Exit -eq 0) "exit=$($r.Exit)"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-rename-ranges-dfm-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
