<#
  run_rename_encoding.ps1 -- rename on units with non-ASCII text (W5-D, 2026-10-25).

  THE DEFECTS.
    (1) Index columns are UTF-8 BYTE columns (the indexer parses the file
        transcoded to UTF-8). Rename read files as ANSI, where one char is one
        byte, so the columns only matched by accident for a BOM-less UTF-8
        file -- and were one too far per high char on an ANSI (cp1252) line:
        such a rename was refused "index out of date" (or, on a decl, mis-
        snapped). A UTF-8-with-BOM file was off by the BOM on line 1.
    (2) TRenameRefactoring.Apply did its own I/O (ANSI for BOM-less files),
        so a non-ASCII NEW name written into a UTF-8 unit became cp1252 bytes.
  CONTRACT: TRenameEdit.Col is a 1-based CHARACTER column in the file as the
  shared reader (TTextFileFormat) decodes it; Apply writes through the shared
  encoding-preserving writer (TTextEditApplier).

  CASES (fixtures generated here; the committed script stays 7-bit ASCII):
    U  UTF-8 WITHOUT BOM: --json ranges are char columns; --apply to Compute2
       gives the exact bytes; --apply to a non-ASCII name writes UTF-8.
    A  ANSI cp1252: --json ranges are char columns (no refusal); --apply bytes.
    B  UTF-8 WITH BOM: --json ranges; --apply bytes, BOM kept.
    C  CONTROL pure ASCII: --apply bytes (the historical output).

  RED-CHECK (2026-10-25, against 63c4c567): 10 checks FAIL -- U/B ranges 5:20
  and 17:33 (byte columns), U2 non-ASCII name written as cp1252, A refused
  "index out of date" (4 checks), B --apply bytes; C (control) all PASS.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-rename-encoding-$PID"
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

$e9 = [char]0xE9; $zh = [char]0x4E2D
$utf8   = [Text.UTF8Encoding]::new($false)
$cp1252 = [Text.Encoding]::GetEncoding(1252)
# Non-ASCII BEFORE the name on the decl line (5) and on a call line (17).
function Body([string]$Hi, [string]$Name) {
  return ("unit Unit1;`r`n`r`ninterface`r`n`r`n{ $Hi } function $Name(A: Integer): Integer;`r`n`r`n" +
    "implementation`r`n`r`nfunction $Name(A: Integer): Integer;`r`nbegin`r`n  Result:= A;`r`nend;`r`n`r`n" +
    "procedure Use;`r`nvar S: string;`r`nbegin`r`n  S:= '$Hi'; S:= S + IntToStr($Name(1));`r`nend;`r`n`r`nend.`r`n")
}
function Same([byte[]]$a, [byte[]]$b) { return [Convert]::ToBase64String($a) -ceq [Convert]::ToBase64String($b) }
function Bom([byte[]]$b) { return [byte[]](@(0xEF, 0xBB, 0xBF) + $b) }

function New-Fixture([string]$Name, [byte[]]$Bytes) {
  $dir = Join-Path $WorkDir $Name
  $src = Join-Path $dir 'src'
  New-Item -ItemType Directory $src | Out-Null
  $pas = Join-Path $src 'Unit1.pas'
  [IO.File]::WriteAllBytes($pas, $Bytes)
  $db = Join-Path $dir 'idx.sqlite'
  Push-Location $dir
  try { & $Exe index $src --db $db 2>&1 | Out-Null } finally { Pop-Location }
  Check "$Name index exits 0" ($LASTEXITCODE -eq 0)
  [pscustomobject]@{ Dir = $dir; Pas = $pas; Db = $db }
}
function Run-Rename($fx, [string[]]$RenameArgs) {
  Push-Location $fx.Dir
  try { $o = & $Exe rename --kind symbol --name Unit1.Compute @RenameArgs --db $fx.Db 2>$null } finally { Pop-Location }
  [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($o -join "`n") }
}
# Every edit's (line, col, len(old)) slice of the DECODED file must be old.
function Check-Ranges([string]$Label, $fx, [Text.Encoding]$Enc) {
  $r = Run-Rename $fx @('--to', 'Compute2', '--json')
  Check "$Label --json exits 0" ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
  $edits = $null
  try { $edits = @($r.Out | ConvertFrom-Json) } catch { }
  Check "$Label --json has 3 edits" (@($edits).Count -eq 3) "count=$(@($edits).Count)"
  if ($null -eq $edits) { return }
  $bytes = [IO.File]::ReadAllBytes($fx.Pas)
  $skip = if (($bytes.Length -ge 3) -and ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)) { 3 } else { 0 }
  $lines = $Enc.GetString($bytes, $skip, $bytes.Length - $skip) -split "`r`n"
  foreach ($e in $edits) {
    $ln = $lines[$e.line - 1]; $txt = ''
    if (($e.col -ge 1) -and (($e.col - 1 + $e.old.Length) -le $ln.Length)) { $txt = $ln.Substring($e.col - 1, $e.old.Length) }
    Check ("$Label range {0}:{1} is the name" -f $e.line, $e.col) ($txt -ceq $e.old) "found='$txt'"
  }
}
function Check-Apply([string]$Label, $fx, [string]$To, [byte[]]$Expected) {
  $r = Run-Rename $fx @('--to', $To, '--apply', '--no-backup')
  Check "$Label --apply exits 0" ($r.Exit -eq 0) "exit=$($r.Exit) $($r.Out)"
  $got = [IO.File]::ReadAllBytes($fx.Pas)
  Check "$Label --apply bytes are exact" (Same $got $Expected) (($utf8.GetString($got) -split "`r`n" | Where-Object { $_ -match 'Comput' }) -join ' / ')
}

$hi = "$e9$zh"
Write-Host 'Fixture U: UTF-8 without BOM' -ForegroundColor Cyan
$u = New-Fixture 'U' ($utf8.GetBytes((Body $hi 'Compute')))
Check-Ranges 'U' $u $utf8
Check-Apply  'U' $u 'Compute2' ($utf8.GetBytes((Body $hi 'Compute2')))
$u2 = New-Fixture 'U2' ($utf8.GetBytes((Body $hi 'Compute')))
Check-Apply  'U2 non-ASCII new name' $u2 "Comput$e9" ($utf8.GetBytes((Body $hi "Comput$e9")))

Write-Host 'Fixture A: ANSI (cp1252)' -ForegroundColor Cyan
$hiA = "$e9$e9"
$a = New-Fixture 'A' ($cp1252.GetBytes((Body $hiA 'Compute')))
Check-Ranges 'A' $a $cp1252
Check-Apply  'A' $a 'Compute2' ($cp1252.GetBytes((Body $hiA 'Compute2')))

Write-Host 'Fixture B: UTF-8 with BOM' -ForegroundColor Cyan
$b = New-Fixture 'B' (Bom ($utf8.GetBytes((Body $hi 'Compute'))))
Check-Ranges 'B' $b $utf8
Check-Apply  'B' $b 'Compute2' (Bom ($utf8.GetBytes((Body $hi 'Compute2'))))

Write-Host 'Fixture C: CONTROL pure ASCII' -ForegroundColor Cyan
$c = New-Fixture 'C' ($cp1252.GetBytes((Body 'ab' 'Compute')))
Check-Ranges 'C' $c $cp1252
Check-Apply  'C' $c 'Compute2' ($cp1252.GetBytes((Body 'ab' 'Compute2')))

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
