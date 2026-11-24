<#
  PeImports.ps1 -- dot-source it. Reads the PE headers of an exe / dll / bpl with no tools installed.

    Get-PeMachine <file>   'x64' | 'x86' | 'other:0x....'
    Get-PeImports <file>   the DLL names of the import table AND the delay-import table (lower case)

  Used by build\pack-lint-release.ps1, installer\Build-Installer.ps1 (is a C runtime needed?) and
  tests\autotest\run_pack_vcruntime_guard.ps1. A file that is not a PE image throws.
#>
function Read-PeFile([string]$Path) {
  $b = [IO.File]::ReadAllBytes($Path)
  if ($b.Length -lt 0x100 -or $b[0] -ne 0x4D -or $b[1] -ne 0x5A) { throw "not a PE image: $Path" }
  $pe = [BitConverter]::ToInt32($b, 0x3C)
  if ([BitConverter]::ToUInt32($b, $pe) -ne 0x4550) { throw "not a PE image: $Path" }
  $machine = [BitConverter]::ToUInt16($b, $pe + 4)
  $nSec = [BitConverter]::ToUInt16($b, $pe + 6)
  $optSize = [BitConverter]::ToUInt16($b, $pe + 20)
  $opt = $pe + 24
  $magic = [BitConverter]::ToUInt16($b, $opt)
  $dirBase = if ($magic -eq 0x20B) { $opt + 112 } else { $opt + 96 }
  $secs = for ($i = 0; $i -lt $nSec; $i++) {
    $s = $opt + $optSize + 40 * $i
    [pscustomobject]@{ VA = [BitConverter]::ToUInt32($b, $s + 12); VSize = [BitConverter]::ToUInt32($b, $s + 8)
                       Raw = [BitConverter]::ToUInt32($b, $s + 20); RawSize = [BitConverter]::ToUInt32($b, $s + 16) }
  }
  [pscustomobject]@{ Bytes = $b; Machine = $machine; DirBase = $dirBase; Sections = @($secs) }
}
function Convert-Rva($Pe, [uint32]$Rva) {
  foreach ($s in $Pe.Sections) {
    if ($Rva -ge $s.VA -and $Rva -lt ($s.VA + [Math]::Max($s.VSize, $s.RawSize))) { return [int]($Rva - $s.VA + $s.Raw) }
  }
  return -1
}
function Read-AsciiZ($Pe, [int]$Off) {
  $e = $Off
  while ($Pe.Bytes[$e] -ne 0) { $e++ }
  [Text.Encoding]::ASCII.GetString($Pe.Bytes, $Off, $e - $Off).ToLowerInvariant()
}
function Get-PeMachine([string]$Path) {
  switch ((Read-PeFile $Path).Machine) { 0x8664 { 'x64' } 0x014C { 'x86' } default { 'other:0x{0:X4}' -f $_ } }
}
function Get-PeImports([string]$Path) {
  $pe = Read-PeFile $Path
  $names = New-Object System.Collections.Generic.List[string]
  # data directory 1 = imports (20-byte entries, name RVA at +12); 13 = delay imports (32-byte, name at +4)
  foreach ($d in @(@(1, 20, 12), @(13, 32, 4))) {
    $rva = [BitConverter]::ToUInt32($pe.Bytes, $pe.DirBase + 8 * $d[0])
    if ($rva -eq 0) { continue }
    $o = Convert-Rva $pe $rva
    if ($o -lt 0) { continue }
    while ($true) {
      $n = [BitConverter]::ToUInt32($pe.Bytes, $o + $d[2])
      if ($n -eq 0) { break }
      $no = Convert-Rva $pe $n
      if ($no -ge 0) { $names.Add((Read-AsciiZ $pe $no)) }
      $o += $d[1]
    }
  }
  @($names | Sort-Object -Unique)
}
# The Microsoft C runtime DLLs that are not part of Windows and so must ship app-local.
function Test-VcRuntimeName([string]$Name) { $Name -match '^(vcruntime|msvcp|concrt|vcomp|vccorlib)\d+.*\.dll$' }
