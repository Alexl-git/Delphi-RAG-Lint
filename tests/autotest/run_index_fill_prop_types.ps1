<#
  run_index_fill_prop_types.ps1 -- `index` FILLS the type of a bare
  re-published property (`published property Text;`) at index time.

  Owner ruling 2026-10-29: the type of a re-publication must be in the index
  when indexing ends -- not recovered by hover write-back -- so the CLI, the
  LSP (read-only stores) and the library DBs need no runtime work.

  Fixture (two units, so an incremental run re-parses ONLY the base unit):
    uBase    : TBase declares `property Text: string read FText write FText`.
    uDerived : TMid(TBase) and TDerived(TMid) both re-publish `property Text;`;
               TOrphan(TNowhere) re-publishes `property Caption;` with an
               ancestor no index holds.

  ORDER:
    (1) FULL INDEX  -- TDerived.Text and TMid.Text carry ': string' (the one
                       memoized format); TBase.Text keeps its own 'string'.
    (2) NEGATIVE    -- TOrphan.Caption stays empty (never fabricates a type).
                       Also (1): a generic property keeps its WHOLE type and an
                       indexed one its element type (no cut at the first blank).
    (3) QUERY/HOVER -- `query --name Text --json` and a read-only hover show
                       the type for TDerived.Text.
    (4) INCREMENTAL -- edit TBase.Text to Integer, re-index without --rebuild:
                       both re-publications (in the UNCHANGED unit) now read
                       ': Integer' -- a stale memo is replaced, not kept.
    (5) EXISTING DB -- bare rows blanked back to empty (a pre-pass index) are
                       filled by a run that parses NOTHING.
    (6) SURFACE     -- `hover --write-back` is gone (the fill made it redundant).

  RED (pre-change engine): (1), (3) json type check via the DB, (4), (5), (6)
  fail; (2) and the TBase control pass.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-index-fill-prop-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$src = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $src | Out-Null

$baseText = @'
unit uBase;

interface

uses System.Generics.Collections;

type
  TBase = class(TObject)
  private
    FText: string;
    FMap: TDictionary<string, Integer>;
    function GetItem(I: Integer): TObject;
  protected
    property Text: string read FText write FText;
    property Map: TDictionary<string, Integer> read FMap write FMap;
    property Items[I: Integer]: TObject read GetItem; default;
  end;

implementation

function TBase.GetItem(I: Integer): TObject;
begin
  Result:= nil;
end;

end.
'@
$derivedText = @'
unit uDerived;

interface

uses uBase;

type
  TMid = class(TBase)
  public
    property Text;
  end;

  TDerived = class(TMid)
  published
    property Text;
    property Map;
    property Items;
  end;

  TOrphan = class(TNowhere)
  published
    property Caption;
  end;

implementation

end.
'@
$baseFile = Join-Path $src 'uBase.pas'
WriteAnsi $baseFile $baseText
WriteAnsi (Join-Path $src 'uDerived.pas') $derivedText
$db = Join-Path $WorkDir 'fill.sqlite'

function SigOf([string]$qn, [string]$d = $db) {
  $r = (& $Exe sql --db $d --json --query "select signature from symbols where qualified_name = '$qn'" 2>$null) -join "`n" | ConvertFrom-Json
  if ($null -eq $r.rows -or @($r.rows).Count -eq 0) { return '<no row>' }
  $v = @($r.rows)[0][0]
  if ($null -eq $v) { return '' } else { return [string]$v }
}

Write-Host ''
Write-Host '(1) a full index fills the re-publications' -ForegroundColor Cyan
$out = (& $Exe index $src --db $db 2>&1) -join "`n"
Check 'index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
Check 'index announces the prop-types stage' ($out -match 'stage: prop-types') "got: [$($out.Length) chars]"
Check 'TDerived.Text = : string' ((SigOf 'uDerived.TDerived.Text') -eq ': string') "got: [$(SigOf 'uDerived.TDerived.Text')]"
Check 'TMid.Text = : string' ((SigOf 'uDerived.TMid.Text') -eq ': string') "got: [$(SigOf 'uDerived.TMid.Text')]"
Check 'generic: TDerived.Map keeps the WHOLE type' ((SigOf 'uDerived.TDerived.Map') -eq ': TDictionary<string, Integer>') "got: [$(SigOf 'uDerived.TDerived.Map')]"
Check 'indexed: TDerived.Items = : TObject' ((SigOf 'uDerived.TDerived.Items') -eq ': TObject') "got: [$(SigOf 'uDerived.TDerived.Items')]"
Check 'CONTROL: TBase.Text keeps its own extracted string' ((SigOf 'uBase.TBase.Text') -eq 'string') "got: [$(SigOf 'uBase.TBase.Text')]"

Write-Host ''
Write-Host '(2) an unresolvable ancestor is left empty' -ForegroundColor Cyan
Check 'TOrphan.Caption stays empty' ((SigOf 'uDerived.TOrphan.Caption') -eq '') "got: [$(SigOf 'uDerived.TOrphan.Caption')]"

Write-Host ''
Write-Host '(3) query and a read-only hover see the stored type' -ForegroundColor Cyan
$q = @((& $Exe query --name Text --db $db --json 2>$null) -join "`n" | ConvertFrom-Json) |
  Where-Object { $_.qualified_name -eq 'uDerived.TDerived.Text' }
