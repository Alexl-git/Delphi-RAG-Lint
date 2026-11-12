<#
  run_doc_stale_anchor_reindex_file_only.ps1 -- 152b DOCU2: the ruling-D-2
  recovery of `document --unit` (ReindexAfterStaleAnchor) must refresh the ONE
  stale file, never walk the unit's folder into a project database.

  THE DEFECT (152b DOCU, FOUND-152b)
  ----------------------------------
  With no --project, ReindexAfterStaleAnchor indexed ExtractFileDir(<unit>):
  `index <dir> --db <projectDb>`, the widening the global rules forbid. The
  index verb refuses a folder into a project-stamped DB (exit 2), so on a
  project DB the recovery always FAILED ("doc: the reindex FAILED") and the run
  exited 1; on an unstamped DB it would have walked every loose .pas beside the
  unit into the index.

  WHAT IS ASSERTED
  ----------------
    P1  positive control: on a fresh index, `document --unit App.pas` (dry run)
        exits 0 and renders an edit; files= of the DB = 3 (Fx.dpr, Core, App).
    R1  App.pas's interface moved down two lines, NO reindex, a loose Loose.pas
        beside it (not in Fx.dpr): `document --unit App.pas --apply` (no
        --project) exits 0 and writes. (Base 1.50.0-alpha: the folder reindex
        is refused, "reindex FAILED", exit 1.)
    R2  the D-2 message is printed (the recovery really ran).
    R3  the DB still holds exactly the same 3 files; Loose.pas is NOT indexed;
        scan_type is still `project`.
    R4  App.pas's doc block lands directly above UseAlpha (the reindexed
        coordinate), not two lines above it.

  Run from a neutral cwd, pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
try {
$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }
$exePath = (Resolve-Path $Exe).Path

$scratch = Join-Path C:\TEMP "draglint_doc_anchor_file_$PID"
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory -Path $scratch | Out-Null
function WriteAscii([string]$Path, [string]$Text) {
  $t = $Text -replace "`r`n","`n" -replace "`n","`r`n"
  [System.IO.File]::WriteAllText($Path, $t, (New-Object System.Text.ASCIIEncoding))
}
WriteAscii (Join-Path $scratch 'Core.pas') @'
unit Core;

interface

function Twice(const A: Integer): Integer;

implementation

function Twice(const A: Integer): Integer;
begin
  Result := A * 2;
end;

end.
'@
WriteAscii (Join-Path $scratch 'App.pas') @'
unit App;

interface

function UseAlpha(const A: Integer): Integer;

implementation

uses Core;

function UseAlpha(const A: Integer): Integer;
begin
  Result := Twice(A);
end;

end.
'@
WriteAscii (Join-Path $scratch 'Fx.dpr') @'
program Fx;

uses
  Core in 'Core.pas',
  App in 'App.pas';

begin
end.
'@
$db   = Join-Path $scratch 'fx.sqlite'
$dpr  = Join-Path $scratch 'Fx.dpr'
$app  = Join-Path $scratch 'App.pas'

function RunEngine([string[]]$EngineArgs) {
  $out = & $exePath @EngineArgs 2>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Text = $out }
}
# Indexed file paths, from an --output dump (sql --json rows are positional and capped).
function IndexedFiles {
  $dump = Join-Path $scratch 'files.json'
  $q = RunEngine @('sql','--db',$db,'--query','SELECT path FROM files ORDER BY path','--json','--output',$dump)
  if ($q.Code -ne 0) { throw "sql failed: $($q.Text)" }
  $j = Get-Content $dump -Raw | ConvertFrom-Json
  return @($j.rows | ForEach-Object { [IO.Path]::GetFileName([string]$_[0]) })
}
function ScanType {
  $dump = Join-Path $scratch 'meta.json'
  $q = RunEngine @('sql','--db',$db,'--query',"SELECT value FROM schema_meta WHERE key = 'scan_type'",'--json','--output',$dump)
  if ($q.Code -ne 0) { throw "sql failed: $($q.Text)" }
  $j = Get-Content $dump -Raw | ConvertFrom-Json
  return [string]$j.rows[0][0]
}

$ix = RunEngine @('index','--project',$dpr,'--db',$db)
if ($ix.Code -ne 0) { throw "fixture index failed: $($ix.Text)" }
$before = IndexedFiles

$p1 = RunEngine @('document','--unit',$app,'--db',$db)
Check 'P1 fresh index: exit 0, an edit rendered' (($p1.Code -eq 0) -and ($p1.Text -match 'insert after line')) "exit $($p1.Code)"
Check 'P1 fresh index: 3 files indexed' ($before.Count -eq 3) ($before -join ',')
Check 'P1 fresh index: scan_type project' ((ScanType) -eq 'project')

# Stale own file: the interface moves down two lines; a loose unit sits beside it.
WriteAscii $app ([IO.File]::ReadAllText($app).Replace("interface`r`n", "interface`r`n`r`n// moved`r`n"))
WriteAscii (Join-Path $scratch 'Loose.pas') @'
unit Loose;

interface

procedure NotInTheProject;

implementation

procedure NotInTheProject;
begin
end;

end.
'@

$r1 = RunEngine @('document','--unit',$app,'--db',$db,'--apply','--no-backup')
Check 'R1 stale own file, no --project: exit 0, applied' (($r1.Code -eq 0) -and ($r1.Text -match 'applied')) "exit $($r1.Code)"
Check 'R2 the D-2 reindex-and-retry ran' ($r1.Text -match 'reindexing and retrying once') ($r1.Text.Trim() -split "`n" | Select-Object -Last 2)
Check 'R2 the reindex did not fail' (-not ($r1.Text -match 'reindex FAILED'))
$after = IndexedFiles
Check 'R3 same 3 files indexed' (($after.Count -eq 3) -and (($after -join ',') -eq ($before -join ','))) ($after -join ',')
Check 'R3 Loose.pas not indexed' (-not ($after -contains 'Loose.pas'))
Check 'R3 scan_type still project' ((ScanType) -eq 'project')
$lines = [IO.File]::ReadAllLines($app)
$decl = [Array]::FindIndex($lines, [Predicate[string]]{ param($l) $l -match '^function UseAlpha' })
Check 'R4 doc block directly above UseAlpha' (($decl -gt 0) -and ($lines[$decl - 1] -match '^///')) "decl line $($decl + 1)"

if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
if ($fail) { Write-Host 'run_doc_stale_anchor_reindex_file_only: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_doc_stale_anchor_reindex_file_only: ALL PASS' -ForegroundColor Green; exit 0
} catch { Write-Host "run_doc_stale_anchor_reindex_file_only: ERROR $_" -ForegroundColor Red; exit 2 }
