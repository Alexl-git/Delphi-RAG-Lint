<#
  Emit-Common.ps1 -- shared helpers, DOT-SOURCED by the emitters. Functions only,
  no top-level side effects: dot-sourcing this must never write a file, call the
  engine, or print.

  Dot-sourcing puts these functions in the CALLER's scope, so they resolve
  $Engine, $Dot and $DbPath dynamically from the emitter's own param block.
  That is deliberate -- it keeps the call sites short -- but it means an emitter
  MUST declare all three parameters with those exact names.

  Two traps are baked in here rather than left to each emitter:

  1. `--format json` splices a human staleness note INTO the JSON stream, and
     with 2>&1 it lands inside the document and breaks ConvertFrom-Json. Every
     engine call is routed through Get-EngineText, which drops ErrorRecords and
     `drag-lint:` lines before anything tries to parse.

  2. The engine emits BOTH shapes: reverse-calltree returns an OBJECT `{...}`
     and `query find-callers --json` returns a bare ARRAY `[...]`. Trimming to
     the first `{` (as an earlier draft did) silently corrupts the array into an
     object followed by garbage. Get-EngineText brackets on whichever of `{` or
     `[` comes FIRST and pairs it with the matching closer.
#>

# NOTE: deliberately NO Set-StrictMode here. Dot-sourcing runs in the CALLER's
# scope, so setting it would silently change the strictness of every emitter --
# exactly the top-level side effect this file is supposed to be free of.

# ---- text -------------------------------------------------------------------

