<#
  run_doc_literal_symbol_id.ps1 -- a /// doc-comment literal belongs to the
  declaration it DOCUMENTS, not to the scope that contains it.

  THE DEFECT. Every `kind = 'doc'` row in string_literals took its symbol_id from
  the containing-symbol line map, like a string literal does. A /// block sits
  ABOVE its declaration, so the line is inside the enclosing class (for a member)
  or the unit (for a type or a unit-level routine): symbol_id named the scope,
  never the documented symbol. Readers that want "the doc text of X"
  (query --text --near, query --concept) had to work around it.

  THE FIX. The indexer already decides which declaration a doc region documents
  (FindDocRegionAbove -> UpsertSymbolDoc). The doc literal now takes THAT
  symbol's id; one attachment rule, not a second one.

  BODY LITERALS (owner ruling 2026-10-28, same re-parse). A string literal in a
  routine's IMPLEMENTATION body took the symbol whose DECLARATION span covers
  the line -- for a method that span is in the class, so a body literal landed
  on the unit. It now takes the innermost routine whose body (impl span)
  covers it; a local const/var declared inside that body stays more specific;
  initialization/finalization is not a routine and keeps the containing rule
  (the section symbol, e.g. DocLit.initialization).

  IMPL DOCS. A /// block directly above a method IMPLEMENTATION, which no
  declaration claims, belongs to that routine.

  CONTROL: a // comment above a declaration keeps the containing-scope rule
  (only 'doc' rows are re-attributed by doc position).

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = ''
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

$exePath = (Resolve-Path $Exe).Path
if ($WorkDir -eq '') {
  $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ("doclit_" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$db = Join-Path $WorkDir 'doclit.sqlite'

# Each marker word occurs exactly ONCE.
$src = @(
  'unit DocLit;',
  '',
  'interface',
  '',
  'type',
  '  /// <summary>wombat type doc</summary>',
  '  TDocHost = class',
  '  private',
  '    /// <summary>walrus field doc</summary>',
  '    FCount: Integer;',
  '    // gecko plain comment above a field',
  '    FOther: Integer;',
  '  public',
  '    /// <summary>meerkat method doc</summary>',
  '    procedure Run;',
  '    procedure Stop;',
  '    /// <summary>ibis property doc</summary>',
  '    property Count: Integer read FCount;',
  '  end;',
  '',
  '/// <summary>tapir routine doc</summary>',
  'procedure UnitLevel;',
  '',
  'implementation',
  '',
  'procedure TDocHost.Run;',
  'begin',
  '  WriteLn(''okapi body literal'');',
  'end;',
  '',
  '/// <summary>heron impl doc</summary>',
  'procedure TDocHost.Stop;',
  'begin',
  'end;',
  '',
  'procedure UnitLevel;',
  'const',
  '  CLocal = ''lynx local const'';',
  '',
  '  procedure Inner;',
  '  begin',
  '    WriteLn(''marmot nested literal'');',
  '  end;',
  '',
  'begin',
  '  Inner;',
  '  WriteLn(''badger outer literal'');',
  'end;',
  '',
  'initialization',
  '  WriteLn(''bison init literal'');',
  'end.'
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $WorkDir 'DocLit.pas'), $src + "`r`n", [Text.Encoding]::ASCII)

# Fresh scratch DB, directory scan: not a project DB, so no widening concern.
$idxOut = & $exePath index $WorkDir --db $db 2>&1
$idxExit = $LASTEXITCODE
Check 'the fixture indexed' ($idxExit -eq 0 -and (Test-Path $db)) "exit=$idxExit"
if (-not (Test-Path $db)) {
  Write-Host ($idxOut -join "`n") -ForegroundColor DarkGray
  Write-Host 'FAIL' -ForegroundColor Red; exit 1
}

# Owner of the literal whose text contains $Word: qualified_name or '' (NULL / no row).
# sql --json rows are POSITIONAL arrays -- read by column index, never $row.name.
function OwnerOf([string]$Word) {
  $q = "SELECT COALESCE(s.qualified_name, '') AS q FROM string_literals sl " +
       "LEFT JOIN symbols s ON s.id = sl.symbol_id WHERE sl.text LIKE '%$Word%'"
  $raw = (& $exePath sql --query $q --db $db --json 2>$null) -join "`n"
  if (-not $raw.Trim()) { return '<no output>' }
  $d = $raw | ConvertFrom-Json
  $rows = @($d.rows)
  if ($rows.Count -ne 1) { return "<$($rows.Count) rows>" }
  return [string]$rows[0][0]
}

Write-Host ''
Write-Host 'A /// literal is owned by the declaration it documents' -ForegroundColor Cyan
$cases = [ordered]@{
  'wombat'  = 'DocLit.TDocHost'
  'walrus'  = 'DocLit.TDocHost.FCount'
  'meerkat' = 'DocLit.TDocHost.Run'
  'ibis'    = 'DocLit.TDocHost.Count'
  'tapir'   = 'DocLit.UnitLevel'
  'heron'   = 'DocLit.TDocHost.Stop'
}
foreach ($k in $cases.Keys) {
  $got = OwnerOf $k
  Check ("$k doc -> " + $cases[$k]) ($got -eq $cases[$k]) "got=$got"
}

Write-Host ''
Write-Host 'A body literal is owned by the innermost routine BODY' -ForegroundColor Cyan
$body = [ordered]@{
  'okapi'  = 'DocLit.TDocHost.Run'
  'marmot' = 'DocLit.UnitLevel.Inner'
  'badger' = 'DocLit.UnitLevel'
  'lynx'   = 'DocLit.UnitLevel.CLocal'
  # not a routine: keeps the containing rule, which already names the section
  # symbol (measured on the base; more specific than the unit, so unchanged)
  'bison'  = 'DocLit.initialization'
}
foreach ($k in $body.Keys) {
  $got = OwnerOf $k
  Check ("$k literal -> " + $body[$k]) ($got -eq $body[$k]) "got=$got"
}

Write-Host 'CONTROL -- a // comment is not re-attributed by doc position' -ForegroundColor Cyan
$got = OwnerOf 'gecko'
Check 'a // comment above a field -> the containing class (unchanged)' ($got -eq 'DocLit.TDocHost') "got=$got"

try { [IO.Directory]::Delete($WorkDir, $true) } catch { }

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
