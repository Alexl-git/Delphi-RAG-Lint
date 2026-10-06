<#
  Ask-Report.ps1 -- ONE command that asks a report question and prints the answer as text.

  Written for AI agents (and anyone else in a hurry). New-DiagramArtifact.ps1 needs up to
  three database paths and an environment variable; an agent that had the report verbs
  described to it still did not run one, because standing that up was the whole job. This
  wrapper does the standing-up and nothing else:

    1. the PROJECT index comes from the engine's own `resolve-dbs` (`--project` on -Project,
       else `--in` on -In) -- never a guessed path. When --in names several indexes, the one
       charts\report-pairs.json pairs is taken; otherwise it stops and asks for -Project.
    2. the SERVER and SQL indexes, for the questions that read them, come from
       charts\report-pairs.json (client index -> server index, SQL index); a missing pair is a
       clear stop that names the file to edit, never a one-sided chart.
    3. freshness: every index it will read is checked with the engine's `sql` envelope
       (`stale` / `stale_files`); a stale one stops the run and prints the exact incremental
       reindex command. It never runs `index` itself.
    4. DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 is set for the bundler call only, and restored after.
    5. the bundle goes under $env:TEMP\drag-lint-reports unless -OutRoot says otherwise.
    6. stdout is the answer, by DEFAULT as a DocInsight block -- `/// <remarks>` ... `/// </remarks>`,
       the same bytes the IDE's drag-lint > Reports menu puts on the clipboard (owner answer 2,
       R5; the formatter is Report.DocInsight.ps1, a port of the plugin's FormatReportAsDocInsight,
       checked against the plugin's own output by Test-AskReport AR-DOC-*). -Plain gives the plain
       answer instead: `BUNDLE <folder>`, one `INDEX <db>[ (server|sql|counterpart)]` line per
       index read, then the TEXT to read -- the whole trace.dlgraph for round-trip (plus a `NOTE the
       chart could not be drawn: <why>` line when dot failed), else a `CHART`
       header (the counts), `TARGET <name> @File.pas:line` for the chart's own selection, one
       `<name> @File.pas:line` line per anchored result row, and `... +N more ... not shown (-Cap N;
       raise -Cap to see them)` for every row the chart itself left out -- a count in the header
       is never silently larger than the rows printed. The DocInsight block is made FROM that plain
       answer (BUNDLE / INDEX / REGENERATE dropped, anchors as (File.pas:line)). Nothing else is
       printed on stdout. The IDE plugin formats the answer itself, so it must ask with -Plain.

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
  [switch] $Open,
  # overrides: an explicit index skips resolution for that index (never its freshness check)
  [string] $DbPath,
  [string] $ServerDbPath,
  [string] $SqlDbPath,
  [string] $CounterpartDb,
  [switch] $ResolveOnly,
  # the plain answer (the BUNDLE / INDEX lines and the text) instead of the default DocInsight block
  [switch] $Plain,
  [int]    $MaxRows = 80,
  [string] $PairsFile = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\report-pairs.json')),
  # '' = found by Resolve-DragLintEngine (Emit-Common.ps1): DRAGLINT_ENGINE, settings.json, the installed or shared engine
  [string] $Engine    = ''
)

$ErrorActionPreference = 'Stop'
$bundler = Join-Path $PSScriptRoot 'New-DiagramArtifact.ps1'
. (Join-Path $PSScriptRoot 'Emit-Common.ps1')   # functions only; Resolve-DragLintEngine
. (Join-Path $PSScriptRoot 'Report.DocInsight.ps1')
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

$exitCode = 0
try {
  # ---- the engine (R2): a missing one is a setup stop that says where it looked
  try { $Engine = Resolve-DragLintEngine $Engine } catch { Stop-Ask 2 $_.Exception.Message }

  # ---- the question -------------------------------------------------------------------
  $valid = @((Get-Command $bundler).Parameters['Question'].Attributes |
             Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
             ForEach-Object { $_.ValidValues })
  if ($valid -notcontains $Question) { Stop-Ask 2 "unknown question '$Question' -- one of: $($valid -join ', ')" }
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
      Stop-Ask 3 ("stale index -- the answer would be short or wrong. Reindex incrementally, then ask again:`n" + ($lines -join "`n"))
    }

    # ---- 4. the bundle ----------------------------------------------------------------------
    $nda = @{ Question = $Question; Target = $Target; DbPath = $DbPath; OutRoot = $OutRoot }
    if ($needServer)                    { $nda.ServerDbPath  = $ServerDbPath }
    if ($needSql)                       { $nda.SqlDbPath     = $SqlDbPath }
    if ($wantOther -and $CounterpartDb) { $nda.CounterpartDb = $CounterpartDb }
    foreach ($n in 'Depth', 'Cap', 'SurfaceCap', 'Control', 'Mode') { if ($PSBoundParameters.ContainsKey($n)) { $nda[$n] = $PSBoundParameters[$n] } }
    if ($Open) { $nda.Open = $true }
    $prevLive = [Environment]::GetEnvironmentVariable('DRAGLINT_CHARTS_ALLOW_LIVE_DB', 'Process')
    try {
      $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB = '1'
      $art = & $bundler @nda 6>$null
    } finally {
      # restore exactly: absent stays absent (SetEnvironmentVariable($null) from PowerShell passes '' and leaves it set)
      if ($null -eq $prevLive) { Remove-Item Env:\DRAGLINT_CHARTS_ALLOW_LIVE_DB -ErrorAction SilentlyContinue } else { $env:DRAGLINT_CHARTS_ALLOW_LIVE_DB = $prevLive }
    }

    # ---- 5. the text to read ----------------------------------------------------------------
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
      $answer.Add("CHART $Question $Target -- $($meta.leftCount) $($meta.leftLabel) / $($meta.rightCount) $($meta.rightLabel)")
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
    # ---- 6. the answer: plain, or (the default) the DocInsight block the IDE's Reports menu makes of it --------
    if ($Plain) { foreach ($a in $answer) { Write-Output $a } }
    else {
      $doc = Format-ReportAsDocInsight $Question $Target (Get-Date) ($answer -join "`r`n")
      foreach ($a in ($doc.TrimEnd("`r", "`n") -split "`r`n")) { Write-Output $a }
    }
  }
} catch {
  $exitCode = $(if ($_.Exception.Data.Contains('AskExit')) { [int]$_.Exception.Data['AskExit'] } else { 1 })
  [Console]::Error.WriteLine("ask-report: $($_.Exception.Message)")
}
exit $exitCode
