<#
  run_rename_dfm_skipped.ps1 -- rename REPORTS the form files it leaves alone
  (W5-D item 4, 2026-10-25; follow-up of W4-ren / X-25).

  THE DEFECT. Renaming an event handler rewrites `OnClick = Name` only in TEXT
  .dfm files the index holds (refs rows). The owner form's own BINARY .dfm is
  refused (BinaryDfmReason), but a descendant form's binary .dfm, or a text
  .dfm the index does not hold, was skipped SILENTLY: the rename reported
  success and the form kept the old name (runtime "property does not exist").

  CONTRACT: TRenameRefactoring.SkippedDfmNotes lists them; the CLI prints one
  `drag-lint: note: <file> ...` line per file on STDERR (stdout -- the edit
  list or the --json array -- is unchanged) and exits as before (0); MCP
  rename_symbol carries them in "skipped_dfm".

  FIXTURE (generated here): TForm1.Button1Click bound in text Unit1.dfm.
    Unit3  TForm3 = class(TForm1), BINARY .dfm binding Button1Click -> noted
    Unit4  TForm4 = class(TForm1), text .dfm added AFTER indexing   -> noted
    Unit6  TForm6 = class(TForm1), text .dfm, indexed               -> rewritten, not noted
    Unit5  TForm5 = class(TComponent), BINARY .dfm with the name    -> not related, not noted
  CONTROL: renaming TForm1.Helper (in no .dfm) prints no note.

  RED-CHECK (2026-10-25, against 63c4c567): the two "noted" checks FAIL, the
  controls PASS.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-dfm-skipped-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
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
  [IO.File]::WriteAllText($Path, ($Body -replace "`r`n", "`n" -replace "`n", "`r`n"), [Text.Encoding]::ASCII)
}
function Write-BinaryDfm([string]$Path, [string]$Cls, [string]$Obj, [string]$Handler) {
  $ms = New-Object System.IO.MemoryStream
  $w  = New-Object System.IO.BinaryWriter($ms)
  $w.Write([byte[]](0xFF, 0x0A, 0x00)); $w.Write([Text.Encoding]::ASCII.GetBytes($Cls.ToUpper())); $w.Write([byte]0)
  $w.Write([byte[]](0x30, 0x10)); $w.Write([int32]0)
  $w.Write([Text.Encoding]::ASCII.GetBytes('TPF0'))
  $w.Write([byte]$Cls.Length); $w.Write([Text.Encoding]::ASCII.GetBytes($Cls))
  $w.Write([byte]$Obj.Length); $w.Write([Text.Encoding]::ASCII.GetBytes($Obj))
  $w.Write([byte]7); $w.Write([Text.Encoding]::ASCII.GetBytes('OnClick'))
  $w.Write([byte]7); $w.Write([byte]$Handler.Length); $w.Write([Text.Encoding]::ASCII.GetBytes($Handler))
  $w.Write([byte[]](0, 0)); $w.Flush()
  [IO.File]::WriteAllBytes($Path, $ms.ToArray())
}
function Form-Unit([string]$U, [string]$Cls, [string]$Parent, [string]$Members) {
  return "unit $U;`n`ninterface`n`nuses`n  Classes$(if ($Parent -eq 'TForm1') { ', Unit1' });`n`ntype`n  $Cls = class($Parent)`n$Members  end;`n`nimplementation`n`nend.`n"
}
function Text-Dfm([string]$Obj, [string]$Cls, [string]$Kw) {
  return "$Kw ${Obj}: $Cls`n  Left = 0`n  object Button1: TButton`n    OnClick = Button1Click`n  end`nend`n"
}

$dir = Join-Path $WorkDir 'P'; $src = Join-Path $dir 'src'
New-Item -ItemType Directory $src | Out-Null
Write-Ascii (Join-Path $src 'Unit1.pas') @'
unit Unit1;

interface

uses
  Classes;

type
  TForm1 = class(TComponent)
  published
    procedure Button1Click(Sender: TObject);
    procedure Helper;
  end;

implementation

procedure TForm1.Button1Click(Sender: TObject);
begin
  Helper;
end;

procedure TForm1.Helper;
begin
end;

