<#
  Report.DocInsight.ps1 -- an Ask-Report answer as a DocInsight `/// <remarks>` block.

  A PORT, byte for byte, of FormatReportAsDocInsight in the IDE plugin
  (C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.ReportText.pas),
  so the text an agent gets from Ask-Report.ps1 is the text the IDE's Reports menu
  puts on the clipboard (owner answer 2, R5 spec section 10). Functions only,
  dot-sourced; no file writes, no engine.

  Kept identical on purpose -- same caption table, same 100-column wrap, same
  scrub table, same dropped lines -- and PROVEN identical: Test-AskReport.ps1
  (AR-DOC-*) compares this port with outputs the plugin's own Delphi formatter
  wrote (charts\fixtures\docinsight\*.expected.txt), and compares the caption
  table below with the plugin's REPORT_QUESTIONS when that source is on disk.
  A change on either side must change both, or that check goes red.
#>

# The plugin's REPORT_QUESTIONS: -Question id -> menu caption (the phrase is the caption without its '...')
$script:ReportCaptions = [ordered]@{
  'butterfly'        = 'Callers and callees (butterfly chart)...'
  'who-calls'        = 'Who calls this routine...'
  'what-it-calls'    = 'What this routine calls...'
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
$script:ReportDocMaxLine = 100
# CHAR_SUBSTS: the non-ASCII characters an answer is known to carry, each with its ASCII stand-in
$script:ReportCharSubst = @{
  0x00A0 = ' '; 0x00B7 = '*'; 0x2022 = '*'; 0x00D7 = 'x'; 0x2010 = '-'; 0x2011 = '-'
  0x2012 = '--'; 0x2013 = '--'; 0x2014 = '--'; 0x2015 = '--'; 0x2018 = "'"; 0x2019 = "'"
  0x201A = "'"; 0x201C = '"'; 0x201D = '"'; 0x201E = '"'; 0x2026 = '...'; 0x2190 = '<-'
  0x2192 = '->'; 0x21D2 = '=>'
}

# ScrubLine: printable ASCII kept, a control character -> ' ', a known character -> its stand-in, anything else '?'
function ConvertTo-ReportAscii([string] $Line) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $Line.ToCharArray()) {
    $n = [int]$c
    if ($n -ge 0x20 -and $n -le 0x7E) { [void]$sb.Append($c) }
    elseif ($n -lt 0x20) { [void]$sb.Append(' ') }
    elseif ($script:ReportCharSubst.ContainsKey($n)) { [void]$sb.Append($script:ReportCharSubst[$n]) }
    else { [void]$sb.Append('?') }
  }
  $sb.ToString()
}

# Delphi's Trim / TrimRight: every character <= ' ' is whitespace
function Get-ReportTrimEnd([string] $s) { $e = $s.Length; while ($e -gt 0 -and [int]$s[$e - 1] -le 0x20) { $e-- }; $s.Substring(0, $e) }
function Get-ReportTrim([string] $s) { $s = Get-ReportTrimEnd $s; $b = 0; while ($b -lt $s.Length -and [int]$s[$b] -le 0x20) { $b++ }; $s.Substring($b) }

# EmitWrapped: words joined up to the 100-column line ('/// ' included); a continuation is indented two more
# spaces; a word longer than the room left is cut, never dropped
function Add-ReportWrapped([System.Text.StringBuilder] $Out, [string] $Indent, [string] $Text) {
  $lead = $Indent; $cur = ''
  foreach ($w0 in @($Text.Split([char[]]@(' '), [StringSplitOptions]::RemoveEmptyEntries))) {
    $word = $w0
    do {
      $room = $script:ReportDocMaxLine - 4 - $lead.Length
      if ($cur -eq '') {
        if ($word.Length -le $room) { $cur = $word; $word = '' }
        else { $cur = $word.Substring(0, $room); $word = $word.Substring($room); [void]$Out.Append('/// ').Append($lead).Append($cur).Append("`r`n"); $cur = ''; $lead = $Indent + '  ' }
      } elseif ($cur.Length + 1 + $word.Length -le $room) { $cur = $cur + ' ' + $word; $word = '' }
      else { [void]$Out.Append('/// ').Append($lead).Append($cur).Append("`r`n"); $cur = ''; $lead = $Indent + '  ' }
    } until ($word -eq '')
  }
  if ($cur -ne '') { [void]$Out.Append('/// ').Append($lead).Append($cur).Append("`r`n") }
}

