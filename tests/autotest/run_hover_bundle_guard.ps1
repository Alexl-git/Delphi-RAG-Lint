<#
  run_hover_bundle_guard.ps1 -- `draglint/hoverBundle` answers a hover in ONE
  LSP request, and its every part agrees with the CLI surface it replaces.

  THE DEFECT THIS PINS:
    A single IDE hover cost FOUR engine round trips -- `textDocument/hover` over
    the warm LSP, then THREE synchronous drag-lint.exe spawns:

      hover --qname --format json      (passed the FULL db list, so it
                                        cold-opened the ~1.4 GB library index
                                        on every hover)
      query find-callers --context 1
      query find-callers --resolved

    Measured 2026-08-19 in the live IDE: ~480 ms LSP + 470 ms + 780 ms, and the
    hover --json spawn on top of that. The plugin starts the LSP server with
    exactly the same --db set, so all three spawns re-opened, from cold, indexes
    a running process already had open.

  WHAT RED LOOKS LIKE (verbatim, against the pre-change build):
    the server does not know the method and replies

      {"jsonrpc":"2.0","id":3,"error":{"code":-32601,
       "message":"method not found: draglint/hoverBundle"}}

    so every assertion below reports '<no-bundle>'. Name that token, not a
    paraphrase: an assertion written against the WORDING of the report would
    have passed against the broken build.

  WHY IT COMPARES AGAINST THE CLI RATHER THAN A GOLDEN:
    The point of the change is that ONE computation now serves both surfaces.
    A golden would pin the bundle's own output and would stay green if the two
    surfaces silently diverged -- which is the failure that matters, because the
    popup would then confidently describe a different symbol than `hover
    --qname` does for the same cursor.

  THE CONTROLS:
    * D_Orphan is called by nobody and passed to nobody. Its bundle MUST report
      zero resolved callers. Without it, "the callers came through" would pass
      just as well against a build that returned every row for every symbol.
    * A_Predicate is reached only as a CALLBACK. It must survive into the
      bundle marked 'callback' -- the shared query is the CLI's own, so losing
      the callback rules in the extraction has to fail here.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-hover-bundle"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}
function WriteAnsi($path, $text) {
  $t = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($path, $t, (New-Object System.Text.ASCIIEncoding))
}
function Frame($obj) {
  $j = $obj | ConvertTo-Json -Compress -Depth 10
  $n = [System.Text.Encoding]::UTF8.GetByteCount($j)
  return "Content-Length: $n`r`n`r`n$j"
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
if (Test-Path $WorkDir) { [System.IO.Directory]::Delete($WorkDir, $true) }
New-Item -ItemType Directory $WorkDir | Out-Null
$SrcDir = Join-Path $WorkDir 'src'
New-Item -ItemType Directory $SrcDir | Out-Null

# ---------------------------------------------------------------------------
# Fixture. Deliberately carries all four shapes the bundle must serve:
#   a documented method with params + a return  -> the structured model
#   an ordinary resolved call                   -> resolvedCallers 'certain'
#   a by-name pass                              -> resolvedCallers 'callback'
#   a routine nothing touches                   -> the zero control
# ---------------------------------------------------------------------------
$Fixture = @'
unit uBundleFix;

interface

type
  TPickPred = function(const AItem: string): Boolean;

  TWorker = class
  public
    /// <summary>Applies the delta and reports how many rows moved.</summary>
    /// <param name="ADelta">Rows to apply; must not be nil.</param>
    /// <returns>Number of rows applied.</returns>
    function ApplyDelta(const ADelta: string; ACount: Integer): Integer;
  end;

function  A_Predicate(const AItem: string): Boolean;
procedure C_Driver;
procedure D_Orphan;

implementation

function TWorker.ApplyDelta(const ADelta: string; ACount: Integer): Integer;
begin
  Result := ACount;
end;

{ Reached ONLY by being handed to Choose -- never called. }
function A_Predicate(const AItem: string): Boolean;
begin
  { An INTRINSIC call, so the guard has one to hover. }
  Result := Length(AItem) > 0;
end;

{ Neither called nor passed anywhere. THE ZERO CONTROL. }
procedure D_Orphan;
begin
  Writeln('orphan');
end;

procedure Choose(P: TPickPred);
begin
  if Assigned(P) then Writeln('chosen');
end;

procedure C_Driver;
var
  W: TWorker;
begin
  Choose(A_Predicate);
  W := TWorker.Create;
  try
    W.ApplyDelta('x', 3);
  finally
    W.Free;
  end;
end;

{ TWO routines, each with a parameter named `btn`. A parameter cannot be
  referenced outside the routine that declares it, so a usage list for ONE of
  them must never contain a line from the other. }
procedure FirstOwner(btn: Integer);
var
  FirstFld: Integer;
begin
  FirstFld := btn;
end;

procedure SecondOwner(btn: Integer);
var
  SecondFld: Integer;
begin
  SecondFld := btn;
end;

end.
'@

$SrcFile = Join-Path $SrcDir 'uBundleFix.pas'
WriteAnsi $SrcFile $Fixture

$Db = Join-Path $WorkDir 'fix.sqlite'
& $Exe index $SrcDir --db $Db 2>&1 | Out-Null
if (-not (Test-Path $Db)) { Write-Host 'FATAL: index produced no DB' -ForegroundColor Red; exit 2 }
Check 'built the fixture index' (Test-Path $Db)

$lines = [System.IO.File]::ReadAllLines($SrcFile)
function LineIndexOf([string]$needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Contains($needle)) { return $i } }
  return -1
}

