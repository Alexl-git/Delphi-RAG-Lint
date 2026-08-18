<#
.SYNOPSIS
  Builds docs\drag-lint-manual.docx and .pdf from the wiki pages.

.DESCRIPTION
  Session 27, item 7. The wiki is 127 pages of reference material with no
  offline, printable, or shareable form. This assembles it into one ordered
  manual.

  WHY THIS SHAPE. Nothing on this machine converts markdown to PDF: pandoc,
  pdflatex, xelatex, tectonic, wkhtmltopdf and LibreOffice are all absent
  (re-verified 2026-08-17). Word 16.0 IS available over COM. So the route is

      wiki markdown -> HTML -> Word COM opens it -> SaveAs .docx -> export .pdf

  The markdown converter here is deliberately NARROW. It is not a general
  CommonMark implementation and must not grow into one: it handles exactly the
  subset this wiki uses -- ATX headings, GFM pipe tables, fenced code, ordered
  and unordered lists, links, bold, italic, inline code, rules and blockquotes.
  We control the input, so the converter can be small and predictable rather
  than large and approximately right.

  ORDER. The manual is ordered as a manual -- getting started, then the IDE, then
  the CLI, then reference -- not as the wiki's flat alphabetical page set.
  Grouping comes from docs\wiki-featuremap.tsv's Surface column, which is derived
  from the product, so a new feature lands in the right part without editing this
  script.

  STALENESS. This output goes out of date the moment a wiki page changes, and
  nobody will remember to regenerate it. tests\autotest\run_manual_freshness_guard.ps1
  fails the battery when the .docx is older than the newest docs\wiki\*.md.

.PARAMETER Repo
  Repository root. Defaults to the parent of this script's directory.

.PARAMETER SkipPdf
  Produce only the .docx. Useful when Word's PDF export is unavailable.
#>
[CmdletBinding()]
param(
  [string]$Repo = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [switch]$SkipPdf
)

$ErrorActionPreference = 'Stop'
$Repo    = (Resolve-Path $Repo).Path
$WikiDir = Join-Path $Repo 'docs\wiki'
$OutDir  = Join-Path $Repo 'docs'
$DocxOut = Join-Path $OutDir 'drag-lint-manual.docx'
$PdfOut  = Join-Path $OutDir 'drag-lint-manual.pdf'

if (-not (Test-Path -LiteralPath $WikiDir)) { throw "wiki directory not found: $WikiDir" }

# ---------------------------------------------------------------------------
# Markdown -> HTML (the narrow subset described above)
# ---------------------------------------------------------------------------

$script:PageAnchors = @{}   # page base name -> anchor id

function Get-Anchor([string]$PageName) {
  return 'pg-' + ($PageName -replace '[^A-Za-z0-9]', '-').ToLowerInvariant()
}

function ConvertTo-HtmlText([string]$Text) {
  # Escape first, then re-introduce the inline markup we support. Doing it the
  # other way round would let page content inject markup into the manual.
  $s = $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')

  # Inline code before anything else -- its contents must not be re-processed.
  $codes = New-Object System.Collections.Generic.List[string]
  $s = [regex]::Replace($s, '`([^`]+)`', {
      param($m)
      $codes.Add($m.Groups[1].Value)
      return [char]0x1 + ($codes.Count - 1).ToString() + [char]0x2
    })

  # Links. A bare page name (no scheme, no slash) is an internal wiki link and
  # becomes an anchor into this same document.
  $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)]+)\)', {
      param($m)
      $label = $m.Groups[1].Value
      $href  = $m.Groups[2].Value
      if ($href -match '^(https?:|mailto:)') { return "<a href=""$href"">$label</a>" }
      $key = ($href -split '[#/]')[0]
      if ($script:PageAnchors.ContainsKey($key)) { return "<a href=""#$($script:PageAnchors[$key])"">$label</a>" }
      return $label   # a link to a page not in the manual: keep the words, drop the link
    })

  $s = [regex]::Replace($s, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
  $s = [regex]::Replace($s, '(?<![\*\w])\*([^*\r\n]+)\*(?!\*)', '<em>$1</em>')

  # restore inline code
  $s = [regex]::Replace($s, [char]0x1 + '(\d+)' + [char]0x2, {
      param($m)
      $c = $codes[[int]$m.Groups[1].Value]
      return "<code>$c</code>"
    })
  return $s
}

