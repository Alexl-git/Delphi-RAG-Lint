unit DRagLint.Charts.Dot;

{ DOT text builders and the one place Graphviz dot.exe runs, for the ported chart
  emitters. Each routine is a port of the named function in charts\src\Emit-Common.ps1
  (line numbers of 2026-10-13); the PowerShell output is the reference (spec P3/P4).

  dot.exe is not drag-lint.exe, so running it here is within spec P5. The caller resolves
  it (DRagLint.Charts.Tools.ResolveGraphvizDot) and passes the path in. }

interface

uses
  System.SysUtils, System.Classes;

const
  /// <summary>The ink of a note / disclosure line (the PS default -Ink / -LineInk).</summary>
  NOTE_INK = '#8A94A6';
  /// <summary>The point size of a disclosure line (the PS default -PointSize).</summary>
  NOTE_POINT_SIZE = 12;
  /// <summary>The longest output path dot.exe can open: MAX_PATH less the NUL (measured on dot 16.1).</summary>
  DOT_MAX_PATH = 259;

type
  /// <summary>dot.exe failed, could not be given a usable path, or a cluster row is empty.</summary>
  EChartsDot = class(Exception);

  /// <summary>One row of a row cluster (the PS row object: Label, Line, Href, Tip, Note).</summary>
  /// <remarks>A row with a blank Href is a NOTE row: no HREF, no TITLE, no line, but it keeps
  /// its port. Line is TEXT because the PS prints `:$($r.Line)` -- a $null line prints ':'.</remarks>
  TDotRow = record
    /// <summary>The row text (plain text; escaped by the builder).</summary>
    Caption: string;
    /// <summary>What follows the ':' of an anchored row; '' prints a bare ':'.</summary>
    Line   : string;
    /// <summary>The row's link (already escaped, e.g. a RowHref); '' makes a note row.</summary>
    Href   : string;
    /// <summary>The tooltip (plain text; escaped by the builder).</summary>
    Tip    : string;
    /// <summary>The dimmed suffix after a middle dot; '' for none.</summary>
    Note   : string;
    /// <summary>An anchored row.</summary>
    /// <param name="pCaption">Row text.</param>
    /// <param name="pLine">1-based line printed after ':'.</param>
    /// <param name="pHref">The link.</param>
    /// <param name="pTip">The tooltip.</param>
    /// <param name="pNote">Dimmed suffix or ''.</param>
    /// <returns>The row.</returns>
    class function Anchored(const pCaption: string; pLine: Integer; const pHref, pTip: string;
      const pNote: string = ''): TDotRow; static;
  end;

  /// <summary>The look of a row cluster (the PS Add-RowCluster style parameters).</summary>
  TClusterStyle = record
    /// <summary>Cluster border colour.</summary>
    Border  : string;
    /// <summary>Cluster fill colour.</summary>
    Fill    : string;
    /// <summary>Header row background.</summary>
    Hdr     : string;
    /// <summary>Anchored row ink (PS default '#1F2933').</summary>
    RowInk  : string;
    /// <summary>Line-number and note ink (PS default NOTE_INK).</summary>
    LineInk : string;
    /// <summary>Header font face (PS default 'Segoe UI').</summary>
    FontSans: string;
    /// <summary>DOT style list (PS default 'rounded,filled').</summary>
    Style   : string;
    /// <summary>Border pen width (PS default 2).</summary>
    PenWidth: Integer;
    /// <summary>The PS defaults with the three colours the caller always passes.</summary>
    /// <param name="pBorder">Border colour.</param>
    /// <param name="pFill">Fill colour.</param>
    /// <param name="pHdr">Header background.</param>
    /// <returns>The style.</returns>
    class function Make(const pBorder, pFill, pHdr: string): TClusterStyle; static;
  end;

  /// <summary>The files one dot layout run wrote, and the anchor count of its SVG.</summary>
  TDotLayout = record
    /// <summary>The .dot written.</summary>
    Dot    : string;
    /// <summary>The .svg.</summary>
    Svg    : string;
    /// <summary>The .plain geometry.</summary>
    Plain  : string;
    /// <summary>The .png.</summary>
    Png    : string;
    /// <summary>The .pdf.</summary>
    Pdf    : string;
    /// <summary>How many &lt;a elements the SVG holds (regex '&lt;a[\s&gt;]', case-sensitive).</summary>
    Anchors: Integer;
  end;

