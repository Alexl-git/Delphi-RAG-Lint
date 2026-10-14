<#
  Ask-Report.ps1 -- ONE command that asks a report question and prints the answer as text.

  Written for AI agents (and anyone else in a hurry). New-DiagramArtifact.ps1 needs up to
  three database paths and an environment variable; an agent that had the report verbs
  described to it still did not run one, because standing that up was the whole job. This
  wrapper does the standing-up and nothing else:

    1. the PROJECT index comes from the engine's own `resolve-dbs` (`--project` on -Project,
       else `--in` on -In) -- never a guessed path. When --in names several indexes, the one
       report-pairs.json pairs is taken; otherwise it stops and asks for -Project.
    2. the SERVER and SQL indexes, for the questions that read them, come from
       report-pairs.json (client index -> server index, SQL index) -- by default
       %APPDATA%\drag-lint\report-pairs.json, else the repo's charts\report-pairs.json
       (Resolve-ReportPairsFile, Emit-Common.ps1); a missing pair is a
       clear stop that names the file to edit, never a one-sided chart.
    3. freshness: every index it will read is checked with the engine's `sql` envelope
       (`stale` / `stale_files`); a stale one stops the run and prints the exact incremental
       reindex command. It never runs `index` itself.
    4. DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 is set for the bundler call only, and restored after.
    5. the bundle goes under $env:TEMP\drag-lint-reports unless -OutRoot says otherwise.
    6. stdout is the answer, by DEFAULT as a DocInsight block -- `/// <remarks>` ... `/// </remarks>`,
       the same bytes the IDE's drag-lint > Reports menu puts on the clipboard (owner answer 2,
       R5). That mode is DELEGATED to the engine: without -Plain (and without -ResolveOnly) this script
       runs `drag-lint ask` with the same arguments and passes its stdout, stderr and exit code through
       -- the one formatter is DRagLint.Charts.DocInsight (Report.DocInsight.ps1, its PowerShell port,
       was deleted 2026-10-14). -Plain gives the plain answer, made here: two header lines (a sentence "<Phrase> (drag-lint report <id>) for <target>, asked on
       <date> <time>, engine <version>." and a `COMMAND <id> -Target ...` line naming the arguments as given, never a
       display switch or an index override), then `BUNDLE <folder>`, one `INDEX <db>[ (server|sql|counterpart)]` line per
       index read, then the TEXT to read -- the whole trace.dlgraph for round-trip (plus a `NOTE the
       chart could not be drawn: <why>` line when dot failed), else a `CHART`
       header (the counts), `TARGET <name> @File.pas:line` for the chart's own selection, one
       `<name> @File.pas:line` line per anchored result row, and `... +N more ... not shown (-Cap N;
       raise -Cap to see them)` for every row the chart itself left out -- a count in the header
       is never silently larger than the rows printed. The DocInsight block is made FROM that plain
       answer (BUNDLE / INDEX / REGENERATE dropped, anchors as (File.pas:line)). Nothing else is
       printed on stdout. `drag-lint ask` runs this script with -Plain for every question not ported to
       Delphi, and the IDE plugin now asks the engine (`drag-lint ask ... --plain`), not this script.

  Exit codes: 0 answered; 1 the question refused or failed (the reason on stderr);
  2 setup -- the indexes could not be resolved (stderr says what to pass or edit);
  3 an index is stale (stderr carries the reindex command).

  -DbPath / -ServerDbPath / -SqlDbPath / -CounterpartDb still override resolution (the tests
  use the frozen clones under charts\scratch\db that way). -ResolveOnly prints the indexes it
  would use and stops.

  Example (the one line to type):
    pwsh -NoProfile -File C:\Projects\Delphi-RAG-lint-wt\archify-ir\charts\src\Ask-Report.ps1 -Question round-trip -Target frmBlueprint4.dxDBGrid1FtrsVNum -Project C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Question,
  [Parameter(Mandatory)][string] $Target,
  # any .pas / .dfm of the project, or the project file itself -- one of the two names the index
  [string] $In,
  [string] $Project,
  [string] $OutRoot = (Join-Path $env:TEMP 'drag-lint-reports'),
  # pass-through to New-DiagramArtifact.ps1, each only when given
  [int]    $Depth,
  [int]    $Cap,
  [int]    $SurfaceCap,
  [string] $Control,
  [string] $Mode,
  # path only: routine B (-Target is routine A)
  [string] $To,
  [switch] $Open,
  # overrides: an explicit index skips resolution for that index (never its freshness check)
  [string] $DbPath,
  [string] $ServerDbPath,
  [string] $SqlDbPath,
  [string] $CounterpartDb,
  [switch] $ResolveOnly,
  # the plain answer (the BUNDLE / INDEX lines and the text) instead of the default DocInsight block
  [switch] $Plain,
  # the old side of a compare may be an old index copy, stale on purpose: report it, do not stop
  [switch] $AllowStale,
  [int]    $MaxRows = 80,
  # '' = Resolve-ReportPairsFile (Emit-Common.ps1): %APPDATA%\drag-lint\report-pairs.json, else charts\report-pairs.json
  [string] $PairsFile = '',
  # '' = found by Resolve-DragLintEngine (Emit-Common.ps1): DRAGLINT_ENGINE, settings.json, the installed or shared engine
  [string] $Engine    = ''
)

