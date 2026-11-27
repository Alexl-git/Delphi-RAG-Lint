# 1.52 EXTGAPS: three index gaps found by lane HBEVENTS (docs\INBOX-hb-extractor-gaps-classvar-dpr-flows-dfm-multibind.md).
#
#   G1 class var read through the CLASS NAME (`TEvgCfg.CInstances`, evgData.pas:83) -> refs.symbol_id
#      bound to evgData.TEvgCfg.CInstances. Resolver: LookupMemberOnType takes skVarDecl (a class var).
#   G2 a .dpr MAIN BLOCK has data_flows rows (evArgs.dpr:11 `Fill(GDpr)` -> an arg row under the
#      program symbol). Indexer + TDataFlowFacts.CollectMainBlock; TCfgBuilder.Build accepts a block.
#   G6 (HBROOTS item 5) `H.OnEvt := H.Handler` (a procedure as the whole RHS) is an address-taken
#      binding: refs.symbol_id set, NO call edge; a statement call / a function RHS stay calls.
#   G4 symbol_facts.dfm_event lists EVERY binding of a shared handler, document order
#      ('btnGo.OnClick, btnAgain.OnClick', evgMain.dfm:15/24).
# Positive controls: the unqualified class-var write inside a method stays bound; routine
# data_flows rows in evaData.pas are unchanged in count (7); FormCreate keeps its single binding.
#
# Fixtures: tests\fixtures\happens-before\events-global and events-args (lane HBEVENTS 3c8cecaf3),
# copied to a scratch folder and indexed there (small DBs only).
#
# Usage: pwsh -File tests/autotest/run_extgaps_extraction.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = '',
    [string] $WorkDir = "$env:TEMP\drag-lint-extgaps-$PID"
)
# Defaults that need the script path are resolved HERE, not in param(): Windows PowerShell 5 run with
# -File leaves $PSScriptRoot/$MyInvocation empty inside an advanced script's param block (Repo became C:\).
if (-not $Exe) { $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe" }
try {
$ErrorActionPreference = 'Stop'
$script:Pass = 0; $script:Fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    if ($Ok) { $script:Pass++; Write-Host "  [PASS] $Name" -ForegroundColor Green }
    else     { $script:Fail++; Write-Host "  [FAIL] $Name  $Detail" -ForegroundColor Red }
}
function Sql([string]$Db, [string]$Q) { ((& { $ErrorActionPreference = 'Continue'; & $Exe sql --db $Db --query $Q 2>&1 | ForEach-Object { "$_" } }) | Select-Object -Skip 1) -join "`n" }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
$Fx = Join-Path $PSScriptRoot '..\fixtures\happens-before'
$Dbs = @{}
foreach ($n in 'events-global', 'events-args') {
    $dir = Join-Path $WorkDir $n
    New-Item -ItemType Directory -Force $dir | Out-Null
    Copy-Item (Join-Path $Fx "$n\*") $dir -Force
    $db = Join-Path $WorkDir "$n.sqlite"
    & { $ErrorActionPreference = 'Continue'; & $Exe index $dir --db $db 2>&1 | ForEach-Object { "$_" } } | Out-Null
    Check "index $n exits 0" ($LASTEXITCODE -eq 0)
    $Dbs[$n] = $db
}
$g = $Dbs['events-global']; $a = $Dbs['events-args']

# G1 -- class var through the class name
$r = Sql $g "select s.qualified_name from refs r join files f on f.id=r.file_id join symbols s on s.id=r.symbol_id where f.path like '%evgData.pas' and r.start_line=83 and r.name_text='CInstances'"
Check 'G1 TEvgCfg.CInstances (evgData.pas:83) binds to evgData.TEvgCfg.CInstances' ($r -match 'evgData\.TEvgCfg\.CInstances') $r
$c = Sql $g "select s.qualified_name from refs r join files f on f.id=r.file_id join symbols s on s.id=r.symbol_id where f.path like '%evgData.pas' and r.start_line=89 and r.name_text='CInstances' and r.kind='write'"
Check 'G1 control: the unqualified write inside TEvgCfg.Init stays bound' ($c -match 'evgData\.TEvgCfg\.CInstances') $c

# G2 -- .dpr main block data_flows
$d = Sql $a "select d.dst_kind, d.dst_name, d.src_name, s.kind from data_flows d join files f on f.id=d.file_id join symbols s on s.id=d.symbol_id where f.path like '%evArgs.dpr'"
Check 'G2 evArgs.dpr main block has an arg row Fill <- GDpr under the program symbol' ($d -match 'arg\s+Fill\s+GDpr\s+program') $d
# 1.52 EXTGAPS2: the calls pass adds 'global' <- 'argout' rows (dst_index >= 0) for globals passed to var / out
# parameters (4 in evaData.pas, pinned by run_extgaps2_extraction.ps1); the extractor's own rows stay 7.
# 1.56 EXT-B1F: declared scalar types add val_class twins beside the kept pre-1.56 rows (REV-1: the empty-val_class set
# stays equal), so the control counts the val_class '' set: still 7 (13 with the twins).
$n = Sql $a "select count(*) from data_flows d join files f on f.id=d.file_id where f.path like '%evaData.pas' and coalesce(d.val_class, '') = '' and not (d.dst_kind='global' and d.src_kind='argout' and d.dst_index >= 0)"
Check 'G2 control: evaData.pas extractor rows unchanged (7)' ($n -match '(?m)^\s*7\s*$') $n

# G4 -- every DFM binding of a shared handler
$e = Sql $g "select sf.dfm_event from symbol_facts sf join symbols s on s.id=sf.symbol_id where s.name='btnGoClick' and s.kind='method' and sf.dfm_event is not null and sf.dfm_event <> ''"
Check 'G4 btnGoClick dfm_event = btnGo.OnClick, btnAgain.OnClick' ($e -match 'btnGo\.OnClick, btnAgain\.OnClick') $e
$fc = Sql $g "select sf.dfm_event from symbol_facts sf join symbols s on s.id=sf.symbol_id where s.name='FormCreate' and sf.dfm_event <> ''"
Check 'G4 control: FormCreate keeps one binding' (($fc -match '\.OnCreate') -and -not ($fc -match ',')) $fc

# G6 -- `H.OnEvt := H.Handler` takes the procedure's address: bound, but no call edge
$ev = Join-Path $WorkDir 'events-assign'
New-Item -ItemType Directory -Force $ev | Out-Null
@"
unit EvAssign;

interface

type
  TEvt = procedure of object;
  THolder = class
  private
    FOnEvt: TEvt;
  public
    procedure Handler;
    function GetVal: Integer;
    property OnEvt: TEvt read FOnEvt write FOnEvt;
  end;

procedure Wire(H: THolder);

implementation

procedure THolder.Handler;
begin
end;

function THolder.GetVal: Integer;
begin
  Result := 1;
end;

procedure Wire(H: THolder);
var
  V: Integer;
begin
  H.OnEvt := H.Handler;
  H.Handler;
  V := H.GetVal;
  if V > 0 then H.Handler;
end;

end.
"@ | Set-Content (Join-Path $ev 'EvAssign.pas') -Encoding ascii
$edb = Join-Path $WorkDir 'events-assign.sqlite'
& { $ErrorActionPreference = 'Continue'; & $Exe index $ev --db $edb 2>&1 | ForEach-Object { "$_" } } | Out-Null
Check 'index events-assign exits 0' ($LASTEXITCODE -eq 0)
function EdgeAt([int]$Line) { Sql $edb "select s.qualified_name, coalesce((select ce.confidence from call_edges ce where ce.ref_id=r.id), 'no-edge') from refs r join symbols s on s.id=r.symbol_id where r.start_line=$Line and r.name_text in ('Handler','GetVal') and r.kind in ('member-access','call') order by r.kind" }
$a1 = EdgeAt 33
Check 'G6 H.OnEvt := H.Handler binds Handler with NO call edge' (($a1 -match 'THolder\.Handler') -and ($a1 -match 'no-edge') -and -not ($a1 -match 'certain')) $a1
$a2 = EdgeAt 34
Check 'G6 control: the statement H.Handler; stays a certain call' ($a2 -match 'THolder\.Handler\s+certain') $a2
$a3 = EdgeAt 35
Check 'G6 control: V := H.GetVal (a function) stays a certain call' ($a3 -match 'THolder\.GetVal\s+certain') $a3
$a4 = EdgeAt 36
Check 'G6 control: if ... then H.Handler; stays a certain call' ($a4 -match 'THolder\.Handler\s+certain') $a4
Write-Host ''
Write-Host ("extgaps extraction: {0} pass, {1} fail" -f $script:Pass, $script:Fail)
if ($script:Fail -gt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  foreach ($d23 in @("$env:TEMP\drag-lint-extgaps-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
