<#
  run_textedit_encoding.ps1 -- the shared write helpers keep a file's encoding,
  BOM and line-ending style (deep review F8, docs\INBOX-2026-10-25-converter-to-
  engine-deep-review-dl.md).

  THE DEFECT. TTextEditApplier.Apply (lint --fix, cycles --fix, convert-apply),
  PrependConvertComment (the convert-apply stamp) and `allow --apply` decoded
  every file as ANSI and wrote it back as ANSI, the applier with forced CRLF:
    - a UTF-8-with-BOM unit had its BOM read as three characters of line 1, so
      a column edit on line 1 landed BEFORE the BOM, the stamp was prepended
      before it, and `allow` on line 1 refused ("not 7-bit ASCII");
    - inserted non-ASCII text was written as ANSI into a UTF-8 file;
    - an LF-only file came back CRLF throughout for a one-line fix.

  WHAT THIS ASSERTS (EncodingHarness.dpr drives the two helpers; allow runs on
  the built exe):
    T1 edit, UTF-8+BOM: BOM kept, edit lands after it, U+00EF written as UTF-8
    T2 edit, LF-only: stays LF
    T3 CONTROL edit, ANSI+CRLF with a 0xE9 byte: byte-identical to the
       historical output (the fix must not move a plain ANSI file by a byte)
    S1 stamp, UTF-8+BOM: BOM first, then the header, then the original text
    S2 stamp, LF-only: header lines end in LF
    S3 CONTROL stamp, ANSI+CRLF: header + CRLF + the original bytes
    A1 allow --apply line 1 of a UTF-8+BOM unit: exit 0, BOM kept, the
       non-ASCII line intact, only line 1 changed
    A2 CONTROL allow --apply on ANSI+CRLF: only the target line changed

  RED-CHECK (2026-10-25, against 6511fe41): T1, T2, S1, S2, A1 FAIL; T3, S3,
  A2 PASS.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-textedit-encoding-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $(if ($Ok) { '' } else { $Detail })) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- build the harness (pure units only: core, refactor, preprocess, report) ---
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$srcDir  = "$PSScriptRoot\..\..\src"
$dprDir  = "$PSScriptRoot\fixtures\textedit"
$outDir  = "$WorkDir\bin"
New-Item -ItemType Directory -Force $outDir | Out-Null
$uArgs   = "-U`"$((@('core','refactor','preprocess','report') | ForEach-Object { "$srcDir\$_" }) -join ';')`" -NS`"System`""
$bat     = "$WorkDir\b.bat"
$log     = "$WorkDir\b.log"
[IO.File]::WriteAllText($bat, (@('@echo off', "call `"$rsvars`"", "cd /d `"$dprDir`"",
  "dcc64 -CC $uArgs -E`"$outDir`" -N0`"$outDir`" EncodingHarness.dpr", 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join "`r`n"), [Text.Encoding]::ASCII)
Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
$blog = Get-Content $log -Raw -ErrorAction SilentlyContinue
$harness = "$outDir\EncodingHarness.exe"
if (($blog -notmatch 'BUILD_EXITCODE=0') -or -not (Test-Path $harness)) {
  Write-Host "FATAL: EncodingHarness did not build:" -ForegroundColor Red
  ($blog -split "`r?`n") | Where-Object { $_ -match 'Error|Fatal|BUILD_EXITCODE' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
  exit 1
}

$utf8Bom = [Text.UTF8Encoding]::new($true)
$latin1  = [Text.Encoding]::Latin1          # == cp1252 for every char used here
$e9 = [char]0xE9; $ef = [char]0xEF; $zh = [char]0x4E2D
function Bom([string]$s) { return [byte[]](@(0xEF, 0xBB, 0xBF) + $utf8Bom.GetBytes($s)) }
function Same([byte[]]$a, [byte[]]$b) { return ($a.Length -eq $b.Length) -and ([Convert]::ToBase64String($a) -eq [Convert]::ToBase64String($b)) }
function Show([byte[]]$b) { return ($b | Select-Object -First 48 | ForEach-Object { $_.ToString('X2') }) -join ' ' }
function Run([string]$Mode, [string]$File, [byte[]]$Bytes) {
  $p = Join-Path $WorkDir $File
  [IO.File]::WriteAllBytes($p, $Bytes)
  & $harness $Mode $p | Out-Null
  return [IO.File]::ReadAllBytes($p)
}

# --- TTextEditApplier.Apply ---
$got = Run 'edit' 't1.pas' (Bom "unit u;`r`n// caf$e9 $zh`r`nend.`r`n")
$exp = Bom "{x}unit u;`r`n// caf$e9 $zh`r`n// na${ef}ve`r`nend.`r`n"
Check 'T1 edit on UTF-8+BOM keeps the BOM, edits after it, writes UTF-8' (Same $got $exp) (Show $got)
$got = Run 'edit' 't2.pas' ($latin1.GetBytes("unit u;`nx;`nend.`n"))
$exp = $latin1.GetBytes("{x}unit u;`nx;`n// na${ef}ve`nend.`n")
Check 'T2 edit on an LF-only file stays LF' (Same $got $exp) (Show $got)
$got = Run 'edit' 't3.pas' ($latin1.GetBytes("unit u;`r`n// caf$e9`r`nend.`r`n"))
$exp = $latin1.GetBytes("{x}unit u;`r`n// caf$e9`r`n// na${ef}ve`r`nend.`r`n")
Check 'T3 CONTROL edit on ANSI+CRLF is byte-identical to the historical output' (Same $got $exp) (Show $got)

# --- PrependConvertComment ---
$hdr = '// drag-lint convert-apply TS', '//   backup: a.pas.BCK1 /  ; rules: r.rules'
$got = Run 'stamp' 's1.pas' (Bom "unit u;`r`n// caf$e9 $zh`r`n")
$exp = Bom ("$($hdr[0])`r`n$($hdr[1])`r`nunit u;`r`n// caf$e9 $zh`r`n")
Check 'S1 stamp on UTF-8+BOM: BOM first, header, original text' (Same $got $exp) (Show $got)
$got = Run 'stamp' 's2.pas' ($latin1.GetBytes("unit u;`nend.`n"))
$exp = $latin1.GetBytes("$($hdr[0])`n$($hdr[1])`nunit u;`nend.`n")
Check 'S2 stamp on LF-only: header lines end in LF' (Same $got $exp) (Show $got)
$got = Run 'stamp' 's3.pas' ($latin1.GetBytes("unit u;`r`n// caf$e9`r`n"))
$exp = $latin1.GetBytes("$($hdr[0])`r`n$($hdr[1])`r`nunit u;`r`n// caf$e9`r`n")
Check 'S3 CONTROL stamp on ANSI+CRLF: header + original bytes' (Same $got $exp) (Show $got)

# --- allow --apply ---
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$body = "interface`r`n// caf$e9 $zh`r`nimplementation`r`nend.`r`n"
$p = Join-Path $WorkDir 'uA1.pas'
[IO.File]::WriteAllBytes($p, (Bom "unit uA1;`r`n$body"))
$o = (& $Exe allow $p --fix-line 1 --fix-rule magic-literal --apply 2>&1) -join ' | '
$code = $LASTEXITCODE
$b = [IO.File]::ReadAllBytes($p)
$hasBom = ($b.Length -ge 3) -and ($b[0] -eq 0xEF) -and ($b[1] -eq 0xBB) -and ($b[2] -eq 0xBF)
$txt = if ($hasBom) { [Text.Encoding]::UTF8.GetString($b, 3, $b.Length - 3) } else { '' }
$nl = $txt.IndexOf("`r`n")
Check 'A1 allow --apply line 1 of UTF-8+BOM: exit 0, BOM kept, only line 1 changed, non-ASCII line intact' `
  (($code -eq 0) -and $hasBom -and ($nl -gt 0) -and ($txt.Substring(0, $nl) -match '^unit uA1;\s+// dl:ok magic-literal@[0-9a-f]+$') -and `
   ($txt.Substring($nl + 2) -eq $body)) "exit=$code; $o; $(Show $b)"
$p = Join-Path $WorkDir 'uA2.pas'
$orig = "unit uA2;`r`ninterface`r`n// caf$e9`r`nimplementation`r`nend.`r`n"
[IO.File]::WriteAllBytes($p, $latin1.GetBytes($orig))
$o = (& $Exe allow $p --fix-line 1 --fix-rule magic-literal --apply 2>&1) -join ' | '
$code = $LASTEXITCODE
$t = $latin1.GetString([IO.File]::ReadAllBytes($p))
$nl = $t.IndexOf("`r`n")
Check 'A2 CONTROL allow --apply on ANSI+CRLF: only the target line changed' `
  (($code -eq 0) -and ($nl -gt 0) -and ($t.Substring(0, $nl) -match '^unit uA2;\s+// dl:ok magic-literal@[0-9a-f]+$') -and `
   ($t.Substring($nl) -eq $orig.Substring($orig.IndexOf("`r`n")))) "exit=$code; $o"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