$ErrorActionPreference = 'Stop'
$bundler = Join-Path $PSScriptRoot 'New-DiagramArtifact.ps1'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')   # functions only; Resolve-DragLintEngine
if (-not $PairsFile) { $PairsFile = Resolve-ReportPairsFile }
# The IDE plugin's REPORT_QUESTIONS: -Question id -> menu caption; the header phrase is the caption without its '...'.
# Also DRagLint.Charts.Question's QUESTION_CAPTIONS. Test-AskReport AR-CAPTIONS compares this table with the plugin's.
$script:ReportCaptions = [ordered]@{
  'butterfly'        = 'Callers and callees (butterfly chart)...'
  'who-calls'        = 'Who calls this routine...'
  'what-it-calls'    = 'What this routine calls...'
  'path'             = 'Call path from this routine to another...'
  'effects'          = 'What this routine changes (side effects)...'
  'touches-tables'   = 'Which tables this routine touches...'
  'exception-paths'  = 'Which exceptions escape this routine...'
  'crosses-boundary' = 'Does this routine leave the process...'
  'protocol-trace'   = 'Where this protocol command travels...'
  'change-impact'    = 'What a change here would break...'
  'tested-by'        = 'Which tests reach this code...'
  'who-writes'       = 'Who writes this field...'
  'who-reads'        = 'Who reads this field...'
  'feeds-from'       = 'What feeds this control (back to the column)...'
  'lands-where'      = 'Where this field lands in the database...'
  'round-trip'       = 'Field round-trip (grid -> server -> SQL)...'
  'class-surface'    = 'What this type exposes (class surface)...'
  'hierarchy'        = 'Ancestors and descendants (hierarchy)...'
  'wiring'           = 'Who registers and resolves this interface...'
  'event-wiring'     = 'Which handler runs on which event (form)...'
  'lifecycle'        = 'Form lifecycle (create -> show -> destroy)...'
  'deps'             = 'Dependencies of this unit...'
  'architecture'     = 'Project architecture (layered zones)...'
  'cycles'           = 'Circular unit dependencies...'
  'consumers'        = 'Who uses this table or column...'
  'shown-where'      = 'Where this database column is shown...'
}
$answer = New-Object System.Collections.Generic.List[string]

