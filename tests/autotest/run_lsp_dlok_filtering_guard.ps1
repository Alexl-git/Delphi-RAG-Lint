#Requires -Version 7
<#
  run_lsp_dlok_filtering_guard.ps1 -- the LSP's publishDiagnostics must honour
  `// dl:ok <rule>@<hash>` (and the legacy `// drag-lint:ignore`) exactly as the
  CLI does (LSP stream task C2).

  THE DEFECT THIS PINS:
    TLspCompletion.BuildDiagnostics filtered findings by config (ShouldKeep) and
    nothing else. A reviewed, marked line kept its squiggle in the IDE gutter
    while `lint` on the same file reported it suppressed -- and the LSP's own
    "Mark as reviewed" code action inserted a marker that then changed nothing
    the user could see.

  THE SPEC IS PARITY. For every variant below:
      count(LSP publish, rule) == count(`lint <fixture> --json`, rule)
  plus a fixed expected count, so a parity that is "both wrong the same way"
  cannot pass either.

  POSITIVE CONTROL: the unmarked fixture publishes TWO with-statement findings,
  and the marked fixture still publishes the finding on the OTHER line. A filter
  that dropped every with-statement, or published nothing, fails both.

  Variants (rule with-statement, findings anchored on lines 11 and 13):
    none        no marker                                  -> 2
    hashed      `allow --apply` marker on line 11          -> 1
    other       marker naming another rule                 -> 2
    placeholder `@0000`                                    -> 2 (suppresses nothing)
    stale       a real-looking but wrong hash              -> 2
    nohash      `dl:ok with-statement` (no @hash)          -> 1 (honoured, unverifiable)
    ignore      legacy `drag-lint:ignore with-statement`   -> 1
    span        hashed marker on the statement's END line  -> 1
    codeaction  codeAction -> apply the edit -> save -> republish
  Plus (I1/I2, fix round 1): duplicate-code with a marker on the anchor, on the
  partner and a stale one; and codeAction round trips for a lone-keyword anchor
  (bare-except) and a routine-metric rule (data.metric), and no action without it.

  Run from any CWD, pwsh 7. -Exe defaults to the lane engine.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-lsp-dlok-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
$Rule = 'with-statement'
$script:LspArgs = 'lsp'   # the metric variants switch it to 'lsp --full-rules'
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function Write-Ascii($p, $t) { [System.IO.File]::WriteAllText($p, $t, [System.Text.Encoding]::ASCII) }

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# ---------- fixture ----------
# Lines 11 and 13 each open a `with` statement whose span ends one line later.
$Base = @(
  'unit uDlOk;'                  # 1
  ''                             # 2
  'interface'                    # 3
  ''                             # 4
  'procedure A(X: TObject);'     # 5
  ''                             # 6
  'implementation'               # 7
  ''                             # 8
  'procedure A(X: TObject);'     # 9
  'begin'                        # 10
  '  with X do'                  # 11
  '    Free;'                    # 12
  '  with X do'                  # 13
  '    Free;'                    # 14
  'end;'                         # 15
  ''                             # 16
  'end.'                         # 17
)
function New-Fixture([string]$Name, [hashtable]$Edits) {
  $dir = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Force $dir | Out-Null
  $lines = [string[]]$Base.Clone()
  if ($Edits) { foreach ($k in $Edits.Keys) { $lines[$k - 1] = $Edits[$k] } }
  $f = Join-Path $dir 'uDlOk.pas'
  Write-Ascii $f (($lines -join "`r`n") + "`r`n")
  return $f
}

