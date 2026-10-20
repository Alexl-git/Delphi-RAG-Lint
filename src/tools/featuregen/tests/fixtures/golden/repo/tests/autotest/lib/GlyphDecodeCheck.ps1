<#
  GlyphDecodeCheck.ps1 -- dot-source me. The standing glyph DECODE guard (1.26.2).

  Invoke-GlyphDecode <path> [<path> ...] reads each .dfm with Delphi's own
  TReader (lib\GlyphDecodeCheck.dpr) into fixture components whose graphic
  properties are the REAL TPicture / TdxSmartGlyph, touches every graphic, and
  returns the checker's lines (ROOT / PIC / GLYPH / PICFAIL / GLYPHFAIL / ERR /
  FATAL). The checker is compiled with dcc64 against the DevExpress Win64 dcus
  once per source version into C:\TEMP\draglint_glyphdecode\<hash>\.

  WHY: DfmLoadCheck proves a .dfm PARSES and never instantiates a class. 1.25.2
  carried twenty TPicture payloads into TdxSmartGlyph byte-identical; every
  file parsed, and every glyph raised `Unsupported image format.` when read.

  Test-GlyphDecodeChecker returns $true when the checker could be built (it
  needs RAD Studio and the DevExpress VCL install); a suite reports a missing
  checker as a FAIL rather than skipping silently.
#>
$script:GlyphRsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
$script:GlyphDxDcu  = 'C:\Program Files (x86)\DevExpress\VCL\Library\RS37\Win64'

function Get-GlyphDecodeChecker {
  $src = Join-Path $PSScriptRoot 'GlyphDecodeCheck.dpr'
  $hash = (Get-FileHash $src).Hash.Substring(0, 12)
  $dir = "C:\TEMP\draglint_glyphdecode\$hash"
  $exe = Join-Path $dir 'GlyphDecodeCheck.exe'
  if (Test-Path $exe) { return $exe }
  New-Item -ItemType Directory -Force $dir | Out-Null
  Copy-Item $src $dir -Force
  $bat = Join-Path $dir 'build.bat'
  $log = Join-Path $dir 'build.log'
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$script:GlyphRsVars`"", "cd /d `"$dir`"",
    "dcc64 -Q -B -NSSystem;Vcl;Winapi;System.Win;Vcl.Imaging -U`"$script:GlyphDxDcu`" -R`"$script:GlyphDxDcu`" GlyphDecodeCheck.dpr",
    'echo BUILD_EXITCODE=%ERRORLEVEL%') -join "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  if (Test-Path $exe) { return $exe }
  return $null
}

function Test-GlyphDecodeChecker { return ($null -ne (Get-GlyphDecodeChecker)) }

function Invoke-GlyphDecode([string[]]$Paths) {
  $exe = Get-GlyphDecodeChecker
  if ($null -eq $exe) { return @('FATAL <checker>: GlyphDecodeCheck.exe could not be built (rsvars.bat / dcc64 / DevExpress dcus)') }
  return @(& $exe @Paths 2>&1 | ForEach-Object { "$_" })
}