# The probe: the cursor sits mid-identifier on the CALL of ApplyDelta, which is
# how a real hover arrives -- not on the declaration.
$callLine = LineIndexOf 'W.ApplyDelta('
$callCol  = $lines[$callLine].IndexOf('ApplyDelta') + 4
Check 'located the "W.ApplyDelta(" probe' ($callLine -ge 0) "line0=$callLine col0=$callCol"
if ($callLine -lt 0) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }

$uri = 'file:///' + ($SrcFile -replace '\\', '/')

# ---------------------------------------------------------------------------
# Drive the server once: standard hover AND the bundle at the SAME position, in
# one session, so a difference cannot be blamed on a different server state.
# ---------------------------------------------------------------------------
$msgs  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
$msgs += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
$msgs += Frame @{ jsonrpc = '2.0'; id = 2; method = 'textDocument/hover';
                  params = @{ textDocument = @{ uri = $uri }; position = @{ line = $callLine; character = $callCol } } }
$msgs += Frame @{ jsonrpc = '2.0'; id = 3; method = 'draglint/hoverBundle';
                  params = @{ textDocument = @{ uri = $uri }; position = @{ line = $callLine; character = $callCol } } }
$msgs += Frame @{ jsonrpc = '2.0'; id = 4; method = 'shutdown'; params = @{} }

$inF = Join-Path $WorkDir 'in.txt'; $outF = Join-Path $WorkDir 'out.txt'; $errF = Join-Path $WorkDir 'err.txt'
[System.IO.File]::WriteAllText($inF, $msgs, (New-Object System.Text.ASCIIEncoding))
Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir `
  -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF `
  -NoNewWindow -Wait | Out-Null