function ConvertTo-ReportXml([string] $s) { $s.Replace('&', '&amp;').Replace('<', '&lt;') }
# ' @File.pas:12' -> ' (File.pas:12)', only a token that looks like a file
function ConvertTo-ReportAnchors([string] $Line) { [regex]::Replace($Line, '(^|\s)@([^\s@]+\.[A-Za-z0-9]+(?::\d+)?)(?=$|[\s,;])', '$1($2)') }

<#
  Format-ReportAsDocInsight -- the plugin's FormatReportAsDocInsight.
  $Answer: Ask-Report's plain stdout (CRLF, LF or CR line ends). Returns CRLF lines, each starting
  with '///', opening '/// <remarks>' and closing '/// </remarks>' (with a final CRLF). Dropped: the
  top-level BUNDLE / INDEX lines, a trace's REGENERATE line, any 'ask-report:' / 'WARNING:' line; a
  CHART header becomes 'Totals: ...', a TARGET row 'Selected: ...'; '@File:line' -> '(File:line)'.
#>
function Format-ReportAsDocInsight([string] $QuestionId, [string] $Target, [datetime] $Date, [string] $Answer) {
  $phrase = $(if ($script:ReportCaptions.Contains($QuestionId)) { $script:ReportCaptions[$QuestionId].TrimEnd('.') } else { 'Report' })
  # FindReportQuestion is case-insensitive (SameText)
  if ($phrase -eq 'Report') { foreach ($k in $script:ReportCaptions.Keys) { if ([string]::Equals($k, $QuestionId, [StringComparison]::OrdinalIgnoreCase)) { $phrase = $script:ReportCaptions[$k].TrimEnd('.') } } }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("/// <remarks>`r`n")
  Add-ReportWrapped $sb '' (ConvertTo-ReportXml (ConvertTo-ReportAscii ("{0} (drag-lint report {1}) for {2}, asked on {3}." -f $phrase, $QuestionId, $Target, $Date.ToString('yyyy-MM-dd'))))
  $findings = 0; $pend = $true
  foreach ($raw in ($Answer.Replace("`r`n", "`n").Replace("`r", "`n") -split "`n")) {
    $line = ConvertTo-ReportAscii (Get-ReportTrimEnd $raw)
    if ((Get-ReportTrim $line) -eq '') { $pend = $true; continue }
    $trimmed = Get-ReportTrim $line
    $indent = ''; $text = ''
    if ($trimmed.StartsWith('ask-report:', [StringComparison]::OrdinalIgnoreCase) -or $trimmed.StartsWith('WARNING:', [StringComparison]::OrdinalIgnoreCase)) { continue }
    if ($line.StartsWith('BUNDLE ', [StringComparison]::Ordinal) -or $line.StartsWith('INDEX ', [StringComparison]::Ordinal)) { continue }
    if ($trimmed.StartsWith('REGENERATE ', [StringComparison]::Ordinal)) { continue }
    if ($line.StartsWith('CHART ', [StringComparison]::Ordinal)) {
      $p = $line.IndexOf(' -- ', [StringComparison]::Ordinal)
      if ($p -lt 0) { continue }
      $text = 'Totals: ' + (Get-ReportTrim $line.Substring($p + 4)) + '.'
    } else {
      if ($trimmed.StartsWith('TARGET ', [StringComparison]::Ordinal)) { $text = 'Selected: ' + (ConvertTo-ReportAnchors (Get-ReportTrim $trimmed.Substring(7))) }
      else { $text = ConvertTo-ReportAnchors $trimmed }
      $lead = 0; while ($lead -lt $line.Length -and $line[$lead] -eq ' ') { $lead++ }
      if ($lead -gt 2) { $indent = '  ' }
      if ($text -eq '') { continue }
    }
    if ($pend) { [void]$sb.Append("///`r`n") }
    $pend = $false
    Add-ReportWrapped $sb $indent (ConvertTo-ReportXml $text)
    $findings++
  }
  if ($findings -eq 0) {
    [void]$sb.Append("///`r`n")
    Add-ReportWrapped $sb '' 'The report returned no findings.'
  }
  [void]$sb.Append("/// </remarks>`r`n")
  $r = $sb.ToString()
  # RemoveAutodocMarker: the provenance marker, assembled so this file never holds it as one literal
  $marker = 'drag-lint' + ':auto'
  while ($r.IndexOf($marker, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $r = [regex]::Replace($r, [regex]::Escape($marker), 'drag-lint auto', 'IgnoreCase') }
  $r
}
