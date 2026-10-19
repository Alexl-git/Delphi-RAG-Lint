<#
  run_usages_field_access.ps1 -- `usages` must report a QUALIFIED field access
  (`AJob.Streaming`, `LJob.Streaming := True`) as a read or a write, and must
  answer for a qualified name (`TJob.Streaming`) at all.

  THE DEFECT (wave 3 lane G, 2026-10-19). `usages --name Streaming` on the
  plugin answered "reads: 0 writes: 1 calls: 7" for TDragLintJob.Streaming, a
  field that is read and written all over the plugin; `TArgs.Watch` in the CLI
  answered the same way. The refs were NOT missing: the extractor records every
  `X.Field` site as refs.kind = 'member-access', and the resolver records the
  direction of each bound one in member_accesses.mode ('read' | 'write').
  `usages` never read member_accesses, and its bucket map sends every kind it
  does not know -- 'member-access' included -- to `calls`. So a field read was
  reported as a CALL, and `reads` stayed 0. Separately, `usages --name
  TJob.Streaming` matched refs.name_text against the DOTTED string, which no
  ref ever carries, and answered 0 for everything beside one declaration.

  CHECKS
    1  fixture health: R1 / W2 are member-access refs BOUND to
       uJob.TJob.Streaming with member_accesses.mode read / write -- without
       that, checks 3-6 would test nothing (FATAL, exit 2)
    2  POSITIVE CONTROL: the BARE write W1 (`Streaming := False`, refs.kind
       'write') is listed under writes -- true before the fix too, so a guard
       that cannot read the document fails here, not vacuously later
    3  bare name: the dotted read R1 is under reads             (RED before)
    4  bare name: the dotted write W2 is under writes           (RED before)
    5  bare name: neither R1 nor W2 is under calls              (RED before)
    6  qualified name TJob.Streaming: R1 in reads, W1 + W2 in writes, and the
       OTHER class's same-named field (R9) is NOT listed        (RED before)
    7  the text summary counts equal the JSON array lengths

  Line numbers are located by `{ Xn }` anchors, never hard-coded.
  Usage: pwsh -File tests\autotest\run_usages_field_access.ps1 [-Exe <drag-lint.exe>]
#>
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Continue'
$script:fail = $false
function Check([string]$n, [bool]$ok, [string]$d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }; $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $(if ($ok) { '' } else { $d })) -ForegroundColor $c
  if (-not $ok) { $script:fail = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path $Exe).Path
$scratch = Join-Path C:\TEMP ("draglint_usages_field_access-{0}" -f $PID)
if (Test-Path $scratch) { [IO.Directory]::Delete($scratch, $true) }
New-Item -ItemType Directory $scratch | Out-Null