/// <summary>A note row (no Href) for AddRowCluster.</summary>
/// <param name="pText">The note text (plain).</param>
/// <returns>The row.</returns>
/// <remarks>Port of New-NoteRow (Emit-Common.ps1:780).</remarks>
function NoteRow(const pText: string): TDotRow;

/// <summary>Appends a non-anchored disclosure row to an HTML-label table being built.</summary>
/// <param name="pTable">The table builder; must not be nil.</param>
/// <param name="pText">Plain text; blank appends nothing. The '&amp;#183;' middle dot survives
/// the escape.</param>
/// <param name="pInk">Font colour.</param>
/// <param name="pPointSize">Font size.</param>
/// <remarks>Port of Add-DisclosureRow (Emit-Common.ps1:771). PS trap closed: blank is
/// IsNullOrWhiteSpace (Char.IsWhiteSpace), not Delphi Trim.</remarks>
procedure AddDisclosureRow(pTable: TStringBuilder; const pText: string; const pInk: string = NOTE_INK;
  pPointSize: Integer = NOTE_POINT_SIZE);

/// <summary>Appends a rounded, label-less cluster holding one HTML-table node of rows.</summary>
/// <param name="pSb">The DOT text being built; must not be nil. Lines end CRLF (AppendLine).</param>
/// <param name="pCid">Cluster id (e.g. 'cluster_focus').</param>
/// <param name="pNid">Node id; ports are '&lt;pNid&gt;:p&lt;n&gt;'.</param>
/// <param name="pTitle">Header text (plain).</param>
/// <param name="pSubtitle">Header suffix after a middle dot (plain); '' for none.</param>
/// <param name="pRows">The rows, in order.</param>
/// <param name="pStyle">Colours and style.</param>
/// <returns>The port of every row, IN ROW ORDER (callers key their port map by ordinal).</returns>
/// <exception cref="EChartsDot">A row with a blank Caption AND a blank Href -- an empty FONT
/// is a dot syntax error, and skipping it would shift every later port.</exception>
/// <remarks>Port of Add-RowCluster (Emit-Common.ps1:2849). Colours are inserted raw, as in
/// the PS; text is escaped with XmlText.</remarks>
function AddRowCluster(pSb: TStringBuilder; const pCid, pNid, pTitle, pSubtitle: string;
  const pRows: TArray<TDotRow>; const pStyle: TClusterStyle): TArray<string>;

/// <summary>Runs dot.exe once for four outputs (svg, plain, png at 110 dpi, pdf).</summary>
/// <param name="pDotExe">The resolved dot.exe.</param>
/// <param name="pDotFile">The input .dot.</param>
/// <param name="pSvg">SVG output.</param>
/// <param name="pPlain">Plain output.</param>
/// <param name="pPng">PNG output.</param>
/// <param name="pPdf">PDF output.</param>
/// <returns>dot's own messages (stdout then stderr), Pango warnings and blank lines removed --
/// what the PS prints as '  dot: ...'.</returns>
/// <exception cref="EChartsDot">A full path over DOT_MAX_PATH; dot could not start; no SVG;
/// a non-zero exit (an SVG can be half a run).</exception>
/// <remarks>Port of Invoke-DotRun (Emit-Common.ps1:2789). Stale outputs are deleted first, so
/// a failed re-run cannot find the previous picture. PS difference by design: the PS resolves
/// dot itself from the caller's $Dot; here the caller resolves it and passes the path.</remarks>
function DotRun(const pDotExe, pDotFile, pSvg, pPlain, pPng, pPdf: string): TArray<string>;

/// <summary>Writes the DOT text and lays it out once into four sibling files.</summary>
/// <param name="pDotExe">The resolved dot.exe.</param>
/// <param name="pDotText">The graph; line ends normalised to CRLF, written UTF-8 without BOM.</param>
/// <param name="pOutDir">Output folder; created when missing.</param>
/// <param name="pBase">File base name: &lt;base&gt;.dot/.svg/.plain/.png/.pdf.</param>
/// <param name="pMessages">dot's messages (see DotRun).</param>
/// <returns>The five paths and the SVG anchor count.</returns>
/// <exception cref="EChartsDot">As DotRun.</exception>
/// <remarks>Port of Invoke-DotLayout (Emit-Common.ps1:2814).</remarks>
function DotLayout(const pDotExe, pDotText, pOutDir, pBase: string; out pMessages: TArray<string>): TDotLayout;

