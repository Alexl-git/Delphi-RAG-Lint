<#
  HermeticEngine.ps1 -- 150 H1 item 1. Dot-source, then: $Exe = Get-HermeticEngine $Exe
  A machine drag-lint.json beside the exe names the real platform libraries and outranks a
  guard's fixtures. Get-HermeticEngine returns $Exe untouched when no drag-lint.json sits
  beside it; otherwise it returns an engine copy WITHOUT the manifest (exe, dlls, rules\)
  in %TEMP%\drag-lint-hermetic\<key>, cached by exe size+mtime and shared by every guard
  (built in a private dir, then moved into place, so parallel guards do not race).
#>
function Get-HermeticEngine {
  param([Parameter(Mandatory)][string] $Exe)
  $src = (Resolve-Path -LiteralPath $Exe).Path
  $dir = Split-Path -Parent $src
  if (-not (Test-Path -LiteralPath (Join-Path $dir 'drag-lint.json'))) { return $src }
  $fi  = Get-Item -LiteralPath $src
  $key = '{0}-{1}' -f $fi.Length, $fi.LastWriteTimeUtc.Ticks
  $root = Join-Path ([IO.Path]::GetTempPath()) 'drag-lint-hermetic'
  $dest = Join-Path $root $key
  $out  = Join-Path $dest 'drag-lint.exe'
  if (Test-Path -LiteralPath $out) { return $out }
  [IO.Directory]::CreateDirectory($root) | Out-Null
  $tmp = Join-Path $root ('tmp-' + [guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($tmp) | Out-Null
  Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '\.(exe|dll|castlib)$' -and $_.Name -notmatch '\.bak' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $tmp }
  if (Test-Path -LiteralPath (Join-Path $dir 'rules')) { Copy-Item -LiteralPath (Join-Path $dir 'rules') -Destination $tmp -Recurse }
  try { [IO.Directory]::Move($tmp, $dest) } catch { [IO.Directory]::Delete($tmp, $true) }
  return $out
}