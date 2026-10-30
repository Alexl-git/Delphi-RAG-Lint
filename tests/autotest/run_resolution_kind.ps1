<#
  run_resolution_kind.ps1 -- XERJ item 3 (lane gaps/xj-3): every caller / callee row of the
  --json answers carries a `resolution` key, LAST, derived (never stored) from columns the
  index already has:
    exact      call_edges row, confidence 'certain' (or a refs.symbol_id the resolver bound)
    ambiguous  call_edges row, confidence 'ambiguous'
    external   refs.external_target set (the callee lives in a library DB)
    name-only  no edge, no external target: the row was matched by NAME alone
  Surfaces: find-callers --resolved, find-callers (name path), find-callees, usages, context.
  Overloads (rb5-ovl, 63096549): W.Pick('a') / W.Pick(1) are decided by argument shape -> exact;
  W.Pick(Trim('a')) cannot be -> ambiguous.
  POSITIVE CONTROLS: one answer (find-callers --name Solo) holds an exact AND a name-only row, so a
  stub that stamps one constant on every row fails; each of the four kinds is seen at least once.
  Run with a worktree exe; the script changes to a neutral CWD (C:\TEMP) itself.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-resolution-kind-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function JsonOf([string[]]$CliArgs) {
  $raw = (& $script:Exe @CliArgs 2>$null | Out-String)
  $b1 = $raw.IndexOf('['); $b2 = $raw.IndexOf('{')
  $b = if ($b1 -lt 0) { $b2 } elseif ($b2 -lt 0) { $b1 } else { [Math]::Min($b1, $b2) }
  if ($b -lt 0) { return $null }
  return $raw.Substring($b)
}
function Kinds($rows) { @($rows | ForEach-Object { $_.resolution }) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$script:Exe = (Resolve-Path $Exe).Path
$Exe = $script:Exe
$FixRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\callresolve\fixtures\xtyped')).Path
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$SrcDir = Join-Path $WorkDir 'src'; New-Item -ItemType Directory $SrcDir | Out-Null
try {
  Push-Location C:\TEMP
  WriteAnsi (Join-Path $SrcDir 'uResKind.pas') @'
unit uResKind;

interface

type
  TPickPred = function(const AItem: string): Boolean;

  TWorker = class
  public
    function Solo: Integer;
    function Pick(const AName: string): Integer; overload;
    function Pick(AIndex: Integer): Integer; overload;
  end;

function A_Predicate(const AItem: string): Boolean;
procedure Driver;
procedure Stray;

implementation

function TWorker.Solo: Integer;
begin
  Result := 1;
end;

function TWorker.Pick(const AName: string): Integer;
begin
  Result := Length(AName);
end;

function TWorker.Pick(AIndex: Integer): Integer;
begin
  Result := AIndex;
end;

function A_Predicate(const AItem: string): Boolean;
begin
  Result := AItem <> '';
end;

procedure Choose(P: TPickPred);
begin
  if Assigned(P) then Writeln('chosen');
end;

procedure Driver;
var
  W: TWorker;
begin
  Choose(A_Predicate);
  W := TWorker.Create;
  try
    W.Solo;
    W.Pick('a');
    W.Pick(1);
    W.Pick(Trim('a'));
    Missing(3);
  finally
    W.Free;
  end;
end;

procedure Stray;
var
  V: TNotDeclaredAnywhere;
begin
  V.Solo;
end;

end.
'@
  $Db = Join-Path $WorkDir 'fix.sqlite'
  & $Exe index $SrcDir --db $Db 2>&1 | Out-Null
  if (-not (Test-Path $Db)) { Write-Host 'FATAL: index produced no DB' -ForegroundColor Red; exit 2 }

  # ---- find-callers --resolved ------------------------------------------------
  $raw = JsonOf @('query','find-callers','--name','Solo','--resolved','--json','--db',$Db)
  $rows = @($raw | ConvertFrom-Json)
  Check 'resolved Solo: one row, resolution=exact' (($rows.Count -eq 1) -and ($rows[0].resolution -ceq 'exact')) "got=$((Kinds $rows) -join ',')"
  Check 'resolved Solo: resolution is the LAST key of the row' ($raw -match '"resolution":\s*"exact"\s*\}') 'key order'
  $pk = @((JsonOf @('query','find-callers','--name','Pick','--resolved','--json','--db',$Db)) | ConvertFrom-Json)
  # rb5-ovl (63096549, 2026-10-28) narrows a same-arity overload tie by ARGUMENT SHAPE: the
  # string / integer literal calls now resolve exact; the call-shaped argument (Trim(..)) is a
  # shape the narrowing cannot read, so that site must stay ambiguous (the ambiguous control).
  $pkk = (@($pk | ForEach-Object { $_.resolution }) | Sort-Object) -join ','
  Check 'resolved Pick: literal-argument overload calls are exact, an unreadable-shape call stays ambiguous' ($pkk -ceq 'ambiguous,exact,exact') "got=$pkk"
  $cb = @((JsonOf @('query','find-callers','--name','A_Predicate','--resolved','--json','--db',$Db)) | ConvertFrom-Json)
  Check 'resolved A_Predicate: a callback reach is name-only' ((@($cb | Where-Object { $_.confidence -ceq 'callback' -and $_.resolution -ceq 'name-only' })).Count -ge 1) "got=$((Kinds $cb) -join ',')"
  $tx = (& $Exe query find-callers --name Pick --resolved --db $Db 2>$null | Out-String)
  Check 'resolved text: totals line names the kinds' ($tx -match '\d+ callers? \(.*\d+ ambiguous') $tx.Trim()

  # ---- find-callers (name path): POSITIVE CONTROL exact + name-only in ONE answer ----
  $nm = @((JsonOf @('query','find-callers','--name','Solo','--json','--db',$Db)) | ConvertFrom-Json)
  Check 'name path Solo: json rows carry resolution' ((@($nm | Where-Object { -not $_.resolution }).Count -eq 0) -and ($nm.Count -ge 2)) "got=$((Kinds $nm) -join ',')"
  Check 'CONTROL name path Solo: an exact row AND a name-only row in one answer' (((Kinds $nm) -contains 'exact') -and ((Kinds $nm) -contains 'name-only')) "got=$((Kinds $nm) -join ',')"
  $ms = @((JsonOf @('query','find-callers','--name','Missing','--json','--db',$Db)) | ConvertFrom-Json)
  Check 'name path Missing: an undeclared callee is name-only' (($ms.Count -ge 1) -and (@($ms | Where-Object { $_.resolution -cne 'name-only' }).Count -eq 0)) "got=$((Kinds $ms) -join ',')"
  $nt = (& $Exe query find-callers --name Solo --db $Db 2>$null | Out-String)
  Check 'name path text: totals line names the kinds' (($nt -match '\d+ caller\(s\) \(') -and ($nt -match 'exact') -and ($nt -match 'name-only')) $nt.Trim()

  # ---- find-callees -----------------------------------------------------------
  $ce = @((JsonOf @('find-callees','--qname','uResKind.Driver','--json','--db',$Db)) | ConvertFrom-Json)
  Check 'find-callees: resolved edges carry exact and ambiguous' ((((Kinds $ce) -contains 'exact') -and ((Kinds $ce) -contains 'ambiguous')) -and (@($ce | Where-Object { -not $_.resolution }).Count -eq 0)) "got=$((Kinds $ce) -join ',')"

  # ---- usages -----------------------------------------------------------------
  $uo = (JsonOf @('usages','--name','Solo','--json','--db',$Db)) | ConvertFrom-Json
  $uk = @($uo.calls | ForEach-Object { $_.resolution })
  Check 'usages: calls rows carry exact and name-only' (($uk -contains 'exact') -and ($uk -contains 'name-only')) "got=$($uk -join ',')"

  # ---- context ------------------------------------------------------------------
  $cj = (JsonOf @('context','--task','modify uResKind.TWorker.Solo','--format','json','--db',$Db)) | ConvertFrom-Json
  Check 'context json: caller_resolution counts exact >= 1 and name-only >= 1' (($null -ne $cj.caller_resolution) -and ($cj.caller_resolution.exact -ge 1) -and ($cj.caller_resolution.'name-only' -ge 1)) "got=$($cj.caller_resolution | ConvertTo-Json -Compress)"
  $cm = (& $Exe context --task 'modify uResKind.TWorker.Solo' --db $Db --format markdown 2>$null | Out-String)
  Check 'context markdown: a name-only caller is suffixed [name-only]' ($cm -match '\[name-only\]') ''

  # ---- external (library DB) ------------------------------------------------------
  $lib = Join-Path $WorkDir 'lib'; $app = Join-Path $WorkDir 'app'
  New-Item -ItemType Directory $lib, $app | Out-Null
  Copy-Item (Join-Path $FixRoot 'xt_lib.pas') $lib
  Copy-Item (Join-Path $FixRoot 'xt_app.pas'), (Join-Path $FixRoot 'xt_app2.pas') $app
  $libDb = Join-Path $WorkDir 'lib.sqlite'; $appxDb = Join-Path $WorkDir 'appx.sqlite'; $appDb = Join-Path $WorkDir 'app.sqlite'
  & $Exe index $lib --db $libDb 2>&1 | Out-Null
  & $Exe index $app --db $appxDb --library-db $libDb 2>&1 | Out-Null
  & $Exe index $app --db $appDb 2>&1 | Out-Null
  $ex = @((JsonOf @('query','find-callers','--name','Read','--json','--db',$appxDb)) | ConvertFrom-Json)
  Check 'external: a library-bound call is resolution=external' ((Kinds $ex) -contains 'external') "got=$((Kinds $ex) -join ',')"
  $ne = @((JsonOf @('query','find-callers','--name','Read','--json','--db',$appDb)) | ConvertFrom-Json)
  Check 'CONTROL external: same site without a library DB is name-only' (($ne.Count -ge 1) -and ((Kinds $ne) -notcontains 'external') -and ((Kinds $ne) -contains 'name-only')) "got=$((Kinds $ne) -join ',')"
  $ec = @((JsonOf @('find-callees','--qname','xt_app.Go','--json','--db',$appxDb)) | ConvertFrom-Json)
  Check 'find-callees external rows are resolution=external' (@($ec | Where-Object { ($_.external -eq $true) -and ($_.resolution -ceq 'external') }).Count -ge 1) "got=$((Kinds $ec) -join ',')"
} finally {
  Pop-Location
  if (Test-Path -LiteralPath $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
}
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