# ---------- LSP plumbing (batch stdin, as run_lsp_publish_respects_defaults) ----------
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Depth 20 -Compress
  return "Content-Length: $([System.Text.Encoding]::UTF8.GetByteCount($j))`r`n`r`n$j"
}
function Read-Frames([string]$Out) {
  # NOTE: PowerShell names are case-insensitive -- $h and $H are ONE variable.
  $res = @()
  $i = 0
  while ($true) {
    $m = [regex]::Match($Out.Substring($i), 'Content-Length:\s*(\d+)\r\n\r\n')
    if (-not $m.Success) { break }
    $start = $i + $m.Index + $m.Length
    $len = [int]$m.Groups[1].Value
    if ($start + $len -gt $Out.Length) { break }
    $res += ($Out.Substring($start, $len) | ConvertFrom-Json)
    $i = $start + $len
  }
  return $res
}
function Invoke-Lsp([string]$PasFile, [object[]]$Extra) {
  $uri  = 'file:///' + ($PasFile -replace '\\', '/')
  $text = [System.IO.File]::ReadAllText($PasFile)
  $msgs = @(
    (Frame @{ jsonrpc='2.0'; id=1; method='initialize'; params=@{ processId=$null; rootUri=$null; capabilities=@{} } })
    (Frame @{ jsonrpc='2.0'; method='initialized'; params=@{} })
    (Frame @{ jsonrpc='2.0'; method='textDocument/didOpen'; params=@{ textDocument=@{ uri=$uri; languageId='pascal'; version=1; text=$text } } })
  )
  foreach ($e in $Extra) { $msgs += (Frame $e) }
  $msgs += (Frame @{ jsonrpc='2.0'; id=99; method='shutdown'; params=@{} })
  $msgs += (Frame @{ jsonrpc='2.0'; method='exit'; params=@{} })
  $dir = Split-Path $PasFile
  $in = Join-Path $dir 'lsp-in.txt'; $so = Join-Path $dir 'lsp-out.txt'; $se = Join-Path $dir 'lsp-err.txt'
  [System.IO.File]::WriteAllText($in, ($msgs -join ''), (New-Object System.Text.UTF8Encoding($false)))
  Start-Process $Exe -ArgumentList $script:LspArgs -WorkingDirectory $dir -RedirectStandardInput $in `
    -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -Wait | Out-Null
  $out = if (Test-Path $so) { [System.IO.File]::ReadAllText($so) } else { '' }
  return @{ Uri = $uri; Frames = @(Read-Frames $out) }
}
# Lines (1-based) of the LAST publishDiagnostics for the file, for $Rule only.
function LspLines([string]$PasFile) {
  $r = Invoke-Lsp $PasFile @()
  $pubs = @($r.Frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' })
  if ($pubs.Count -eq 0) { return ,@('NO-PUBLISH') }
  $last = $pubs[-1]
  return ,@($last.params.diagnostics | Where-Object { $_.code -eq $Rule } | ForEach-Object { [int]$_.range.start.line + 1 })
}
# `lint --json` is a bare array; the line field is start_line, the id is rule.
function CliLines([string]$PasFile) {
  $raw = (& $Exe lint $PasFile --json 2>$null) -join "`n"
  $arr = @()
  if ($raw.Trim()) { $arr = @($raw | ConvertFrom-Json) }
  return ,@($arr | Where-Object { $_.rule -eq $Rule } | ForEach-Object { [int]$_.start_line })
}
function Verify([string]$Name, [string]$PasFile, [int]$Expect) {
  $lsp = LspLines $PasFile
  $cli = CliLines $PasFile
  $d = "lsp=[" + ($lsp -join ',') + "] cli=[" + ($cli -join ',') + "]"
  Check "$Name : LSP publishes $Expect $Rule" ($lsp.Count -eq $Expect -and $lsp -notcontains 'NO-PUBLISH') $d
  Check "$Name : parity with lint --json" (($lsp -join ',') -eq ($cli -join ',')) $d
  return $lsp
}

# ---------- the hash, computed by the CLI's own `allow` ----------
$hashedFile = New-Fixture 'hashed' @{}
& $Exe allow $hashedFile --fix-line 11 --fix-rule $Rule --apply 2>&1 | Out-Null
$hashedLine = ([System.IO.File]::ReadAllLines($hashedFile))[10]
$hm = [regex]::Match($hashedLine, 'dl:ok with-statement@([0-9a-f]{4})')
Check 'SETUP: allow --apply wrote a hashed marker on line 11' $hm.Success $hashedLine
$HashHex = $hm.Groups[1].Value
$wrong = if ($HashHex -eq 'beef') { 'cafe' } else { 'beef' }