$raw = [System.IO.File]::ReadAllText($outF)
$hoverMd = '<no-hover>'
$bundle  = $null
$bundleErr = ''
foreach ($m in [regex]::Matches($raw, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
  try { $o = $m.Value.Trim() | ConvertFrom-Json } catch { continue }
  if ($o.id -eq 2 -and $null -ne $o.result) { $hoverMd = [string]$o.result.contents.value }
  if ($o.id -eq 3) {
    if ($null -ne $o.result) { $bundle = $o.result }
    elseif ($null -ne $o.error) { $bundleErr = [string]$o.error.message }
  }
}

Check 'textDocument/hover still answers' ($hoverMd -ne '<no-hover>' -and $hoverMd -ne '') "len=$($hoverMd.Length)"
Check 'draglint/hoverBundle answers at all' ($null -ne $bundle) $(if ($null -ne $bundle) { '' } elseif ($bundleErr) { "error: $bundleErr" } else { '<no-reply at all>' })

if ($null -eq $bundle) {
  Write-Host ''
  Write-Host 'FAIL -- no bundle; every remaining assertion is moot.' -ForegroundColor Red
  exit 1
}

# ---- R5: markdown identical to textDocument/hover -------------------------
Check 'bundle.markdown is byte-identical to textDocument/hover' ($bundle.markdown -ceq $hoverMd) `
  "bundle=$($bundle.markdown.Length) hover=$($hoverMd.Length)"

# ---- R4: the resolved qname is reported, not mined from markdown ----------
Check 'bundle.qname resolved to the method' ($bundle.qname -match 'TWorker\.ApplyDelta') "qname=$($bundle.qname)"

# ---- R6: model field-identical to `hover --qname --format json` -----------
$cliHoverRaw = & $Exe hover --qname $bundle.qname --db $Db --format json 2>$null | Out-String
$cliHover = $null
$mObj = [regex]::Match($cliHoverRaw, '\{.*\}', 'Singleline')
if ($mObj.Success) { try { $cliHover = $mObj.Value | ConvertFrom-Json } catch { $cliHover = $null } }
Check 'CLI hover --format json parsed' ($null -ne $cliHover)

if ($null -ne $cliHover) {
  foreach ($f in @('qname', 'kind', 'signature', 'unit', 'def_line', 'return_type')) {
    $a = [string]$cliHover.$f
    $b = [string]$bundle.model.$f
    Check "model.$f matches the CLI" ($a -ceq $b) "cli='$a' bundle='$b'"
  }
  $cliParams = @($cliHover.params).Count
  $bunParams = @($bundle.model.params).Count
  Check 'model.params count matches the CLI' ($cliParams -eq $bunParams) "cli=$cliParams bundle=$bunParams"
}

# ---- R1/R4: resolvedCallers agree with `find-callers --resolved` ----------
function CliResolved([string]$name) {
  $raw = & $Exe query find-callers --name $name --resolved --json --db $Db 2>$null | Out-String
  $m = [regex]::Match($raw, '\[.*\]', 'Singleline')
  if (-not $m.Success) { return @() }
  try { return @($m.Value | ConvertFrom-Json) } catch { return @() }
}
$cliRes = CliResolved 'ApplyDelta'
$bunRes = @($bundle.resolvedCallers)
Check 'resolvedCallers count matches find-callers --resolved' ($cliRes.Count -eq $bunRes.Count) `
  "cli=$($cliRes.Count) bundle=$($bunRes.Count)"
$cliKey = ($cliRes | ForEach-Object { "$($_.caller_qname)|$($_.confidence)|$($_.target_qname)" } | Sort-Object) -join ';'
$bunKey = ($bunRes | ForEach-Object { "$($_.caller_qname)|$($_.confidence)|$($_.target_qname)" } | Sort-Object) -join ';'
Check 'resolvedCallers rows match the CLI row-for-row' ($cliKey -ceq $bunKey) "cli='$cliKey' bundle='$bunKey'"

# ---- P7: a RESOLVED row must carry its source line, same as a name row ----
# Reported from the live IDE 2026-08-19, hovering the routine name at
# uMainZeissCopy.pas:4106: "CALLED FROM shows line numbers but no code". When
# SelectCallers picks the RESOLVED set, every row was emitted without a `code`
# key by construction, so the popup's grid rendered bare line numbers.
#
# The assertion is SELF-VALIDATING rather than a golden: it reads each row's OWN
# file at its OWN line and demands the text match. A weaker "code is non-empty"
# check would pass against a build that filled every row from the HOVERED file,
# or off by a line -- and that is the failure that would actually ship, because
# a plausible wrong line reads exactly like a right one.
$bad = @()
foreach ($r in $bunRes) {
  if (-not $r.line) { $bad += "row $($r.caller_qname) has no line at all"; continue }
  $rf = [string]$r.file
  if (-not (Test-Path $rf)) { $bad += "row $($r.caller_qname) names a missing file '$rf'"; continue }
  $rl = [System.IO.File]::ReadAllLines($rf)
  $want = ''
  if ($r.line -ge 1 -and $r.line -le $rl.Count) { $want = $rl[$r.line - 1].Trim() }
  if ([string]::IsNullOrWhiteSpace([string]$r.code)) {
    $bad += "row $($r.caller_qname) code is EMPTY (line $($r.line) reads '$want')"
  } elseif (([string]$r.code) -cne $want) {
    $bad += "row $($r.caller_qname) code='$($r.code)' but $($r.line) reads '$want'"
  }
}
Check 'every resolvedCallers row carries the text at its OWN file:line' ($bad.Count -eq 0) ($bad -join ' | ')
# Positive control: the above is vacuous if there are no rows to check.
Check 'CONTROL: there WERE resolved rows to check' ($bunRes.Count -gt 0) "count=$($bunRes.Count)"

# Which line a resolved row points AT is a deliberate choice, so pin it. The
# index carries two: the caller ROUTINE's start line (what the CLI prints, and
# what this row used to carry) and the CALL SITE's own line. "Called from" means
# the statement, not the routine header -- and the difference is invisible to
# the check above, which would pass just as happily on 'procedure C_Driver;'.
$drv = @($bunRes | Where-Object { $_.caller_qname -match 'C_Driver' })
Check 'a resolved row points at the CALL, not the caller routine header' `
  ($drv.Count -gt 0 -and ([string]$drv[0].code) -match 'ApplyDelta') `
  "code='$(if ($drv.Count) { $drv[0].code } else { '<no C_Driver row>' })'"

# The row must be OPENABLE. FilePath is filename-only for resolved rows by the
# CLI's cross-machine contract; the popup navigates to whatever it is handed, so
# a bare name there is a dead link -- which is how this defect first showed up.
Check 'a resolved row names a full, openable path' `
  ($drv.Count -gt 0 -and [System.IO.Path]::IsPathRooted([string]$drv[0].file)) `
  "file='$(if ($drv.Count) { $drv[0].file } else { '' })'"

# ---- R4: nameCallers carry the call site's own source line ----------------
$bunName = @($bundle.nameCallers)
Check 'nameCallers is non-empty for a called method' ($bunName.Count -gt 0) "count=$($bunName.Count)"
$withCode = @($bunName | Where-Object { $_.code -match 'ApplyDelta' })
Check 'a nameCallers row carries its own source line' ($withCode.Count -gt 0) `
  "first='$(if ($bunName.Count) { $bunName[0].code } else { '' })'"

# ---- THE CONTROLS ---------------------------------------------------------
function BundleAt([int]$line0, [int]$col0) {
  $m  = Frame @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ processId = $null; rootUri = $null; capabilities = @{} } }
  $m += Frame @{ jsonrpc = '2.0'; method = 'initialized'; params = @{} }
  $m += Frame @{ jsonrpc = '2.0'; id = 7; method = 'draglint/hoverBundle';
                 params = @{ textDocument = @{ uri = $uri }; position = @{ line = $line0; character = $col0 } } }
  $m += Frame @{ jsonrpc = '2.0'; id = 8; method = 'shutdown'; params = @{} }
  [System.IO.File]::WriteAllText($inF, $m, (New-Object System.Text.ASCIIEncoding))
  Start-Process $Exe -ArgumentList @('lsp', '--db', $Db) -WorkingDirectory $WorkDir `
    -RedirectStandardInput $inF -RedirectStandardOutput $outF -RedirectStandardError $errF `
    -NoNewWindow -Wait | Out-Null
  $r = [System.IO.File]::ReadAllText($outF)
  foreach ($mm in [regex]::Matches($r, '\{"jsonrpc".*?(?=Content-Length:|$)', 'Singleline')) {
    try { $o = $mm.Value.Trim() | ConvertFrom-Json } catch { continue }
    if ($o.id -eq 7 -and $null -ne $o.result) { return $o.result }
  }
  return $null
}

# CONTROL 1 -- the orphan. Zero resolved callers, and it must still HOVER,
# so an empty caller list cannot be confused with a failed lookup.
$orphanLine = LineIndexOf 'procedure D_Orphan;'
$orphanDecl = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i].Contains('procedure D_Orphan;') -and $i -gt $callLine - 40) { $orphanDecl = $i }
}
$orphanCol = $lines[$orphanLine].IndexOf('D_Orphan') + 3
$ob = BundleAt $orphanLine $orphanCol
Check 'CONTROL: the orphan still produces a bundle' ($null -ne $ob) $(if ($null -ne $ob) { '' } else { '<no-bundle>' })
if ($null -ne $ob) {
  Check 'CONTROL: the orphan has ZERO resolved callers' (@($ob.resolvedCallers).Count -eq 0) `
    "count=$(@($ob.resolvedCallers).Count)"
  Check 'CONTROL: the orphan still resolved a qname' ($ob.qname -match 'D_Orphan') "qname=$($ob.qname)"
}

