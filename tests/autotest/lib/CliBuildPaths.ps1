<#
  CliBuildPaths.ps1 -- dot-source helper for console test harnesses that compile
  engine units with dcc64 directly (a bare .dpr cannot be built by msbuild).

  WHY THIS EXISTS. Harnesses used to carry their own hand-kept -U lists. When
  DRagLint.Index.CallResolver started using TreeSitter (resolver 1.8.0, with-scope
  parsing), the CLI kept building -- its .dproj lists third_party\delphi-tree-sitter
  and the System;Winapi;... unit scopes -- while three harnesses broke, each in its
  own way (F2613 'TreeSitter' not found / F2613 'SysUtils' not found). A list that
  mirrors the .dproj by hand drifts silently; this one is READ FROM the .dproj.

  Get-CliDcc64Args  -- the CLI's DCC_UnitSearchPath (absolute) and DCC_Namespace,
                       evaluated the way MSBuild does for one platform: every
                       PropertyGroup that is not conditioned on ANOTHER platform,
                       in document order, each '<new>;$(Prop)' PREPENDING to what
                       came before.
  Copy-TreeSitterDlls -- stage third_party\dll-win64\tree-sitter*.dll beside a
                       harness exe. TreeSitter / TreeSitterLib and any unit with an
                       `external 'tree-sitter-delphi13'` import them IMPLICITLY, so
                       a missing DLL kills the process at load -- and a wrong-
                       bitness copy found on PATH gives 0xC000007B (see
                       build\build_draglint_win64.bat). Throws when none are found:
                       a harness that runs without them answers '' for every case.

  Usage:
    . (Join-Path $PSScriptRoot '..\autotest\lib\CliBuildPaths.ps1')
    $cli = Get-CliDcc64Args
    "dcc64 -B $($cli.Args) ..."
    Copy-TreeSitterDlls -Dest $exeDir
#>

$script:CliBuildPathsRepo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

function Get-CliDcc64Args {
  [CmdletBinding()]
  param(
    [string] $Platform = 'Win64',
    [string] $Dproj    = (Join-Path $script:CliBuildPathsRepo 'src\cli\drag-lint.dproj')
  )
  if (-not (Test-Path -LiteralPath $Dproj)) { throw "CliBuildPaths: .dproj not found: $Dproj" }
  $cliDir = Split-Path -Parent (Resolve-Path -LiteralPath $Dproj).Path
  [xml]$x = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Dproj).Path)
  $otherPlatforms = @('Win32', 'Win64', 'Linux64', 'OSX64', 'OSXARM64', 'Android', 'Android64', 'iOSDevice64', 'iOSSimARM64') |
    Where-Object { $_ -ne $Platform }

  $values = @{ DCC_UnitSearchPath = @(); DCC_Namespace = @() }
  foreach ($pg in $x.Project.PropertyGroup) {
    $cond = [string]$pg.Condition
    $skip = $false
    # Not \b: '_' is a word character, so \bWin32 misses '$(Base_Win32)'.
    foreach ($o in $otherPlatforms) { if ($cond -match "(?<![A-Za-z0-9])$([regex]::Escape($o))(?![A-Za-z0-9])") { $skip = $true } }
    if ($skip) { continue }
    foreach ($prop in @('DCC_UnitSearchPath', 'DCC_Namespace')) {
      $raw = $pg.$prop
      if ($null -eq $raw) { continue }
      $new = New-Object System.Collections.Generic.List[string]
      foreach ($part in ([string]$raw -split ';')) {
        $t = $part.Trim()
        if ($t -eq '') { continue }
        if ($t -eq "`$($prop)") { foreach ($old in $values[$prop]) { if (-not $new.Contains($old)) { $new.Add($old) } }; continue }
        if ($t.StartsWith('$(')) { continue }
        if ($prop -eq 'DCC_UnitSearchPath') { $t = [IO.Path]::GetFullPath((Join-Path $cliDir $t)) }
        if (-not $new.Contains($t)) { $new.Add($t) }
      }
      $values[$prop] = @($new)
    }
  }
  $dirs = @($values.DCC_UnitSearchPath)
  $ns   = @($values.DCC_Namespace)
  if ($dirs.Count -eq 0) { throw "CliBuildPaths: no DCC_UnitSearchPath read from $Dproj" }
  if ($ns.Count -eq 0)   { throw "CliBuildPaths: no DCC_Namespace read from $Dproj" }
  $uArg  = '-U"{0}"' -f ($dirs -join ';')
  $nsArg = '-NS"{0}"' -f ($ns -join ';')
  [pscustomobject]@{
    SearchDirs = $dirs
    Namespaces = $ns
    UArg       = $uArg
    NSArg      = $nsArg
    Args       = "$uArg $nsArg"
  }
}

function Copy-TreeSitterDlls {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Dest,
    [string] $SourceDir = (Join-Path $script:CliBuildPathsRepo 'third_party\dll-win64')
  )
  $dlls = @(Get-ChildItem -LiteralPath $SourceDir -Filter 'tree-sitter*.dll' -File -ErrorAction SilentlyContinue)
  if ($dlls.Count -eq 0) { throw "CliBuildPaths: no tree-sitter*.dll in $SourceDir" }
  if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Force $Dest | Out-Null }
  foreach ($d in $dlls) { Copy-Item -LiteralPath $d.FullName -Destination $Dest -Force }
  return @($dlls | ForEach-Object Name)
}