Write-Host 'LSP publishDiagnostics vs dl:ok markers (parity with lint)' -ForegroundColor Cyan
$none = Verify 'none (POSITIVE CONTROL)' (New-Fixture 'none' @{}) 2
$hashedPub = Verify 'hashed' $hashedFile 1
Check 'hashed : the UNMARKED line 13 is still published (not a blanket drop)' ($hashedPub -contains 13) ("lsp=[" + ($hashedPub -join ',') + "]")
Verify 'other rule'   (New-Fixture 'other'       @{ 11 = "  with X do  // dl:ok empty-except@$HashHex" }) 2 | Out-Null
Verify 'placeholder'  (New-Fixture 'placeholder' @{ 11 = '  with X do  // dl:ok with-statement@0000' }) 2 | Out-Null
Verify 'stale hash'   (New-Fixture 'stale'       @{ 11 = "  with X do  // dl:ok with-statement@$wrong" }) 2 | Out-Null
Verify 'no hash'      (New-Fixture 'nohash'      @{ 11 = '  with X do  // dl:ok with-statement' }) 1 | Out-Null
Verify 'legacy ignore'(New-Fixture 'ignore'      @{ 11 = '  with X do  // drag-lint:ignore with-statement' }) 1 | Out-Null
Verify 'span end line'(New-Fixture 'span'        @{ 12 = "    Free;  // dl:ok with-statement@$HashHex" }) 1 | Out-Null

