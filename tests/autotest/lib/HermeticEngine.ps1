<#
  HermeticEngine.ps1 -- 150 H1 item 1. Dot-source, then: $Exe = Get-HermeticEngine $Exe
  A machine drag-lint.json beside the exe names the real platform libraries and outranks a
  guard's fixtures. Get-HermeticEngine returns $Exe untouched when no drag-lint.json sits
  beside it; otherwise it returns an engine copy WITHOUT the manifest (exe, dlls, rules\)
  in %TEMP%\drag-lint-hermetic\<key>, cached by exe size+mtime + rules\ count/size/newest mtime, shared by every guard (keeps the newest 3 keys, H01)
  (built in a private dir, then moved into place, so parallel guards do not race).
#>
function Get-HermeticEngine {
  param([Parameter(Mandatory)][string] $Exe)
  $src = (Resolve-Path -LiteralPath $Exe).Path
  $dir = Split-Path -Parent $src
  if (-not (Test-Path -LiteralPath (Join-Path $dir 'drag-lint.json'))) { return $src }
  $fi  = Get-Item -LiteralPath $src
  # rules\ is part of the key (RMU FOUND, v151): a rules\*.scm edit beside the SAME exe must
  # not be served from a cache built with the old rule files.
  $rf  = @(Get-ChildItem -LiteralPath (Join-Path $dir 'rules') -File -Recurse -ErrorAction SilentlyContinue)
  $rk  = '{0}-{1}-{2}' -f $rf.Count, ($rf | Measure-Object -Property Length -Sum).Sum, [long](($rf | ForEach-Object { $_.LastWriteTimeUtc.Ticks } | Measure-Object -Maximum).Maximum)
  $key = '{0}-{1}-r{2}' -f $fi.Length, $fi.LastWriteTimeUtc.Ticks, $rk
  $root = Join-Path ([IO.Path]::GetTempPath()) 'drag-lint-hermetic'
  $dest = Join-Path $root $key
  $out  = Join-Path $dest 'drag-lint.exe'
  # 1.52.3 TESTS-ENV: an entry can be INCOMPLETE (a parallel H01 eviction that hit locked files
  # leaves a half-deleted dir whose exe survives): the cached exe then dies 0xC0000135 and the
  # runners only print "index failed". Heal: copy back every companion the source dir has and the
  # entry lacks (exe/dll/castlib by name, every rules\ file by relative path); a copy that fails is skipped, never thrown.
  if (Test-Path -LiteralPath $out) {
    $want = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '\.(exe|dll|castlib)$' -and $_.Name -notmatch '\.bak' })
    foreach ($w in $want) {
      if (-not (Test-Path -LiteralPath (Join-Path $dest $w.Name))) {
        try { Copy-Item -LiteralPath $w.FullName -Destination $dest -ErrorAction Stop } catch { $null = $_ }
      }
    }
    $rsrc = Join-Path $dir 'rules'
    if (Test-Path -LiteralPath $rsrc) {
      foreach ($rf2 in @(Get-ChildItem -LiteralPath $rsrc -File -Recurse)) {
        $rel = $rf2.FullName.Substring($rsrc.Length).TrimStart('\')
        $dst = Join-Path (Join-Path $dest 'rules') $rel
        if (-not (Test-Path -LiteralPath $dst)) {
          try { [IO.Directory]::CreateDirectory((Split-Path -Parent $dst)) | Out-Null; Copy-Item -LiteralPath $rf2.FullName -Destination $dst -ErrorAction Stop } catch { $null = $_ }
        }
      }
    }
    return $out
  }
  [IO.Directory]::CreateDirectory($root) | Out-Null
  $tmp = Join-Path $root ('tmp-' + [guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($tmp) | Out-Null
  Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match '\.(exe|dll|castlib)$' -and $_.Name -notmatch '\.bak' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $tmp }
  if (Test-Path -LiteralPath (Join-Path $dir 'rules')) { Copy-Item -LiteralPath (Join-Path $dir 'rules') -Destination $tmp -Recurse }
  try { [IO.Directory]::Move($tmp, $dest) } catch { [IO.Directory]::Delete($tmp, $true) }
  # H01: every engine rebuild adds a ~100 MB key dir; keep the newest 3 (by creation), evict the rest.
  # A dir still in use by a running guard is locked: the delete fails and is skipped, never thrown.
  @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'tmp-*' } |
    Sort-Object CreationTimeUtc -Descending | Select-Object -Skip 3) | ForEach-Object {
      try { [IO.Directory]::Delete($_.FullName, $true) } catch { $null = $_ }
    }
  return $out
}