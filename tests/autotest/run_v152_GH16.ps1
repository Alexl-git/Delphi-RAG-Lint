<#
  run_v152_GH16.ps1 -- GitHub #16: source text from a unit saved as UTF-8 WITH a BOM came out
  double-encoded in `context` (and find-callers --context): the BOM printed as text and every
  non-ASCII character as two. Readers used TFile.ReadAllLines(path, TEncoding.ANSI).
  1. context (utf8 output) of a UTF-8+BOM unit: e-acute is C3 A9, never C3 83 C2 A9; no BOM bytes.
  2. find-callers --context of a call inside that unit: same.
  3. control: a cp1252 unit (no BOM) with the same comment still prints C3 A9.
  The fixture bytes are written from code points so this file stays 7-bit ASCII. pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = '')
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
$exe = (Resolve-Path $Exe).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("dl_gh16_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fx = Join-Path $work 'fx'
[void][IO.Directory]::CreateDirectory($fx)
$eacute = [string][char]0xE9
[IO.File]::WriteAllText((Join-Path $fx 'Shapes.pas'), ("unit Shapes;`r`ninterface`r`ntype`r`n  TCircle = class`r`n  public`r`n    procedure Draw;`r`n  end;`r`nimplementation`r`nprocedure TCircle.Draw; begin end;`r`nend.`r`n"), [Text.Encoding]::ASCII)
$painter = "unit Painter;`r`ninterface`r`nuses Shapes;`r`nprocedure PaintCircle(C: TCircle);`r`nimplementation`r`nprocedure PaintCircle(C: TCircle);`r`nbegin`r`n  { caf$($eacute): draw the circle }`r`n  C.Draw;`r`nend;`r`nend.`r`n"
[IO.File]::WriteAllText((Join-Path $fx 'Painter.pas'), $painter, (New-Object Text.UTF8Encoding $true))
$ansi = "unit AnsiPainter;`r`ninterface`r`nuses Shapes;`r`nprocedure PaintAnsi(C: TCircle);`r`nimplementation`r`nprocedure PaintAnsi(C: TCircle);`r`nbegin`r`n  { caf$($eacute): draw it again }`r`n  C.Draw;`r`nend;`r`nend.`r`n"
[IO.File]::WriteAllText((Join-Path $fx 'AnsiPainter.pas'), $ansi, [Text.Encoding]::GetEncoding(1252))
$db = Join-Path $work 'fx.sqlite'
function Hex([byte[]]$b) { ($b | ForEach-Object { $_.ToString('X2') }) -join ' ' }
function RunBytes([string[]]$a) {
  $out = Join-Path $work ('o_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.txt')
  $psi = [Diagnostics.ProcessStartInfo]::new($exe)
  foreach ($x in $a) { $psi.ArgumentList.Add($x) }
  $psi.RedirectStandardOutput = $true; $psi.UseShellExecute = $false; $psi.WorkingDirectory = $work
  $pr = [Diagnostics.Process]::Start($psi)
  $ms = [IO.MemoryStream]::new(); $pr.StandardOutput.BaseStream.CopyTo($ms); $pr.WaitForExit()
  return ,$ms.ToArray()
}
$good = Hex ([Text.Encoding]::UTF8.GetBytes("caf$eacute"))           # 63 61 66 C3 A9
$bad  = 'C3 83 C2 A9'
$bom  = 'EF BB BF'
$bomx = 'C3 AF C2 BB C2 BF'
Push-Location $work
try {
  & { $ErrorActionPreference = 'Continue'; & $exe index $fx --db $db *> $null }
  Check 'fixture indexed' ($LASTEXITCODE -eq 0 -and (Test-Path $db)) "exit $LASTEXITCODE"

  $h = Hex (RunBytes @('context', '--task', 'modify Painter.PaintCircle', '--format', 'md', '--output-encoding', 'utf8', '--db', $db))
  Check 'context BOM unit: e-acute is C3 A9' ($h.Contains($good)) 'caf + C3 A9 not found'
  Check 'context BOM unit: not double-encoded' (-not $h.Contains($bad)) 'found C3 83 C2 A9'
  Check 'context BOM unit: no BOM in output' ((-not $h.Contains($bomx)) -and (-not $h.Contains($bom))) 'found BOM bytes'

  $h = Hex (RunBytes @('query', 'find-callers', '--name', 'Draw', '--context', '2', '--output-encoding', 'utf8', '--db', $db))
  Check 'find-callers --context BOM unit: not double-encoded' ((-not $h.Contains($bad)) -and $h.Contains($good)) 'C3 83 C2 A9 present or C3 A9 missing'

  $h = Hex (RunBytes @('context', '--task', 'modify AnsiPainter.PaintAnsi', '--format', 'md', '--output-encoding', 'utf8', '--db', $db))
  Check 'control: cp1252 unit still prints C3 A9' ($h.Contains($good) -and -not $h.Contains($bad)) 'cp1252 decode changed'
}
finally {
  Pop-Location
  try { [IO.Directory]::Delete($work, $true) } catch { }
}
if ($script:fail) { Write-Host 'FAIL'; exit 1 }
Write-Host 'PASS'; exit 0
