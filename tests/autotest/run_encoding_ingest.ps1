# drag-lint source-encoding ingest regression test (v0.86).
#
# The whole text pipeline assumes source bytes are UTF-8 (tree-sitter is fed
# TSInputEncodingUTF8 and ~30 slice helpers call TEncoding.UTF8.GetString).
# A VALID CP1252 file whose bytes are not valid UTF-8 (e.g. 0xAE '(R)' / 0xA9 '(C)'
# in a copyright resourcestring -- the SOFTWID.PAS class) threw EEncodingError
# during literal extraction, so the file was SKIPPED at index and errored at lint.
#
# Fix (Task 3): EnsureUtf8Bytes transcodes ANSI/UTF-16 bytes to UTF-8 at every
# byte-ingest boundary, so such files index (symbols > 0, 0 errors) and their
# literals are text-searchable.
#
# Usage: pwsh -File tests/autotest/run_encoding_ingest.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $WorkDir = "$env:TEMP\drag-lint-encoding-ingest"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# --- fixture 1: HighByte.pas -- valid CP1252, bytes 0xAE / 0xA9 inside a
#     resourcestring literal (invalid UTF-8 -> the SOFTWID skip class). Written
#     as RAW BYTES so the high bytes survive verbatim (no PS re-encoding). ---
$hbPath = Join-Path $WorkDir 'HighByte.pas'
$lf     = "`r`n"
$hbText =
    "unit HighByte;$lf" +
    "$lf" +
    "interface$lf" +
    "$lf" +
    "resourcestring$lf" +
    "  C = 'Micronite " + [char]0xAE + " Copyright" + [char]0xA9 + "';$lf" +
    "$lf" +
    "implementation$lf" +
    "$lf" +
    "end.$lf"
# Latin-1 (ISO-8859-1) maps each char 0..255 to the same byte value, so
# [char]0xAE -> byte 0xAE and [char]0xA9 -> byte 0xA9 exactly (CP1252-compatible
# for this range). GetEncoding(28591) = ISO-8859-1.
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
[System.IO.File]::WriteAllBytes($hbPath, $latin1.GetBytes($hbText))
# sanity: the raw bytes really contain 0xAE and 0xA9
$hbBytes = [System.IO.File]::ReadAllBytes($hbPath)
Check 'HighByte.pas has 0xAE byte' ($hbBytes -contains 0xAE)
Check 'HighByte.pas has 0xA9 byte' ($hbBytes -contains 0xA9)

# --- fixture 2: Utf16.pas -- a valid ASCII unit encoded UTF-16LE WITH BOM. ---
$u16Path = Join-Path $WorkDir 'Utf16.pas'
$u16Text =
    "unit Utf16;$lf" +
    "$lf" +
    "interface$lf" +
    "$lf" +
    "resourcestring$lf" +
    "  D = 'WideUnit token';$lf" +
    "$lf" +
    "implementation$lf" +
    "$lf" +
    "end.$lf"
# TEncoding.Unicode (UTF-16LE) with BOM (FF FE ...).
$utf16 = [System.Text.UnicodeEncoding]::new($false, $true)  # littleEndian, BOM
[System.IO.File]::WriteAllBytes($u16Path, $utf16.GetPreamble() + $utf16.GetBytes($u16Text))
$u16Bytes = [System.IO.File]::ReadAllBytes($u16Path)
Check 'Utf16.pas starts FF FE (UTF-16LE BOM)' (($u16Bytes[0] -eq 0xFF) -and ($u16Bytes[1] -eq 0xFE))

# --- index the fixtures ---
$db     = "$WorkDir\enc.sqlite"
$idxOut = & $Exe index $WorkDir --db $db 2>&1
$idxTxt = ($idxOut | Out-String)
Check 'index exits 0' ($LASTEXITCODE -eq 0) (($idxOut | Select-Object -Last 1))

# HighByte.pas: indexed with REAL symbols, NOT skipped (the SOFTWID skip class).
$hbSkipped = $idxTxt -match 'SKIP\s+\S*HighByte\.pas'
$hbMatch   = [regex]::Match($idxTxt, 'HighByte\.pas\s*->\s*(\d+)\s+symbols')
$hbSyms    = if ($hbMatch.Success) { [int]$hbMatch.Groups[1].Value } else { -1 }
Check 'HighByte.pas indexed (-> line present)' $hbMatch.Success
Check 'HighByte.pas NOT skipped'               (-not $hbSkipped)
Check 'HighByte.pas produced symbols (> 0)'    ($hbSyms -gt 0) ("(got $hbSyms)")

# Utf16.pas: indexed with REAL symbols (not the raw-bytes 0-symbols+parse-error
# case), NOT skipped. Match the reported "-> N symbols" and require N > 0.
$u16Skipped = $idxTxt -match 'SKIP\s+\S*Utf16\.pas'
$u16Match   = [regex]::Match($idxTxt, 'Utf16\.pas\s*->\s*(\d+)\s+symbols')
$u16Syms    = if ($u16Match.Success) { [int]$u16Match.Groups[1].Value } else { -1 }
Check 'Utf16.pas indexed (-> line present)' $u16Match.Success
Check 'Utf16.pas NOT skipped'               (-not $u16Skipped)
Check 'Utf16.pas produced symbols (> 0)'    ($u16Syms -gt 0) ("(got $u16Syms)")

# --- text search: the transcoded literal must be findable ---
$qOut = & $Exe query --text "Micronite" --substring --db $db 2>&1
$qTxt = ($qOut | Out-String)
Check 'query --text Micronite exits 0' ($LASTEXITCODE -eq 0)
Check 'query --text finds the transcoded literal' ($qTxt -match 'Micronite')

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
