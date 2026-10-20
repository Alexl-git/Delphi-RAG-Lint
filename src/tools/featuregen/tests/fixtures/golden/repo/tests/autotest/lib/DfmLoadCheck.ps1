<#
  DfmLoadCheck.ps1 -- dot-source me. The standing .dfm LOAD guard (1.25.2).

  Test-DfmLoads <path> [<path> ...] runs each .dfm through Delphi's own text
  reader (lib\DfmLoadCheck.dpr: ObjectTextToBinary, then a binary -> text ->
  binary round trip) and returns the FAIL lines -- an empty array means every
  file loads. The checker is compiled with dcc64 once per source version into
  C:\TEMP\draglint_dfmloadcheck\<hash>\ and reused after that.

  WHY: a dry run proves the PLAN, never the BYTES. Converted DMREADINGS wrote
  'FieldDefs.Items.Attributes = []' and 'CachedUpdates = (False)]' for two
  releases while every text assertion stayed green; Delphi refused the file at
  line 28. Every convert suite that WRITES a .dfm checks it here.

  Test-DfmLoadsChecker returns $true when the checker could be built (it needs
  RAD Studio's rsvars.bat); a suite reports a missing checker as a FAIL rather
  than skipping silently.
#>
$script:DfmLoadRsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'

function Get-DfmLoadChecker {
  $src = Join-Path $PSScriptRoot 'DfmLoadCheck.dpr'
  $hash = (Get-FileHash $src).Hash.Substring(0, 12)
  $dir = "C:\TEMP\draglint_dfmloadcheck\$hash"
  $exe = Join-Path $dir 'DfmLoadCheck.exe'
  if (Test-Path $exe) { return $exe }
  New-Item -ItemType Directory -Force $dir | Out-Null
  Copy-Item $src $dir -Force
  $bat = Join-Path $dir 'build.bat'
  $log = Join-Path $dir 'build.log'
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$script:DfmLoadRsVars`"", "cd /d `"$dir`"",
    'dcc64 -Q -B -NSSystem DfmLoadCheck.dpr', 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  if (Test-Path $exe) { return $exe }
  return $null
}

function Test-DfmLoadsChecker { return ($null -ne (Get-DfmLoadChecker)) }

function Test-DfmLoads([string[]]$Paths) {
  $exe = Get-DfmLoadChecker
  if ($null -eq $exe) { return @('FAIL <checker>: DfmLoadCheck.exe could not be built (rsvars.bat / dcc64)') }
  $out = & $exe @Paths 2>&1
  return @($out | Where-Object { $_ -match '^FAIL ' })
}