# ---------- a rule loaded TWICE (2026-10-23 main sweep) ----------
# TQueryRuleLoader walks <exe-dir>\rules RECURSIVELY, so a staged engine whose
# rules\ also holds a nested copy (rules\rules\, from an xcopy into an existing
# folder) runs every .scm rule twice. `lint` drops the exact duplicates in
# FinalizeAndOutput; the LSP published both (lsp=[11,13,11,13] cli=[11,13]).
# The parity spec covers that layout too: stage the engine with a nested copy.
Write-Host ''
Write-Host 'a .scm rule loaded twice (nested rules\ copy next to the engine)' -ForegroundColor Cyan
$DupEngine = Join-Path $WorkDir 'dup-engine'
New-Item -ItemType Directory -Force $DupEngine | Out-Null
$ExeDir = Split-Path $Exe
Copy-Item $Exe $DupEngine -Force
Copy-Item (Join-Path $ExeDir '*.dll') $DupEngine -Force
Copy-Item (Join-Path $ExeDir 'rules') (Join-Path $DupEngine 'rules') -Recurse -Force
Copy-Item (Join-Path $ExeDir 'rules') (Join-Path $DupEngine 'rules\rules') -Recurse -Force
Check 'SETUP: the staged engine holds the rule twice' `
  (@(Get-ChildItem (Join-Path $DupEngine 'rules') -Recurse -Filter "$Rule.scm").Count -eq 2) ''
$RealExe = $Exe
$Exe = Join-Path $DupEngine (Split-Path $RealExe -Leaf)
Verify 'rule loaded twice (POSITIVE CONTROL shape)' (New-Fixture 'duprule' @{}) 2 | Out-Null
Verify 'rule loaded twice, hashed marker' $hashedFile 1 | Out-Null
$Exe = $RealExe

# ---------- the plugin path: codeAction -> apply edit -> save -> republish ----------
Write-Host ''
Write-Host 'codeAction -> InsertInto -> save -> next publish' -ForegroundColor Cyan
$caFile = New-Fixture 'codeaction' @{}
$caUri  = 'file:///' + ($caFile -replace '\\', '/')
$diag = @{ range = @{ start = @{ line = 10; character = 2 }; end = @{ line = 11; character = 9 } };
           severity = 3; source = 'drag-lint'; code = $Rule; message = "'with' statement makes symbol scope ambiguous" }
$req = @{ jsonrpc='2.0'; id=2; method='textDocument/codeAction';
          params=@{ textDocument=@{ uri=$caUri }; range=$diag.range; context=@{ diagnostics=@($diag) } } }
$r = Invoke-Lsp $caFile @($req)
$resp = @($r.Frames | Where-Object { $_.id -eq 2 }) | Select-Object -First 1
$edit = $null
if ($resp -and $resp.result) {
  $act = @($resp.result)[0]
  $chg = $act.edit.changes.PSObject.Properties | Select-Object -First 1
  if ($chg) { $edit = @($chg.Value)[0] }
}
Check 'codeAction returned a text edit' ($null -ne $edit) ($(if ($edit) { $edit.newText } else { 'no edit' }))
if ($edit) {
  $lines = [System.IO.File]::ReadAllLines($caFile)
  $lines[[int]$edit.range.start.line] = $edit.newText
  Write-Ascii $caFile (($lines -join "`r`n") + "`r`n")
  $ca = Verify 'codeaction (after save)' $caFile 1
  Check 'codeaction : the other finding (line 13) is still published' ($ca -contains 13) ("lsp=[" + ($ca -join ',') + "]")
}

# ---------- I1: duplicate-code (clone) findings honour a marker on EITHER end ----------
Write-Host ''
Write-Host 'duplicate-code: marker on the anchor, on the partner, and neither' -ForegroundColor Cyan
$Rule = 'duplicate-code'
$CloneBody = @(
  "  LTotal := LTotal + ComputeWeight(ASource.Alpha, ASource.Beta);"
  "  if LTotal > FUpperBound then LTotal := FUpperBound;"
  "  LScaled := Round(LTotal * FScaleFactor) + FOffsetBase;"
  "  LBuffer.Append(Format('%s=%d', [ASource.Caption, LScaled]));"
  "  if not TryResolveTarget(ASource.Handle, LTarget) then Exit(False);"
  "  LTarget.Rebind(LScaled, FUpperBound - LTotal);"
  "  FHistory.Add(TSample.Create(LTarget.Id, LScaled, Now));"
  "  while FHistory.Count > FRetentionLimit do FHistory.Delete(0);"
  "  LRatio := LScaled / (FUpperBound + FOffsetBase + 1);"
  "  if LRatio < FMinimumRatio then FlagUnderflow(ASource.Caption, LRatio);"
  "  LStatus := DescribeRatio(LRatio, FMinimumRatio, FUpperBound);"
  "  FLogger.Trace('rebind', LStatus, LTarget.Id, LScaled, LRatio);"
) -join "`r`n"
function DupRoutine([string]$Name) {
@"
function $Name(const ASource: TSourceRec): Boolean;
var
  LTotal, LScaled: Integer;
  LRatio: Double;
  LTarget: TTarget;
  LBuffer: TStringBuilder;
  LStatus: string;
begin
  Result := True;
  LTotal := 0;
  LBuffer := TStringBuilder.Create;
$CloneBody
  LBuffer.Free;
end;
"@
}
function New-DupFixture([string]$Name) {
  $dir = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Force $dir | Out-Null
  $f = Join-Path $dir 'uDup.pas'
  $txt = "unit uDup;`r`n`r`ninterface`r`n`r`nimplementation`r`n`r`nuses System.SysUtils;`r`n`r`n" +
         (DupRoutine 'One') + "`r`n`r`n" + (DupRoutine 'Two') + "`r`n`r`nend.`r`n"
  Write-Ascii $f (($txt -replace "`r`n", "`n") -replace "`n", "`r`n")
  return $f
}
$dupNone = New-DupFixture 'dupnone'
$cli0 = CliLines $dupNone
Check 'SETUP: lint reports exactly one duplicate-code finding' ($cli0.Count -eq 1) ("cli=[" + ($cli0 -join ',') + "]")
if ($cli0.Count -eq 1) {
  $anchor = [int]$cli0[0]
  Verify 'dup none (POSITIVE CONTROL)' $dupNone 1 | Out-Null
  $dupA = New-DupFixture 'dupanchor'
  & $Exe allow $dupA --fix-line $anchor --fix-rule $Rule --apply 2>&1 | Out-Null
  Check 'SETUP: allow wrote the anchor marker' ((([IO.File]::ReadAllLines($dupA))[$anchor - 1]) -match 'dl:ok duplicate-code@[0-9a-f]{4}')
  Verify 'dup marker on the ANCHOR end' $dupA 0 | Out-Null
  $partner = 0
  $m = [regex]::Match(((& $Exe lint $dupNone --json 2>$null) -join "`n"), 'also at [^"]*?:(\d+)')
  if ($m.Success) { $partner = [int]$m.Groups[1].Value }
  Check 'SETUP: the partner line is known' ($partner -gt 0) "partner=$partner"
  if ($partner -gt 0) {
    $dupB = New-DupFixture 'duppartner'
    & $Exe allow $dupB --fix-line $partner --fix-rule $Rule --apply 2>&1 | Out-Null
    Check 'SETUP: allow wrote the partner marker' ((([IO.File]::ReadAllLines($dupB))[$partner - 1]) -match 'dl:ok duplicate-code@[0-9a-f]{4}')
    Verify 'dup marker on the PARTNER end' $dupB 0 | Out-Null
    $dupS = New-DupFixture 'dupstale'
    $ls = [IO.File]::ReadAllLines($dupS)
    $ls[$partner - 1] += "  // dl:ok duplicate-code@$wrong"
    Write-Ascii $dupS (($ls -join "`r`n") + "`r`n")
    Verify 'dup STALE partner hash suppresses nothing' $dupS 1 | Out-Null
  }
}

