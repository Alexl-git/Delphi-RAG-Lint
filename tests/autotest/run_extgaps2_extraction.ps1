# 1.52 EXTGAPS2: the index gaps lane EXTGAPS left open (docs\INBOX-hb-extractor-gaps-classvar-dpr-flows-dfm-multibind.md
# items 3 and 6, and the HBINTRA non-ASCII column finding).
#
#   HB6  an `exports` entry is a ref of kind 'export' (REF_KIND_EXPORT), bound to the routine (refs.symbol_id),
#        with NO call edge -- it names the routine, it does not call it.
#   HB3  a unit variable passed as the whole argument of a var / out parameter of a resolved project routine gets
#        a data_flows row dst_kind 'global', src_kind 'argout' (written by the calls pass after binding).
#   COL  index columns are CHARACTER columns: a non-ASCII character earlier on the line (2-byte, and a 4-byte one
#        that is a surrogate pair in a string) no longer moves refs.start_col / end_col.
# Positive controls: an ordinary call keeps its certain call edge; a const argument, a local argument and the
# extractor's own arg rows are unchanged; an ASCII line keeps its column.
#
# Usage: pwsh -File tests/autotest/run_extgaps2_extraction.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = '',
    [string] $WorkDir = "$env:TEMP\drag-lint-extgaps2-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
    else     { $script:Fail++; Write-Host "  [FAIL] $Name  $Detail" -ForegroundColor Red }
}
function Sql([string]$Db, [string]$Q) { ((& { $ErrorActionPreference = 'Continue'; & $Exe sql --db $Db --query $Q 2>&1 | ForEach-Object { "$_" } }) | Where-Object { $_ -notmatch '^\(loaded' -and $_ -notmatch 'row\(s\) in' -and $_.Trim() -ne '' } | Select-Object -Skip 2) -join "`n" }
function IndexDir([string]$Name, [hashtable]$Files) {
    $dir = Join-Path $WorkDir $Name
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($k in $Files.Keys) { [IO.File]::WriteAllText((Join-Path $dir $k), ($Files[$k] -replace "`r?`n", "`r`n"), [Text.UTF8Encoding]::new($false)) }
    $db = Join-Path $WorkDir "$Name.sqlite"
    & { $ErrorActionPreference = 'Continue'; & $Exe index $dir --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
    Check "index $Name exits 0" ($LASTEXITCODE -eq 0)
    return $db
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# ---- HB6: exports entry ----
$x6 = IndexDir 'exports' @{ 'ExpLib.dpr' = @"
library ExpLib;

procedure Exported1;
begin
end;

function Exported2(A: Integer): Integer;
begin
  Result := A;
end;

procedure Helper;
begin
end;

procedure Caller;
begin
  Helper;
end;

exports
  Exported1,
  Exported2 name 'E2';

begin
  Caller;
end.
"@ }
function RefAt([int]$Line, [string]$Name) { Sql $x6 "select r.kind, coalesce(s.qualified_name,'unbound'), (select count(*) from call_edges c where c.ref_id=r.id) from refs r left join symbols s on s.id=r.symbol_id where r.start_line=$Line and r.name_text='$Name'" }
$e1 = RefAt 22 'Exported1'
Check 'HB6 exports Exported1 -> kind export, bound to ExpLib.Exported1, 0 call edges' ($e1 -match '^export\s+ExpLib\.Exported1\s+0\s*$') $e1
$e2 = RefAt 23 'Exported2'
Check 'HB6 exports Exported2 name ''E2'' -> kind export, bound, 0 call edges' ($e2 -match '^export\s+ExpLib\.Exported2\s+0\s*$') $e2
$c1 = RefAt 18 'Helper'
Check 'HB6 control: the call Helper; stays a call with 1 call edge' ($c1 -match '^call\s+ExpLib\.Helper\s+1\s*$') $c1
$nc = Sql $x6 "select count(*) from refs where kind='call' and name_text like 'Exported%'"
Check 'HB6 no exports entry is a call ref any more' ($nc -match '^\s*0\s*$') $nc

# ---- HB3: var / out argument writes a global ----
$x3 = IndexDir 'argout' @{ 'HbOut.pas' = @"
unit HbOut;

interface

var
  GCount: Integer;
  GName: string;

procedure Fill(var A: Integer);
procedure Load(out S: string);
procedure Show(const S: string);
procedure Run;

implementation

procedure Fill(var A: Integer);
begin
  A := 1;
end;

procedure Load(out S: string);
begin
  S := 'x';
end;

procedure Show(const S: string);
begin
end;

procedure Run;
var
  L: Integer;
begin
  Fill(GCount);
  Load(GName);
  Show(GName);
  Fill(L);
end;

end.
"@ }
$g = Sql $x3 "select dst_line, dst_col, dst_index, dst_name, src_index, src_line, src_col, src_name from data_flows where dst_kind='global' and src_kind='argout' order by dst_line"
Check 'HB3 Fill(GCount) (var) -> global GCount at 34:8 <- argout 0 of Fill at 34:3' ($g -match '(?m)^34\s+8\s+0\s+GCount\s+0\s+34\s+3\s+Fill\s*$') $g
Check 'HB3 Load(GName) (out) -> global GName at 35:8 <- argout 0 of Load at 35:3' ($g -match '(?m)^35\s+8\s+0\s+GName\s+0\s+35\s+3\s+Load\s*$') $g
Check 'HB3 control: Show(GName) (const) and Fill(L) (a local) write no global' (-not ($g -match '(?m)^3[67]\s')) $g
# 1.56 EXT-B1F: a declared scalar adds a val_class twin beside the kept pre-1.56 arg row (REV-1: the empty-val_class
# set stays equal), so the control counts that set: still 3 (4 with the twin).
$a = Sql $x3 "select count(*) from data_flows where dst_kind='arg' and coalesce(val_class, '') = ''"
Check 'HB3 control: the extractor''s 3 arg rows are unchanged' ($a -match '^\s*3\s*$') $a
& { $ErrorActionPreference = 'Continue'; & $Exe index (Join-Path $WorkDir 'argout') --db $x3 --force-reparse 2>&1 | ForEach-Object { "$_" } } | Out-Null
$n = Sql $x3 "select count(*) from data_flows where dst_kind='global' and src_kind='argout'"
Check 'HB3 a re-index re-derives the rows once (2, not 4)' ($n -match '^\s*2\s*$') $n

# ---- COL: character columns ----
$e = [string][char]0xE9 + [char]0xE8
$sp = [char]::ConvertFromUtf32(0x1F600)
$xc = IndexDir 'nonascii' @{ 'NonAsc.pas' = @"
unit NonAsc;

interface

procedure Foo;
procedure Bar;

implementation

procedure Foo;
begin
end;

procedure Bar;
begin
  {$e} Foo;
  {$sp} Foo;
  Foo;
end;

end.
"@ }
$r = Sql $xc "select start_line, start_col, end_col from refs where name_text='Foo' and kind='call' order by start_line"
Check 'COL Foo after a 2-char non-ASCII comment: start_col 8, end_col 11 (bytes gave 10 / 13)' ($r -match '(?m)^16\s+8\s+11\s*$') $r
Check 'COL Foo after a surrogate-pair comment: start_col 8 (UTF-16 units; bytes gave 10)' ($r -match '(?m)^17\s+8\s+11\s*$') $r
Check 'COL control: Foo on an ASCII line keeps start_col 3' ($r -match '(?m)^18\s+3\s+6\s*$') $r

Write-Host ''
Write-Host ("extgaps2 extraction: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