Check 'query --name Text --json carries : string for TDerived.Text' (@($q).Count -eq 1 -and $q[0].signature -eq ': string') "got: [$(@($q).Count) row(s), sig=$($q.signature)]"
$h = (& $Exe hover --qname uDerived.TDerived.Text --db $db --format json 2>$null) -join "`n" | ConvertFrom-Json
Check 'hover json type = string' ($h.type -eq 'string') "got: [$($h.type)]"
Check 'hover json declared_in = uBase.TBase' ($h.declared_in -eq 'uBase.TBase') "got: [$($h.declared_in)]"

Write-Host ''
Write-Host '(4) incremental: the ancestor changes type, the unchanged unit follows' -ForegroundColor Cyan
# files.parsed_at has 1 s granularity and the scope is parsed_at >= the last
# pass's start (inclusive, so a same-second file is re-checked, never missed).
# Step past (1)'s second with an unrelated unit, then past that one's, so the
# scope assertion below sees only uBase's change.
Start-Sleep -Seconds 1
WriteAnsi (Join-Path $src 'uOther.pas') "unit uOther;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nend.`r`n"
$null = & $Exe index $src --db $db 2>$null
Start-Sleep -Seconds 1
WriteAnsi $baseFile (($baseText -replace 'FText: string', 'FText: Integer') -replace 'Text: string read', 'Text: Integer read')
$out = (& $Exe index $src --db $db 2>&1) -join "`n"
Check 'incremental index exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
# Scoped: the 4 same-named rows of what uBase declares; TOrphan.Caption is out of scope.
Check 'incremental re-checks only the affected rows (4 of 5)' ($out -match 'prop-types: 4 bare re-publication\(s\), 2 filled, 0 unresolved') "got: [$(($out -split "`n" | Where-Object { $_ -match 'prop-types:' }) -join ' | ')]"
Check 'premise: TBase.Text is Integer now' ((SigOf 'uBase.TBase.Text') -eq 'Integer') "got: [$(SigOf 'uBase.TBase.Text')]"
Check 'TDerived.Text = : Integer' ((SigOf 'uDerived.TDerived.Text') -eq ': Integer') "got: [$(SigOf 'uDerived.TDerived.Text')]"
Check 'TMid.Text = : Integer' ((SigOf 'uDerived.TMid.Text') -eq ': Integer') "got: [$(SigOf 'uDerived.TMid.Text')]"
$out = (& $Exe index $src --db $db 2>&1) -join "`n"
Check 'no-change re-index keeps : Integer' ((SigOf 'uDerived.TDerived.Text') -eq ': Integer') "got: [$(SigOf 'uDerived.TDerived.Text')]"
Check 'no-change re-index skips the pass (marker)' ($out -match 'stage: prop-types -- skipped') "got: [$(($out -split "`n" | Where-Object { $_ -match 'prop-types' }) -join ' | ')]"

Write-Host ''
Write-Host '(5) an existing unfilled index is filled by the next run (nothing parsed)' -ForegroundColor Cyan
# An index written before this pass existed = bare rows with an EMPTY
# signature. Recreate that state on the CURRENT DB (no file changed since (4)),
# so the next run parses nothing and must still fill -- the cheap unfilled path.
$py = Get-Command python -ErrorAction SilentlyContinue
if ($null -ne $py) {
  $null = & $py.Source -I -c "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute(""update symbols set signature='' where kind='property' and qualified_name in ('uDerived.TDerived.Text','uDerived.TMid.Text')""); c.execute(""delete from schema_meta where key='prop_types_filled'""); c.commit(); c.close()" $db
  Check 'premise: rows blanked like a pass-less index' ((SigOf 'uDerived.TDerived.Text') -eq '') "got: [$(SigOf 'uDerived.TDerived.Text')]"
  $out = (& $Exe index $src --db $db 2>&1) -join "`n"
  Check 'prop-types stage ran on a run that parsed nothing' ($out -match 'prop-types: 5 bare re-publication\(s\), 2 filled, 1 unresolved') "got: [$(($out -split "`n" | Where-Object { $_ -match 'prop-types' }) -join ' | ')]"
  Check 'TDerived.Text re-filled = : Integer' ((SigOf 'uDerived.TDerived.Text') -eq ': Integer') "got: [$(SigOf 'uDerived.TDerived.Text')]"
  Check 'TMid.Text re-filled = : Integer' ((SigOf 'uDerived.TMid.Text') -eq ': Integer') "got: [$(SigOf 'uDerived.TMid.Text')]"
} else {
  Write-Host '  [SKIP] no python on PATH to blank the rows' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '(6) hover --write-back is removed' -ForegroundColor Cyan
$null = & $Exe hover --qname uDerived.TDerived.Text --db $db --write-back 2>$null
Check 'hover --write-back is rejected (non-zero exit)' ($LASTEXITCODE -ne 0) "exit=$LASTEXITCODE"

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
} finally {
  if ($WorkDir -and (Test-Path $WorkDir)) { try { [System.IO.Directory]::Delete($WorkDir, $true) } catch { $null = $_ } }
}