implementation

uses
  Winapi.Windows, System.IOUtils, System.RegularExpressions, System.Character, System.StrUtils,
  DRagLint.Charts.Text, DRagLint.Charts.Process;

const
  ROW_INK_DEFAULT = '#1F2933';
  FONT_SANS_DEFAULT = 'Segoe UI';
  STYLE_DEFAULT = 'rounded,filled';
  PEN_WIDTH_DEFAULT = 2;
  MIDDOT = '&#183;';
  ESCAPED_MIDDOT = '&amp;#183;';
  PANGO_WARNING = 'Pango-WARNING';
  ANCHOR_PATTERN = '<a[\s>]';
  PNG_DPI_SWITCH = '-Gdpi=110';
  WAIT_FOREVER = 0;

function IsBlank(const pS: string): Boolean;
begin
  { [string]::IsNullOrWhiteSpace: Char.IsWhiteSpace, not Delphi Trim's <= #32 }
  for var C in pS do
    if not C.IsWhiteSpace then
      Exit(False);
  Result:= True;
end;

function Quoted(const pS: string): string;
begin
  Result:= '"' + pS + '"';
end;

class function TDotRow.Anchored(const pCaption: string; pLine: Integer; const pHref, pTip, pNote: string): TDotRow;
begin
  Result.Caption:= pCaption;
  Result.Line:= IntToStr(pLine);
  Result.Href:= pHref;
  Result.Tip:= pTip;
  Result.Note:= pNote;
end;

class function TClusterStyle.Make(const pBorder, pFill, pHdr: string): TClusterStyle;
begin
  Result.Border:= pBorder;
  Result.Fill:= pFill;
  Result.Hdr:= pHdr;
  Result.RowInk:= ROW_INK_DEFAULT;
  Result.LineInk:= NOTE_INK;
  Result.FontSans:= FONT_SANS_DEFAULT;
  Result.Style:= STYLE_DEFAULT;
  Result.PenWidth:= PEN_WIDTH_DEFAULT;
end;

function NoteRow(const pText: string): TDotRow;
begin
  Result:= Default(TDotRow);
  Result.Caption:= pText;
end;

procedure AddDisclosureRow(pTable: TStringBuilder; const pText, pInk: string; pPointSize: Integer);
begin
  if IsBlank(pText) then
    Exit;
  var Body:= XmlText(pText).Replace(ESCAPED_MIDDOT, MIDDOT);
  pTable.Append(Format('<TR><TD ALIGN="LEFT"><FONT COLOR="%s" POINT-SIZE="%d">%s</FONT></TD></TR>', [pInk, pPointSize, Body]));
end;

function AddRowCluster(pSb: TStringBuilder; const pCid, pNid, pTitle, pSubtitle: string;
  const pRows: TArray<TDotRow>; const pStyle: TClusterStyle): TArray<string>;
begin
  pSb.AppendLine(Format('  subgraph %s {', [pCid]));
  pSb.AppendLine(Format('    style="%s"; color="%s"; fillcolor="%s"; penwidth=%d;',
    [pStyle.Style, pStyle.Border, pStyle.Fill, pStyle.PenWidth]));
  pSb.AppendLine('    label=""; margin=10;');
  var HdrText:= XmlText(pTitle);
  if pSubtitle <> '' then
    HdrText:= HdrText + ' ' + MIDDOT + ' ' + XmlText(pSubtitle);
  var Tbl:= TStringBuilder.Create;
  try
    Tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    Tbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
      [pStyle.Hdr, pStyle.FontSans, HdrText]));
    SetLength(Result, Length(pRows));
    for var P:= 1 to Length(pRows) do
    begin
      var R:= pRows[P - 1];
      if IsBlank(R.Caption) and IsBlank(R.Href) then
        raise EChartsDot.CreateFmt('Add-RowCluster (%s): row %d is empty -- did a , $array return get wrapped in @()?', [pCid, P]);
      Result[P - 1]:= Format('%s:p%d', [pNid, P]);
      if IsBlank(R.Href) then
      begin
        Tbl.Append(Format('<TR><TD PORT="p%d" ALIGN="LEFT"><FONT COLOR="%s" POINT-SIZE="12">%s</FONT></TD></TR>',
          [P, pStyle.LineInk, XmlText(R.Caption)]));
        Continue;
      end;
      Tbl.Append(Format('<TR><TD PORT="p%d" ALIGN="LEFT" HREF="%s" TITLE="%s">', [P, R.Href, XmlText(R.Tip)]));
      Tbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [pStyle.RowInk, XmlText(R.Caption)]));
      Tbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="12">:%s</FONT>', [pStyle.LineInk, R.Line]));
      if R.Note <> '' then
        Tbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="11">%s %s</FONT>', [pStyle.LineInk, MIDDOT, XmlText(R.Note)]));
      Tbl.Append('</TD></TR>');
    end;
    Tbl.Append('</TABLE>');
    pSb.AppendLine(Format('    %s [label=<%s>];', [pNid, Tbl.ToString]));
    pSb.AppendLine('  }');
  finally
    Tbl.Free;
  end;