function ConvertTo-XmlText([string] $s) {
  if ($null -eq $s) { return '' }
  $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function Get-UnitName([string] $file) {
  if ([string]::IsNullOrWhiteSpace($file)) { return '(unknown)' }
  [IO.Path]::GetFileNameWithoutExtension($file)
}

function Get-ShortName([string] $qname, [string] $unit) {
  if ([string]::IsNullOrWhiteSpace($qname)) { return '' }
  if ($unit -and $qname.StartsWith("$unit.", [StringComparison]::OrdinalIgnoreCase)) {
    return $qname.Substring($unit.Length + 1)
  }
  $qname
}

function New-RowHref([string] $File, [int] $Line) {
  'draglint://open?file=' + [uri]::EscapeDataString($File) + '&amp;line=' + $Line
}

# ---- engine -----------------------------------------------------------------

# Runs the engine and returns ONLY the JSON document, or '' when there is none.
# Records the exit code in $script:LastEngineExit for the caller's message.
function Get-EngineText([string[]] $ArgList) {
  $raw = & $Engine @ArgList 2>&1 |
         Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
         Where-Object {
           $s = [string]$_
           $s -notmatch '^\(?loaded defaults' -and
           $s -notmatch '^drag-lint:'         -and
           $s -notmatch '^\s+may be stale'    -and
           $s -notmatch '^\s+drag-lint index '
         }
  $script:LastEngineExit = $LASTEXITCODE
  $txt = ($raw -join "`n")
  if ([string]::IsNullOrWhiteSpace($txt)) { return '' }

  # bracket on whichever opener comes first -- see header note 2
  $bo = $txt.IndexOf('{')
  $ba = $txt.IndexOf('[')
  if ($bo -lt 0 -and $ba -lt 0) { return '' }
  if ($bo -lt 0) { $open = $ba } elseif ($ba -lt 0) { $open = $bo } else { $open = [Math]::Min($bo, $ba) }
  $close = if ($txt[$open] -eq '[') { $txt.LastIndexOf(']') } else { $txt.LastIndexOf('}') }
  if ($close -le $open) { return '' }
  $txt.Substring($open, $close - $open + 1)
}

function Invoke-EngineJson([string[]] $ArgList) {
  $txt = Get-EngineText $ArgList
  if ([string]::IsNullOrWhiteSpace($txt)) {
    throw "engine returned nothing for $($ArgList -join ' ') (exit $script:LastEngineExit)"
  }
  $txt | ConvertFrom-Json
}

# schema sql/1 returns `columns` (name/type) and `rows` as POSITIONAL ARRAYS --
# zip them so callers can use property names. Hard row cap 200; the caller is
# expected to assert .Truncated where the plan says to.
function Invoke-IndexQuery([string] $sql) {
  $txt = Get-EngineText @('sql', '--db', $DbPath, '--query', $sql, '--format', 'json')
  if ([string]::IsNullOrWhiteSpace($txt)) { return , @() }
  try { $o = $txt | ConvertFrom-Json } catch { throw "index query returned non-JSON: $txt" }
  $script:LastQueryTruncated = [bool]$o.truncated
  if ($o.truncated) { Write-Host "  NOTE: result truncated at row_cap $($o.row_cap)" }
  $names = @($o.columns | ForEach-Object { $_.name })
  $out = New-Object System.Collections.ArrayList
  foreach ($row in @($o.rows)) {
    $vals = @($row)
    $h = [ordered]@{}
    for ($i = 0; $i -lt $names.Count; $i++) {
      $h[$names[$i]] = $(if ($i -lt $vals.Count) { $vals[$i] } else { $null })
    }
    [void]$out.Add([pscustomobject]$h)
  }
  , $out.ToArray()
}

function ConvertTo-SqlText([string] $s) { $s.Replace("'", "''") }

# Callers want the BODY, so prefer impl_start_line over the interface decl line.
function Get-SymbolLocation([string] $Qname) {
  $q = ConvertTo-SqlText $Qname
  $rows = @(Invoke-IndexQuery @"
SELECT s.id AS id, s.kind AS kind, s.start_line AS start_line,
       s.impl_start_line AS impl_start_line, s.impl_end_line AS impl_end_line,
       f.path AS path
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.qualified_name = '$q'
"@)
  if ($rows.Count -eq 0) { throw "$Qname is not in this index" }
  if ($rows.Count -gt 1) {
    Write-Host "  NOTE: $Qname resolves to $($rows.Count) symbols; using the first (id $($rows[0].id))"
  }
  $r = $rows[0]
  $focus = if ($r.impl_start_line) { [int]$r.impl_start_line } else { [int]$r.start_line }
  [pscustomobject]@{
    Id = [int]$r.id; Kind = [string]$r.kind; Path = [string]$r.path
    DeclLine = [int]$r.start_line
    ImplStart = $(if ($r.impl_start_line) { [int]$r.impl_start_line } else { 0 })
    ImplEnd   = $(if ($r.impl_end_line)   { [int]$r.impl_end_line }   else { 0 })
    FocusLine = $focus
  }
}

# ---- dot --------------------------------------------------------------------

# ONE layout run, four outputs -- so the geometry in .plain can never drift from
# the picture in .svg. Verified 2026-09-22.
function Invoke-DotLayout([string] $DotText, [string] $OutDir, [string] $Base) {
  New-Item -ItemType Directory -Force $OutDir | Out-Null
  $dotO = Join-Path $OutDir "$Base.dot"
  $svgO = Join-Path $OutDir "$Base.svg"
  $plnO = Join-Path $OutDir "$Base.plain"
  $pngO = Join-Path $OutDir "$Base.png"
  $pdfO = Join-Path $OutDir "$Base.pdf"
  foreach ($f in @($svgO, $plnO, $pngO, $pdfO)) { if (Test-Path $f) { Remove-Item $f -Force } }

  [IO.File]::WriteAllText($dotO, ($DotText -replace "`r`n", "`n" -replace "`n", "`r`n"),
                          (New-Object Text.UTF8Encoding($false)))

  & $Dot -Tsvg -o $svgO -Tplain -o $plnO -Tpng -Gdpi=110 -o $pngO -Tpdf -o $pdfO $dotO 2>&1 |
    Where-Object { $_ -notmatch 'Pango-WARNING' -and ([string]$_).Trim() -ne '' } |
    ForEach-Object { Write-Host "  dot: $_" }

  if (-not (Test-Path $svgO)) { throw 'dot produced no SVG' }
  $svg = [IO.File]::ReadAllText($svgO)

  [pscustomobject]@{
    Dot = $dotO; Svg = $svgO; Plain = $plnO; Png = $pngO; Pdf = $pdfO
    Anchors = ([regex]::Matches($svg, '<a[\s>]')).Count
  }
}

# Shared rounded-cluster builder. The cluster carries NO label -- Graphviz draws
# a cluster label inside the border and the rounded corner cuts through it; the
# title is a header ROW of the table instead.
#
# $Rows: objects with Label, Line, Href, Tip and optional Note (dimmed suffix).
# Returns the port id assigned to each row, IN ORDER, so callers can key the
# port map by ORDINAL. Keying by name is wrong: one method legitimately appears
# at two different call sites.
#
# -Title/-Subtitle/-Note take PLAIN TEXT and are escaped here. The middot
# separators are emitted OUTSIDE the escape on purpose: passing "a &#183; b" as
# a title would escape the ampersand and render the literal text "&#183;".
# -Style allows "rounded,filled,dashed" for a cluster whose rows are NOT facts
# of the same grade as the solid ones.
function Add-RowCluster {
  param(
    [System.Text.StringBuilder] $Sb, [string] $Cid, [string] $Nid,
    [string] $Title, [string] $Subtitle,
    $Rows, [string] $Border, [string] $Fill, [string] $Hdr,
    [string] $RowInk = '#1F2933', [string] $LineInk = '#8A94A6',
    [string] $FontSans = 'Segoe UI', [string] $Style = 'rounded,filled',
    [int] $PenWidth = 2
  )
  [void]$Sb.AppendLine("  subgraph $Cid {")
  [void]$Sb.AppendLine("    style=`"$Style`"; color=`"$Border`"; fillcolor=`"$Fill`"; penwidth=$PenWidth;")
  [void]$Sb.AppendLine('    label=""; margin=10;')

  $hdrText = ConvertTo-XmlText $Title
  if ($Subtitle) { $hdrText += ' &#183; ' + (ConvertTo-XmlText $Subtitle) }

  $tbl = New-Object System.Text.StringBuilder
  [void]$tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">')
  [void]$tbl.Append("<TR><TD ALIGN=`"LEFT`" BGCOLOR=`"$Hdr`"><FONT COLOR=`"#FFFFFF`" FACE=`"$FontSans`" POINT-SIZE=`"14`"><B> $hdrText </B></FONT></TD></TR>")

  $ports = New-Object System.Collections.ArrayList
  $p = 0
  foreach ($r in $Rows) {
    $p++
    [void]$tbl.Append("<TR><TD PORT=`"p$p`" ALIGN=`"LEFT`" HREF=`"$($r.Href)`" TITLE=`"$(ConvertTo-XmlText $r.Tip)`">")
    [void]$tbl.Append("<FONT COLOR=`"$RowInk`">$(ConvertTo-XmlText $r.Label)</FONT>")
    [void]$tbl.Append("  <FONT COLOR=`"$LineInk`" POINT-SIZE=`"12`">:$($r.Line)</FONT>")
    $note = $null
    if ($r.PSObject.Properties.Name -contains 'Note') { $note = [string]$r.Note }
    if ($note) {
      [void]$tbl.Append("  <FONT COLOR=`"$LineInk`" POINT-SIZE=`"11`">&#183; $(ConvertTo-XmlText $note)</FONT>")
    }
    [void]$tbl.Append('</TD></TR>')
    [void]$ports.Add("${Nid}:p$p")
  }
  [void]$tbl.Append('</TABLE>')
  [void]$Sb.AppendLine("    $Nid [label=<$($tbl.ToString())>];")
  [void]$Sb.AppendLine('  }')
  , $ports.ToArray()
}
