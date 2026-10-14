<#
  Test-Parity.ps1 -- the parity harness for the in-process charts core (spec P3/P4/N5).

  P3  the PowerShell output is the REFERENCE: a question is ported only when the Delphi
      output equals the script's output on the frozen index copies.
  P4  the harness runs a question BOTH ways and reports EVERY difference. A difference is a
      finding with a mechanism, never a re-baseline: this script has no code path that
      rewrites an expected value, and none must be added.
  N5  (Determinism) the same question run twice on the same index must give an EMPTY
      `compare` diff. A non-empty one is a defect in the REPORT, not in Compare.

  -Mode Determinism   for each case in charts\parity\cases.json: Ask-Report.ps1 -Plain twice
                      (-AllowStale, the frozen clones, OUR engine via -Engine), then
                      `drag-lint compare --old <1> --new <2> --format json`. PASS = exit 0;
                      exit 1 prints the hunks and the N5 verdict; exit 2/3 = SETUP. The table
                      also times each run -- the owner's first timing of the PS producer.
  -Mode Core          builds tests\charts\ChartsCoreProbe.exe if missing and, per clone and per
                      name, compares what Emit-Common.ps1 computes with what the probe prints
                      (symbol location, member selection, edgeless files + disclosure, zones,
                      stripped-source sha, source context), field by field with -ceq.
                      Step 2 (2026-10-13) adds: the Graphviz dot walk and the clone guard
                      (once per clone), and per name a row cluster + disclosure row built
                      from the symbol's file and one dot layout of it (shas of .dot/.svg/
                      .plain and the anchor count; dot.exe runs on both sides); then the
                      checks, sql, columns, orm and chains sections (index-wide, once per clone).
  -Mode Question      (P3 end to end) for each case whose question the probe reports as ported
                      (ChartsCoreProbe --ported): Ask-Report.ps1 -Plain as Determinism runs it, and the
                      probe's question mode (the in-process Delphi question, same index, the SAME
                      -OutRoot after the PS bundle is moved aside). The text is compared with `drag-lint compare` (the step-1 diff and its
                      spec-s5 normalisation, nothing looser); every bundle file both sides wrote is
                      compared too: graph.dot/.svg/.plain/.png byte for byte, meta.json/index.html/
                      xref.txt with only the generated time and the bundle root masked (the facts N1
                      already drops from the text), graph.pdf reported and not compared (see
                      $BundleSkipped). Questions not ported are listed as SKIP. The probe is rebuilt
                      when any src\charts unit or the probe source is newer than it.

  Usage:  pwsh -File charts\src\Test-Parity.ps1 -Mode Core -Only who-writes -Clone DL
          pwsh -File charts\src\Test-Parity.ps1 -Mode Question -Only touches-tables
          -Only   restricts the CASES (by question id); the fixed names of each clone in play
                  always run.
          -Clone  restricts the clones to those whose file name starts with the text (DL, CLIENT...).
  Output: <OutDir>\parity-summary.md (default charts\scratch\parity-<stamp>\), per-run files beside it.
  Exit:   0 = no MISMATCH and every determinism case passed; 1 = otherwise; 2 = setup failure.

  ENGINE PINNING. Every engine call here uses -Exe (default: the worktree's own build), never
  third_party\dll-win64: Ask-Report gets -Engine <Exe> and $Engine is set to <Exe> before
  Emit-Common.ps1 is dot-sourced, so a swap of the shared exe cannot change a result mid-run.

  PS TRAPS CLOSED IN THIS FILE. -ceq everywhere a value is compared (the default -eq is
  case-insensitive and would hide exactly the difference being hunted). A one-item array is
  never trusted to stay an array: nodes are normalised before they are compared. A number and
  a numeric-looking string are different types here ('n' vs 's'): the type is part of the value.
#>
[CmdletBinding()]
param(
  [string]$Mode   = 'Determinism',
  [string]$Only   = '',
  [string]$Clone  = '',
  [string]$Exe    = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot "..\scratch\parity-$Stamp" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir  = (Resolve-Path -LiteralPath $OutDir).Path
$Exe     = (Resolve-Path -LiteralPath $Exe).Path
$DbRoot  = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\scratch\db')).Path
$CasesPath = Join-Path $PSScriptRoot '..\parity\cases.json'
$AskReport = Join-Path $PSScriptRoot 'Ask-Report.ps1'
$RepoRoot  = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if ($Mode -notin 'Determinism', 'Core', 'Question') { Write-Host "FATAL: -Mode must be Determinism, Core or Question (got '$Mode')" -ForegroundColor Red; exit 2 }

$cases = @((Get-Content -LiteralPath $CasesPath -Raw | ConvertFrom-Json).cases)
if ($Only) { $cases = @($cases | Where-Object { $_.question -ieq $Only }) }
if ($Clone) { $cases = @($cases | Where-Object { ([string]$_.db).StartsWith($Clone, [StringComparison]::OrdinalIgnoreCase) }) }
$summary = New-Object System.Collections.Generic.List[string]
function Add-Summary([string] $Line) { $summary.Add($Line) }

# ============================== Determinism (N5) ==============================

function Invoke-AskPlain($Case, [string] $OutFile, [string] $BundleRoot) {
  $a = @('-NoProfile', '-File', $AskReport, '-Question', $Case.question, '-Target', $Case.target,
         '-DbPath', (Join-Path $DbRoot $Case.db))
  if ($Case.serverDb)      { $a += @('-ServerDbPath', (Join-Path $DbRoot $Case.serverDb)) }
  if ($Case.sqlDb)         { $a += @('-SqlDbPath', (Join-Path $DbRoot $Case.sqlDb)) }
  if ($Case.counterpartDb) { $a += @('-CounterpartDb', (Join-Path $DbRoot $Case.counterpartDb)) }
  $a += @($Case.extra)
  $a += @('-AllowStale', '-Plain', '-Engine', $Exe, '-OutRoot', $BundleRoot)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $out = & pwsh @a 2>"$OutFile.err"
  $code = $LASTEXITCODE
  $sw.Stop()
  [IO.File]::WriteAllText($OutFile, ((@($out) -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
  [pscustomobject]@{ Exit = $code; Seconds = [Math]::Round($sw.Elapsed.TotalSeconds, 1) }
}

function Get-FirstDiffPair([string] $A, [string] $B) {
  $la = @([IO.File]::ReadAllText($A) -split "\r?\n")
  $lb = @([IO.File]::ReadAllText($B) -split "\r?\n")
  $n = [Math]::Max($la.Count, $lb.Count)
  for ($i = 0; $i -lt $n; $i++) {
    $x = $(if ($i -lt $la.Count) { $la[$i] } else { '(missing)' })
    $y = $(if ($i -lt $lb.Count) { $lb[$i] } else { '(missing)' })
    if ($x -cne $y) { return "line $($i + 1): [1] $x  <>  [2] $y" }
  }
  '(no line differs after splitting -- a line-ending-only difference)'
}

function Invoke-DeterminismMode {
  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($c in $cases) {
    Write-Host "determinism: $($c.question) ..."
    $f1 = Join-Path $OutDir "$($c.question).1.txt"
    $f2 = Join-Path $OutDir "$($c.question).2.txt"
    $r1 = Invoke-AskPlain $c $f1 (Join-Path $OutDir 'bundles')
    $r2 = Invoke-AskPlain $c $f2 (Join-Path $OutDir 'bundles')
    $row = [ordered]@{ Question = $c.question; Exit = ''; Run1 = $r1.Seconds; Run2 = $r2.Seconds; Verdict = '' }
    if ($r1.Exit -ne 0 -or $r2.Exit -ne 0) {
      $row.Exit = "ask $($r1.Exit)/$($r2.Exit)"
      $row.Verdict = "SETUP: Ask-Report exited non-zero (see $($c.question).1.txt.err)"
    } else {
      $cmp = & $Exe compare --old $f1 --new $f2 --format json 2>"$OutDir\$($c.question).compare.err"
      $code = $LASTEXITCODE
      $cmpText = (@($cmp) -join "`n")
      [IO.File]::WriteAllText((Join-Path $OutDir "$($c.question).compare.json"), $cmpText)
      $row.Exit = $code
      if ($code -eq 0) { $row.Verdict = 'PASS' }
      elseif ($code -eq 1) {
        $row.Verdict = "N5 FAIL: $($c.question) is non-deterministic -- a defect in the report, not in Compare"
        Write-Host $row.Verdict -ForegroundColor Red
        Write-Host $cmpText.Substring(0, [Math]::Min(3000, $cmpText.Length))
        Write-Host ('first differing line pair: ' + (Get-FirstDiffPair $f1 $f2))
      } else { $row.Verdict = "SETUP: compare exited $code" }
    }
    $rows.Add([pscustomobject]$row)
  }
  Add-Summary '## Determinism (N5)'
  Add-Summary ''
  Add-Summary '| question | exit | run 1 s | run 2 s | verdict |'
  Add-Summary '|---|---|---|---|---|'
  foreach ($r in $rows) { Add-Summary "| $($r.Question) | $($r.Exit) | $($r.Run1) | $($r.Run2) | $($r.Verdict) |" }
  Add-Summary ''
  @($rows | Where-Object { $_.Verdict -cne 'PASS' }).Count
}

# ================================ Core (P3/P4) ================================

# Names run on every clone in addition to the case targets: 5 qualified + 2 bare per clone.
# The five qualified ones are, in order, a field, a property, a method with a body, a class
# and a unit (the SQL clone: tables, columns, a trigger); the bare ones are one that is unique
# in the index and one that is ambiguous. All were read off the frozen clones on 2026-10-11.
$FixedNames = [ordered]@{
  'CLIENT-Micronite2027.sqlite' = @(
    'uMain.TfrmMAIN.dxRibbon1', 'uDataChannels.Model.TDataChannelsModel.dsrDataChannels', 'uMain.TfrmMAIN.FormDestroy',
    'uLoggingServiceP.TABZLoggingSys', 'uVarNames.ViewModel', 'ApdStatusLight8', 'ID')
  'SERVER-MicroniteMW1Service.sqlite' = @(
    'uMicronite_MW_Service1.TMicroniteMW1.FPipesLogFile', 'IuMicObject.IGlobalObject.FieldAsType',
    'uMicronite_MW_Service1.TMicroniteMW1.LogActivity', 'uCHIPFORM.TmcCHIPFORM', 'IuMicObject', 'CPSamp', 'ID')
  'SQL-drag-lint-sql.sqlite' = @(
    'CPSET', 'CONTROLPLANNINGPRESETS', 'CHIPFORM.SYSTID', 'CHIPFORM.REASON', 'DATACHAN_BIU5', 'OPERID', 'ID')
  'DL-drag-lint.sqlite' = @(
    'TreeSitterLib.TSInput.payload', 'TreeSitter.TTSTree.Tree', 'TreeSitter.TTSLanguageHelper.SymbolCount',
    'DRagLint.Core.Indexer.TIndexer', 'DRagLint.Core.Indexer', 'BaseIndent', 'Kind')
  'DataCopy-DataCopy.sqlite' = @(
    'uConfigurationService.TConfigurationService.FBackupIgnored', 'uConfigurationService.TConfigurationService.ToPath',
    'uConfigurationService.TConfigurationService.GetBackupPath1', 'uFileUtils.EUnableToFindDirectory',
    'uConfigurationService', 'FCSVColumnNames', 'FLock')
  'TESTS-MicroniteTests.sqlite' = @(
    'uOptrlistRoleSync.TOptrlistSyncItem.OldLogin', 'DUnitX.TestFramework.ITestFixtureInfo.Name',
    'Test.FtrName.TFtrNameTests.DimSpec_Spec_SingleLower_is_LSL_MIN', 'Test.OptrlistRoleSync.TOptrlistCaptureTests',
    'Test.OptrlistRoleSync', 'Cpkrd2', 'Name')
}
$script:LeafCount = 0
$CoreKinds = @('field', 'property')
$ZoneSample = 10
$EdgelessListed = 5
$FollowingLines = 2

# ---- node normalisation and comparison -----------------------------------------
# Type-tagged scalars: 's' string, 'n' number, 'b' bool, 'z' null. So '12' vs 12 is a visible
# difference and so is a $null that the other side wrote as ''.
function Convert-ParityNode($Value) {
  if ($null -eq $Value) { return @{ t = 'z'; v = '<null>' } }
  if ($Value -is [bool]) { return @{ t = 'b'; v = $(if ($Value) { 'true' } else { 'false' }) } }
  if ($Value -is [string]) { return @{ t = 's'; v = $Value } }
  if ($Value -is [ValueType] -and $Value -isnot [datetime]) { return @{ t = 'n'; v = ([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)) } }
  if ($Value -is [datetime]) { return @{ t = 's'; v = $Value.ToString('o') } }
  if ($Value -is [System.Collections.IDictionary]) {
    $d = [ordered]@{}
    foreach ($k in $Value.Keys) { $d[[string]$k] = Convert-ParityNode $Value[$k] }
    return @{ t = 'o'; v = $d }
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $l = New-Object System.Collections.Generic.List[object]
    foreach ($e in $Value) { $l.Add((Convert-ParityNode $e)) }
    return @{ t = 'a'; v = $l }
  }
  $d = [ordered]@{}
  foreach ($p in $Value.PSObject.Properties) { $d[$p.Name] = Convert-ParityNode $p.Value }
  @{ t = 'o'; v = $d }
}

function Get-ParityHint($Ps, $Dl, [string] $Key) {
  $a = [string]$Ps.v; $b = [string]$Dl.v
  if ($Ps.t -ne $Dl.t) {
    if (($Ps.t -eq 'z') -or ($Dl.t -eq 'z')) { return "missing JSON property reads `$null (PS `$null vs Delphi value)" }
    if (($Ps.t -in 's', 'n') -and ($Dl.t -in 's', 'n') -and $a -ceq $b) { return 'string->number coercion (PS -eq on "12" vs 12)' }
    return 'type differs (string/number/bool/null)'
  }
  if ($a -ieq $b -and $a -cne $b) { return 'case-insensitive -eq/-contains/Group-Object in PS' }
  if (($a -eq '' -and $b -eq '<null>') -or ($a -eq '<null>' -and $b -eq '')) { return "'' vs null: missing JSON property reads `$null" }
  if ($Key -like '*.#') {
    $ia = 0; $ib = 0
    if ([int]::TryParse($a, [ref]$ia) -and [int]::TryParse($b, [ref]$ib) -and [Math]::Abs($ia - $ib) -eq 1) {
      return 'count differs by one: single-item unroll or $null dropped from an array'
    }
  }
  if (($a -match '^-?\d+$') -and ($b -match '^-?\d+$') -and ([int64]$a -eq [int64]$b)) { return 'string->number coercion' }
  if ($a.Trim() -ceq $b.Trim()) { return 'whitespace: PS String.Trim vs Delphi Trim (Char.IsWhiteSpace vs <= #32)' }
  'no table entry -- diagnose by hand'
}

function Compare-ParityNode([string] $Key, $Ps, $Dl, $Out) {
  if ($Ps.t -eq 'o' -and $Dl.t -eq 'o') {
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($k in $Ps.v.Keys) { $keys.Add($k) }
    foreach ($k in $Dl.v.Keys) { if (-not ($keys | Where-Object { $_ -ieq $k })) { $keys.Add($k) } }
    foreach ($k in $keys) {
      $pv = $(if ($Ps.v.Contains($k)) { $Ps.v[$k] } else { @{ t = 'z'; v = '<absent>' } })
      $dv = $(if ($Dl.v.Contains($k)) { $Dl.v[$k] } else { @{ t = 'z'; v = '<absent>' } })
      Compare-ParityNode "$Key.$k" $pv $dv $Out
    }
    return
  }
  if ($Ps.t -eq 'a' -and $Dl.t -eq 'a') {
    $pa = @($Ps.v | ForEach-Object { [string]$_.v }); $da = @($Dl.v | ForEach-Object { [string]$_.v })
    $scalars = $true
    foreach ($e in $Ps.v) { if ($e.t -in 'o', 'a') { $scalars = $false } }
    foreach ($e in $Dl.v) { if ($e.t -in 'o', 'a') { $scalars = $false } }
    if ($scalars -and $pa.Count -eq $da.Count -and (($pa -join "`n") -cne ($da -join "`n"))) {
      $sp = @($pa | Sort-Object { $_ } -CaseSensitive); $sd = @($da | Sort-Object { $_ } -CaseSensitive)
      if (($sp -join "`n") -ceq ($sd -join "`n")) {
        $Out.Add([pscustomobject]@{ Field = $Key; Ps = ('[' + ($pa -join ', ') + ']'); Delphi = ('[' + ($da -join ', ') + ']')
                                    Hint = 'order differs: Sort-Object culture/case-insensitive sort' })
        return
      }
    }
    if ($Ps.v.Count -ne $Dl.v.Count) {
      $Out.Add([pscustomobject]@{ Field = "$Key.#"; Ps = [string]$Ps.v.Count; Delphi = [string]$Dl.v.Count
                                  Hint = $(if ([Math]::Abs($Ps.v.Count - $Dl.v.Count) -eq 1) { 'count differs by one: single-item unroll or $null dropped from an array' } else { 'count differs' }) })
    }
    $n = [Math]::Min($Ps.v.Count, $Dl.v.Count)
    for ($i = 0; $i -lt $n; $i++) { Compare-ParityNode "$Key[$i]" $Ps.v[$i] $Dl.v[$i] $Out }
    return
  }
  $script:LeafCount++
  if ($Ps.t -eq $Dl.t -and ([string]$Ps.v) -ceq ([string]$Dl.v)) { return }
  $Out.Add([pscustomobject]@{ Field = $Key; Ps = [string]$Ps.v; Delphi = [string]$Dl.v; Hint = (Get-ParityHint $Ps $Dl $Key) })
}

# ---- the PowerShell side: Emit-Common.ps1 through the pinned engine -----------------------
$Engine = $Exe
$DbPath = ''
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')   # functions only; resolves $Engine and $DbPath dynamically

function Get-ParityStrippedSha([string] $Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return '(file missing)' }
  $lines = Get-StrippedSourceLines $Path
  $bytes = [Text.Encoding]::GetEncoding(28591).GetBytes(($lines -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

function Get-PsGlobalFacts {
  $facts = [ordered]@{}
  try {
    $rows = Get-EdgelessFiles
    $listed = @($rows | Select-Object -First $EdgelessListed | ForEach-Object { "$($_.p):$($_.n)" })
    $facts.edgeless = [ordered]@{ count = [int]@($rows).Count; disclosure = [string](Get-EdgelessDisclosure $rows); files = $listed }
  } catch { $facts.edgeless = [ordered]@{ error = $_.Exception.Message } }
  try {
    $pathRows = Get-AllIndexRows 'SELECT DISTINCT path FROM files' 'path'
    $paths = @($pathRows | ForEach-Object { [string]$_.path })
    $dirs = @($paths | ForEach-Object { [IO.Path]::GetDirectoryName($_) })
    $root = Get-CommonRootLen $dirs
    $step = [Math]::Max(1, [int][Math]::Floor($paths.Count / $ZoneSample))
    $sample = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $paths.Count; $i += $step) { $sample.Add((Get-PathZone $paths[$i] $root) + '|' + $paths[$i]) }
    $sample.Add((Get-PathZone '' $root) + '|')
    $facts.zones = [ordered]@{ rootLen = [int]$root; sample = $sample.ToArray() }
  } catch { $facts.zones = [ordered]@{ error = $_.Exception.Message } }
  $facts
}

# ---- step 2 (2026-10-13): the dot walk, the clone guard, the row cluster and one dot layout ----
# Each tool question is one message the PS can print; the probe answers the same question with
# DRagLint.Charts.Tools. A value is the resolved path; a failure is {error = <message>}.
function Get-PsToolValue([scriptblock] $Ask) {
  try { [string](& $Ask) } catch { [ordered]@{ error = $_.Exception.Message } }
}

function Get-PsToolFacts([string[]] $ClonePaths) {
  $t = [ordered]@{}
  $t.dotDefault         = Get-PsToolValue { Resolve-GraphvizDot '' }
  $t.dotExplicitMissing = Get-PsToolValue { Resolve-GraphvizDot (Join-Path $OutDir 'nope\dot.exe') }
  $t.dotBadSetting      = Get-PsToolValue { Resolve-GraphvizDot '' -SettingsPath (Join-Path $OutDir 'settings-bad-dot.json') }
  $t.dotNothing         = Get-PsToolValue { Resolve-GraphvizDot '' -SettingsPath (Join-Path $OutDir 'absent.json') `
                            -ChartsRoot (Join-Path $OutDir 'fake\charts') -ScriptDir (Join-Path $OutDir 'fake\charts\src') `
                            -SharedDefault (Join-Path $OutDir 'nope\shared-dot.exe') }
  $clones = New-Object System.Collections.Generic.List[object]
  foreach ($p in $ClonePaths) {
    $o = [ordered]@{ path = $p }
    try {
      # the override's NOTE is Write-Host (stream 6): capture it beside the value
      $items = @(Get-CloneDb $p 6>&1)
      $o.value = [string]@($items | Where-Object { $_ -is [string] })[-1]
      $o.note  = (@($items | Where-Object { $_ -isnot [string] } | ForEach-Object { [string]$_ }) -join "`n")
    } catch { $o.error = $_.Exception.Message }
    $clones.Add($o)
  }
  $t.clone = $clones.ToArray()
  $t
}

# Test-InterfaceLoop over the whole clone (the probe's ChecksJson asks the same): every unit a
# member, every uses row between two of them an edge, the FIRST row of a pair kept (as
# Emit-Cycles builds its map); anyLoop forces every section to 'interface'.
function Get-PsCheckFacts {
  try {
    $members = @((Get-AllIndexRows "SELECT DISTINCT LOWER(qualified_name) AS u FROM symbols WHERE kind = 'unit'" 'u') | ForEach-Object { [string]$_.u })
    $rows = Get-AllIndexRows @"
SELECT LOWER(su.qualified_name) AS src, LOWER(uu.unit_name) AS dst, uu.section AS section, uu.id AS uid, su.id AS sid
  FROM unit_uses uu JOIN files sf ON sf.id = uu.file_id JOIN symbols su ON su.file_id = sf.id AND su.kind = 'unit'
 WHERE LOWER(uu.unit_name) IN (SELECT LOWER(qualified_name) FROM symbols WHERE kind = 'unit')
"@ 'uid, sid'
    $map = @{}; $forced = @{}
    $intf = [pscustomobject]@{ section = 'interface' }
    foreach ($e in $rows) {
      $k = [string]$e.src + '|' + [string]$e.dst
      if (-not $map.ContainsKey($k)) { $map[$k] = $e; $forced[$k] = $intf }
    }
    [ordered]@{ members = $members.Count; edges = @($rows).Count
                intfLoop = [bool](Test-InterfaceLoop $map $members); anyLoop = [bool](Test-InterfaceLoop $forced $members) }
  } catch { [ordered]@{ error = $_.Exception.Message } }
}

# The SQL helpers over the whole clone (the probe's SqlJson asks the same): the collapsed table
# set, the procedure set and the trigger set, one digest line per item.
function Get-ParityTextSha([string] $Text) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

function Get-PsSqlFacts {
  try {
    $s = Get-SqlTableSet $DbPath
    $f = [ordered]@{ tableCount = [int]$s.TableCount; declarations = [int]$s.DeclarationCount; collapsed = [int]$s.CollapsedNames
                     procedureDecls = [int]$s.ProcedureDeclCount; names = @($s.Names) }
    $f.tables = @(foreach ($n in $s.Names) {
      $t = $s.Tables[$n]
      $decls = @($t.Declarations | ForEach-Object { "$($_.Id):$($_.File):$($_.Line):$($_.Columns)" }) -join ';'
      $older = @($t.OlderOnlyColumns.Keys | ForEach-Object { $o = $t.OlderOnlyColumns[$_]; "$_=$($o.Column)@$($o.File):$($o.Line)" }) -join ';'
      "$($t.Name)|$($t.Id)|$($t.File)|$($t.Line)|$($t.DeclCount)|$decls|$(@($t.ColumnNames) -join ',')|$older"
    })
    $f.procs = @(foreach ($p in (Get-SqlProcedureSet $DbPath).Declarations) {
      "$($p.Id)|$($p.Name)|$($p.File)|$($p.Line)|$($p.EndLine)|$($p.Stale)|$($p.Found)|$($p.Reason)|$(@($p.Tables) -join ',')|" +
        "$(@($p.Procs) -join ',')|$(if ($p.Found) { Get-ParityTextSha $p.Text } else { '<null>' })"
    })
    $f.trigs = @(foreach ($t in (Get-SqlTriggerSet $DbPath).Triggers) {
      "$($t.Id)|$($t.Name)|$($t.File)|$($t.Line)|$($t.EndLine)|$($t.Table)|$($t.TableKnown)|$($t.Stale)|$($t.Found)|" +
        "$(@($t.Columns) -join ',')|$(@($t.OtherTables) -join ',')"
    })
    $f
  } catch { [ordered]@{ error = $_.Exception.Message } }
}

# THE column state over the whole SQL clone (the probe's ColumnsJson asks the same): per table
# its first extracted column, its first older-only column and NOT_A_COLUMN (SqlSearched 'SRV'
# on even tables, a server hit on every fifth), the not-held list, and the quoted state
# through Hide-ExtractedColumns.
function Get-PsStateDigest($S) {
  "$($S.Table)|$($S.Column)|$($S.State)|$($S.IsColumn)|$($S.File)|$($S.Line)|$($S.Text)|$($S.Label)|$($S.OlderFile)|" +
    "$($S.OlderLine)|$($S.QuotedScan)|$(Get-ColumnHopLabel $S)|$(Get-ColumnStateName $S.State)"
}

function Get-PsColumnFacts {
  try {
    $s = Get-SqlTableSet $DbPath
    $states = New-Object System.Collections.Generic.List[string]
    $notHeld = New-Object System.Collections.Generic.List[string]
    for ($k = 0; $k -lt $s.Names.Count; $k++) {
      $t = $s.Tables[$s.Names[$k]]
      $probe = @()
      if (@($t.ColumnNames).Count) { $probe += @($t.ColumnNames)[0] }
      if ($t.OlderOnlyColumns.Count) { $probe += @($t.OlderOnlyColumns.Keys)[0] }
      foreach ($c in $probe) { $states.Add((Get-PsStateDigest (Get-SqlColumnState $s $t.Name $c))) }
      $hit = $(if ($k % 5 -eq 0) { [pscustomobject]@{ File = 'S.pas'; Line = 7; Routine = "TFoo.$($t.Name)" } } else { $null })
      $searched = $(if ($k % 2 -eq 0) { 'SRV' } else { '' })
      $states.Add((Get-PsStateDigest (Get-SqlColumnState $s $t.Name 'NOT_A_COLUMN' $null $hit $searched)))
      $notHeld.Add("$($t.Name):" + (@(Get-ColumnsNotHeld $s $t.Name @($probe + 'NOT_A_COLUMN')) -join ','))
    }
    $f = [ordered]@{ states = $states.ToArray(); notHeld = $notHeld.ToArray() }
    $ip = $s.Tables['IPCHART']; $fc = $s.Tables['FOLDERCOUNT']
    if ($ip -and $ip.Columns.Contains('ACTION') -and $fc -and $fc.Columns.Contains('TABLE')) {
      $h = Hide-ExtractedColumns $s @('IPCHART.ACTION', 'FOLDERCOUNT.TABLE')
      $f.quoted = @((Get-PsStateDigest (Get-SqlColumnState $h 'IPCHART' 'ACTION')), (Get-PsStateDigest (Get-SqlColumnState $h 'FOLDERCOUNT' 'TABLE')))
    }
    $f
  } catch { [ordered]@{ error = $_.Exception.Message } }
}

# Get-FieldBindingChains over the clone against the SQL clone (the probe's ChainsJson asks the
# same): every chain (by key, ordinal -- a hashtable has no order), every datasource, every
# binding, every re-point table (by key). Get-OrmLinksState once per clone.
function Get-PsSiteDigest($S) {
  "$($S.Control)|$($S.ControlFrom)|$($S.Receiver)|$($S.Prop)|$($S.File)|$($S.Line)|$($S.Routine)|$($S.Rhs)|$($S.Stale)"
}

function Get-PsChainsFacts([string] $SqlDb) {
  try {
    $s = Get-SqlTableSet $SqlDb
    $fb = Get-FieldBindingChains $s
    $keys = [string[]]@($fb.Chains.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    $chains = @(foreach ($k in $keys) {
      $c = $fb.Chains[$k]
      $ds = $c.DataSource
      [ordered]@{
        key = $k
        head = "$($c.Form)|$($c.FormFile)|$($c.PasFile)|$($c.DsName)|$($c.Module)|$($c.Dangling)"
        ds = $(if ($ds) { "$($ds.Id)|$($ds.Name)|$($ds.Qname)|$($ds.Type)|$($ds.File)|$($ds.Line)|$($ds.SameFile)" } else { '<null>' })
        controls = @($c.Controls | ForEach-Object { "$($_.Control)|$($_.ControlType)|$($_.ControlId)|$($_.Prop)|$($_.File)|$($_.Line)|$($_.IsLookup)" })
        rePointedAt = @($c.RePointedAt | ForEach-Object { Get-PsSiteDigest $_ })
        dataSetSites = @($c.DataSetSites | ForEach-Object { "$($_.Kind)|$($_.File)|$($_.Line)|$($_.Routine)|$($_.Rhs)|$($_.Eid)" })
        rhsType = $(if ($c.RhsType) { $r = $c.RhsType; "$($r.Rhs)|$($r.Root)|$($r.RootKind)|$($r.TypeName)|$($r.TypeKind)|$($r.TypeFile)|$($r.TypeLine)" } else { '<null>' })
        candidates = @($c.CandidateTables | ForEach-Object { "${_}:$($c.CandidateLines[$_])" })
        bound = @($c.BoundColumns)
        columnMatch = @($c.ColumnMatch)
        caseOnly = @($c.CaseOnlyLiterals)
        tail = "$($c.ResolvedTable)|$($c.Grade)|$($c.StopReason)"
        hops = @($c.Hops | ForEach-Object { "$($_.Hop)|$($_.Grade)|$($_.Label)|$($_.File)|$($_.Line)|$($_.Reason)" })
      }
    })
    $rkeys = [string[]]@($fb.RePoints.Keys)
    [Array]::Sort($rkeys, [StringComparer]::Ordinal)
    $rps = @(foreach ($k in $rkeys) {
      $r = $fb.RePoints[$k]
      $d = $r.DataSet
      [ordered]@{
        key = $k
        head = "$($r.Status)|$($r.Owner)|$($r.NilSites)|$($r.Table)|$($r.TableLine)|$($r.TableLines)|$($r.Stop)|$($r.StaleFile)"
        sites = @($r.Sites | ForEach-Object { Get-PsSiteDigest $_ })
        hops = @($r.Hops | ForEach-Object { "$($_.Hop)|$($_.Grade)|$($_.Label)|$($_.File)|$($_.Line)|$($_.Routine)|$($_.Reason)|$($_.Ask)" })
        dataSet = $(if ($d) { "$($d.Name)|$($d.Id)|$($d.ClassId)|$($d.File)|$($d.Fid)|$($d.Line)|$($d.Type)" } else { '<null>' })
      }
    })
    [ordered]@{
      chains = $chains
      dataSources = @($fb.DataSources | ForEach-Object { "$($_.FormFile)|$($_.DsName)|$($_.Grade)" })
      bindings = @($fb.Bindings | ForEach-Object { "$($_.Id)|$($_.Dfm)|$($_.Line)|$($_.Prop)|$($_.Column)|$($_.ControlId)|$($_.Control)|$($_.Ds)|" +
                                                   "$($_.Outcome)|$($_.Table)|$($_.Dangling)|$($_.RePointKey)|$($_.RePoint)" })
      rePoints = $rps
    }
  } catch { [ordered]@{ error = $_.Exception.Message } }
}

# The exception helpers (the probe's ExcGlobalJson / ExcJson ask the same): index-wide stats and
# the name filter over the first 60 pre-filtered ref names once per clone; per name the
# source-only rows and try-blocks of the symbol's body (its whole file when it has none), every
# handler's re-raise verdict, and the classes of the first 40 read/type_use refs in that span.
function Get-PsExcGlobalFacts {
  try {
    $s = Get-ExceptionIndexStats
    $names = Invoke-IndexQuery "SELECT DISTINCT r.name_text AS n FROM refs r WHERE $(Get-ExceptionNameSql 'r.name_text') ORDER BY r.name_text LIMIT 60"
    [ordered]@{
      stats = "$($s.Candidates)|$($s.Raise)|$($s.Handle)|$($s.Dropped)|$($s.Stale)|$($s.RaiseRoutines)|$($s.HandleRoutines)|$($s.Files)|$($s.FreshFiles)"
      names = @($names | ForEach-Object { "$([string]$_.n)=$(Test-ExceptionTypeName ([string]$_.n))" })
    }
  } catch { [ordered]@{ error = $_.Exception.Message } }
}

function Get-PsTryDigest([string[]] $Lines, [int] $From, [int] $To) {
  $tb = Get-TryBlocks $Lines $From $To
  $out = @("$($tb.Decided)|$($tb.Reason)")
  foreach ($b in $tb.Blocks) {
    $v = @()
    if ($b.Except) { $v += "bare=$(Test-HandlerReraises $Lines $b $b.Except $true)" }
    foreach ($p in $b.On) { $hb = Find-HandlerBlock $tb $p; if ($hb) { $v += "$p=$(Test-HandlerReraises $Lines $hb $p $false)" } }
    $out += "$($b.Try)/$($b.Except)/$($b.Finally)/$($b.End)/$(@($b.On) -join ',')/$($v -join ';')"
  }
  $out
}

function Get-PsExcFacts([string] $Path, [int] $From, [int] $To) {
  if (-not $Path) { return [ordered]@{ error = '(no symbol)' } }
  try {
    $scan = Get-ExceptionSourceRows $Path $From $To
    $f = [ordered]@{ stale = [bool]$scan.Stale; rows = @($scan.Rows | ForEach-Object { "$($_.Kind)|$($_.Line)|$($_.Col)|$($_.Text)" }) }
    if (-not $scan.Stale) { $f.tries = @(Get-PsTryDigest (Get-StrippedSourceLines (Resolve-SourceReadPath $Path $null)) $From $To) }
    $q = ConvertTo-SqlText $Path
    $refs = Invoke-IndexQuery @"
SELECT r.kind AS kind, r.start_line AS line, r.start_col AS col, r.end_col AS ecol
  FROM refs r JOIN files f ON f.id = r.file_id
 WHERE f.path = '$q' AND r.kind IN ('read','type_use') AND r.start_line BETWEEN $From AND $To
 ORDER BY r.start_line, r.start_col, r.id LIMIT 40
"@
    $f.classes = @($refs | ForEach-Object {
      $c = Get-SourceContext $Path ([int]$_.line) ([int]$_.col) ([int]$_.ecol - [int]$_.col)
      "$($_.line):$($_.col):$($_.kind):$(Get-ExceptionRefClass $c ([string]$_.kind))" })
    $f
  } catch { [ordered]@{ error = $_.Exception.Message } }
}

function Get-PsOrmFacts {
  try { $o = Get-OrmLinksState $DbPath; [ordered]@{ db = [string]$o.Db; rows = [int]$o.Rows; computedAt = [string]$o.ComputedAt } }
  catch { [ordered]@{ error = $_.Exception.Message } }
}

function Get-ParityFileSha([string] $Path) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { (($sha.ComputeHash([IO.File]::ReadAllBytes($Path)) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $sha.Dispose() }
}

# Up to 6 symbols of the symbol's file, in line order, as anchored rows (every other row
# with a note) plus a disclosure note row; the probe's ClusterText builds the same rows.
function Get-PsClusterText([string] $QName, [string] $Path) {
  $q = ConvertTo-SqlText $Path
  $rows = Invoke-IndexQuery @"
SELECT s.name AS name, s.qualified_name AS qname, s.kind AS kind, s.start_line AS line
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE f.path = '$q' ORDER BY s.start_line, s.id LIMIT 6
"@
  $list = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $rows.Count; $i++) {
    $r = $rows[$i]
    $list.Add([pscustomobject]@{ Label = [string]$r.name; Line = $r.line; Href = (New-RowHref $Path ([int]$r.line))
                                 Tip = [string]$r.qname; Note = $(if ($i % 2 -eq 0) { [string]$r.kind } else { '' }) })
  }
  $total = Invoke-IndexQuery "SELECT COUNT(*) AS n FROM symbols s JOIN files f ON f.id = s.file_id WHERE f.path = '$q'"
  $noteText = Get-DisclosureText ([int]$total[0].n - $rows.Count) 0 'symbols'
  if ($noteText) { $list.Add((New-NoteRow $noteText)) }
  $sb = New-Object System.Text.StringBuilder
  $ports = Add-RowCluster -Sb $sb -Cid 'cluster_focus' -Nid 'focus' -Title $QName -Subtitle (Get-UnitName $Path) `
                          -Rows $list.ToArray() -Border '#3B6EA8' -Fill '#EEF3FA' -Hdr '#3B6EA8'
  $t = New-Object System.Text.StringBuilder
  Add-DisclosureRow $t "$QName &#183; $Path"
  [pscustomobject]@{ Text = $sb.ToString(); Ports = @($ports); Disclosure = $t.ToString() }
}

function Get-PsClusterFacts([string] $QName, [string] $Path, [string] $LayoutDir) {
  $f = [ordered]@{}
  if (-not $Path) { $f.cluster = [ordered]@{ error = '(no symbol)' }; $f.layout = [ordered]@{ error = '(no symbol)' }; return $f }
  try {
    $c = Get-PsClusterText $QName $Path
    $f.cluster = [ordered]@{ text = $c.Text; ports = $c.Ports; disclosure = $c.Disclosure }
  } catch { $f.cluster = [ordered]@{ error = $_.Exception.Message } }
  try {
    $c = Get-PsClusterText $QName $Path
    $l = Invoke-DotLayout ("digraph G {`n  rankdir=LR; node [shape=plaintext];`n" + $c.Text + "}`n") $LayoutDir 'c'
    $f.layout = [ordered]@{ dotSha = (Get-ParityFileSha $l.Dot); svgSha = (Get-ParityFileSha $l.Svg)
                            plainSha = (Get-ParityFileSha $l.Plain); anchors = [int]$l.Anchors }
  } catch { $f.layout = [ordered]@{ error = $_.Exception.Message } }
  $f
}

function Get-PsFacts([string] $QName) {
  $f = [ordered]@{}
  $locPath = ''
  try {
    $l = Get-SymbolLocation $QName
    $locPath = $l.Path
    $f.symbolLocation = [ordered]@{ id = [int]$l.Id; kind = [string]$l.Kind; path = [string]$l.Path; declLine = [int]$l.DeclLine
                                    implStart = [int]$l.ImplStart; implEnd = [int]$l.ImplEnd; focusLine = [int]$l.FocusLine }
  } catch { $f.symbolLocation = [ordered]@{ error = $_.Exception.Message } }
  $memPath = ''
  try {
    $m = Resolve-MemberSelection $QName $CoreKinds -AllowMissing
    if ($null -eq $m) { $f.memberSelection = [ordered]@{ found = $false } }
    else {
      $memPath = $m.Path
      $f.memberSelection = [ordered]@{ found = $true; id = [int]$m.Id; kind = [string]$m.Kind; path = [string]$m.Path
                                       qname = [string]$m.Qname; name = [string]$m.Name; propAccess = [string]$m.PropAccess
                                       declLine = [int]$m.DeclLine; implStart = [int]$m.ImplStart; implEnd = [int]$m.ImplEnd
                                       focusLine = [int]$m.FocusLine }
    }
  } catch { $f.memberSelection = [ordered]@{ error = $_.Exception.Message } }

  # the first call ref of the symbol's file: the one place a source context is asked about
  $ctxArgs = $null
  if ($locPath) {
    try {
      $q = ConvertTo-SqlText $locPath
      $refRows = Invoke-IndexQuery @"
SELECT r.line AS line, r.start_col AS start_col, r.end_col AS end_col
  FROM refs r JOIN files f ON f.id = r.file_id
 WHERE f.path = '$q' AND r.kind = 'call'
 ORDER BY r.line, r.start_col, r.id LIMIT 1
"@
      if ($refRows.Count -gt 0) {
        $ctxArgs = [pscustomobject]@{ File = $locPath; Line = [int]$refRows[0].line; Col = [int]$refRows[0].start_col
                                      Len = [int]$refRows[0].end_col - [int]$refRows[0].start_col }
      }
    } catch { $ctxArgs = $null }
  }
  $sha = [ordered]@{}
  foreach ($p in @($locPath, $memPath, $(if ($ctxArgs) { $ctxArgs.File } else { '' }))) {
    if (-not $p) { continue }
    if ($sha.Contains($p)) { continue }
    try { $sha[$p] = Get-ParityStrippedSha $p } catch { $sha[$p] = 'error: ' + $_.Exception.Message }
  }
  $f.strippedSha = $sha
  if (-not $ctxArgs) { $f.context = [ordered]@{ error = '(no --file given)' } }
  else {
    try {
      $c = Get-SourceContext $ctxArgs.File $ctxArgs.Line $ctxArgs.Col $ctxArgs.Len $null $FollowingLines
      $f.context = [ordered]@{ path = [string]$c.Path; line = [int]$c.Line; stale = [bool]$c.Stale; before = $c.Before; token = $c.Token
                               after = $c.After; prevLine = $c.PrevLine; prevLineNo = [int]$c.PrevLineNo; following = @($c.Following) }
    } catch { $f.context = [ordered]@{ error = $_.Exception.Message } }
  }
  $implS = $(if ($f.symbolLocation.Contains('implStart')) { $f.symbolLocation.implStart } else { 0 })
  $implE = $(if ($f.symbolLocation.Contains('implEnd')) { $f.symbolLocation.implEnd } else { 0 })
  [pscustomobject]@{ Facts = $f; Ctx = $ctxArgs; LocPath = $locPath; ImplStart = $implS; ImplEnd = $implE }
}

function Invoke-Probe([string] $ProbeExe, [string] $Db, [string] $QName, $Ctx, [string] $LayoutDir, [string[]] $ClonePaths, [bool] $Globals) {
  $a = @('--db', $Db, '--qname', $QName, '--kinds', ($CoreKinds -join ','))
  if ($Ctx) { $a += @('--file', $Ctx.File, '--line', [string]$Ctx.Line, '--col', [string]$Ctx.Col, '--len', [string]$Ctx.Len) }
  $a += @('--charts-root', (Join-Path $RepoRoot 'charts'), '--scratch', $OutDir, '--layout-dir', $LayoutDir)
  foreach ($p in $ClonePaths) { $a += @('--clone-path', $p) }
  if ($Globals) { $a += @('--globals', '1', '--sql-db', (Join-Path $DbRoot 'SQL-drag-lint-sql.sqlite')) }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $o = & $ProbeExe @a 2>&1
  $sw.Stop()
  $text = (@($o) -join "`n")
  try { $json = $text | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }
  [pscustomobject]@{ Json = $json; Text = $text; Seconds = $sw.Elapsed.TotalSeconds }
}

function Invoke-CoreMode {
  $probeExe = Join-Path $RepoRoot 'charts\scratch\probe\ChartsCoreProbe.exe'
  if (-not (Test-Path -LiteralPath $probeExe)) {
    Write-Host 'building ChartsCoreProbe ...'
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'tests\charts\run_charts_core_probe_build.ps1') | Out-Host
    if (-not (Test-Path -LiteralPath $probeExe)) { Write-Host 'FATAL: probe build failed' -ForegroundColor Red; exit 2 }
  }
  # clone -> names: case targets (honouring -Only) first, then the fixed names; exact duplicates once
  $plan = [ordered]@{}
  foreach ($db in $FixedNames.Keys) {
    if ($Clone -and -not $db.StartsWith($Clone, [StringComparison]::OrdinalIgnoreCase)) { continue }
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($c in $cases) { if ($c.db -ceq $db -and -not $names.Contains([string]$c.target)) { $names.Add([string]$c.target) } }
    foreach ($n in $FixedNames[$db]) { if (-not $names.Contains($n)) { $names.Add($n) } }
    $plan[$db] = $names
  }
  # the settings file the dotBadSetting question reads: a "dot" key that names a missing file
  $badDot = Join-Path $OutDir 'nope\dot.exe'
  [IO.File]::WriteAllText((Join-Path $OutDir 'settings-bad-dot.json'), ('{"dot": "' + $badDot.Replace('\', '\\') + '"}'))
  $nonClone = Join-Path $RepoRoot 'src\cli\_D-RAG\drag-lint.sqlite'
  $sqlClone = Join-Path $DbRoot 'SQL-drag-lint-sql.sqlite'
  $mismatches = New-Object System.Collections.Generic.List[object]
  $rowsOut = New-Object System.Collections.Generic.List[object]
  $nameNo = 0
  foreach ($db in $plan.Keys) {
    $script:DbPath = Join-Path $DbRoot $db
    $DbPath = $script:DbPath
    Write-Host "== $db ($($plan[$db].Count) names)"
    # the clone, a history copy beside it, a non-clone index and a missing clone name
    $clonePaths = @($DbPath)
    if (Test-Path -LiteralPath "$DbPath.pre-1.9") { $clonePaths += "$DbPath.pre-1.9" }
    if (Test-Path -LiteralPath $nonClone) { $clonePaths += $nonClone }
    $clonePaths += (Join-Path $DbRoot 'missing.sqlite')
    $globalDone = $false
    foreach ($q in $plan[$db]) {
      $nameNo++
      $layoutPs = Join-Path $OutDir "dot\$nameNo\ps"
      $layoutDl = Join-Path $OutDir "dot\$nameNo\dl"
      $swPs = [Diagnostics.Stopwatch]::StartNew()
      $ps = Get-PsFacts $q
      $facts = $ps.Facts
      foreach ($kv in (Get-PsClusterFacts $q $ps.LocPath $layoutPs).GetEnumerator()) { $facts[$kv.Key] = $kv.Value }
      $impl = [int]$ps.ImplStart
      $facts.exc = $(if ($impl -gt 0) { Get-PsExcFacts $ps.LocPath $impl ([int]$ps.ImplEnd) } else { Get-PsExcFacts $ps.LocPath 1 999999 })
      if (-not $globalDone) {
        foreach ($kv in (Get-PsGlobalFacts).GetEnumerator()) { $facts[$kv.Key] = $kv.Value }
        $facts.tools = Get-PsToolFacts $clonePaths
        $facts.checks = Get-PsCheckFacts
        $facts.sql = Get-PsSqlFacts
        $facts.columns = Get-PsColumnFacts
        $facts.orm = Get-PsOrmFacts
        $facts.excGlobal = Get-PsExcGlobalFacts
        $facts.chains = Get-PsChainsFacts $sqlClone
      }
      $swPs.Stop()
      $probe = Invoke-Probe $probeExe $DbPath $q $ps.Ctx $layoutDl $clonePaths (-not $globalDone)
      $found = New-Object System.Collections.Generic.List[object]
      if ($null -eq $probe.Json) {
        $found.Add([pscustomobject]@{ Field = '(probe)'; Ps = '(a JSON object)'; Delphi = $probe.Text.Substring(0, [Math]::Min(300, $probe.Text.Length)); Hint = 'probe printed no JSON: diagnose the probe first' })
      } else {
        $psNode = Convert-ParityNode $facts
        $dlNode = Convert-ParityNode $probe.Json
        # a section only one side computed (the index-wide ones run once per clone) is not compared elsewhere
        foreach ($k in @($dlNode.v.Keys)) { if (-not $psNode.v.Contains($k)) { $dlNode.v.Remove($k) } }
        foreach ($k in @($psNode.v.Keys)) { if (-not $dlNode.v.Contains($k)) { $dlNode.v[$k] = @{ t = 'z'; v = '<absent>' } } }
        Compare-ParityNode '' $psNode $dlNode $found
      }
      $globalDone = $true
      foreach ($m in $found) {
        $m | Add-Member -NotePropertyName Clone -NotePropertyValue $db
        $m | Add-Member -NotePropertyName QName -NotePropertyValue $q
        $mismatches.Add($m)
        Write-Host ("MISMATCH {0} [{1} / {2}]: ps={3} delphi={4} -- check: {5}" -f $m.Field.TrimStart('.'), $db, $q, $m.Ps, $m.Delphi, $m.Hint) -ForegroundColor Red
      }
      $rowsOut.Add([pscustomobject]@{ Clone = $db; QName = $q; Mismatches = $found.Count; PsSeconds = [Math]::Round($swPs.Elapsed.TotalSeconds, 1); DelphiSeconds = [Math]::Round($probe.Seconds, 2) })
      Write-Host ("  {0}: {1} mismatch(es)  ps {2}s  delphi {3}s" -f $q, $found.Count, [Math]::Round($swPs.Elapsed.TotalSeconds, 1), [Math]::Round($probe.Seconds, 2))
    }
  }
  Add-Summary '## Core (PS Emit-Common vs Delphi ports)'
  Add-Summary ''
  Add-Summary '| clone | name | mismatches | PS s | Delphi s |'
  Add-Summary '|---|---|---|---|---|'
  foreach ($r in $rowsOut) { Add-Summary "| $($r.Clone) | $($r.QName) | $($r.Mismatches) | $($r.PsSeconds) | $($r.DelphiSeconds) |" }
  Add-Summary ''
  Add-Summary "Compared: $($rowsOut.Count) name(s) over $($plan.Count) clone(s), $($script:LeafCount) leaf field(s) compared with -ceq; **$($mismatches.Count) MISMATCH(es)**."
  Add-Summary ''
  if ($mismatches.Count) {
    Add-Summary '### Mismatches (findings with a mechanism; never re-baselined -- P4)'
    Add-Summary ''
    Add-Summary '| clone | name | field | ps | delphi | check |'
    Add-Summary '|---|---|---|---|---|---|'
    foreach ($m in $mismatches) {
      $cell = { param($s) ([string]$s).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ') }
      Add-Summary ("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $m.Clone, $m.QName, (& $cell $m.Field.TrimStart('.')), (& $cell $m.Ps), (& $cell $m.Delphi), (& $cell $m.Hint))
    }
    Add-Summary ''
  }
  $mismatches.Count
}

# ============================ Question (P3, end to end) ===========================

# The probe's sources: rebuilt when any is newer than the exe, so a question is never compared
# against a Delphi build of yesterday's code.
function Get-ProbeExe {
  $probeExe = Join-Path $RepoRoot 'charts\scratch\probe\ChartsCoreProbe.exe'
  $srcs = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'src\charts') -Filter '*.pas') + @(Get-Item -LiteralPath (Join-Path $RepoRoot 'tests\charts\ChartsCoreProbe.dpr'))
  $stale = -not (Test-Path -LiteralPath $probeExe)
  if (-not $stale) { $t = (Get-Item -LiteralPath $probeExe).LastWriteTimeUtc; $stale = [bool]@($srcs | Where-Object { $_.LastWriteTimeUtc -gt $t }).Count }
  if ($stale) {
    Write-Host 'building ChartsCoreProbe ...'
    & pwsh -NoProfile -File (Join-Path $RepoRoot 'tests\charts\run_charts_core_probe_build.ps1') | Out-Host
    if (-not (Test-Path -LiteralPath $probeExe)) { Write-Host 'FATAL: probe build failed' -ForegroundColor Red; exit 2 }
  }
  $probeExe
}

# The text a bundle file holds once the two facts that legitimately differ between two runs are
# masked: the time it was generated (the same N1 rule that drops the header's date/time) and the
# bundle's own root folder (the same N1 rule that drops the BUNDLE line; -Mode Question now has
# both sides write under ONE root in turn, so this mask is a no-op there). Nothing else is touched.
function Get-MaskedBundleText([string] $Path, [string] $Root) {
  $t = [IO.File]::ReadAllText($Path)
  $t = $t.Replace($Root, '<BUNDLE-ROOT>')
  $t = [regex]::Replace($t, '(?<="generated": ")[^"]*', '<GENERATED>')
  $t = [regex]::Replace($t, '(?<=generated <b>)[^<]*', '<GENERATED>')
  [regex]::Replace($t, '(?<=/// Generated: )\S+', '<GENERATED>')
}

# Per bundle file: 'same' or why not. graph.pdf is reported, never compared: dot's cairo PDF is not
# byte-stable (two PS runs of one question differ, measured 2026-10-13), and its content is the
# .dot source, which IS compared byte for byte.
$BundleBytewise = @('graph.dot', 'graph.svg', 'graph.plain', 'graph.png')
$BundleMasked   = @('meta.json', 'index.html', 'xref.txt')
$BundleSkipped  = @{ 'graph.pdf' = 'not compared: cairo PDF output differs between two PS runs of the same question' }
function Compare-Bundle([string] $PsDir, [string] $DlDir, [string] $PsRoot, [string] $DlRoot) {
  $out = New-Object System.Collections.Generic.List[object]
  $names = @(@(Get-ChildItem -LiteralPath $PsDir -File | ForEach-Object Name) + @(Get-ChildItem -LiteralPath $DlDir -File | ForEach-Object Name) | Sort-Object -Unique)
  foreach ($n in $names) {
    $p = Join-Path $PsDir $n; $d = Join-Path $DlDir $n
    if ($BundleSkipped.ContainsKey($n)) { $out.Add([pscustomobject]@{ File = $n; Same = $null; Why = $BundleSkipped[$n] }); continue }
    if (-not (Test-Path -LiteralPath $p)) { $out.Add([pscustomobject]@{ File = $n; Same = $false; Why = 'only the Delphi bundle has it' }); continue }
    if (-not (Test-Path -LiteralPath $d)) { $out.Add([pscustomobject]@{ File = $n; Same = $false; Why = 'only the PS bundle has it' }); continue }
    if ($n -in $BundleMasked) {
      $same = (Get-MaskedBundleText $p $PsRoot) -ceq (Get-MaskedBundleText $d $DlRoot)
      $out.Add([pscustomobject]@{ File = $n; Same = $same; Why = $(if ($same) { 'equal (generated time and bundle root masked)' } else { 'differs after masking -- diff the two files' }) })
    } elseif ($n -in $BundleBytewise) {
      $same = (Get-ParityFileSha $p) -ceq (Get-ParityFileSha $d)
      $out.Add([pscustomobject]@{ File = $n; Same = $same; Why = $(if ($same) { 'byte-equal' } else { 'bytes differ' }) })
    } else {
      $out.Add([pscustomobject]@{ File = $n; Same = $false; Why = 'a bundle file this harness does not know -- add it to a list above' })
    }
  }
  $out
}

function Invoke-QuestionMode {
  $probeExe = Get-ProbeExe
  $ported = @(& $probeExe --ported 2>$null | Where-Object { $_ })
  $chartsRoot = Join-Path $RepoRoot 'charts'
  # ONE bundle root for both sides, used in turn: a bundle path is part of the answer (the
  # '... N more row(s) not printed here (-MaxRows ..): <bundle>\graph.dot' line), so two roots
  # would put a difference into the text that neither producer made. Ask-Report writes under
  # $bRoot first and its bundle is moved to $psKeep; then the Delphi question writes under $bRoot.
  # Nothing is masked or rewritten: each side's bytes name the same root because they were
  # written there.
  $bRoot  = Join-Path $OutDir 'question\b'
  $psKeep = Join-Path $OutDir 'question\ps'
  New-Item -ItemType Directory -Force $bRoot, $psKeep | Out-Null
  $psRoot = $bRoot
  $dlRoot = $bRoot
  $rows = New-Object System.Collections.Generic.List[object]
  $bad = 0
  foreach ($c in $cases) {
    if ($ported -notcontains $c.question) { $rows.Add([pscustomobject]@{ Question = $c.question; Text = 'not ported'; Files = ''; PsS = ''; DlS = ''; Verdict = 'SKIP' }); continue }
    if ($c.serverDb -or $c.sqlDb -or $c.counterpartDb -or @($c.extra).Count) {
      $rows.Add([pscustomobject]@{ Question = $c.question; Text = ''; Files = ''; PsS = ''; DlS = ''; Verdict = 'SETUP: the probe passes one index and no extra arguments' }); $bad++; continue
    }
    Write-Host "question: $($c.question) ..."
    $psFile = Join-Path $OutDir "$($c.question).ps.txt"
    $dlFile = Join-Path $OutDir "$($c.question).dl.txt"
    $r1 = Invoke-AskPlain $c $psFile $psRoot
    # move the PS bundle out of the shared root before the Delphi side writes the same folder
    $psWrote = ((Get-Content -LiteralPath $psFile | Where-Object { $_ -like 'BUNDLE *' } | Select-Object -First 1) -replace '^BUNDLE ', '')
    $psBundle = ''
    if ($psWrote -and (Test-Path -LiteralPath $psWrote)) {
      $psBundle = Join-Path $psKeep (Split-Path $psWrote -Leaf)
      if (Test-Path -LiteralPath $psBundle) { Remove-Item -LiteralPath $psBundle -Recurse -Force }
      Move-Item -LiteralPath $psWrote -Destination $psBundle
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $dlOut = & $probeExe --question $c.question --target $c.target --db (Join-Path $DbRoot $c.db) --out-root $dlRoot --charts-root $chartsRoot 2>"$dlFile.err"
    $dlExit = $LASTEXITCODE
    $sw.Stop()
    [IO.File]::WriteAllText($dlFile, ((@($dlOut) -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
    $row = [ordered]@{ Question = $c.question; Text = ''; Files = ''; PsS = $r1.Seconds; DlS = [Math]::Round($sw.Elapsed.TotalSeconds, 1); Verdict = '' }
    if ($r1.Exit -ne 0 -or $dlExit -ne 0) {
      $row.Verdict = "SETUP/REFUSAL: Ask-Report exit $($r1.Exit), Delphi exit $dlExit (see $($c.question).*.txt.err)"
      $bad++; $rows.Add([pscustomobject]$row); continue
    }
    # the text: the step-1 diff with its own normalisation (spec s5), never a looser rule
    $cmp = & $Exe compare --old $psFile --new $dlFile --format json 2>"$OutDir\$($c.question).question-compare.err"
    $code = $LASTEXITCODE
    $cmpText = (@($cmp) -join "`n")
    [IO.File]::WriteAllText((Join-Path $OutDir "$($c.question).question-compare.json"), $cmpText)
    $textDiffs = -1
    try { $j = $cmpText | ConvertFrom-Json -ErrorAction Stop; $textDiffs = [int]$j.counts.removed + [int]$j.counts.added } catch { }
    $row.Text = $(if ($code -eq 0) { '0 differences' } elseif ($code -eq 1) { "$textDiffs line(s) differ" } else { "compare exited $code" })
    # the bundle: every file either side wrote
    $dlBundle = ((Get-Content -LiteralPath $dlFile | Where-Object { $_ -like 'BUNDLE *' } | Select-Object -First 1) -replace '^BUNDLE ', '')
    $files = @(Compare-Bundle $psBundle $dlBundle $psRoot $dlRoot)
    $fileBad = @($files | Where-Object { $_.Same -eq $false })
    $row.Files = (@($files | ForEach-Object { "$($_.File): $($_.Why)" }) -join '; ')
    foreach ($f in $fileBad) { Write-Host "  DIFF $($c.question) $($f.File): $($f.Why)" -ForegroundColor Red }
    if ($code -ne 0) {
      Write-Host "  DIFF $($c.question) text: $($row.Text)" -ForegroundColor Red
      Write-Host ('  first differing line pair: ' + (Get-FirstDiffPair $psFile $dlFile))
    }
    $row.Verdict = $(if ($code -eq 0 -and $fileBad.Count -eq 0) { 'PASS' } else { 'FINDING' })
    if ($row.Verdict -ne 'PASS') { $bad++ }
    $rows.Add([pscustomobject]$row)
    Write-Host ("  {0}: text {1}; {2} of {3} bundle file(s) compared equal  ps {4}s  delphi {5}s" -f $c.question, $row.Text,
                @($files | Where-Object { $_.Same -eq $true }).Count, $files.Count, $row.PsS, $row.DlS)
  }
  Add-Summary '## Question (Ask-Report -Plain vs the in-process Delphi question)'
  Add-Summary ''
  Add-Summary "Ported in this build: $(if ($ported.Count) { $ported -join ', ' } else { '(none)' })."
  Add-Summary ''
  Add-Summary '| question | text | bundle | PS s | Delphi s | verdict |'
  Add-Summary '|---|---|---|---|---|---|'
  foreach ($r in $rows) { Add-Summary "| $($r.Question) | $($r.Text) | $($r.Files.Replace('|', '\|')) | $($r.PsS) | $($r.DlS) | $($r.Verdict) |" }
  Add-Summary ''
  $bad
}

# ===================================== run =========================================

Add-Summary "# Parity summary -- mode $Mode, $Stamp"
Add-Summary ''
Add-Summary "Engine: ``$Exe``; clones: ``$DbRoot``; cases: $($cases.Count)$(if ($Only) { ", -Only $Only" })$(if ($Clone) { ", -Clone $Clone" })."
Add-Summary ''
$bad = 0
if ($Mode -eq 'Determinism') { $bad = Invoke-DeterminismMode } elseif ($Mode -eq 'Question') { $bad = Invoke-QuestionMode } else { $bad = Invoke-CoreMode }
$summaryPath = Join-Path $OutDir 'parity-summary.md'
[IO.File]::WriteAllText($summaryPath, (($summary -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "summary: $summaryPath"
if ($bad -gt 0) { Write-Host "RESULT: $bad finding(s)" -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: parity holds' -ForegroundColor Green
exit 0
