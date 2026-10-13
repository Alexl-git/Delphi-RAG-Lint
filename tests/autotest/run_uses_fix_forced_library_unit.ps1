<#
  run_uses_fix_forced_library_unit.ps1 -- `uses-fix --only <LibraryUnit>` must
  act on a unit that is NOT in the project index.

  THE DEFECT THIS PINS (owner request 2026-10-13, ORM3 COMMON\BASICS.PAS):
    `lint` reported 21 unused-unit-in-uses findings on BASICS.PAS --
    System.Win.Registry among them -- and `uses-fix` proposed ONE candidate.
    Candidacy was decided from the PROJECT index only (`if not
    IndexedUnits.ContainsKey(uStem) then Continue`), and a library unit
    (RTL, VCL, DevExpress) is never a file in a project index. So the IDE's
    "Fix it" on such a finding -- which passes `--only <Unit>` -- came back
    `unmatched` for nearly every row.

  THE FIX: a unit named by --only that IS in this file's uses clause but got
  no index-driven candidate is a FORCED candidate. It is decided by compiling:
    * no initialization/finalization section -> try REMOVE; if that does not
      verify and the entry is in the interface, try MOVE to implementation;
    * HAS one (asked of the project store, then the --library-db / platform
      library store) -> never removed, only MOVED, because moving keeps the
      section running;
    * cannot tell -> skipped, never removed.

  Unlike run_uses_fix_json_and_only.ps1 this fixture REALLY COMPILES (it uses
  real RTL/VCL units against <BDS>\lib\Win64\release), so `verified` is a
  real verdict and --apply really writes -- which also covers the `backup`
  and `applied` fields that runner names as untested.

  Needs RAD Studio 37.0 and C:\Projects\.drag-lint\library-Win64.sqlite.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe   = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$LibDb = 'C:\Projects\.drag-lint\library-Win64.sqlite'
)
$scratch = Join-Path C:\TEMP "draglint_uses_fix_forced_$PID"
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f (@('FAIL','PASS')[[int][bool]$ok]), $n, $d) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if (-not $ok) { $script:fail = $true }
}
function WritePas([string]$Path, [string]$Text) {
  [System.IO.File]::WriteAllText($Path, (($Text -replace "`r`n", "`n") -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
}

Write-Host '== uses-fix: --only forces a LIBRARY unit to be decided by compiling ==' -ForegroundColor Cyan
$exePath = (Resolve-Path $Exe).Path
if (-not (Test-Path $LibDb)) { Write-Host "FATAL: library index not found: $LibDb" -ForegroundColor Red; exit 1 }
if (Test-Path $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
$src = Join-Path $scratch 'src'
New-Item -ItemType Directory -Path $src -Force | Out-Null
$db = Join-Path $scratch 'uf.sqlite'

# One entry per line: the editor only rewrites a clean single-unit entry.
#   System.SysUtils      used IN THE INTERFACE (Exception)      -> skipped
#   System.Win.Registry  unused, no init                         -> remove
#   System.StrUtils      used in the implementation only, no init -> remove
#                        fails to compile, so -> move
#   System.IniFiles      used in the implementation only, HAS init -> move,
#                        never remove
#   Vcl.Controls         unused, HAS init                        -> move, never
#                        remove (the section keeps running)
#   System.Classes       last entry, used in the interface -- never named
$main = @'
unit uMain;

interface

uses
  System.SysUtils,
  System.Win.Registry,
  System.StrUtils,
  System.IniFiles,
  Vcl.Controls,
  System.Classes;

type
  TMain = class(TComponent)
  private
    FErr: Exception;
  public
    procedure Run(const S: string);
  end;

implementation

procedure TMain.Run(const S: string);
var
  I: TIniFile;
begin
  I:= TIniFile.Create(ReverseString(S));
  I.Free;
end;

end.
'@
$unit = Join-Path $src 'uMain.pas'
WritePas $unit $main
$proj = Join-Path $src 'App.dproj'
WritePas $proj @'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup>
    <DCCReference Include="uMain.pas"/>
  </ItemGroup>
</Project>
'@

& $exePath index $src --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db) $db

function RunJson([string[]]$ExtraArgs) {
  $a = @('uses-fix', $unit, '--project', $proj, '--db', $db, '--library-db', $LibDb, '--platform', 'win64',
         '--remove-unused', '--format', 'json') + $ExtraArgs
  $raw = (& $exePath @a 2>$null | Out-String)
  $i = $raw.IndexOf('{')
  if ($i -lt 0) { return $null }
  try { return ($raw.Substring($i) | ConvertFrom-Json) } catch { return $null }
}
function ItemOf($J, [string]$Name) { @($J.items | Where-Object { $_.unit -eq $Name }) }

# PREMISE: the index-driven pass alone offers none of these -- they are not
# project files. Without this, a pass below could be the OLD path answering.
$plain = RunJson @()
Check 'P1 premise: with no --only, no library unit is a candidate' `
  (@($plain.items | Where-Object { $_.unit -match '^(System|Vcl)\.' }).Count -eq 0) `
  "items: $(@($plain.items | ForEach-Object { $_.unit }) -join ', ')"

$r = RunJson @('--only', 'System.Win.Registry')
$it = ItemOf $r 'System.Win.Registry'
Check 'R1 an unused no-init library unit is a candidate (not unmatched)' `
  (($it.Count -eq 1) -and (@($r.unmatched) -notcontains 'System.Win.Registry')) "unmatched=$(@($r.unmatched) -join ',')"
Check 'R2 ... it is REMOVED, and the removal verified' `
  (($it.kind -eq 'remove') -and ($it.status -eq 'verified')) "kind=$($it.kind) status=$($it.status) reason=$($it.reason)"

$s = RunJson @('--only', 'System.StrUtils')
$it = ItemOf $s 'System.StrUtils'
Check 'S1 a no-init unit used only in the implementation is MOVED (its removal does not compile)' `
  (($it.kind -eq 'move') -and ($it.status -eq 'verified')) "kind=$($it.kind) status=$($it.status) reason=$($it.reason)"

$n = RunJson @('--only', 'System.IniFiles')
$it = ItemOf $n 'System.IniFiles'
Check 'I1 a unit WITH an initialization section is moved, never removed' `
  (($it.kind -eq 'move') -and ($it.status -eq 'verified')) "kind=$($it.kind) status=$($it.status) reason=$($it.reason)"

$c = RunJson @('--only', 'Vcl.Controls')
$it = ItemOf $c 'Vcl.Controls'
Check 'C1 an UNUSED unit with an initialization section is still not removed (moved instead)' `
  (($it.kind -eq 'move') -and ($it.status -eq 'verified')) "kind=$($it.kind) status=$($it.status) reason=$($it.reason)"

$u = RunJson @('--only', 'System.SysUtils')
$it = ItemOf $u 'System.SysUtils'
Check 'U1 CONTROL: a unit the interface needs is skipped -- neither edit compiles' `
  (($it.Count -eq 1) -and ($it.status -eq 'skipped')) "kind=$($it.kind) status=$($it.status) reason=$($it.reason)"

$x = RunJson @('--only', 'System.NoSuchUnit')
Check 'X1 CONTROL: a name that is not in the uses clause stays unmatched' `
  (@($x.unmatched) -contains 'System.NoSuchUnit') "unmatched=$(@($x.unmatched) -join ',')"

# --apply really writes, and says so.
$w = RunJson @('--only', 'System.Win.Registry', '--apply')
$after = [System.IO.File]::ReadAllText($unit)
Check 'W1 --apply reports applied=true' ($w.applied -eq $true) "applied=$($w.applied)"
Check 'W2 ... the entry is commented out in the file' ($after -match '(?m)^\s*//\s*System\.Win\.Registry,') ''
Check 'W3 ... no other entry was touched' `
  (($after -match '(?m)^\s*System\.StrUtils,') -and ($after -match '(?m)^\s*Vcl\.Controls,')) ''
Check 'W4 ... a .bak holds the original' `
  ((Test-Path ($unit + '.bak')) -and ([System.IO.File]::ReadAllText($unit + '.bak') -match '(?m)^\s*System\.Win\.Registry,')) ''
Check 'W5 ... and the backup is named in the document' ($w.backup -match 'uMain\.pas\.bak$') "backup=$($w.backup)"

Write-Host ''
if ($script:fail) { Write-Host 'USES-FIX forced library unit: FAIL' -ForegroundColor Red; exit 1 }
else { Write-Host 'USES-FIX forced library unit: PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
