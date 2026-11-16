<#
  fixtures\v1511-RES\common.ps1 -- shared by the run_v1511_RES_*.ps1 runners (dot-sourced).

  Build-ResFixture copies tests\autotest\fixtures\v1511-RES into a work folder
  and indexes it with the engine under test:
    lib.sqlite    the library folder (ResLib.pas)
    proj.sqlite   proj\ + prog\ with --library-db lib.sqlite
    nolib.sqlite  the same sources with NO library store (positive control:
                  the library store, not the fixture, makes the bindings)
  Every index run passes --db, so no real project DB is ever touched.

  Get-ResRefs returns one object per refs row. sql --json rows are POSITIONAL
  arrays, so each row is mapped onto the column names by index.
#>
function Build-ResFixture([string]$ExePath, [string]$WorkDir) {
  $src = $PSScriptRoot
  New-Item -ItemType Directory -Force $WorkDir | Out-Null
  $code = Join-Path $WorkDir 'code'
  New-Item -ItemType Directory -Force $code | Out-Null
  Copy-Item (Join-Path $src 'lib') $WorkDir -Recurse -Force
  Copy-Item (Join-Path $src 'proj\*') $code -Force
  Copy-Item (Join-Path $src 'prog\*') $code -Force
  $r = [pscustomobject]@{
    Lib   = Join-Path $WorkDir 'lib.sqlite'
    Proj  = Join-Path $WorkDir 'proj.sqlite'
    NoLib = Join-Path $WorkDir 'nolib.sqlite'
    Log   = ''
  }
  & $ExePath index (Join-Path $WorkDir 'lib') --db $r.Lib *> $null
  $r.Log = (& $ExePath index $code --db $r.Proj --library-db $r.Lib 2>&1) -join "`n"
  & $ExePath index $code --db $r.NoLib *> $null
  return $r
}

function Get-ResRefs([string]$ExePath, [string]$Db) {
  $q = 'select coalesce(s.name, ''''), f.path, r.kind, r.name_text, coalesce(r.receiver_text, ''''), ' +
       'coalesce(r.external_target, ''''), coalesce(r.external_kind, ''''), coalesce(r.symbol_id, 0), r.start_line ' +
       'from refs r join files f on f.id = r.file_id left join symbols s on s.id = r.enclosing_symbol_id ' +
       'order by f.path, r.start_line, r.start_col'
  $j = (& $ExePath sql --query $q --db $Db --json 2>$null) -join "`n" | ConvertFrom-Json
  $out = @()
  foreach ($row in $j.rows) {
    $out += [pscustomobject]@{
      Encl     = [string]$row[0]
      File     = [IO.Path]::GetFileName([string]$row[1])
      Kind     = [string]$row[2]
      Name     = [string]$row[3]
      Receiver = [string]$row[4]
      Target   = [string]$row[5]
      XKind    = [string]$row[6]
      SymbolId = [long]$row[7]
      Line     = [int]$row[8]
    }
  }
  return ,@($out)
}

# The ONE ref of that kind and name inside routine $Encl of $File ('' = the main block / unit level).
function Find-ResRef($Refs, [string]$File, [string]$Encl, [string]$Kind, [string]$Name, [string]$Receiver = '*') {
  $hit = @($Refs | Where-Object {
    $_.File -eq $File -and $_.Encl -eq $Encl -and $_.Kind -eq $Kind -and $_.Name -eq $Name -and
    (($Receiver -eq '*') -or ($_.Receiver -eq $Receiver)) })
  if ($hit.Count -ne 1) { return $null }
  return $hit[0]
}

function Get-ResSummaries([string]$ExePath, [string]$Db) {
  $q = 'select s.qualified_name, f.effect_summary from symbols s join symbol_facts f on f.symbol_id = s.id'
  $j = (& $ExePath sql --query $q --db $Db --json 2>$null) -join "`n" | ConvertFrom-Json
  $map = @{}
  foreach ($r in $j.rows) { $map[[string]$r[0]] = [string]$r[1] }
  return $map
}

function Test-ResFlag([string]$Summary, [string]$Flag) {
  return @($Summary -split ',' | Where-Object { $_ -eq $Flag }).Count -gt 0
}
