<#
  run_facts_init_section.ps1 -- B10 F2: a ref inside a unit's initialization or
  finalization section belongs to that section.

  The parser emits such refs with enclosing_symbol_id NULL although the section
  has a symbol row. ResolveSectionEnclosing (a resolve writer) backfills them
  from the section's start..end range BEFORE the call stream, so three things
  follow, and all are checked on real output:
    * no NULL enclosing ref is left inside a section range;
    * a dotted receiver in a section types at all (TypeReceiver gave up on a
      NULL enclosing, so `GThing.Ping;` had no edge);
    * call-path can start from <Unit>.initialization.

  POSITIVE CONTROLS: a ref OUTSIDE every section stays NULL (a rule that wrote
  every NULL ref would pass the first check), and the section's rows are counted
  (an empty result would pass it too). On a 1.43 engine the attribution checks
  fail, which is the RED this guard was written against.

  Usage: pwsh -File tests\autotest\run_facts_init_section.ps1 [-Exe <drag-lint.exe>]
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-facts-init-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail) -ForegroundColor $(if ($Ok) { 'Green' } else { 'Red' })
  if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
$src = Join-Path $WorkDir 'src'
[void][IO.Directory]::CreateDirectory($src)
$db = Join-Path $WorkDir 'facts.sqlite'
$pas = Join-Path $src 'InitFx.pas'

$unitText = @'
unit InitFx;

interface

type
  TThing = class
  public
    procedure Ping;
  end;

var
  GThing: TThing;

procedure Boot;
procedure NeverCalled;
procedure OnlyFromSection;
function MakeThing: TThing;

implementation

procedure TThing.Ping;
begin
end;

function MakeThing: TThing;
begin
  Result:= TThing.Create;
end;

procedure Boot;
begin
  GThing.Ping;
end;

procedure NeverCalled;
begin
end;

procedure OnlyFromSection;
begin
end;

initialization
  GThing:= MakeThing;
  Boot;
  OnlyFromSection;
  GThing.Ping;

finalization
  GThing.Free;

end.
'@

function Scalar([string]$Sql) {
  $j = (& $Exe sql --query $Sql --db $db --json) | Out-String | ConvertFrom-Json
  return $j.rows[0][0]
}

try {
  [IO.File]::WriteAllText($pas, ($unitText -replace "`r?`n", "`r`n"))
  & $Exe index $src --db $db *> (Join-Path $WorkDir 'index1.log')
  Check 'fixture indexes' ($LASTEXITCODE -eq 0)

  $sections = "(SELECT id, file_id, start_line, end_line FROM symbols WHERE kind IN ('initialization','finalization'))"
  $nullIn = "SELECT COUNT(*) FROM refs r JOIN $sections s ON s.file_id = r.file_id AND r.start_line BETWEEN s.start_line AND s.end_line WHERE r.enclosing_symbol_id IS NULL"
  Check 'F2: 0 NULL enclosing refs inside a section range' ((Scalar $nullIn) -eq 0)

  $initCount = Scalar "SELECT COUNT(*) FROM refs r JOIN symbols s ON s.id = r.enclosing_symbol_id WHERE s.qualified_name = 'InitFx.initialization'"
  Check 'POSITIVE: initialization owns its refs' ($initCount -ge 5) "count=$initCount"
  $finCount = Scalar "SELECT COUNT(*) FROM refs r JOIN symbols s ON s.id = r.enclosing_symbol_id WHERE s.qualified_name = 'InitFx.finalization'"
  Check 'POSITIVE: finalization owns its refs' ($finCount -ge 1) "count=$finCount"

  $outside = "SELECT COUNT(*) FROM refs r WHERE r.enclosing_symbol_id IS NULL AND NOT EXISTS (SELECT 1 FROM $sections s WHERE s.file_id = r.file_id AND r.start_line BETWEEN s.start_line AND s.end_line)"
  $outsideNull = Scalar $outside
  Check 'POSITIVE: a ref outside every section stays NULL' ($outsideNull -ge 1) "count=$outsideNull"

  $dotted = Scalar "SELECT COUNT(*) FROM refs r JOIN symbols s ON s.id = r.enclosing_symbol_id WHERE s.qualified_name = 'InitFx.initialization' AND r.kind = 'call' AND r.name_text = 'Ping' AND r.symbol_id IS NOT NULL"
  Check 'a dotted receiver in a section now binds (GThing.Ping)' ($dotted -eq 1) "count=$dotted"

  $direct = & $Exe call-path --from 'InitFx.initialization' --to 'OnlyFromSection' --json --db $db
  $directExit = $LASTEXITCODE
  $directTxt = $direct | Out-String
  Check 'call-path from <Unit>.initialization finds a direct callee' (($directExit -eq 0) -and ($directTxt -match 'OnlyFromSection')) "exit=$directExit"
  $hops = & $Exe call-path --from 'InitFx.initialization' --to 'TThing.Ping' --json --db $db
  Check 'call-path from <Unit>.initialization reaches a callee' (($LASTEXITCODE -eq 0) -and (($hops | Out-String) -match 'Ping')) "exit=$LASTEXITCODE"
  & $Exe call-path --from 'InitFx.finalization' --to 'OnlyFromSection' --json --db $db *> $null
  Check 'POSITIVE: finalization has no such path (exit 1)' ($LASTEXITCODE -eq 1) "exit=$LASTEXITCODE"

  $dead = (& $Exe find-deadcode --db $db 2>&1) | Out-String
  Check 'POSITIVE: a routine nothing calls is still reported dead' ($dead -match 'NeverCalled')
  Check 'a routine called only from a section is not dead' ($dead -notmatch 'OnlyFromSection')

  # Incremental: the file's refs are re-emitted NULL, the pass must attribute them again.
  [IO.File]::WriteAllText($pas, (($unitText -replace "`r?`n", "`r`n") -replace 'procedure NeverCalled;\r\nbegin', "procedure NeverCalled;`r`n`r`nbegin"))
  & $Exe index $src --db $db *> (Join-Path $WorkDir 'index2.log')
  Check 'edited fixture reindexes' ($LASTEXITCODE -eq 0)
  Check 'F2: 0 NULL after an incremental re-emit' ((Scalar $nullIn) -eq 0)
  $again = Scalar "SELECT COUNT(*) FROM refs r JOIN symbols s ON s.id = r.enclosing_symbol_id WHERE s.qualified_name = 'InitFx.initialization'"
  Check 'POSITIVE: the re-emitted section still owns its refs' ($again -eq $initCount) "count=$again"
}
finally {
  if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "note: could not delete $WorkDir" } }
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