end;

function DotMessages(const pRun: TProcessResult): TArray<string>;
begin
  Result:= [];
  for var Line in (pRun.StdOut + #10 + pRun.StdErr).Split([#10]) do
  begin
    var S:= Line.TrimRight([#13]);
    if ContainsText(S, PANGO_WARNING) or IsBlank(S) then
      Continue;
    Result:= Result + [S];
  end;
end;

function DotRun(const pDotExe, pDotFile, pSvg, pPlain, pPng, pPdf: string): TArray<string>;
begin
  for var P in [pDotFile, pSvg, pPlain, pPng, pPdf] do
  begin
    var Full:= ExpandFileName(P);
    if Length(Full) > DOT_MAX_PATH then
      raise EChartsDot.CreateFmt('output path is %d characters, over the %d that dot.exe can open ' +
        '(it is not long-path aware, so it would write NO SVG): %s -- use a shorter -OutDir/-OutRoot.',
        [Length(Full), DOT_MAX_PATH, Full]);
  end;
  for var P in [pSvg, pPlain, pPng, pPdf] do
  begin
    if System.SysUtils.DeleteFile(P) then
      Continue;
    var Err:= GetLastError;
    if (Err <> ERROR_FILE_NOT_FOUND) and (Err <> ERROR_PATH_NOT_FOUND) then
      raise EChartsDot.CreateFmt('cannot remove the previous output %s: %s', [P, SysErrorMessage(Err)]);
  end;
  var Cmd:= string.Join(' ', [Quoted(pDotExe), '-Tsvg', '-o', Quoted(pSvg), '-Tplain', '-o', Quoted(pPlain),
    '-Tpng', PNG_DPI_SWITCH, '-o', Quoted(pPng), '-Tpdf', '-o', Quoted(pPdf), Quoted(pDotFile)]);
  var Run: TProcessResult;
  if not RunCapture(Cmd, '', WAIT_FOREVER, Run) then
    raise EChartsDot.CreateFmt('dot could not be started: %s', [pDotExe]);
  Result:= DotMessages(Run);
  var Why:= if Length(Result) > 0 then ' dot said: ' + string.Join(' | ', Result) else ' dot printed nothing.';
  if not FileExists(pSvg) then
    raise EChartsDot.CreateFmt('dot produced no SVG at %s (exit %d).%s', [pSvg, Run.ExitCode, Why]);
  if Run.ExitCode <> 0 then
    raise EChartsDot.CreateFmt('dot exited %d for %s.%s', [Run.ExitCode, pDotFile, Why]);
end;

function DotLayout(const pDotExe, pDotText, pOutDir, pBase: string; out pMessages: TArray<string>): TDotLayout;
begin
  ForceDirectories(pOutDir);
  Result.Dot:= TPath.Combine(pOutDir, pBase + '.dot');
  Result.Svg:= TPath.Combine(pOutDir, pBase + '.svg');
  Result.Plain:= TPath.Combine(pOutDir, pBase + '.plain');
  Result.Png:= TPath.Combine(pOutDir, pBase + '.png');
  Result.Pdf:= TPath.Combine(pOutDir, pBase + '.pdf');
  var Crlf:= pDotText.Replace(#13#10, #10).Replace(#10, #13#10);
  TFile.WriteAllBytes(Result.Dot, TEncoding.UTF8.GetBytes(Crlf));
  pMessages:= DotRun(pDotExe, Result.Dot, Result.Svg, Result.Plain, Result.Png, Result.Pdf);
  var Svg:= TFile.ReadAllText(Result.Svg, TEncoding.UTF8);
  Result.Anchors:= TRegEx.Matches(Svg, ANCHOR_PATTERN).Count;
end;

end.
