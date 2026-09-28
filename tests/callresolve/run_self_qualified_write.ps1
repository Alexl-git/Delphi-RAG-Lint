<#
  run_self_qualified_write.ps1 -- `Self.FField := X` is a WRITE of FField.

  THE DEFECT (INBOX-self-qualified-field-write-indexed-as-read.md, located
  2026-09-27): the extractor's ref-gap D branch (Parser.Delphi13.pas, the
  exprDot case) emits the member of every `Self.X` as a `read` ref, whichever
  side of `:=` it sits on, and the `assignment` case only emits `write` for a
  bare-identifier left side. So `Self.FFlag := False` was indexed as a READ,
  its member_accesses row said mode=read, and `find-callers --resolved` listed
  a writer as a reader -- charts' who-writes under-reported, and "is this field
  ever written" could answer a false no.

  WHAT IS PINNED
    * `Self.FFlag := False`      -> ONE ref, kind write, bound to TThing.FFlag
    * `Result := Self.FFlag`     -> still kind read            (control)
    * bare `FFlag := True`       -> still kind write           (control)
    * `Self.FFlag := FFlag` inside a routine with a LOCAL FFlag: the LHS write
      binds the FIELD (Self names the member), the RHS read binds the LOCAL
    * `Self.FItems[0] := 1` and bare `FItems[0] := 1` produce the SAME ref kind
      -- whatever the bare form is, the Self form must not differ from it
    * find-callers --resolved reports the Self write with mode=write
  Every "is a write" check has a "still a read" twin, so an extractor that
  simply emitted `write` for every Self.X would fail here.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-self-write-$PID"
)
$ErrorActionPreference = 'Stop'
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

