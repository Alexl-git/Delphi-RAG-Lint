<#
  DfmChainLoad.ps1 -- dot-source me. A REAL VCL load of an inheritance chain
  of .dfm files (1.26.5).

  Invoke-DfmChainLoad 'Base.dfm+Child.dfm' [...] reads every file of each
  chain into ONE root with TReader.ReadRootComponent (lib\DfmChainLoad.dpr,
  FireDAC / BDE / Data.DB field classes registered) and returns its lines:
  'ERR ...' / 'FATAL ...' per reader error, 'FIELDS <dataset>: f1 f2 ...' per
  TDataSet in Fields order, then 'DONE ...'.
  Get-DfmFieldOrder <chain> <dataset> returns that dataset's field names.

  WHY: the `[n]` child-position marker on a .dfm header decides where a
  parent's child lands at load (SetChildOrder). Text checks cannot see an
  order change; only a load can.

  Compiled with dcc32 (BDE ships Win32 only) once per source version into
  C:\TEMP\draglint_dfmchainload\<hash>\ and reused.
#>
$script:DfmChainRsVars = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'

function Get-DfmChainLoader {
  $src = Join-Path $PSScriptRoot 'DfmChainLoad.dpr'
  $hash = (Get-FileHash $src).Hash.Substring(0, 12)
  $dir = "C:\TEMP\draglint_dfmchainload\$hash"
  $exe = Join-Path $dir 'DfmChainLoad.exe'
  if (Test-Path $exe) { return $exe }
  New-Item -ItemType Directory -Force $dir | Out-Null
  Copy-Item $src $dir -Force
  $bat = Join-Path $dir 'build.bat'
  $log = Join-Path $dir 'build.log'
  [IO.File]::WriteAllText($bat, (@('@echo off', "call `"$script:DfmChainRsVars`"", "cd /d `"$dir`"",
    'dcc32 -Q -B -NSSystem;Winapi;System.Win;Data;Vcl;Bde DfmChainLoad.dpr', 'echo BUILD_EXITCODE=%ERRORLEVEL%') -join "`r`n"), [Text.Encoding]::ASCII)
  Start-Process cmd.exe -ArgumentList '/c', "`"$bat`"" -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait | Out-Null
  if (Test-Path $exe) { return $exe }
  return $null
}

function Test-DfmChainLoader { return ($null -ne (Get-DfmChainLoader)) }

function Invoke-DfmChainLoad([string[]]$Chains) {
  $exe = Get-DfmChainLoader
  if ($null -eq $exe) { return @('FATAL <loader>: DfmChainLoad.exe could not be built (rsvars.bat / dcc64)') }
  return @(& $exe @Chains 2>&1 | ForEach-Object { "$_" })
}

function Get-DfmFieldOrder([string]$Chain, [string]$DataSet) {
  $line = @(Invoke-DfmChainLoad @($Chain) | Where-Object { $_ -like "FIELDS ${DataSet}:*" })
  if ($line.Count -eq 0) { return '<no dataset>' }
  return $line[0].Substring(("FIELDS ${DataSet}:").Length).Trim()
}