end.
'@
Write-Ascii (Join-Path $src 'Unit1.dfm') (Text-Dfm 'Form1' 'TForm1' 'object')
Write-Ascii (Join-Path $src 'Unit3.pas') (Form-Unit 'Unit3' 'TForm3' 'TForm1' '')
Write-BinaryDfm (Join-Path $src 'Unit3.dfm') 'TForm3' 'Form3' 'Button1Click'
Write-Ascii (Join-Path $src 'Unit4.pas') (Form-Unit 'Unit4' 'TForm4' 'TForm1' '')
Write-Ascii (Join-Path $src 'Unit6.pas') (Form-Unit 'Unit6' 'TForm6' 'TForm1' '')
Write-Ascii (Join-Path $src 'Unit6.dfm') (Text-Dfm 'Form6' 'TForm6' 'inherited')
Write-Ascii (Join-Path $src 'Unit5.pas') (Form-Unit 'Unit5' 'TForm5' 'TComponent' "  published`n    procedure Button1Click(Sender: TObject);`n")
Write-BinaryDfm (Join-Path $src 'Unit5.dfm') 'TForm5' 'Form5' 'Button1Click'
$db = Join-Path $dir 'idx.sqlite'
Push-Location $dir
try { & $Exe index $src --db $db 2>&1 | Out-Null } finally { Pop-Location }
Check 'index exits 0' ($LASTEXITCODE -eq 0)
# Unit4.dfm appears after indexing: on disk, not in the index.
Write-Ascii (Join-Path $src 'Unit4.dfm') (Text-Dfm 'Form4' 'TForm4' 'inherited')

function Run-Rename([string[]]$RenameArgs) {
  $errFile = Join-Path $WorkDir 'stderr.txt'
  Push-Location $dir
  try { $o = & $Exe rename @RenameArgs --db $db 2>$errFile } finally { Pop-Location }
  $code = $LASTEXITCODE
  $err = if (Test-Path $errFile) { [IO.File]::ReadAllText($errFile) } else { '' }
  [pscustomobject]@{ Exit = $code; Out = ($o -join "`n"); Err = $err }
}
$notes = { param($r) @(($r.Err -split "`r?`n") | Where-Object { $_ -match '^drag-lint: note: ' }) }

foreach ($m in @(
    @{ N = '--json';   A = @('--kind', 'symbol', '--name', 'Unit1.TForm1.Button1Click', '--to', 'OkClick', '--json') },
    @{ N = 'dry run';  A = @('--kind', 'symbol', '--name', 'Unit1.TForm1.Button1Click', '--to', 'OkClick') },
    @{ N = 'legacy';   A = @('--qname', 'Unit1.TForm1.Button1Click', '--to', 'OkClick', '--dry-run') })) {
  $r = Run-Rename $m.A
  $n = & $notes $r
  Check "$($m.N) exits 0"                                ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out) $($r.Err)"
  Check "$($m.N) notes Unit3.dfm (binary descendant form)" (@($n | Where-Object { $_ -match 'Unit3\.dfm' -and $_ -match '(?i)binary' }).Count -eq 1) ($n -join ' | ')
  Check "$($m.N) notes Unit4.dfm (not in the index)"     (@($n | Where-Object { $_ -match 'Unit4\.dfm' -and $_ -match '(?i)not in the index' }).Count -eq 1) ($n -join ' | ')
  Check "$($m.N) CONTROL no note for Unit6.dfm (indexed text, rewritten)" (@($n | Where-Object { $_ -match 'Unit6\.dfm' }).Count -eq 0) ($n -join ' | ')
  Check "$($m.N) CONTROL no note for Unit5.dfm (unrelated form)"          (@($n | Where-Object { $_ -match 'Unit5\.dfm' }).Count -eq 0) ($n -join ' | ')
  if ($m.N -eq '--json') {
    $ed = $null; try { $ed = @($r.Out | ConvertFrom-Json) } catch { }
    Check '--json stdout is still a bare edit array'      ($null -ne $ed -and $ed.Count -gt 0) $r.Out
    Check '--json rewrites Unit6.dfm (indexed descendant)' (@($ed | Where-Object { $_.file -like '*Unit6.dfm' }).Count -eq 1)
  }
}
$r = Run-Rename @('--kind', 'symbol', '--name', 'Unit1.TForm1.Helper', '--to', 'Helper2', '--json')
Check 'CONTROL Helper rename exits 0'  ($r.Exit -eq 0) "exit=$($r.Exit)"
Check 'CONTROL Helper rename: no note' ((& $notes $r).Count -eq 0) $r.Err
$r = Run-Rename @('--kind', 'symbol', '--name', 'Unit1.TForm1.Button1Click', '--to', 'OkClick', '--apply', '--no-backup')
Check '--apply exits 0 and still notes both' (($r.Exit -eq 0) -and ((& $notes $r).Count -eq 2)) "exit=$($r.Exit) $($r.Err)"
Check '--apply leaves Unit4.dfm (unindexed) as it was' ((Get-Content -Raw (Join-Path $src 'Unit4.dfm')) -cmatch 'OnClick = Button1Click')
Check '--apply rewrites Unit6.dfm' ((Get-Content -Raw (Join-Path $src 'Unit6.dfm')) -cmatch 'OnClick = OkClick')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
