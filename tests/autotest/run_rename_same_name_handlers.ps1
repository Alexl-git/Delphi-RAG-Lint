<#
  run_rename_same_name_handlers.ps1 -- X-25 (ENGINE wave 4b, lane L-ren).

  Renaming an event handler used to be NAME-based: every ref named like the
  method was rewritten, so renaming TForm1.Button1Click also renamed the call
  to TForm2.Button1Click in Unit2.pas and the `OnClick = Button1Click` binding
  in Unit2.dfm -- another form's handler, which then no longer exists.

  Contract (rename spec 2.2 + X-25), renaming Unit1.TForm1.Button1Click:
    * a .pas ref the resolver bound to ANOTHER symbol is not edited;
    * a .dfm event binding is edited only when the form's root class IS the
      owner class, or descends from it without (re)declaring the same name;
    * the owning Unit1.dfm and the inherited form Unit3.dfm (TForm3 =
      class(TForm1), binding inherited) ARE rewritten;
    * Unit2 (unrelated same-named handler) and Unit4 (TForm4 = class(TForm1)
      that redeclares Button1Click) are byte-identical after --apply;
    * --json and the default dry run list exactly those edits.
  Positive control: the pre-fix engine fails the "exact edit set" and the
  "Unit2 untouched" checks (watched RED before the fix).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-same-name-$PID"
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

$Files = [ordered]@{}
$Files['Unit1.pas'] = @'
unit Unit1;

interface

uses
  Classes;

type
  TForm1 = class(TComponent)
  published
    procedure Button1Click(Sender: TObject);
  end;

implementation

procedure TForm1.Button1Click(Sender: TObject);
begin
end;

end.
'@
$Files['Unit1.dfm'] = @'
object Form1: TForm1
  object Button1: TButton
    OnClick = Button1Click
  end
end
'@
$Files['Unit2.pas'] = @'
unit Unit2;

interface

uses
  Classes;

type
  TForm2 = class(TComponent)
  published
    procedure Button1Click(Sender: TObject);
    procedure Other;
  end;

implementation

procedure TForm2.Button1Click(Sender: TObject);
begin
end;

procedure TForm2.Other;
begin
  Button1Click(nil);
end;

end.
'@
$Files['Unit2.dfm'] = @'
object Form2: TForm2
  object Button1: TButton
    OnClick = Button1Click
  end
end
'@
$Files['Unit3.pas'] = @'
unit Unit3;

interface

uses
  Classes, Unit1;

type
  TForm3 = class(TForm1)
  end;

implementation

end.
'@
$Files['Unit3.dfm'] = @'
inherited Form3: TForm3
  object Button9: TButton
    OnClick = Button1Click
  end
end
'@
$Files['Unit4.pas'] = @'
unit Unit4;

interface

uses
  Classes, Unit1;

type
  TForm4 = class(TForm1)
  published
    procedure Button1Click(Sender: TObject);
  end;

implementation

procedure TForm4.Button1Click(Sender: TObject);
begin
end;

end.
'@
$Files['Unit4.dfm'] = @'
inherited Form4: TForm4
  object Button8: TButton
    OnClick = Button1Click
  end
end
'@

function New-Fixture([string]$Name) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  foreach ($k in $Files.Keys) { Write-Ascii (Join-Path $src $k) $Files[$k] }
  $db = Join-Path $dir 'idx.sqlite'
  Push-Location $dir
  try { & $Exe index $src --db $db 2>&1 | Out-Null } finally { Pop-Location }
  Check "$Name index exits 0" ($LASTEXITCODE -eq 0)
  [pscustomobject]@{ Dir = $dir; Src = $src; Db = $db }
}

function Run-Rename($fx, [string[]]$RenameArgs) {
  Push-Location $fx.Dir
  try { $o = & $Exe rename @RenameArgs --db $fx.Db 2>&1 } finally { Pop-Location }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($o -join "`n") }
}

function FileHash($fx, [string]$Leaf) {
  [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fx.Src $Leaf)))
}

# The exact edit set: Unit1.pas decl (11) + impl header (16), Unit1.dfm binding (3),
# Unit3.dfm inherited binding (3). Nothing in Unit2 / Unit4.
$Expected = @('Unit1.dfm:3', 'Unit1.pas:11', 'Unit1.pas:16', 'Unit3.dfm:3')
$RenArgs  = @('--kind', 'symbol', '--name', 'Unit1.TForm1.Button1Click', '--to', 'OkClick')

Write-Host 'Fixture J: --json lists exactly the owner''s edits' -ForegroundColor Cyan
$j = New-Fixture 'J'
$r = Run-Rename $j ($RenArgs + '--json')
Check 'json exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
$edits = @()
try { $edits = @($r.Out | ConvertFrom-Json) } catch { }
$got = @($edits | ForEach-Object { '{0}:{1}' -f (Split-Path -Leaf $_.file), $_.line } | Sort-Object)
Check 'json edit set is exact' (($got -join ',') -ceq ($Expected -join ',')) "got=$($got -join ',')"
Check 'json has no Unit2 edit' (-not ($got -match '^Unit2\.'))
Check 'json has no Unit4 edit' (-not ($got -match '^Unit4\.'))

