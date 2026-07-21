<#
  run_prop_access_extract.ps1 -- proptree assignability engine, Task 6 (R1).

  REAL property writability: the parser now records prop_access = ro/rw/wo from
  each property's read/write accessor clause; proptree wires is_writable =
  (prop_access <> 'ro'), with a NULL/empty prop_access defaulting to TRUE
  (back-compat) and a bare redeclaration inheriting the nearest CLASS ancestor's
  accessor clause.

  extraction rule (parser, from the declProp getter/setter grammar fields):
    read only            -> 'ro'   (is_writable = false)
    read + write         -> 'rw'   (is_writable = true)
    write only           -> 'wo'   (is_writable = true; a valid TARGET)
    neither (bare redecl) -> NULL  (inherits ancestor's prop_access)

  FIXTURE (PropAccFix.pas):
    TAccBase(TPersistent) -- three properties covering every accessor shape:
        property RO: Integer read FRO;              -> prop_access 'ro'
        property RW: Integer read FRW write FRW;    -> prop_access 'rw'
        property WO: Integer write FWO;             -> prop_access 'wo'
    TAccSub(TAccBase) -- 'property RO;' BARE redeclaration: own prop_access
        stored NULL, must RESOLVE to the inherited 'ro' -> is_writable false.
    TAccSubW(TAccBase) -- 'property RO read FRO write FRO;' re-states read AND
        adds write: own prop_access 'rw' -> is_writable true (the "adding write
        becomes rw" case).

  Load-bearing assertions:
    - stored prop_access: TAccBase.RO='ro', .RW='rw', .WO='wo'; TAccSub.RO IS
      NULL (bare); TAccSubW.RO='rw'.
    - proptree TAccBase: RO.is_writable=false, RW.is_writable=true,
      WO.is_writable=true.
    - proptree TAccSub:  RO.is_writable=false (INHERITED read-only).
    - proptree TAccSubW: RO.is_writable=true  (own rw).

  Run from a NEUTRAL CWD ($env:TEMP\drag-lint-prop-access-extract by default).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-prop-access-extract",
  [string]$Python  = 'C:\Python314\python.exe'
)
$ErrorActionPreference = 'Continue'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null
$work = Join-Path $WorkDir 'fixture'
New-Item -ItemType Directory $work | Out-Null

function Write-Ascii([string]$Path, [string]$Body) {
  $norm = $Body -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}

Write-Ascii (Join-Path $work 'PropAccFix.pas') @'
unit PropAccFix;

interface

type
  TAccBase = class(TPersistent)
  private
    FRO: Integer;
    FRW: Integer;
    FWO: Integer;
  published
    property RO: Integer read FRO;
    property RW: Integer read FRW write FRW;
    property WO: Integer write FWO;
  end;

  TAccSub = class(TAccBase)
  published
    property RO;   // bare redeclaration -> inherits ancestor's 'ro'
  end;

  TAccSubW = class(TAccBase)
  published
    property RO read FRO write FRO;   // re-states read + adds write -> 'rw'
  end;

implementation

end.
'@

$db = Join-Path $WorkDir 'propacc.sqlite'
Write-Host 'Indexing fixture (FRESH, so prop_access is populated by the new exe)' -ForegroundColor Cyan
$indexOut = & $Exe index $work --db $db 2>&1
$indexExit = $LASTEXITCODE
Check 'index exits 0' ($indexExit -eq 0) "exit=$indexExit; $($indexOut | Select-Object -Last 1)"

# --- 1. Stored prop_access straight from the DB (extraction seam). ----------------
Write-Host ''
Write-Host 'stored prop_access (direct DB read)' -ForegroundColor Cyan
$chk = Join-Path $WorkDir 'check.py'
Write-Ascii $chk @'
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
def pa(qname):
    r = c.execute("SELECT prop_access FROM symbols WHERE qualified_name=? AND kind='property'", (qname,)).fetchone()
    if r is None:
        return "MISSING"
    return "NULL" if r[0] is None else r[0]
for q in ("PropAccFix.TAccBase.RO","PropAccFix.TAccBase.RW","PropAccFix.TAccBase.WO",
          "PropAccFix.TAccSub.RO","PropAccFix.TAccSubW.RO"):
    print(q, pa(q))
c.close()
'@
$rows = & $Python $chk $db
$pa = @{}
foreach ($line in $rows) {
  $parts = $line -split '\s+'
  if ($parts.Count -ge 2) { $pa[$parts[0]] = $parts[1] }
}
Write-Host ("  DB: " + ($rows -join ' | ')) -ForegroundColor DarkGray
Check "TAccBase.RO prop_access == 'ro'"  ($pa['PropAccFix.TAccBase.RO'] -eq 'ro')  "got=$($pa['PropAccFix.TAccBase.RO'])"
Check "TAccBase.RW prop_access == 'rw'"  ($pa['PropAccFix.TAccBase.RW'] -eq 'rw')  "got=$($pa['PropAccFix.TAccBase.RW'])"
Check "TAccBase.WO prop_access == 'wo'"  ($pa['PropAccFix.TAccBase.WO'] -eq 'wo')  "got=$($pa['PropAccFix.TAccBase.WO'])"
Check "TAccSub.RO (bare) prop_access IS NULL" ($pa['PropAccFix.TAccSub.RO'] -eq 'NULL') "got=$($pa['PropAccFix.TAccSub.RO'])"
Check "TAccSubW.RO prop_access == 'rw'" ($pa['PropAccFix.TAccSubW.RO'] -eq 'rw') "got=$($pa['PropAccFix.TAccSubW.RO'])"

# --- proptree helper ---
function Get-Tree([string]$Database, [string]$QName) {
  Push-Location $WorkDir
  try {
    $raw = (& $Exe proptree --qname $QName --format json --db $Database) -join "`n"
    $exit = $LASTEXITCODE
  } finally { Pop-Location }
  $tree = $null
  try { $tree = $raw | ConvertFrom-Json } catch { }
  return @{ Tree = $tree; Exit = $exit; Raw = $raw }
}
function IndexByPath($tree) {
  $h = @{}
  foreach ($p in @($tree.properties)) { $h[$p.path] = $p }
  return $h
}

# --- 2. proptree TAccBase: is_writable derived from own prop_access. ---------------
Write-Host ''
Write-Host 'proptree PropAccFix.TAccBase' -ForegroundColor Cyan
$r = Get-Tree $db 'PropAccFix.TAccBase'
Check 'TAccBase proptree exits 0' ($r.Exit -eq 0) "exit=$($r.Exit)"
Check 'TAccBase proptree parses as JSON' ($null -ne $r.Tree) "raw=$($r.Raw)"
if ($null -ne $r.Tree) {
  $b = IndexByPath $r.Tree
  Check "TAccBase.RO is_writable == false (read-only)" ($b['RO'].is_writable -eq $false) "got=$($b['RO'].is_writable)"
  Check "TAccBase.RW is_writable == true (read-write)"  ($b['RW'].is_writable -eq $true)  "got=$($b['RW'].is_writable)"
  Check "TAccBase.WO is_writable == true (write-only)"  ($b['WO'].is_writable -eq $true)  "got=$($b['WO'].is_writable)"
}

# --- 3. proptree TAccSub: bare redeclaration inherits read-only. -------------------
Write-Host ''
Write-Host 'proptree PropAccFix.TAccSub (bare redeclaration inherits ro)' -ForegroundColor Cyan
$rs = Get-Tree $db 'PropAccFix.TAccSub'
Check 'TAccSub proptree exits 0' ($rs.Exit -eq 0) "exit=$($rs.Exit)"
if ($null -ne $rs.Tree) {
  $s = IndexByPath $rs.Tree
  Check "TAccSub.RO is_writable == false (INHERITED read-only)" ($s['RO'].is_writable -eq $false) "got=$($s['RO'].is_writable)"
}

# --- 4. proptree TAccSubW: own rw (re-states read + adds write). -------------------
Write-Host ''
Write-Host 'proptree PropAccFix.TAccSubW (re-states read + adds write -> rw)' -ForegroundColor Cyan
$rw = Get-Tree $db 'PropAccFix.TAccSubW'
Check 'TAccSubW proptree exits 0' ($rw.Exit -eq 0) "exit=$($rw.Exit)"
if ($null -ne $rw.Tree) {
  $w = IndexByPath $rw.Tree
  Check "TAccSubW.RO is_writable == true (own rw)" ($w['RO'].is_writable -eq $true) "got=$($w['RO'].is_writable)"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