function W([string]$name, [string]$body) {
  [IO.File]::WriteAllText((Join-Path $scratch $name), ($body -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
}
function LineOf([string]$path, [string]$anchor) {
  $lines = [IO.File]::ReadAllText($path) -split "`r`n"
  $hits = @(); for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($anchor)) { $hits += ($i + 1) } }
  if ($hits.Count -ne 1) { Write-Host "FATAL: anchor '$anchor' matched $($hits.Count) lines -- broken FIXTURE" -ForegroundColor Red; exit 2 }
  return $hits[0]
}
function Sql([string]$db, [string]$q) {
  $j = (& $exePath sql --db $db --query $q --json 2>$null) -join "`n"
  try { $o = $j | ConvertFrom-Json } catch { return ,@() }
  $cols = @($o.columns | ForEach-Object { $_.name }); $out = @()
  foreach ($r in @($o.rows)) { $h = [ordered]@{}; for ($i = 0; $i -lt $cols.Count; $i++) { $h[$cols[$i]] = @($r)[$i] }; $out += [pscustomobject]$h }
  return ,$out
}
function Usages([string]$db, [string]$name) {
  $raw = (& $exePath usages --name $name --db $db --format json 2>$null) -join "`n"
  $s = $raw.IndexOf('{'); $e = $raw.LastIndexOf('}')
  if ($s -lt 0 -or $e -lt $s) { return $null }
  try { return ($raw.Substring($s, $e - $s + 1) | ConvertFrom-Json) } catch { return $null }
}
function Has($arr, [string]$file, [int]$line) {
  return @(@($arr) | Where-Object { $_ -and ([string]$_.file).EndsWith('\' + $file) -and [int]$_.line -eq $line }).Count -ge 1
}

try {
  W 'uJob.pas' @'
unit uJob;
interface
type
  TJob = class
  public
    Streaming: Boolean;
    procedure Reset;
  end;
  TOther = class
  public
    Streaming: Boolean;
  end;
function MakeJob: TJob;
implementation
procedure TJob.Reset;
begin
  Streaming := False;                 { W1 bare write }
end;
function MakeJob: TJob;
var
  LJob: TJob;
begin
  LJob := TJob.Create;
  LJob.Streaming := True;             { W2 dotted write }
  Result := LJob;
end;
end.
'@
  W 'uUse.pas' @'
unit uUse;
interface
uses uJob;
function IsStreaming(AJob: TJob; AOther: TOther): Boolean;
implementation
function IsStreaming(AJob: TJob; AOther: TOther): Boolean;
begin
  if AJob.Streaming then              { R1 dotted read }
    Exit(True);
  Result := AOther.Streaming;         { R9 other class, same field name }
end;
end.
'@
  $fJob = Join-Path $scratch 'uJob.pas'; $fUse = Join-Path $scratch 'uUse.pas'
  $W1 = LineOf $fJob '{ W1 '; $W2 = LineOf $fJob '{ W2 '; $R1 = LineOf $fUse '{ R1 '; $R9 = LineOf $fUse '{ R9 '
  $db = Join-Path $scratch 'p.sqlite'

  Write-Host '== check 1: fixture health ==' -ForegroundColor Cyan
  & $exePath index $scratch --db $db *> (Join-Path $scratch 'index.log')
  if ($LASTEXITCODE -ne 0) { Write-Host "FATAL: index exit $LASTEXITCODE" -ForegroundColor Red; exit 2 }
  foreach ($site in @(@('uUse.pas', $R1, 'read'), @('uJob.pas', $W2, 'write'))) {
    $r = Sql $db ("SELECT s.qualified_name AS qn, ma.mode AS mode FROM refs r JOIN files f ON f.id = r.file_id " +
                  "JOIN symbols s ON s.id = r.symbol_id JOIN member_accesses ma ON ma.ref_id = r.id " +
                  "WHERE f.path LIKE '%\{0}' AND r.start_line = {1} AND r.kind = 'member-access' AND r.name_text = 'Streaming'" -f $site[0], $site[1])
    $ok = (@($r).Count -eq 1) -and ($r[0].qn -eq 'uJob.TJob.Streaming') -and ($r[0].mode -eq $site[2])
    Check ("1 {0}:{1} is a bound member-access, mode {2}" -f $site[0], $site[1], $site[2]) $ok ($r | ConvertTo-Json -Compress)
    if (-not $ok) { Write-Host 'FATAL: fixture does not exercise the defect' -ForegroundColor Red; exit 2 }
  }

  $u = Usages $db 'Streaming'
  Write-Host '== check 2: POSITIVE CONTROL ==' -ForegroundColor Cyan
  Check '2 bare write W1 is under writes' (($null -ne $u) -and (Has $u.writes 'uJob.pas' $W1)) ($u | ConvertTo-Json -Compress -Depth 4)

  Write-Host '== checks 3-5: bare name ==' -ForegroundColor Cyan
  Check '3 dotted read R1 is under reads'   (Has $u.reads  'uUse.pas' $R1) ("reads=" + ($u.reads | ConvertTo-Json -Compress))
  Check '4 dotted write W2 is under writes' (Has $u.writes 'uJob.pas' $W2) ("writes=" + ($u.writes | ConvertTo-Json -Compress))
  Check '5 R1 and W2 are NOT under calls'   (-not (Has $u.calls 'uUse.pas' $R1) -and -not (Has $u.calls 'uJob.pas' $W2)) ("calls=" + ($u.calls | ConvertTo-Json -Compress))

  Write-Host '== check 6: qualified name ==' -ForegroundColor Cyan
  $q = Usages $db 'TJob.Streaming'
  Check '6a TJob.Streaming: one declaration'   (($null -ne $q) -and (@($q.declarations).Count -eq 1)) ($q | ConvertTo-Json -Compress -Depth 4)
  Check '6b TJob.Streaming: R1 under reads'    (Has $q.reads 'uUse.pas' $R1) ("reads=" + ($q.reads | ConvertTo-Json -Compress))
  Check '6c TJob.Streaming: W1 + W2 under writes' ((Has $q.writes 'uJob.pas' $W1) -and (Has $q.writes 'uJob.pas' $W2)) ("writes=" + ($q.writes | ConvertTo-Json -Compress))
  $all = @($q.reads) + @($q.writes) + @($q.calls)
  Check '6d TJob.Streaming: TOther.Streaming read R9 NOT listed' (-not (Has $all 'uUse.pas' $R9)) ''
  Check '6e bare Streaming DOES list R9 (control for 6d)' ((Has $u.reads 'uUse.pas' $R9) -or (Has $u.calls 'uUse.pas' $R9)) ''

  Write-Host '== check 7: text summary agrees with JSON ==' -ForegroundColor Cyan
  $t = (& $exePath usages --name Streaming --db $db 2>$null) -join "`n"
  $want = "reads: {0}  writes: {1}  calls: {2}" -f @($u.reads).Count, @($u.writes).Count, @($u.calls).Count
  Check '7 text counts equal JSON counts' ($t.Contains($want)) "want '$want' in: $t"
}
finally {
  try { [IO.Directory]::Delete($scratch, $true) } catch { }
}
if ($script:fail) { Write-Host 'run_usages_field_access: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'run_usages_field_access: PASS' -ForegroundColor Green; exit 0