function Stop-Ask([int] $Code, [string] $Message) {
  $x = [Exception]::new($Message); $x.Data['AskExit'] = $Code; throw $x
}
function Invoke-Engine([string[]] $ArgList) {
  $o = & $Engine @ArgList 2>$null
  [pscustomobject]@{ Exit = $LASTEXITCODE; Text = (@($o) -join "`n") }
}
# the engine prints a JSON document on stdout. Notes normally go to stderr (dropped above), but a
# line such as `[note] ...` on stdout also starts with '[' -- so the document is the first LINE from
# which the rest parses as JSON, not the first '{' or '[' character (fix round 1, M-4).
function ConvertFrom-EngineJson([string] $Text) {
  $lines = @($Text -split "\r?\n")
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].TrimStart() -notmatch '^[\{\[]') { continue }
    try { return (($lines[$i..($lines.Count - 1)] -join "`n") | ConvertFrom-Json -ErrorAction Stop) } catch { }
  }
  $null
}
function Test-SamePath([string] $A, [string] $B) {
  if (-not $A -or -not $B) { return $false }
  [string]::Equals([IO.Path]::GetFullPath($A), [IO.Path]::GetFullPath($B), [StringComparison]::OrdinalIgnoreCase)
}
function Find-Pair([string] $Db) {
  foreach ($p in $pairs) { if ((Test-SamePath $p.client $Db) -or (Test-SamePath $p.server $Db)) { return $p } }
  $null
}
# the incremental reindex command for a stale index, or $null when none can be derived for certain
function Get-ReindexCommand([string] $Db) {
  foreach ($p in $pairs) { if ((Test-SamePath $p.sql $Db) -and $p.sqlSection) { return "& '$Engine' index --all --only $($p.sqlSection)" } }
  $dir = Split-Path -Parent $Db
  if ((Split-Path -Leaf $dir) -ieq '_D-RAG') {
    $projDir = Split-Path -Parent $dir
    $base = [IO.Path]::GetFileNameWithoutExtension($Db)
    foreach ($ext in '.dproj', '.dpr') {
      $pf = Join-Path $projDir "$base$ext"
      if (-not (Test-Path -LiteralPath $pf)) { continue }
      $rr = Invoke-Engine @('resolve-dbs', '--project', $pf, '--json')
      if ($rr.Exit -eq 0 -and (Test-SamePath (ConvertFrom-EngineJson $rr.Text).db $Db)) { return "& '$Engine' index --project '$pf' --db '$Db'" }
    }
  }
  $null
}

