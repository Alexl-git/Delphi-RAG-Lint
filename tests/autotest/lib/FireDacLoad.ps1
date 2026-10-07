<#
  FireDacLoad.ps1 -- dot-source me. A REAL FireDAC load of a converted .dfm
  (1.26.1).

  Invoke-FireDacLoad <path> [<path> ...] runs each .dfm through VCL's reader
  (lib\FireDacLoad.dpr: ObjectTextToBinary, then TReader.ReadRootComponent
  into a TDataModule) with the real FireDAC classes registered, and returns
  its output lines: 'FAIL <file>: ...' for every reader error, then one
  'PARAMS <file> <comp> <count>' and one 'PARAM ... Name=.. DataType=..
  ParamType=.. Value=..' per parameter of every TFDQuery / TFDStoredProc.

  WHY: DfmLoadCheck proves the TEXT parses; it never instantiates a class, so
  a ParamData item member TFDParam does not publish loads there and fails in
  the application. This one reads the stream into the real objects.

  Compiled with dcc64 once per source version into
  C:\TEMP\draglint_firedacload\<hash>\ and reused. Test-FireDacLoader returns
  $true when it could be built; a suite reports a missing loader as a FAIL.
#>
$script:FireDacLoadRsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'

function Get-FireDacLoader {
  $src = Join-Path $PSScriptRoot 'FireDacLoad.dpr'
  $hash = (Get-FileHash $src).Hash.Substring(0, 12)
  $dir = "C:\TEMP\draglint_firedacload\$hash"
  $exe = Join-Path $dir 'FireDacLoad.exe'
  if (Test-Path $exe) { return $exe }
  New-Item -ItemType Directory -Force $dir | Out-Null
  Copy-Item $src $dir -Force
  $bat = Join-Path $dir 'build.bat'
  $log = Join-Path $dir 'build.log'
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$script:FireDacLoadRsVars`"", "cd /d `"$dir`"",
    'dcc64 -Q -B -NSSystem;Winapi;System.Win;Data;Vcl FireDacLoad.dpr', 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  if (Test-Path $exe) { return $exe }
  return $null
}

function Test-FireDacLoader { return ($null -ne (Get-FireDacLoader)) }

function Invoke-FireDacLoad([string[]]$Paths) {
  $exe = Get-FireDacLoader
  if ($null -eq $exe) { return @('FAIL <loader>: FireDacLoad.exe could not be built (rsvars.bat / dcc64)') }
  return @(& $exe @Paths 2>&1 | ForEach-Object { "$_" })
}