$unit = @(
  'unit uSelfW;'
  ''
  'interface'
  ''
  'type'
  '  TThing = class'
  '  private'
  '    FFlag: Boolean;'
  '    FItems: TArray<Integer>;'
  '  public'
  '    procedure SetViaSelf;'
  '    procedure SetBare;'
  '    function ReadViaSelf: Boolean;'
  '    procedure Shadowed;'
  '    procedure SetIndexedSelf;'
  '    procedure SetIndexedBare;'
  '  end;'
  ''
  'implementation'
  ''
  'procedure TThing.SetViaSelf;'
  'begin'
  '  Self.FFlag := False;'
  'end;'
  ''
  'procedure TThing.SetBare;'
  'begin'
  '  FFlag := True;'
  'end;'
  ''
  'function TThing.ReadViaSelf: Boolean;'
  'begin'
  '  Result := Self.FFlag;'
  'end;'
  ''
  'procedure TThing.Shadowed;'
  'var'
  '  FFlag: Boolean;'
  'begin'
  '  FFlag := True;'
  '  Self.FFlag := FFlag;'
  'end;'
  ''
  'procedure TThing.SetIndexedSelf;'
  'begin'
  '  Self.FItems[0] := 1;'
  'end;'
  ''
  'procedure TThing.SetIndexedBare;'
  'begin'
  '  FItems[0] := 1;'
  'end;'
  ''
  'end.'
) -join "`r`n"
$pas = Join-Path $WorkDir 'uSelfW.pas'
[IO.File]::WriteAllText($pas, $unit + "`r`n", [Text.Encoding]::ASCII)
$dprPath = Join-Path $WorkDir 'App.dpr'
[IO.File]::WriteAllText($dprPath, ((@('program App;', '', 'uses', "  uSelfW in 'uSelfW.pas';", '', 'begin', 'end.') -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
$db = Join-Path $WorkDir 'App.sqlite'

$lines = [IO.File]::ReadAllLines($pas)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$ln = [ordered]@{
  SelfWrite   = LineOf 'Self.FFlag := False;'
  BareWrite   = LineOf 'FFlag := True;'
  SelfRead    = LineOf 'Result := Self.FFlag;'
  ShadowSelf  = LineOf 'Self.FFlag := FFlag;'
  IdxSelf     = LineOf 'Self.FItems[0] := 1;'
  IdxBare     = LineOf 'FItems[0] := 1;'
}
Check 'fixture statements located' (@($ln.Values) -notcontains -1) (($ln.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')

& $Exe index --project $dprPath --db $db 2>&1 | Out-Null
Check 'fixture indexed' ((Test-Path $db) -and $LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# sql --json rows are POSITIONAL arrays: map them onto columns[].name.
function SqlRows([string]$Query) {
  $raw = & $Exe sql --db $db --json --query $Query 2>$null | Out-String
  $doc = $raw | ConvertFrom-Json
  $names = @($doc.columns | ForEach-Object { $_.name })
  $out = @()
  foreach ($r in @($doc.rows)) {
    $o = [ordered]@{}
    for ($k = 0; $k -lt $names.Count; $k++) { $o[$names[$k]] = $r[$k] }
    $out += [pscustomobject]$o
  }
  return ,@($out)
}

$refs = SqlRows @"
SELECT r.start_line AS line, r.start_col AS col, r.kind AS kind, r.name_text AS name,
       COALESCE(s.qualified_name, '') AS target, COALESCE(s.kind, '') AS target_kind,
       COALESCE(ma.mode, '') AS mode
FROM refs r
LEFT JOIN symbols s ON s.id = r.symbol_id
LEFT JOIN member_accesses ma ON ma.ref_id = r.id
WHERE r.name_text IN ('FFlag','FItems')
ORDER BY r.start_line, r.start_col
"@
Write-Host '  refs for FFlag / FItems:' -ForegroundColor DarkGray
foreach ($r in $refs) { Write-Host ("    {0}:{1} {2,-13} {3,-6} -> {4} [{5}] mode={6}" -f $r.line, $r.col, $r.kind, $r.name, $r.target, $r.target_kind, $r.mode) -ForegroundColor DarkGray }
Check 'refs query returned rows (the fixture is not vacuous)' ($refs.Count -gt 0) "rows=$($refs.Count)"

function RefsOn([int]$Line) { return ,@($refs | Where-Object { [int]$_.line -eq $Line }) }

Write-Host ''
Write-Host 'Self.FFlag := False' -ForegroundColor Cyan
$sw = RefsOn $ln.SelfWrite
Check 'exactly ONE ref for FFlag on the Self write line' (@($sw).Count -eq 1) "got $(@($sw).Count): $((@($sw) | ForEach-Object { $_.kind }) -join ',')"
Check 'its kind is write' (@($sw | Where-Object { $_.kind -eq 'write' }).Count -eq 1)
Check 'it binds the FIELD uSelfW.TThing.FFlag' (@($sw | Where-Object { $_.target -eq 'uSelfW.TThing.FFlag' }).Count -eq 1)

Write-Host ''
Write-Host 'Controls: what was already right stays right' -ForegroundColor Cyan
$sr = RefsOn $ln.SelfRead
Check 'Result := Self.FFlag is still a READ' ((@($sr).Count -ge 1) -and (@($sr | Where-Object { $_.kind -eq 'write' }).Count -eq 0)) "kinds=$((@($sr) | ForEach-Object { $_.kind }) -join ',')"
$bw = RefsOn $ln.BareWrite
Check 'bare FFlag := True is still a WRITE of the field' (@($bw | Where-Object { $_.kind -eq 'write' -and $_.target -eq 'uSelfW.TThing.FFlag' }).Count -eq 1)

Write-Host ''
Write-Host 'Self.FFlag := FFlag beside a LOCAL FFlag' -ForegroundColor Cyan
$sh = RefsOn $ln.ShadowSelf
$shW = @($sh | Where-Object { $_.kind -eq 'write' })
$shR = @($sh | Where-Object { $_.kind -eq 'read' })
Check 'the LHS is a write bound to the FIELD, not the local' (($shW.Count -eq 1) -and ($shW[0].target -eq 'uSelfW.TThing.FFlag')) "write targets=$(($shW | ForEach-Object { $_.target }) -join ',')"
# Bare READS of a local are not bound by design (the member-reads stream binds
# members only), so the invariant is that the RHS never binds the FIELD.
Check 'the RHS read does NOT bind the FIELD (it is the local)' (($shR.Count -eq 1) -and ($shR[0].target -ne 'uSelfW.TThing.FFlag')) "read targets=[$(($shR | ForEach-Object { $_.target }) -join ',')]"

Write-Host ''
Write-Host 'Indexed element write: the Self form matches the bare form' -ForegroundColor Cyan
$is = @((RefsOn $ln.IdxSelf) | ForEach-Object { $_.kind }) -join ','
$ib = @((RefsOn $ln.IdxBare) | ForEach-Object { $_.kind }) -join ','
Check 'Self.FItems[0] := 1 has the same ref kinds as FItems[0] := 1' ($is -eq $ib) "self=[$is] bare=[$ib]"

Write-Host ''
Write-Host 'find-callers --resolved reports the Self write as a write' -ForegroundColor Cyan
$fc = & $Exe query find-callers --name FFlag --resolved --json --db $db 2>$null | Out-String | ConvertFrom-Json
$fcSelf = @($fc | Where-Object { [int]$_.line -eq $ln.SelfWrite })
Check 'TThing.SetViaSelf appears with mode write' (@($fcSelf | Where-Object { $_.mode -eq 'write' }).Count -ge 1) "rows on that line: $((@($fcSelf) | ForEach-Object { "$($_.caller_qname)/$($_.mode)" }) -join '; ')"
$fcRead = @($fc | Where-Object { [int]$_.line -eq $ln.SelfRead })
Check 'CONTROL: TThing.ReadViaSelf still appears, not as a write' ((@($fcRead).Count -ge 1) -and (@($fcRead | Where-Object { $_.mode -eq 'write' }).Count -eq 0)) "rows: $((@($fcRead) | ForEach-Object { "$($_.caller_qname)/$($_.mode)" }) -join '; ')"

Write-Host ''
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue }
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
