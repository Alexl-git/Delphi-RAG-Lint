<#
  VcRuntime.ps1 -- dot-source it (needs PeImports.ps1 beside it). Ships the Microsoft C runtime
  app-local: the tree-sitter DLLs import VCRUNTIME140.dll, which is not part of Windows, so on a
  clean machine the engine does not start without it (1.54, installer lane).

    Resolve-VcRuntimeDir <x64|x86> [override]  the folder the DLLs are taken from at pack time: the
        newest Visual Studio "VC\Redist\MSVC\<ver>\<arch>\Microsoft.VC*.CRT". Throws when there is none.
    Assert-VcRuntimeFile <file> <x64|x86>      throws unless it is <arch> and carries a valid Microsoft signature.
    Get-VcRuntimeNeeded <files>                the C runtime names those PE files import and the set does not hold.
    Add-VcRuntime -Stage -Arch [-RedistDir]    copies every C runtime DLL the exe/dll files of Stage need, beside them.

  The DLLs are never taken from git and never from System32. All failures throw.
#>
. (Join-Path $PSScriptRoot 'PeImports.ps1')

function Resolve-VcRuntimeDir([string]$Arch, [string]$Override = '') {
  if ($Override -ne '') {
    if (-not (Test-Path -LiteralPath (Join-Path $Override 'vcruntime140.dll'))) { throw "no vcruntime140.dll in $Override" }
    return $Override
  }
  $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
  $hits = foreach ($r in $roots) {
    Get-ChildItem -Path "$r\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\$Arch\Microsoft.VC*.CRT\vcruntime140.dll" -ErrorAction SilentlyContinue
  }
  $best = @($hits) | Sort-Object { [version]$_.VersionInfo.FileVersionRaw } | Select-Object -Last 1
  if (-not $best) { throw "no Visual Studio C++ redist folder holds vcruntime140.dll for $Arch (VC\Redist\MSVC\<ver>\$Arch\Microsoft.VC*.CRT). Install the Visual Studio C++ redistributable component or pass the folder." }
  $best.DirectoryName
}

function Assert-VcRuntimeFile([string]$Path, [string]$Arch) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "C runtime missing: $Path" }
  $m = Get-PeMachine $Path
  if ($m -ne $Arch) { throw "C runtime $Path is $m, expected $Arch" }
  $s = Get-AuthenticodeSignature -LiteralPath $Path
  if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    throw "C runtime $Path is not validly signed by Microsoft (status $($s.Status), signer $($s.SignerCertificate.Subject))"
  }
}

function Get-VcRuntimeNeeded([string[]]$Files) {
  $have = @($Files | ForEach-Object { [IO.Path]::GetFileName($_).ToLowerInvariant() })
  $need = foreach ($f in $Files) { Get-PeImports $f | Where-Object { (Test-VcRuntimeName $_) -and ($have -notcontains $_) } }
  @($need | Sort-Object -Unique)
}

function Add-VcRuntime([string]$Stage, [string]$Arch, [string]$RedistDir = '') {
  $added = @()
  while ($true) {
    $files = @(Get-ChildItem -LiteralPath $Stage -File | Where-Object { $_.Extension -in '.exe', '.dll' } | ForEach-Object { $_.FullName })
    $need = @(Get-VcRuntimeNeeded $files)
    if ($need.Count -eq 0) { break }
    $dir = Resolve-VcRuntimeDir $Arch $RedistDir
    foreach ($n in $need) {
      $src = Join-Path $dir $n
      Assert-VcRuntimeFile $src $Arch
      Copy-Item -LiteralPath $src -Destination (Join-Path $Stage $n)
      $added += $n
    }
  }
  @($added)
}