Write-Host 'Fixture D: dry run names exactly the owner''s files' -ForegroundColor Cyan
$d = New-Fixture 'D'
$before = @{}; foreach ($k in $Files.Keys) { $before[$k] = FileHash $d $k }
$r = Run-Rename $d $RenArgs
Check 'dry run exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
Check 'dry run names Unit1.dfm' ($r.Out -match 'Unit1\.dfm')
Check 'dry run names Unit3.dfm' ($r.Out -match 'Unit3\.dfm')
Check 'dry run does not name Unit2' (-not ($r.Out -match 'Unit2\.'))
Check 'dry run does not name Unit4' (-not ($r.Out -match 'Unit4\.'))
$same = $true; foreach ($k in $Files.Keys) { if ((FileHash $d $k) -cne $before[$k]) { $same = $false } }
Check 'dry run writes nothing' $same

Write-Host 'Fixture A: --apply rewrites the owner and the inherited form only' -ForegroundColor Cyan
$a = New-Fixture 'A'
$before = @{}; foreach ($k in $Files.Keys) { $before[$k] = FileHash $a $k }
$r = Run-Rename $a ($RenArgs + @('--apply', '--no-backup'))
Check 'apply exits 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
foreach ($k in @('Unit2.pas', 'Unit2.dfm', 'Unit4.pas', 'Unit4.dfm')) {
  Check "$k byte-identical" ((FileHash $a $k) -ceq $before[$k])
}
$u1  = Get-Content -Raw (Join-Path $a.Src 'Unit1.pas')
$d1  = Get-Content -Raw (Join-Path $a.Src 'Unit1.dfm')
$d3  = Get-Content -Raw (Join-Path $a.Src 'Unit3.dfm')
Check 'Unit1.pas decl renamed'      ($u1 -cmatch 'procedure OkClick\(Sender: TObject\);')
Check 'Unit1.pas impl renamed'      ($u1 -cmatch 'procedure TForm1\.OkClick\(Sender: TObject\);')
Check 'Unit1.dfm binding rewritten' ($d1 -cmatch 'OnClick = OkClick\r\n')
Check 'Unit3.dfm binding rewritten' ($d3 -cmatch 'OnClick = OkClick\r\n')
Check 'Unit3.pas byte-identical'    ((FileHash $a 'Unit3.pas') -ceq $before['Unit3.pas'])

Write-Host 'Fixture U: --apply keeps a UTF-8 BOM .pas and an LF .dfm as they were stored (F8)' -ForegroundColor Cyan
# Apply used to decode every file as ANSI and write ANSI + CRLF: the BOM bytes
# turned into three code-page chars, a non-ASCII comment was re-encoded, and an
# LF file came back CRLF. Positive control: the pre-F8 Apply fails all four.
$u = New-Fixture 'U'
$e9 = [string][char]0xE9
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$u1Text = ((Get-Content -Raw (Join-Path $u.Src 'Unit1.pas')) -replace 'implementation\r\n', ("implementation`r`n// caf$e9`r`n"))
[IO.File]::WriteAllText((Join-Path $u.Src 'Unit1.pas'), $u1Text, $utf8Bom)
$lfDfm = (Get-Content -Raw (Join-Path $u.Src 'Unit1.dfm')) -replace "`r`n", "`n"
[IO.File]::WriteAllText((Join-Path $u.Src 'Unit1.dfm'), $lfDfm, [Text.Encoding]::ASCII)
Push-Location $u.Dir
try { & $Exe index $u.Src --db $u.Db 2>&1 | Out-Null } finally { Pop-Location }
$r = Run-Rename $u ($RenArgs + @('--apply', '--no-backup'))
Check 'U apply exits 0' ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
$ub = [IO.File]::ReadAllBytes((Join-Path $u.Src 'Unit1.pas'))
Check 'U Unit1.pas keeps its UTF-8 BOM' ($ub.Length -ge 3 -and $ub[0] -eq 0xEF -and $ub[1] -eq 0xBB -and $ub[2] -eq 0xBF -and -not ($ub.Length -ge 6 -and $ub[3] -eq 0xEF))
$ut = [IO.File]::ReadAllText((Join-Path $u.Src 'Unit1.pas'), [Text.Encoding]::UTF8)
Check 'U Unit1.pas non-ASCII comment intact' ($ut.Contains("// caf$e9`r`n"))
Check 'U Unit1.pas renamed'                  ($ut -cmatch 'procedure TForm1\.OkClick\(Sender: TObject\);')
$ud = [IO.File]::ReadAllText((Join-Path $u.Src 'Unit1.dfm'))
Check 'U Unit1.dfm binding rewritten'        ($ud -cmatch 'OnClick = OkClick\n')
Check 'U Unit1.dfm still LF-only'            (-not $ud.Contains("`r"))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d25 in @("$env:TEMP\drag-lint-rename-same-name-$PID")) { if (Test-Path -LiteralPath $d25) { Remove-Item -LiteralPath $d25 -Recurse -Force -ErrorAction SilentlyContinue } }
}