# ---------- I2: codeAction hashes the way verification does ----------
# The diagnostic is taken from the REAL publish (so data.metric travels), the edit
# applied, the file saved, and the next publish must drop the finding like lint.
function Invoke-CodeActionRoundTrip([string]$Name, [string]$PasFile, [string]$RuleId) {
  $script:Rule = $RuleId
  $r1 = Invoke-Lsp $PasFile @()
  $pub = @($r1.Frames | Where-Object { $_.method -eq 'textDocument/publishDiagnostics' })[-1]
  $diag = @($pub.params.diagnostics | Where-Object { $_.code -eq $RuleId })[0]
  Check "$Name : the finding is published" ($null -ne $diag)
  if (-not $diag) { return }
  $req = @{ jsonrpc='2.0'; id=2; method='textDocument/codeAction';
            params=@{ textDocument=@{ uri=$r1.Uri }; range=$diag.range; context=@{ diagnostics=@($diag) } } }
  $r2 = Invoke-Lsp $PasFile @($req)
  $resp = @($r2.Frames | Where-Object { $_.id -eq 2 }) | Select-Object -First 1
  $edit = $null
  if ($resp -and $resp.result) {
    $act = @($resp.result)[0]
    if ($act) { $chg = $act.edit.changes.PSObject.Properties | Select-Object -First 1; if ($chg) { $edit = @($chg.Value)[0] } }
  }
  Check "$Name : codeAction returned a text edit" ($null -ne $edit) ($(if ($edit) { $edit.newText } else { 'no edit' }))
  if ($edit) {
    $lines = [System.IO.File]::ReadAllLines($PasFile)
    $lines[[int]$edit.range.start.line] = $edit.newText
    Write-Ascii $PasFile (($lines -join "`r`n") + "`r`n")
    Verify "$Name (after save)" $PasFile 0 | Out-Null
  }
}
function New-RoutineFixture([string]$Name) {
  $dir = Join-Path $WorkDir $Name
  New-Item -ItemType Directory -Force $dir | Out-Null
  $f = Join-Path $dir 'uP.pas'
  $ls = @('unit uP;','','interface','','procedure A(X: TObject; B, C, D, E, F, G, H, I, J: Integer);','','implementation','',
          'procedure A(X: TObject; B, C, D, E, F, G, H, I, J: Integer);','begin','  try','    X.Free;','  except','    X := nil;','  end;','end;','','end.')
  Write-Ascii $f (($ls -join "`r`n") + "`r`n")
  return $f
}
Write-Host ''
Write-Host 'codeAction round trip: lone-keyword anchor (bare-except) and a metric rule' -ForegroundColor Cyan
Invoke-CodeActionRoundTrip 'bare-except (anchor on the lone except)' (New-RoutineFixture 'cabare') 'bare-except'
# routine-metric rules reach the gutter only through the full-rules path (out-of-process lint --json)
$script:LspArgs = 'lsp --full-rules'
Invoke-CodeActionRoundTrip 'metric rule too-many-parameters' (New-RoutineFixture 'cametric') 'too-many-parameters'
# a metric diagnostic WITHOUT data.metric gets no action (the refusal `allow` makes)
$script:Rule = 'too-many-parameters'
$nm = New-RoutineFixture 'canometric'
$nmDiag = @{ range = @{ start = @{ line = 8; character = 0 }; end = @{ line = 8; character = 9 } };
             severity = 3; source = 'drag-lint'; code = 'too-many-parameters'; message = 'too many parameters' }
$nmReq = @{ jsonrpc='2.0'; id=2; method='textDocument/codeAction';
            params=@{ textDocument=@{ uri=('file:///' + ($nm -replace '\\', '/')) }; range=$nmDiag.range; context=@{ diagnostics=@($nmDiag) } } }
$nmR = Invoke-Lsp $nm @($nmReq)
$nmResp = @($nmR.Frames | Where-Object { $_.id -eq 2 }) | Select-Object -First 1
Check 'metric rule without data.metric : NO action offered' ($null -ne $nmResp -and @($nmResp.result).Count -eq 0)
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}