function ConvertFrom-Markdown([string]$Md, [string]$PageName) {
  $sb    = New-Object System.Text.StringBuilder
  $lines = $Md -split "`r?`n"
  $i     = 0
  $inCode = $false
  $listStack = New-Object System.Collections.Generic.List[string]

  function CloseLists([System.Text.StringBuilder]$b, $stack) {
    while ($stack.Count -gt 0) {
      [void]$b.AppendLine("</$($stack[$stack.Count-1])>")
      $stack.RemoveAt($stack.Count - 1)
    }
  }

  while ($i -lt $lines.Count) {
    $line = $lines[$i]

    # fenced code
    if ($line -match '^\s*```') {
      CloseLists $sb $listStack
      $i++
      [void]$sb.AppendLine('<pre><code>')
      while ($i -lt $lines.Count -and $lines[$i] -notmatch '^\s*```') {
        [void]$sb.AppendLine($lines[$i].Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;'))
        $i++
      }
      [void]$sb.AppendLine('</code></pre>')
      $i++
      continue
    }

    # GFM pipe table: a header row followed by a separator row
    if ($line -match '^\s*\|' -and ($i + 1) -lt $lines.Count -and $lines[$i+1] -match '^\s*\|[\s\-:|]+\|\s*$') {
      CloseLists $sb $listStack
      $headers = @($line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
      [void]$sb.AppendLine('<table><thead><tr>')
      foreach ($h in $headers) { [void]$sb.AppendLine("<th>$(ConvertTo-HtmlText $h)</th>") }
      [void]$sb.AppendLine('</tr></thead><tbody>')
      $i += 2
      while ($i -lt $lines.Count -and $lines[$i] -match '^\s*\|') {
        $cells = @($lines[$i].Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        [void]$sb.AppendLine('<tr>')
        foreach ($c in $cells) { [void]$sb.AppendLine("<td>$(ConvertTo-HtmlText $c)</td>") }
        [void]$sb.AppendLine('</tr>')
        $i++
      }
      [void]$sb.AppendLine('</tbody></table>')
      continue
    }

    # headings. The page's own H1 carries the anchor for cross-page links.
    if ($line -match '^(#{1,6})\s+(.*)$') {
      CloseLists $sb $listStack
      $level = $Matches[1].Length
      $text  = ConvertTo-HtmlText $Matches[2].Trim()
      # Demote by one: the manual's H1 is the PART title, so a page title is H2.
      $hl = [Math]::Min($level + 1, 6)
      if ($level -eq 1 -and $script:PageAnchors.ContainsKey($PageName)) {
        [void]$sb.AppendLine("<h$hl id=""$($script:PageAnchors[$PageName])"">$text</h$hl>")
      } else {
        [void]$sb.AppendLine("<h$hl>$text</h$hl>")
      }
      $i++
      continue
    }

    if ($line -match '^\s*(---+|\*\*\*+)\s*$') {
      CloseLists $sb $listStack
      [void]$sb.AppendLine('<hr/>')
      $i++
      continue
    }

    if ($line -match '^\s*>\s?(.*)$') {
      CloseLists $sb $listStack
      [void]$sb.AppendLine("<blockquote>$(ConvertTo-HtmlText $Matches[1])</blockquote>")
      $i++
      continue
    }

    # lists
    if ($line -match '^(\s*)([-*+]|\d+\.)\s+(.*)$') {
      $marker = $Matches[2]
      $tag    = if ($marker -match '^\d') { 'ol' } else { 'ul' }
      if ($listStack.Count -eq 0 -or $listStack[$listStack.Count-1] -ne $tag) {
        CloseLists $sb $listStack
        [void]$sb.AppendLine("<$tag>")
        $listStack.Add($tag)
      }
      [void]$sb.AppendLine("<li>$(ConvertTo-HtmlText $Matches[3])</li>")
      $i++
      continue
    }

    if ([string]::IsNullOrWhiteSpace($line)) {
      CloseLists $sb $listStack
      $i++
      continue
    }

    # paragraph: absorb following non-blank, non-structural lines
    CloseLists $sb $listStack
    $para = @($line)
    $i++
    while ($i -lt $lines.Count -and
           -not [string]::IsNullOrWhiteSpace($lines[$i]) -and
           $lines[$i] -notmatch '^(#{1,6}\s|\s*```|\s*\||\s*([-*+]|\d+\.)\s|\s*>|\s*(---+|\*\*\*+)\s*$)') {
      $para += $lines[$i]
      $i++
    }
    [void]$sb.AppendLine("<p>$(ConvertTo-HtmlText ($para -join ' '))</p>")
  }
  CloseLists $sb $listStack
  return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Chapter order
# ---------------------------------------------------------------------------

# Explicit front matter: the pages a reader needs in this order, before any
# per-feature reference material.
$Front = @('Home', 'Installation', 'Maintenance', 'Features')
$IdeIntro = @('IDE-Menu-Reference', 'About-and-Status')
$Back  = @('Rules', 'LSP', 'Feature-Index')

# Everything else is grouped by the feature map's Surface column, which is
# derived from the product rather than maintained by hand here.
$surfaceOf = @{}
$fmPath = Join-Path $Repo 'docs\wiki-featuremap.tsv'
if (Test-Path -LiteralPath $fmPath) {
  $rows = Get-Content -LiteralPath $fmPath | Select-Object -Skip 1
  foreach ($r in $rows) {
    $c = @($r -split "`t" | ForEach-Object { $_.Trim('"') })
    if ($c.Count -ge 7 -and $c[6]) { $surfaceOf[$c[6]] = $c[1] }
  }
}

$allPages = @(Get-ChildItem -LiteralPath $WikiDir -Filter *.md -File | Select-Object -ExpandProperty BaseName)
$named    = @($Front + $IdeIntro + $Back)
$rest     = @($allPages | Where-Object { $named -notcontains $_ } | Sort-Object)

$idePages = @($rest | Where-Object { $s = $surfaceOf[$_]; $s -and $s -match 'IDE' })
$cliPages = @($rest | Where-Object { $s = $surfaceOf[$_]; $s -and $s -notmatch 'IDE' })
$other    = @($rest | Where-Object { -not $surfaceOf.ContainsKey($_) })

$parts = @(
  @{ Title = 'Part I -- Getting started';        Pages = @($Front | Where-Object { $allPages -contains $_ }) },
  @{ Title = 'Part II -- The RAD Studio plugin'; Pages = @(@($IdeIntro | Where-Object { $allPages -contains $_ }) + $idePages) },
  @{ Title = 'Part III -- The command line';     Pages = $cliPages },
  @{ Title = 'Part IV -- Reference';             Pages = @(@($Back | Where-Object { $allPages -contains $_ }) + $other) }
)

# Anchors must exist before any page is converted, so cross-page links resolve
# regardless of the order pages are processed in.
foreach ($p in $allPages) { $script:PageAnchors[$p] = Get-Anchor $p }

# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------

$version = 'unknown'
$verPas = Join-Path $Repo 'src\cli\DRagLint.CLI.pas'
foreach ($cand in @($verPas, (Join-Path $Repo 'src\core\DRagLint.Core.Model.pas'))) {
  if (Test-Path -LiteralPath $cand) {
    $m = [regex]::Match((Get-Content -LiteralPath $cand -Raw), "DRAGLINT_VERSION\s*=\s*'([^']+)'")
    if ($m.Success) { $version = $m.Groups[1].Value; break }
  }
}

$css = @'
body { font-family: Calibri, "Segoe UI", sans-serif; font-size: 11pt; line-height: 1.35; }
h1 { font-size: 26pt; page-break-before: always; border-bottom: 2px solid #444; padding-bottom: 6pt; }
h2 { font-size: 18pt; page-break-before: always; color: #1a1a1a; }
h3 { font-size: 14pt; color: #222; }
h4 { font-size: 12pt; color: #333; }
code { font-family: Consolas, "Courier New", monospace; font-size: 9.5pt; background: #f4f4f4; }
pre { font-family: Consolas, "Courier New", monospace; font-size: 9pt; background: #f4f4f4;
      border: 1px solid #ddd; padding: 6pt; }
table { border-collapse: collapse; width: 100%; font-size: 10pt; }
th, td { border: 1px solid #bbb; padding: 4pt 6pt; text-align: left; vertical-align: top; }
th { background: #eee; }
blockquote { border-left: 3px solid #bbb; margin-left: 0; padding-left: 10pt; color: #444; }
.title { font-size: 40pt; font-weight: bold; }
.subtitle { font-size: 15pt; color: #555; }
'@

$html = New-Object System.Text.StringBuilder
[void]$html.AppendLine('<html><head><meta charset="utf-8"/><title>drag-lint manual</title>')
[void]$html.AppendLine("<style>$css</style></head><body>")

# title page (no page-break before the first heading)
[void]$html.AppendLine('<p class="title">drag-lint</p>')
[void]$html.AppendLine('<p class="subtitle">Symbol-aware index, RAG and lint for Delphi / Object Pascal</p>')
[void]$html.AppendLine("<p>Version $version<br/>Generated $(Get-Date -Format 'yyyy-MM-dd')</p>")

$pageCount = 0
foreach ($part in $parts) {
  if ($part.Pages.Count -eq 0) { continue }
  [void]$html.AppendLine("<h1>$($part.Title)</h1>")
  foreach ($p in $part.Pages) {
    $file = Join-Path $WikiDir "$p.md"
    if (-not (Test-Path -LiteralPath $file)) { continue }
    $md = Get-Content -LiteralPath $file -Raw
    [void]$html.AppendLine((ConvertFrom-Markdown $md $p))
    $pageCount++
  }
}
[void]$html.AppendLine('</body></html>')

$tmpHtml = Join-Path ([System.IO.Path]::GetTempPath()) ("draglint-manual-" + [Guid]::NewGuid().ToString('N') + ".html")
[System.IO.File]::WriteAllText($tmpHtml, $html.ToString(), (New-Object System.Text.UTF8Encoding $false))
Write-Host "assembled $pageCount page(s) -> $tmpHtml" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Word COM
# ---------------------------------------------------------------------------

$wdFormatXMLDocument = 16
$wdExportFormatPDF   = 17

$word = $null
$doc  = $null
try {
  $word = New-Object -ComObject Word.Application
  $word.Visible       = $false
  $word.DisplayAlerts = 0

  $doc = $word.Documents.Open($tmpHtml, $false, $true)   # ConfirmConversions=false, ReadOnly=true

  # A native TOC gives page numbers in the PDF, which an HTML list cannot.
  # Non-fatal: the document is still complete and navigable without it.
  #
  # Insert it before the FIRST HEADING, not at Range(0,0) -- at the very start it
  # lands ahead of the title page, so the manual opens on a contents list with no
  # title above it and reads as unfinished. The title block is only a few
  # paragraphs, so a bounded scan finds the first Part heading cheaply.
  try {
    $tocRange = $doc.Range(0, 0)
    $limit = [Math]::Min(40, $doc.Paragraphs.Count)
    for ($pi = 1; $pi -le $limit; $pi++) {
      $par = $doc.Paragraphs.Item($pi)
      if ($par.OutlineLevel -eq 1) {
        $tocRange = $par.Range
        # COLLAPSE TO START. Handing Add() a whole paragraph range makes it
        # REPLACE that paragraph: the first Part heading disappeared entirely
        # from the document while the other three survived, which is invisible
        # unless you count occurrences.
        $tocRange.Collapse(1)   # wdCollapseStart
        break
      }
    }
    [void]$doc.TablesOfContents.Add($tocRange, $true, 1, 3)
    $doc.TablesOfContents.Item(1).Update()
  } catch {
    Write-Host "  (table of contents skipped: $($_.Exception.Message))" -ForegroundColor DarkYellow
  }

  $doc.SaveAs2($DocxOut, $wdFormatXMLDocument)
  Write-Host "wrote $DocxOut" -ForegroundColor Green

  if (-not $SkipPdf) {
    # Positional args up to CreateBookmarks. Without the last one Word emits a
    # PDF with NO navigation pane at all, which for a 170+ page manual means the
    # only way to reach anything is scrolling. Order:
    #   OutputFileName, ExportFormat, OpenAfterExport, OptimizeFor, Range,
    #   From, To, Item, IncludeDocProps, KeepIRM, CreateBookmarks
    # CreateBookmarks = 1 is wdExportCreateHeadingBookmarks.
    $doc.ExportAsFixedFormat($PdfOut, $wdExportFormatPDF, $false, 0, 0, 1, 1, 0, $true, $true, 1)
    Write-Host "wrote $PdfOut" -ForegroundColor Green
  }
}
finally {
  if ($doc  -ne $null) { try { $doc.Close(0) } catch {} }
  if ($word -ne $null) { try { $word.Quit()  } catch {} }
  foreach ($o in @($doc, $word)) {
    if ($o -ne $null) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($o) } catch {} }
  }
  Remove-Item -LiteralPath $tmpHtml -ErrorAction SilentlyContinue
}

foreach ($f in @($DocxOut, $PdfOut)) {
  if (Test-Path -LiteralPath $f) {
    $len = (Get-Item -LiteralPath $f).Length
    Write-Host ("  {0}  {1:N0} bytes" -f [System.IO.Path]::GetFileName($f), $len)
  }
}