# the COMMAND line (header contract, H2): the question, the target, the project or unit and every
# argument that changes the answer, as GIVEN; never a display switch, never an index override (R5)
function Get-ReportCommandLine([string] $Question, [string] $Target, [hashtable] $Bound) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("COMMAND $Question -Target `"$Target`"")
  if ($Bound.ContainsKey('To') -and $Bound['To'])           { [void]$sb.Append(" -To `"$($Bound['To'])`"") }
  if ($Bound.ContainsKey('Project') -and $Bound['Project']) { [void]$sb.Append(" -Project `"$([IO.Path]::GetFullPath($Bound['Project']))`"") }
  elseif ($Bound.ContainsKey('In') -and $Bound['In'])       { [void]$sb.Append(" -In `"$([IO.Path]::GetFullPath($Bound['In']))`"") }
  foreach ($n in 'Depth', 'Cap', 'SurfaceCap') { if ($Bound.ContainsKey($n)) { [void]$sb.Append(" -$n $($Bound[$n])") } }
  if ($Bound.ContainsKey('Control') -and $Bound['Control']) { [void]$sb.Append(" -Control `"$($Bound['Control'])`"") }
  if ($Bound.ContainsKey('Mode') -and $Bound['Mode'])       { [void]$sb.Append(" -Mode $($Bound['Mode'])") }
  if ($Bound.ContainsKey('MaxRows'))                        { [void]$sb.Append(" -MaxRows $($Bound['MaxRows'])") }
  $sb.ToString()
}
function Get-EngineVersion {
  $rr = Invoke-Engine @('info', '--json')
  $o = $(if ($rr.Exit -eq 0) { ConvertFrom-EngineJson $rr.Text })
  if ($o -and $o.version) { [string]$o.version } else { 'unknown' }
}

$exitCode = 0
try {
  # ---- the engine (R2): a missing one is a setup stop that says where it looked
  try { $Engine = Resolve-DragLintEngine $Engine } catch { Stop-Ask 2 $_.Exception.Message }

  # ---- the default (DocInsight) answer is the engine's: `drag-lint ask` with the same arguments -----------
  if (-not $Plain -and -not $ResolveOnly) {
    $ea = @('ask', $Question, '--target', $Target)
    $flag = [ordered]@{ To = '--to'; Project = '--project'; In = '--in'; DbPath = '--db'; ServerDbPath = '--server-db'; SqlDbPath = '--sql-db'
                         CounterpartDb = '--counterpart-db'; Depth = '--depth'; Cap = '--cap'; SurfaceCap = '--surface-cap'; Control = '--control'
                         Mode = '--mode'; MaxRows = '--max-rows'; OutRoot = '--out-root'; PairsFile = '--pairs-file' }
    foreach ($k in $flag.Keys) { if ($PSBoundParameters.ContainsKey($k) -and "$($PSBoundParameters[$k])" -ne '') { $ea += @($flag[$k], "$($PSBoundParameters[$k])") } }
    if ($AllowStale) { $ea += '--allow-stale' }
    if ($Open)       { $ea += '--open' }
    & $Engine @ea
    exit $LASTEXITCODE
  }

  # ---- the question -------------------------------------------------------------------
  $valid = @((Get-Command $bundler).Parameters['Question'].Attributes |
             Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
             ForEach-Object { $_.ValidValues })
  if ($valid -notcontains $Question) { Stop-Ask 2 "unknown question '$Question' -- one of: $($valid -join ', ')" }
  # R13: from here on the question is the MATCHED ValidateSet id, lower-cased. PS trap: -notcontains above is
  # case-insensitive, so 'Who-Reads' passed it and would otherwise reach the header sentence and COMMAND as typed.
  $Question = @($valid | Where-Object { $_ -eq $Question })[0].ToLowerInvariant()
  $needServer = $Question -in 'round-trip', 'lands-where'
  $needSql    = $Question -in 'round-trip', 'lands-where', 'consumers', 'feeds-from'
  $wantOther  = $Question -eq 'crosses-boundary'

  $pairs = @()
  $pairsFound = Test-Path -LiteralPath $PairsFile
  if ($pairsFound) { $pairs = @((Get-Content -LiteralPath $PairsFile -Raw | ConvertFrom-Json).pairs) }

  # ---- 1. the project index -------------------------------------------------------------
  if (-not $DbPath) {
    if ($Project) {
      if (-not (Test-Path -LiteralPath $Project)) { Stop-Ask 2 "project file not found: $Project" }
      $pj = (Resolve-Path -LiteralPath $Project).ProviderPath
      $rr = Invoke-Engine @('resolve-dbs', '--project', $pj, '--json')
      $o = $(if ($rr.Exit -eq 0) { ConvertFrom-EngineJson $rr.Text } else { $null })
      if (-not $o -or -not $o.db) { Stop-Ask 2 "resolve-dbs --project $pj found no index (exit $($rr.Exit)) -- the project is not in the engine's index manifest" }
      $DbPath = [string]$o.db
    } elseif ($In) {
      if (-not (Test-Path -LiteralPath $In)) { Stop-Ask 2 "file not found: $In" }
      $inFull = (Resolve-Path -LiteralPath $In).ProviderPath
      $rr = Invoke-Engine @('resolve-dbs', '--in', $inFull, '--json')
      $cands = @($(if ($rr.Exit -eq 0) { ConvertFrom-EngineJson $rr.Text }) | Where-Object { $_ })
      if ($cands.Count -eq 0) { Stop-Ask 2 "no index covers $inFull (resolve-dbs --in, exit $($rr.Exit)) -- pass -Project <x.dproj>" }
      if ($cands.Count -eq 1) { $DbPath = [string]$cands[0] }
      else {
        # several projects hold this unit: the one report-pairs.json names is the declared choice
        $paired = @($cands | Where-Object { Find-Pair $_ })
        if ($paired.Count -ne 1) { Stop-Ask 2 "$($cands.Count) indexes cover ${inFull}: $($cands -join ', ') -- pass -Project <x.dproj> to pick one" }
        $DbPath = [string]$paired[0]
      }
    } else {
      Stop-Ask 2 ('name the project: -Project <x.dproj> or -In <any .pas/.dfm of it>. The target alone does not ' +
                  'name a file -- a form instance, class or field maps to a unit only through an index, and ' +
                  'choosing that index is the step being asked for.')
    }
  }

  # ---- 2. the other indexes, from the pairing file ----------------------------------------
  $fromPairs = @()
  if (($needServer -and -not $ServerDbPath) -or ($needSql -and -not $SqlDbPath) -or ($wantOther -and -not $CounterpartDb)) {
    $pair = Find-Pair $DbPath
    if (-not $pair) {
      if ($needServer -or $needSql) {
        $orPass = "or pass $(if ($needServer) { '-ServerDbPath and ' })-SqlDbPath"
        if (-not $pairsFound) {
          Stop-Ask 2 ("$Question also reads $(if ($needServer) { 'the SERVER index and ' })the SQL-script index, and " +
                      "$([IO.Path]::GetFileName($PairsFile)) not found at $PairsFile, so no pairs are configured -- copy " +
                      "charts\report-pairs.example.json to that path and fill in client, server and sql (each checked with resolve-dbs), $orPass")
        }
        Stop-Ask 2 ("$Question also reads $(if ($needServer) { 'the SERVER index and ' })the SQL-script index, and $PairsFile " +
                    "has no entry for $DbPath -- add one (client, server, sql; check each with resolve-dbs), $orPass")
      }
      # crosses-boundary without a counterpart draws one side and says so (the bundler's own behaviour)
    } else {
      if ($needServer -and -not $ServerDbPath) {
        if (-not (Test-SamePath $pair.client $DbPath)) { Stop-Ask 2 "$Question starts from the CLIENT index; $DbPath is the SERVER of pair '$($pair.name)' in $PairsFile -- pass the client project" }
        $ServerDbPath = [string]$pair.server; $fromPairs += $ServerDbPath
      }
      if ($needSql -and -not $SqlDbPath) { $SqlDbPath = [string]$pair.sql; $fromPairs += $SqlDbPath }
      if ($wantOther -and -not $CounterpartDb) {
        $CounterpartDb = [string]$(if (Test-SamePath $pair.client $DbPath) { $pair.server } else { $pair.client }); $fromPairs += $CounterpartDb
      }
    }
  }
  # a pairing-file path must still be one the manifest configures
  if ($fromPairs.Count) {
    $rr = Invoke-Engine @('resolve-dbs', '--json')
    $known = @($(if ($rr.Exit -eq 0) { ConvertFrom-EngineJson $rr.Text }) | Where-Object { $_ })
    foreach ($f in $fromPairs) {
      if (-not @($known | Where-Object { Test-SamePath $_ $f }).Count) { Stop-Ask 2 "$PairsFile names $f, which the engine's manifest no longer configures (resolve-dbs) -- fix the pair" }
    }
  }

  # full paths from here on: messages name the index exactly as the engine and the bundle will
  $DbPath = [IO.Path]::GetFullPath($DbPath)
  if ($ServerDbPath)  { $ServerDbPath  = [IO.Path]::GetFullPath($ServerDbPath) }
  if ($SqlDbPath)     { $SqlDbPath     = [IO.Path]::GetFullPath($SqlDbPath) }
  if ($CounterpartDb) { $CounterpartDb = [IO.Path]::GetFullPath($CounterpartDb) }
  $use = [ordered]@{ PROJECT = $DbPath }
  if ($needServer)                   { $use.SERVER = $ServerDbPath }
  if ($needSql)                      { $use.SQL = $SqlDbPath }
  if ($wantOther -and $CounterpartDb) { $use.COUNTERPART = $CounterpartDb }
  if ($ResolveOnly) {
    foreach ($k in $use.Keys) { Write-Output "$k $($use[$k])" }
  } else {
    # ---- 3. freshness -----------------------------------------------------------------------
    $stale = @()
    foreach ($db in @($use.Values | Select-Object -Unique)) {
      if (-not (Test-Path -LiteralPath $db)) { Stop-Ask 2 "index not found: $db" }
      $rr = Invoke-Engine @('sql', '--db', $db, '--query', 'SELECT 1 AS n', '--format', 'json')
      $o = $(if ($rr.Exit -eq 0) { ConvertFrom-EngineJson $rr.Text } else { $null })
      if (-not $o) { Stop-Ask 1 "the engine could not open $db (exit $($rr.Exit))" }
      if ($null -eq $o.PSObject.Properties['stale']) { [Console]::Error.WriteLine("ask-report: note -- the engine reports no freshness for $db; answering unchecked") }
      elseif ($o.stale) { $stale += [pscustomobject]@{ Db = $db; Files = $o.stale_files } }
    }
    if ($stale.Count) {
      $lines = foreach ($s in $stale) {
        $cmd = Get-ReindexCommand $s.Db
        "  $($s.Db): $($s.Files) file(s) changed since it was indexed"
        $(if ($cmd) { "    $cmd" } else { "    no reindex command can be derived for it (not a <project>\_D-RAG\<name>.sqlite the manifest resolves; a clone under charts\scratch\db is re-taken, not reindexed)" })
      }
      if ($AllowStale) { [Console]::Error.WriteLine("ask-report: note -- stale index allowed by -AllowStale: " + (($stale | ForEach-Object { "$($_.Db): $($_.Files) file(s)" }) -join '; ')) }
      else { Stop-Ask 3 ("stale index -- the answer would be short or wrong. Reindex incrementally, then ask again:`n" + ($lines -join "`n")) }
    }

    # ---- 4. the bundle ----------------------------------------------------------------------
    $nda = @{ Question = $Question; Target = $Target; DbPath = $DbPath; OutRoot = $OutRoot }
    if ($needServer)                    { $nda.ServerDbPath  = $ServerDbPath }
    if ($needSql)                       { $nda.SqlDbPath     = $SqlDbPath }
    if ($wantOther -and $CounterpartDb) { $nda.CounterpartDb = $CounterpartDb }
    foreach ($n in 'Depth', 'Cap', 'SurfaceCap', 'Control', 'Mode', 'To') { if ($PSBoundParameters.ContainsKey($n)) { $nda[$n] = $PSBoundParameters[$n] } }
    if ($Open) { $nda.Open = $true }
    $prevLive = [Environment]::GetEnvironmentVariable('DRAGLINT_CHARTS_ALLOW_LIVE_DB', 'Process')
    # the chart is drawn by the engine resolved above (fix round 1): the emitters resolve DRAGLINT_ENGINE first
    $prevEng  = [Environment]::GetEnvironmentVariable('DRAGLINT_ENGINE', 'Process')
    try {
      $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB = '1'
      $env:DRAGLINT_ENGINE = $Engine
      $art = & $bundler @nda 6>$null
    } finally {
      # restore exactly: absent stays absent (SetEnvironmentVariable($null) from PowerShell passes '' and leaves it set)
      if ($null -eq $prevLive) { Remove-Item Env:\DRAGLINT_CHARTS_ALLOW_LIVE_DB -ErrorAction SilentlyContinue } else { $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB = $prevLive }
      if ($null -eq $prevEng)  { Remove-Item Env:\DRAGLINT_ENGINE -ErrorAction SilentlyContinue } else { $env:DRAGLINT_ENGINE = $prevEng }
    }

    # ---- 5. the text to read ----------------------------------------------------------------
    # the header (contract section 3): the sentence with time + engine, then the COMMAND that reruns it
    $sentTarget = $(if ($To) { "$Target -> $To" } else { $Target })
    $phrase = $(if ($script:ReportCaptions.Contains($Question)) { $script:ReportCaptions[$Question].TrimEnd('.') } else { 'Report' })
    $answer.Add(('{0} (drag-lint report {1}) for {2}, asked on {3}, engine {4}.' -f $phrase, $Question, $sentTarget, (Get-Date).ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture), (Get-EngineVersion)))
    $bound = @{}; foreach ($k in $PSBoundParameters.Keys) { $bound[$k] = $PSBoundParameters[$k] }   # a dictionary, not a hashtable
    $answer.Add((Get-ReportCommandLine $Question $Target $bound))
    $answer.Add("BUNDLE $($art.Bundle)")
    # which index(es) answered (fix round 1, M-1): the project index, then any other the question read
    $answer.Add("INDEX $DbPath")
    if ($needServer)                    { $answer.Add("INDEX $ServerDbPath (server)") }
    if ($needSql)                       { $answer.Add("INDEX $SqlDbPath (sql)") }
    if ($wantOther -and $CounterpartDb) { $answer.Add("INDEX $CounterpartDb (counterpart)") }
    $tracePath = Join-Path $art.Bundle 'trace.dlgraph'
    $dotPath   = Join-Path $art.Bundle 'graph.dot'
    if (Test-Path -LiteralPath $tracePath) {
      foreach ($tl in ([IO.File]::ReadAllText($tracePath).TrimEnd("`r", "`n") -split "`r`n")) { $answer.Add($tl) }
      # owner answer 3 (R5): the text is delivered even when dot failed, with a line saying the chart is missing
      $meta = Get-Content -LiteralPath (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
      if ($meta.emitter.PSObject.Properties['ChartError'] -and $meta.emitter.ChartError) { $answer.Add("NOTE the chart could not be drawn: $($meta.emitter.ChartError)") }
    } else {
      $meta = Get-Content -LiteralPath (Join-Path $art.Bundle 'meta.json') -Raw | ConvertFrom-Json
      $answer.Add("CHART $Question $Target$(if ($To) { " -> $To" }) -- $($meta.leftCount) $($meta.leftLabel) / $($meta.rightCount) $($meta.rightLabel)")
      $rows = New-Object System.Collections.Generic.List[string]
      $targets = New-Object System.Collections.Generic.List[string]
      $notShown = New-Object System.Collections.Generic.List[string]
      $inFocus = $false
      foreach ($dl in $(if (Test-Path -LiteralPath $dotPath) { [IO.File]::ReadAllLines($dotPath) } else { @() })) {
        # the chart's own selection lives in `subgraph cluster_focus...`: it is the TARGET, not a result (M-2)
        if ($dl -match '^\s*subgraph cluster_focus') { $inFocus = $true }
        elseif ($dl -match '^\s*\}\s*$') { $inFocus = $false }
        # an UNANCHORED cell that says what the chart left out: the cap disclosure above all (I-2).
        # A reader told "24 routines" and shown 20 rows must be told the other 4 exist.
        foreach ($m in [regex]::Matches($dl, '<TD(?![^>]*HREF=)[^>]*>(.*?)</TD>')) {
          $txt = ([Net.WebUtility]::HtmlDecode(($m.Groups[1].Value -replace '<[^>]+>', '')).Trim()) -replace '[^\x20-\x7E]', ' '
          if ($txt -notmatch 'not shown') { continue }
          if ($txt -match '^\+\d+ more') {
            $cm = [regex]::Match("$($meta.regenerate)", ' -(SurfaceCap|Cap) (\d+)')
            $capHow = $(if ($cm.Success) { " (-$($cm.Groups[1].Value) $($cm.Groups[2].Value); raise -$($cm.Groups[1].Value) to see them)" } else { ' (raise -Cap to see them)' })
            $txt += $capHow
          }
          if (-not $notShown.Contains($txt)) { $notShown.Add($txt) }
        }
        # one anchored row per <TD HREF=draglint://..>: the qualified name when the tooltip is
        # "<qname> -- <file>:<line>" (or a bare qname), else the row's label plus the tooltip as a note
        foreach ($m in [regex]::Matches($dl, '<TD[^>]*?HREF="draglint://open\?file=([^"&]*)&amp;line=(\d+)"[^>]*?TITLE="([^"]*)"[^>]*>(.*?)</TD>')) {
          $tip   = [Net.WebUtility]::HtmlDecode($m.Groups[3].Value).Trim()
          $label = [Net.WebUtility]::HtmlDecode(([regex]::Match($m.Groups[4].Value, '<FONT[^>]*>(.*?)</FONT>').Groups[1].Value -replace '<[^>]+>', '')).Trim()
          $note  = ''
          if ($tip -match '\s--\s') { $name = ($tip -split '\s+--\s+', 2)[0].Trim() }
          elseif ($tip -and $tip -notmatch '\s') { $name = $tip }
          else { $name = $label; $note = $tip }
          $leaf = [IO.Path]::GetFileName([uri]::UnescapeDataString($m.Groups[1].Value))
          $row  = $(if ([int]$m.Groups[2].Value -gt 0) { "$name @${leaf}:$($m.Groups[2].Value)" } else { "$name @$leaf" })
          if ($note) { $row += " -- $note" }
          $row = $row -replace '[^\x20-\x7E]', ' '
          if ($inFocus) { if (-not $targets.Contains($row)) { $targets.Add($row) } }
          elseif (-not $rows.Contains($row)) { $rows.Add($row) }
        }
      }
      foreach ($row in $targets) { $answer.Add("  TARGET $row") }
      if ($rows.Count -eq 0) { $answer.Add("  (no anchored result rows -- open $($art.Shell))") }
      foreach ($row in ($rows | Select-Object -First $MaxRows)) { $answer.Add("  $row") }
      foreach ($txt in $notShown) { $answer.Add("  ... $txt") }
      if ($rows.Count -gt $MaxRows) { $answer.Add("  ... $($rows.Count - $MaxRows) more row(s) not printed here (-MaxRows $MaxRows): $dotPath") }
    }
    # ---- 6. the answer (plain: the default mode was delegated to `drag-lint ask` above) -------------------
    foreach ($a in $answer) { Write-Output $a }
  }
} catch {
  $exitCode = $(if ($_.Exception.Data.Contains('AskExit')) { [int]$_.Exception.Data['AskExit'] } else { 1 })
  [Console]::Error.WriteLine("ask-report: $($_.Exception.Message)")
}
exit $exitCode