# CONTROL 2 -- the callback reach must survive the extraction, marked
# 'callback'. If the shared query lost the callback rules, this is what fails.
$predLine = LineIndexOf 'function A_Predicate(const AItem: string): Boolean;'
$predCol  = $lines[$predLine].IndexOf('A_Predicate') + 3
$pb = BundleAt $predLine $predCol
Check 'CONTROL: the callback-reached routine produces a bundle' ($null -ne $pb) $(if ($null -ne $pb) { '' } else { '<no-bundle>' })
if ($null -ne $pb) {
  $cb = @($pb.resolvedCallers | Where-Object { $_.confidence -eq 'callback' })
  Check 'CONTROL: the callback reach survives into the bundle' ($cb.Count -gt 0) `
    "confidences=$((@($pb.resolvedCallers) | ForEach-Object { $_.confidence }) -join ',')"
}

# ---- CONTROL 3: a COMPILER INTRINSIC still gets a usable model ------------
# An intrinsic has no indexed symbol, so the bundle long returned model:null and
# the plugin fell back to the PLAIN string popup. Reported from the live IDE
# 2026-08-19: hovering Length gave uncoloured text, where every other symbol
# renders a coloured signature. The server knows the intrinsic's signature --
# it puts it in the markdown -- so it can hand back a real model instead.
#
# RED against the pre-fix build: model is null, so kind/signature are empty.
$intrLine = LineIndexOf 'Result := Length(AItem) > 0;'
$intrCol  = $lines[$intrLine].IndexOf('Length') + 3
$ib = BundleAt $intrLine $intrCol
Check 'CONTROL: hovering an intrinsic produces a bundle' ($null -ne $ib) $(if ($null -ne $ib) { '' } else { '<no-bundle>' })
if ($null -ne $ib) {
  Check 'INTRINSIC: the model is NOT null' ($null -ne $ib.model) `
    'model:null -> the plugin shows the uncoloured string popup'
  if ($null -ne $ib.model) {
    Check 'INTRINSIC: kind is reported' ($ib.model.kind -eq 'intrinsic') "kind='$($ib.model.kind)'"
    Check 'INTRINSIC: qname names the System unit' ($ib.model.qname -eq 'System.Length') `
      "qname='$($ib.model.qname)'"
    # The requirement is what the IDE itself shows for Length: a parameter list
    # and a return type, so the popup can render a coloured header
    # "intrinsic System.Length(const S): Integer". Asserted as those two facts
    # rather than as whatever string the implementation happens to build.
    Check 'INTRINSIC: the parameter list is carried' ($ib.model.signature -match '^\(') `
      "signature='$($ib.model.signature)'"
    Check 'INTRINSIC: the return type is carried' ($ib.model.return_type -eq 'Integer') `
      "return_type='$($ib.model.return_type)'"
  }
  Check 'INTRINSIC: markdown is still returned' ($ib.markdown -match 'intrinsic') `
    "markdown='$($ib.markdown)'"
}

# ---- CONTROL 4: a PARAMETER's usages must not leak across routines --------
# Owner, live IDE, 2026-08-19, uMainZeissCopy.pas:4143 `Fbtn := btn;`
#   "When I hover over btn it shows me 2 uses. btn is a parameter to this
#    method. The other use is in another method and is different btn also a
#    parameter. Not this one."
#
# That file declares TTransferLogger.Create(... btn: TdxBarButton ...) and
# TErrorLogger.Create(... btn: TdxBarButton ...). The SYMBOL resolved correctly
# (typeat reported uMainZeissCopy.TTransferLogger.Create.btn); it was the usage
# list that was gathered by BARE NAME across the whole index, so it swept up the
# other constructor's parameter.
#
# A parameter or local cannot be referenced outside its own routine. Anything
# from another routine is not a usage of it -- it is a different symbol that
# happens to share a name.
$fLine = LineIndexOf 'FirstFld := btn;'
$fCol  = 0
if ($fLine -ge 0) { $fCol = $lines[$fLine].IndexOf(':= btn') + 4 }
Check 'located the parameter probe' ($fLine -ge 0) "line0=$fLine col0=$fCol"
$pb2 = BundleAt $fLine $fCol
Check 'CONTROL: hovering a parameter produces a bundle' ($null -ne $pb2) $(if ($null -ne $pb2) { '' } else { '<no-bundle>' })
if ($null -ne $pb2) {
  Check 'PARAM: the parameter itself resolved' ($pb2.qname -match 'FirstOwner\.btn') "qname='$($pb2.qname)'"
  $rows = @($pb2.nameCallers) + @($pb2.resolvedCallers)
  # Any row must sit inside FirstOwner. SecondOwner's line is the leak.
  $secondLine0 = LineIndexOf 'SecondFld := btn;'
  $leaked = @($rows | Where-Object { $_.line -eq ($secondLine0 + 1) })
  Check 'PARAM: no usage row comes from the OTHER routine' ($leaked.Count -eq 0) `
    "rows=$(($rows | ForEach-Object { $_.line }) -join ',')  otherRoutineLine=$($secondLine0 + 1)"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
