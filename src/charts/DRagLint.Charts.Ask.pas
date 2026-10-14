unit DRagLint.Charts.Ask;

(* One ported chart question, asked end to end in-process: the bundle that
  New-DiagramArtifact.ps1 writes and the plain answer that Ask-Report.ps1 -Plain prints.

  Ported once for every chart question; the question itself is one registered emitter
  (DRagLint.Charts.Question). The PowerShell output is the reference (spec P3): the bundle
  holds graph.dot/.svg/.plain/.png/.pdf, meta.json, index.html and xref.txt with the PS
  bytes, and the answer is Ask-Report's plain lines -- the header sentence, COMMAND,
  BUNDLE, INDEX, the CHART line and one line per row read back from graph.dot.

  NOT PORTED, because no ported question needs it: the round-trip text branch
  (trace.dlgraph), and the -SqlDbPath / -ServerDbPath / -CounterpartDb parts of the
  regenerate command. Index resolution (-Project / -In), the pairing file and the
  freshness check are the producer's job, before this unit is called.

  PS traps closed here: [regex]::Matches is case-SENSITIVE while -match / -notmatch are
  case-insensitive; WebUtility.HtmlDecode decodes numeric references (&#183; becomes a
  middle dot, which the ASCII scrub then turns into a space); [uri]::UnescapeDataString
  decodes %XX as UTF-8 and never turns '+' into a space; String.Trim trims
  Char.IsWhiteSpace, not Delphi Trim's '<= #32'; ConvertTo-Json indents by two spaces with
  CRLF and Set-Content adds a final CRLF; the shell and the xref are CRLF without a final
  line end. *)

interface

uses
  System.SysUtils, DRagLint.Charts.ReportHeader, DRagLint.Charts.Question;

type
  /// <summary>The answer to one chart question.</summary>
  TAskAnswer = record
    /// <summary>The plain answer, one line per element, no line ends.</summary>
    Lines    : TArray<string>;
    /// <summary>The bundle folder.</summary>
    BundleDir: string;
  end;

/// <summary>Asks one ported chart question: emits, bundles, and reads the answer back.</summary>
/// <param name="pArgs">The question, resolved: full index path, effective caps, dot.exe.</param>
/// <returns>The plain answer and the bundle folder.</returns>
/// <exception cref="EChartsQuestion">The question is not ported.</exception>
/// <remarks>Any exception the emitter raises is a refusal and propagates unchanged; a bundle
/// folder this call created is removed again when it is still empty. Not thread-safe while
/// pArgs.AllowLiveDb is set: the clone-guard override is a process environment variable.</remarks>
function AskChartQuestion(const pArgs: TQuestionArgs): TAskAnswer;

/// <summary>The bundle folder name's target part.</summary>
/// <param name="pTarget">The selection.</param>
/// <returns>pTarget with every character outside A-Z a-z 0-9 replaced by '_'.</returns>
function BundleSlug(const pTarget: string): string;

/// <summary>The COMMAND line of the answer header (Ask-Report's Get-ReportCommandLine).</summary>
/// <param name="pCmd">The question and its explicit arguments.</param>
/// <returns>'COMMAND &lt;id&gt; -Target "t"' then -To, -Project (full path) or -In (full path),
/// -Depth, -Cap, -SurfaceCap, -Control, -Mode, -MaxRows -- each only when given (-To,
/// -Project, -In, -Control and -Mode only when not empty).</returns>
function ReportCommandText(const pCmd: TReportCommand): string;

/// <summary>The result lines Ask-Report reads back from a chart's graph.dot.</summary>
/// <param name="pDotLines">graph.dot, one element per line.</param>
/// <param name="pRegenerate">meta.json's regenerate command (names the cap of a '+N more' line).</param>
/// <param name="pMaxRows">How many result rows to print.</param>
/// <param name="pDotPath">graph.dot's path, for the 'more rows' line.</param>
/// <param name="pShellPath">index.html's path, for the 'no anchored rows' line.</param>
/// <returns>'  TARGET ...' lines, then the result rows, then '  ... &lt;not shown&gt;' lines.</returns>
function DotAnswerRows(const pDotLines: TArray<string>; const pRegenerate: string; pMaxRows: Integer;
  const pDotPath, pShellPath: string): TArray<string>;

/// <summary>Decodes HTML character references as System.Net.WebUtility.HtmlDecode does for
/// the text a chart label can hold.</summary>
/// <param name="pText">Text with &amp;amp; &amp;lt; &amp;gt; &amp;quot; &amp;apos; and
/// numeric (&amp;#NNN; / &amp;#xHH;) references.</param>
/// <returns>The decoded text, one pass; any other '&amp;' is kept.</returns>
/// <remarks>Approximation: the other HTML named entities are not decoded. A chart label never
/// holds one -- XmlText escapes every '&amp;' and the emitters add only &amp;#183;.</remarks>
function HtmlDecode(const pText: string): string;

/// <summary>Decodes %XX escapes as [uri]::UnescapeDataString: bytes as UTF-8, '+' kept.</summary>
/// <param name="pText">Escaped text.</param>
/// <returns>The decoded text; a '%' not followed by two hex digits is kept.</returns>
function UnescapeDataString(const pText: string): string;

implementation

uses
  Winapi.Windows, System.Classes, System.IOUtils, System.StrUtils, System.Character, System.DateUtils,
  System.Generics.Collections, System.RegularExpressions, DRagLint.Charts.Text
  , DRagLint.Charts.Tools // dl:unit DRagLint.Charts.Tools accepted -- the clone-guard override's variable name travels with the guard (CloneDb) that reads it
  ;

const
  LF = #10;
  CRLF = #13#10;
  ROW_INDENT = '  ';
  GRAPH_DOT = 'graph.dot';
  GRAPH_SVG = 'graph.svg';
  GRAPH_PLAIN = 'graph.plain';
  GRAPH_PNG = 'graph.png';
  GRAPH_PDF = 'graph.pdf';
  META_JSON = 'meta.json';
  SHELL_HTML = 'index.html';
  XREF_TXT = 'xref.txt';
  PATH_QUESTION = 'path';
  ISO_UTC = 'yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"';
  ASKED_ON = 'yyyy"-"mm"-"dd hh":"nn';
  HEX_BASE = 16;
  HEX_LETTER_BASE = 10;
  MAX_CODE_POINT = $10FFFF;
  SURROGATE_FIRST = $D800;
  SURROGATE_LAST = $DFFF;
  ESCAPE_LEN = 3;
  { Ask-Report's dot read-back }
  RE_FOCUS_OPEN = '^\s*subgraph cluster_focus';
  RE_CLUSTER_CLOSE = '^\s*\}\s*$';
  RE_PLAIN_TD = '<TD(?![^>]*HREF=)[^>]*>(.*?)</TD>';
  RE_ANCHORED_TD = '<TD[^>]*?HREF="draglint://open\?file=([^"&]*)&amp;line=(\d+)"[^>]*?TITLE="([^"]*)"[^>]*>(.*?)</TD>';
  RE_FIRST_FONT = '<FONT[^>]*>(.*?)</FONT>';
  RE_TAG = '<[^>]+>';
  RE_NOT_PRINTABLE = '[^\x20-\x7E]';
  RE_NOT_SHOWN = 'not shown';
  RE_MORE = '^\+\d+ more';
  RE_CAP_ARG = ' -(SurfaceCap|Cap) (\d+)';
  RE_TIP_SEP = '\s--\s';
  RE_TIP_SPLIT = '\s+--\s+';
  RE_WHITESPACE = '\s';
  RE_SLUG = '[^A-Za-z0-9]';
  RE_SVG_PROLOG = '(?s)^.*?(?=<svg)';
  G_FILE = 1;
  G_LINE = 2;
  G_TIP = 3;
  G_BODY = 4;
  G_INNER = 1;
  G_CAP_NAME = 1;
  G_CAP_VALUE = 2;
  { New-DiagramArtifact's per-question regenerate arguments }
  REGEN_DEPTH: array[0..5] of string = ('butterfly', 'who-calls', 'what-it-calls', 'change-impact',
    'exception-paths', 'round-trip');
  REGEN_CAP: array[0..12] of string = ('who-writes', 'who-reads', 'hierarchy', 'wiring', 'protocol-trace',
    'shown-where', 'tested-by', 'crosses-boundary', 'exception-paths', 'consumers', 'feeds-from',
    'lands-where', 'path');

  { New-DiagramArtifact.ps1's index.html, its $note for a chart question and its footer, verbatim; 
    the @@NAME@@ tokens are the here-string's variables (the template holds '%', so no Format). }
  HTML_TEMPLATE =
    '<!doctype html>' + LF +
    '<meta charset="utf-8">' + LF +
    '<title>@@QUESTION@@ -- @@SHORT@@</title>' + LF +
    '<style>' + LF +
    '  :root{--bg:#F6F7F9;--panel:#fff;--ink:#131820;--muted:#5B6674;--line:#DDE2E8;' + LF +
    '        --accent:#0F766E;--accent-soft:#E2F1EF;--warn:#9A5408;--warn-soft:#FBF0E0;' + LF +
    '        --mono:''Cascadia Mono'',Consolas,monospace;' + LF +
    '        --sans:''Segoe UI'',system-ui,sans-serif;}' + LF +
    '  @media (prefers-color-scheme:dark){:root{--bg:#0E1319;--panel:#151C24;--ink:#E6EBF1;' + LF +
    '        --muted:#96A2B1;--line:#293441;--accent:#4FD1C0;--accent-soft:#12312D;' + LF +
    '        --warn:#E0A458;--warn-soft:#33260F;}}' + LF +
    '  *{box-sizing:border-box}' + LF +
    '  body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.6 var(--sans);}' + LF +
    '  header{padding:20px 24px;border-bottom:1px solid var(--line);}' + LF +
    '  h1{margin:0 0 6px;font-size:22px;font-weight:650;}' + LF +
    '  h1 code{font-family:var(--mono);font-size:.85em;}' + LF +
    '  .meta{font-family:var(--mono);font-size:12.5px;color:var(--muted);' + LF +
    '        display:flex;flex-wrap:wrap;gap:6px 22px;}' + LF +
    '  .meta b{color:var(--ink);font-weight:600;}' + LF +
    '  main{padding:20px 24px;}' + LF +
    '  .stage{background:var(--panel);border:1px solid var(--line);border-radius:10px;' + LF +
    '         padding:16px;overflow:auto;}' + LF +
    '  .stage svg{max-width:100%;height:auto;}' + LF +
    '  .stage a{cursor:pointer;}' + LF +
    '  .stage a:hover text{text-decoration:underline;}' + LF +
    '  .stage pre a{color:var(--accent);text-decoration:none;}' + LF +
    '  .stage pre a:hover{text-decoration:underline;}' + LF +
    '  .note{margin:18px 0 0;border-left:4px solid var(--warn);background:var(--warn-soft);' + LF +
    '        padding:14px 18px;border-radius:0 8px 8px 0;font-size:14px;}' + LF +
    '  .note b{color:var(--warn);}' + LF +
    '  #toast{position:fixed;left:50%;bottom:26px;transform:translateX(-50%);' + LF +
    '         background:var(--ink);color:var(--bg);font-family:var(--mono);font-size:13px;' + LF +
    '         padding:11px 16px;border-radius:8px;max-width:min(92vw,720px);' + LF +
    '         box-shadow:0 6px 24px rgba(0,0,0,.25);opacity:0;pointer-events:none;' + LF +
    '         transition:opacity .18s;}' + LF +
    '  #toast.on{opacity:1;}' + LF +
    '  footer{padding:16px 24px 32px;color:var(--muted);font-family:var(--mono);font-size:12px;}' + LF +
    '  code.k{background:var(--accent-soft);color:var(--accent);padding:1px 6px;border-radius:4px;}' + LF +
    '</style>' + LF +
    '<header>' + LF +
    '  <h1>@@QUESTION@@ &mdash; <code>@@SHORT@@</code></h1>' + LF +
    '  <div class="meta">' + LF +
    '    <span><b>@@LEFTCOUNT@@</b> @@LEFTLABEL@@</span>' + LF +
    '    <span><b>@@RIGHTCOUNT@@</b> @@RIGHTLABEL@@</span>' + LF +
    '    @@ANCHORSPAN@@' + LF +
    '    <span>index <b>@@INDEXNAME@@</b></span>' + LF +
    '    <span>generated <b>@@GENERATED@@</b></span>' + LF +
    '  </div>' + LF +
    '</header>' + LF +
    '<main>' + LF +
    '  <div class="stage">@@SVG@@</div>' + LF +
    '' + LF +
    '  <div class="note">' + LF +
    '@@NOTE@@' + LF +
    '  </div>' + LF +
    '</main>' + LF +
    '<footer>' + LF +
    '  @@FOOTFILES@@meta.json (regenerate command + index fingerprint)' + LF +
    '</footer>' + LF +
    '<div id="toast"></div>' + LF +
    '<script>' + LF +
    '(function () {' + LF +
    '  var t = document.getElementById(''toast''), timer = null;' + LF +
    '  function toast(msg) {' + LF +
    '    t.textContent = msg; t.classList.add(''on'');' + LF +
    '    clearTimeout(timer); timer = setTimeout(function () { t.classList.remove(''on''); }, 5200);' + LF +
    '  }' + LF +
    '  // DOC-R1: the click is NEVER cancelled. The browser hands the draglint:// URI to the registered' + LF +
    '  // protocol handler (Register-DragLintProtocol.ps1 -> Open-DragLintUri.ps1 -> the IDE plugin''s pipe' + LF +
    '  // \\.\pipe\drag-lint-open-source); the toast only says what was asked, and what to do if nothing opens.' + LF +
    '  document.querySelector(''.stage'').addEventListener(''click'', function (ev) {' + LF +
    '    var a = ev.target.closest(''a''); if (!a) return;' + LF +
    '    var href = a.getAttribute(''href'') || a.getAttribute(''xlink:href'') || '''';' + LF +
    '    if (href.indexOf(''draglint://'') !== 0) return;' + LF +
    '    var m = /file=([^&]*)&(?:amp;)?line=(\d+)/.exec(href);' + LF +
    '    var what = href;' + LF +
    '    if (m) { try { what = decodeURIComponent(m[1]) + '':'' + m[2]; } catch (e) { what = m[1] + '':'' + m[2]; } }' + LF +
    '    toast(''opening '' + what + '' in the IDE -- if nothing opens, register the handler once: charts\\src\\Register-DragLintProtocol.ps1'');' + LF +
    '  });' + LF +
    '})();' + LF +
    '</script>';

  NOTE_CHART =
    '    <p><b>Clicks open the file in your running IDE.</b> Every row is a real anchor' + LF +
    '    carrying <code class="k">draglint://open?file=..&amp;line=..</code>. The IDE' + LF +
    '    plugin already runs the pipe server' + LF +
    '    (<code class="k">DragLint.Plugin.OpenSourceServer.pas</code>, started from' + LF +
    '    <code class="k">DragLint.Plugin.Wizard.pas:117</code>), listening on' + LF +
    '    <code class="k">\\.\pipe\drag-lint-open-source</code> for' + LF +
    '    <code class="k">&lt;file&gt;&lt;TAB&gt;&lt;line&gt;&lt;LF&gt;</code>.</p>' + LF +
    '    <p style="margin-top:10px">A browser cannot write to a named pipe, so the' + LF +
    '    one-time bridge is a protocol handler:' + LF +
    '    <code class="k">charts\src\Register-DragLintProtocol.ps1</code> (HKCU only,' + LF +
    '    no elevation, <code class="k">-Unregister</code> to undo). A click also shows' + LF +
    '    a short note naming the file and line it asked for; if nothing opens, the' + LF +
    '    handler is not registered on this machine. The handler opens only a local' + LF +
    '    source file (.pas .dfm .dpr .inc .sql .fmx) and, when the IDE is not' + LF +
    '    running, shows it in Notepad.</p>';

  ANCHOR_SPAN = '<span><b>%d</b> click targets</span>';
  FOOT_FILES = 'graph.svg &middot; graph.png &middot; graph.pdf &middot; graph.plain (geometry, same layout run) &middot; ';

function InList(const pId: string; const pList: array of string): Boolean;
begin
  for var S in pList do
    if SameText(S, pId) then
      Exit(True);
  Result:= False;
end;

{ String.Trim: Char.IsWhiteSpace at both ends }
function TrimWs(const pS: string): string;
begin
  var B:= 1;
  var E:= Length(pS);
  while (B <= E) and pS[B].IsWhiteSpace do
    Inc(B);
  while (E >= B) and pS[E].IsWhiteSpace do
    Dec(E);
  Result:= Copy(pS, B, E - B + 1);
end;

function BundleSlug(const pTarget: string): string;
begin
  Result:= TRegEx.Replace(pTarget, RE_SLUG, '_');
end;

function ReportCommandText(const pCmd: TReportCommand): string;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append('COMMAND ').Append(pCmd.Question).Append(' -Target "').Append(pCmd.Get('Target')).Append('"');
    if pCmd.Get('To') <> '' then
      SB.Append(' -To "').Append(pCmd.Get('To')).Append('"');
    if pCmd.Get('Project') <> '' then
      SB.Append(' -Project "').Append(ExpandFileName(pCmd.Get('Project'))).Append('"')
    else if pCmd.Get('In') <> '' then
      SB.Append(' -In "').Append(ExpandFileName(pCmd.Get('In'))).Append('"');
    for var N in ['Depth', 'Cap', 'SurfaceCap'] do
      if pCmd.Has(N) then
        SB.Append(' -').Append(N).Append(' ').Append(pCmd.Get(N));
    if pCmd.Get('Control') <> '' then
      SB.Append(' -Control "').Append(pCmd.Get('Control')).Append('"');
    if pCmd.Get('Mode') <> '' then
      SB.Append(' -Mode ').Append(pCmd.Get('Mode'));
    if pCmd.Has('MaxRows') then
      SB.Append(' -MaxRows ').Append(pCmd.Get('MaxRows'));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function HtmlDecode(const pText: string): string;
begin
  if not pText.Contains('&') then
    Exit(pText);
  var SB:= TStringBuilder.Create;
  try
    var I:= 1;
    while I <= Length(pText) do
    begin
      var Semi:= if pText[I] = '&' then PosEx(';', pText, I + 1) else 0;
      if Semi > 0 then
      begin
        var Name:= Copy(pText, I + 1, Semi - I - 1);
        var Code:= -1;
        if Name = 'amp' then Code:= Ord('&')
        else if Name = 'lt' then Code:= Ord('<')
        else if Name = 'gt' then Code:= Ord('>')
        else if Name = 'quot' then Code:= Ord('"')
        else if Name = 'apos' then Code:= Ord('''')
        else if (Length(Name) > 1) and (Name[1] = '#') then
        begin
          var Num:= Copy(Name, 2, MaxInt);
          if (Num <> '') and CharInSet(Num[1], ['x', 'X']) then
            Code:= StrToIntDef('$' + Copy(Num, 2, MaxInt), -1)
          else if (Num <> '') and CharInSet(Num[1], ['0'..'9']) then
            Code:= StrToIntDef(Num, -1);
        end;
        if (Code >= 0) and (Code <= MAX_CODE_POINT) and not ((Code >= SURROGATE_FIRST) and (Code <= SURROGATE_LAST)) then
        begin
          SB.Append(Char.ConvertFromUtf32(Code));
          I:= Semi + 1;
          Continue;
        end;
      end;
      SB.Append(pText[I]);
      Inc(I);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function HexVal(const pC: Char): Integer;
begin
  case pC of
    '0'..'9': Result:= Ord(pC) - Ord('0');
    'a'..'f': Result:= Ord(pC) - Ord('a') + HEX_LETTER_BASE;
    'A'..'F': Result:= Ord(pC) - Ord('A') + HEX_LETTER_BASE;
  else
    Result:= -1;
  end;
end;

function UnescapeDataString(const pText: string): string;
var
  Bytes: TBytes;
begin
  if not pText.Contains('%') then
    Exit(pText);
  var SB:= TStringBuilder.Create;
  try
    var I:= 1;
    while I <= Length(pText) do
    begin
      Bytes:= nil;
      while (I + 2 <= Length(pText)) and (pText[I] = '%') and (HexVal(pText[I + 1]) >= 0) and (HexVal(pText[I + 2]) >= 0) do
      begin
        Bytes:= Bytes + [Byte(HexVal(pText[I + 1]) * HEX_BASE + HexVal(pText[I + 2]))];
        Inc(I, ESCAPE_LEN);
      end;
      if Length(Bytes) > 0 then
      begin
        SB.Append(TEncoding.UTF8.GetString(Bytes));
        Continue;
      end;
      SB.Append(pText[I]);
      Inc(I);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function Scrub(const pS: string): string;
begin
  Result:= TRegEx.Replace(pS, RE_NOT_PRINTABLE, ' ');
end;

{ What a '+N more' line says about raising the cap, from the regenerate command }
function CapHow(const pRegenerate: string): string;
begin
  var Cm:= TRegEx.Match(pRegenerate, RE_CAP_ARG);
  if Cm.Success then
    Result:= Format(' (-%s %s; raise -%s to see them)',
      [Cm.Groups[G_CAP_NAME].Value, Cm.Groups[G_CAP_VALUE].Value, Cm.Groups[G_CAP_NAME].Value])
  else
    Result:= ' (raise -Cap to see them)';
end;

function DotAnswerRows(const pDotLines: TArray<string>; const pRegenerate: string; pMaxRows: Integer;
  const pDotPath, pShellPath: string): TArray<string>;
begin
  { ordinal Contains, as List[string].Contains: TStringList.IndexOf would compare with AnsiCompareStr }
  var Rows:= TList<string>.Create;
  var Targets:= TList<string>.Create;
  var NotShown:= TList<string>.Create;
  try
    var InFocus:= False;
    for var DL in pDotLines do
    begin
      if TRegEx.IsMatch(DL, RE_FOCUS_OPEN, [roIgnoreCase]) then InFocus:= True
      else if TRegEx.IsMatch(DL, RE_CLUSTER_CLOSE) then InFocus:= False;
      for var M in TRegEx.Matches(DL, RE_PLAIN_TD) do
      begin
        var Txt:= Scrub(TrimWs(HtmlDecode(TRegEx.Replace(M.Groups[G_INNER].Value, RE_TAG, ''))));
        if not TRegEx.IsMatch(Txt, RE_NOT_SHOWN, [roIgnoreCase]) then
          Continue;
        var Shown:= if TRegEx.IsMatch(Txt, RE_MORE, [roIgnoreCase]) then Txt + CapHow(pRegenerate) else Txt;
        if not NotShown.Contains(Shown) then
          NotShown.Add(Shown);
      end;
      for var M in TRegEx.Matches(DL, RE_ANCHORED_TD) do
      begin
        var Tip:= TrimWs(HtmlDecode(M.Groups[G_TIP].Value));
        var Font:= TRegEx.Match(M.Groups[G_BODY].Value, RE_FIRST_FONT);
        var LabelText:= if Font.Success then Font.Groups[G_INNER].Value else '';
        LabelText:= TrimWs(HtmlDecode(TRegEx.Replace(LabelText, RE_TAG, '')));
        var Note:= '';
        var Name: string;
        if TRegEx.IsMatch(Tip, RE_TIP_SEP) then
          Name:= TrimWs(Copy(Tip, 1, TRegEx.Match(Tip, RE_TIP_SPLIT).Index - 1))
        else if (Tip <> '') and not TRegEx.IsMatch(Tip, RE_WHITESPACE) then
          Name:= Tip
        else
        begin
          Name:= LabelText;
          Note:= Tip;
        end;
        var Leaf:= FileNameOf(UnescapeDataString(M.Groups[G_FILE].Value));
        var Line:= StrToIntDef(M.Groups[G_LINE].Value, 0);
        var Row:= if Line > 0 then Format('%s @%s:%s', [Name, Leaf, M.Groups[G_LINE].Value]) else Name + ' @' + Leaf;
        if Note <> '' then
          Row:= Row + ' -- ' + Note;
        Row:= Scrub(Row);
        if InFocus then
        begin
          if not Targets.Contains(Row) then Targets.Add(Row);
        end
        else if not Rows.Contains(Row) then
          Rows.Add(Row);
      end;
    end;
    Result:= [];
    for var T in Targets do
      Result:= Result + [ROW_INDENT + 'TARGET ' + T];
    if Rows.Count = 0 then
      Result:= Result + [ROW_INDENT + '(no anchored result rows -- open ' + pShellPath + ')'];
    for var K:= 0 to Rows.Count - 1 do
      if K < pMaxRows then
        Result:= Result + [ROW_INDENT + Rows[K]];
    for var T in NotShown do
      Result:= Result + [ROW_INDENT + '... ' + T];
    if Rows.Count > pMaxRows then
      Result:= Result + [Format('%s... %d more row(s) not printed here (-MaxRows %d): %s',
        [ROW_INDENT, Rows.Count - pMaxRows, pMaxRows, pDotPath])];
  finally
    NotShown.Free;
    Targets.Free;
    Rows.Free;
  end;
end;

{ New-DiagramArtifact's regenerate command for the ported (one-index) questions }
function RegenerateText(const pArgs: TQuestionArgs): string;
begin
  Result:= Format('New-DiagramArtifact.ps1 -Question %s -Target %s -DbPath "%s"', [pArgs.Question, pArgs.Target, pArgs.DbPath]);
  if InList(pArgs.Question, REGEN_DEPTH) then
    Result:= Result + ' -Depth ' + IntToStr(pArgs.Depth);
  if InList(pArgs.Question, REGEN_CAP) then
    Result:= Result + ' -Cap ' + IntToStr(pArgs.Cap);
  if SameText(pArgs.Question, 'class-surface') then
    Result:= Result + ' -SurfaceCap ' + IntToStr(pArgs.SurfaceCap);
  if SameText(pArgs.Question, 'event-wiring') and (pArgs.Command.Get('Control') <> '') then
    Result:= Result + ' -Control ' + pArgs.Command.Get('Control');
  if SameText(pArgs.Question, PATH_QUESTION) then
    Result:= Result + ' -To ' + pArgs.Command.Get('To');
end;

function JsonPair(const pIndent, pName, pJson: string; pLast: Boolean): string;
begin
  Result:= pIndent + PsJsonString(pName) + ': ' + pJson + (if pLast then '' else ',') + CRLF;
end;

function MetaJson(const pArgs: TQuestionArgs; const pChart: TChartResult; const pLeftLabel, pRightLabel,
  pGenerated, pRegenerate: string): string;
const
  IND = '  ';
  IND2 = '    ';
begin
  var Size:= TFile.GetSize(pArgs.DbPath);  { raises for a missing index, as Get-Item does }
  var Mtime:= FormatDateTime(ISO_UTC, TFile.GetLastWriteTimeUtc(pArgs.DbPath));
  var SB:= TStringBuilder.Create;
  try
    SB.Append('{').Append(CRLF);
    SB.Append(JsonPair(IND, 'question', PsJsonString(pArgs.Question), False));
    SB.Append(JsonPair(IND, 'qname', PsJsonString(pArgs.Target), False));
    SB.Append(JsonPair(IND, 'depth', IntToStr(pArgs.Depth), False));
    SB.Append(JsonPair(IND, 'index', PsJsonString(ExpandFileName(pArgs.DbPath)), False));
    SB.Append(JsonPair(IND, 'indexBytes', IntToStr(Size), False));
    SB.Append(JsonPair(IND, 'indexMtime', PsJsonString(Mtime), False));
    SB.Append(JsonPair(IND, 'generated', PsJsonString(pGenerated), False));
    SB.Append(JsonPair(IND, 'leftLabel', PsJsonString(pLeftLabel), False));
    SB.Append(JsonPair(IND, 'leftCount', if pChart.LeftJson <> '' then pChart.LeftJson else IntToStr(pChart.LeftCount), False));
    SB.Append(JsonPair(IND, 'rightLabel', PsJsonString(pRightLabel), False));
    SB.Append(JsonPair(IND, 'rightCount', if pChart.RightJson <> '' then pChart.RightJson else IntToStr(pChart.RightCount), False));
    SB.Append(JsonPair(IND, 'testChart', 'false', False));
    SB.Append(JsonPair(IND, 'clickTargets', IntToStr(pChart.ClickTargets), False));
    SB.Append(JsonPair(IND, 'allClickable', if pChart.AllClickable then 'true' else 'false', False));
    SB.Append(JsonPair(IND, 'regenerate', PsJsonString(pRegenerate), False));
    if Length(pChart.Fields) = 0 then
      SB.Append(IND).Append('"emitter": {}').Append(CRLF)
    else
    begin
      SB.Append(IND).Append('"emitter": {').Append(CRLF);
      for var K:= 0 to High(pChart.Fields) do
        SB.Append(JsonPair(IND2, pChart.Fields[K].Name, pChart.Fields[K].Json, K = High(pChart.Fields)));
      SB.Append(IND).Append('}').Append(CRLF);
    end;
    SB.Append('}').Append(CRLF);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function ToCrlf(const pS: string): string;
begin
  Result:= pS.Replace(CRLF, LF).Replace(LF, CRLF);
end;

function ShellHtml(const pArgs: TQuestionArgs; const pChart: TChartResult; const pLeftLabel, pRightLabel,
  pGenerated, pSvgPath: string): string;
begin
  var Svg:= TRegEx.Replace(TFile.ReadAllText(pSvgPath, TEncoding.UTF8), RE_SVG_PROLOG, '');
  var Short:= if SameText(pArgs.Question, PATH_QUESTION) then pArgs.Target + ' -&gt; ' + pArgs.Command.Get('To') else pArgs.Target;
  Result:= HTML_TEMPLATE
    .Replace('@@QUESTION@@', pArgs.Question)
    .Replace('@@SHORT@@', Short)
    .Replace('@@LEFTCOUNT@@', IntToStr(pChart.LeftCount))
    .Replace('@@LEFTLABEL@@', pLeftLabel)
    .Replace('@@RIGHTCOUNT@@', IntToStr(pChart.RightCount))
    .Replace('@@RIGHTLABEL@@', pRightLabel)
    .Replace('@@ANCHORSPAN@@', Format(ANCHOR_SPAN, [pChart.ClickTargets]))
    .Replace('@@INDEXNAME@@', FileNameOf(pArgs.DbPath))
    .Replace('@@GENERATED@@', pGenerated)
    .Replace('@@FOOTFILES@@', FOOT_FILES)
    .Replace('@@NOTE@@', NOTE_CHART)
    .Replace('@@SVG@@', Svg);
  Result:= ToCrlf(Result);
end;

function XrefText(const pArgs: TQuestionArgs; const pShellPath, pGenerated, pRegenerate: string): string;
begin
  var Diagram:= pArgs.Question + ' of ' + pArgs.Target;
  if SameText(pArgs.Question, PATH_QUESTION) then
    Diagram:= Diagram + ' to ' + pArgs.Command.Get('To');
  Result:= '/// <remarks>' + CRLF +
    '/// Diagram: ' + Diagram + CRLF +
    '/// Artifact: ' + pShellPath + CRLF +
    '/// Generated: ' + pGenerated + ' from ' + FileNameOf(pArgs.DbPath) + CRLF +
    '/// Regenerate: ' + pRegenerate + CRLF +
    '/// The artifact is REGENERATED, not edited. This comment names a stable path' + CRLF +
    '/// so it never needs rewriting when the diagram changes.' + CRLF +
    '/// </remarks>';
end;

{ Move-Item -Force: one replacing move, the OS error raised as is }
procedure MoveOver(const pFrom, pTo: string);
begin
  if (pFrom = '') or not TFile.Exists(pFrom) then
    Exit;
  if not MoveFileEx(PChar(pFrom), PChar(pTo), MOVEFILE_REPLACE_EXISTING or MOVEFILE_COPY_ALLOWED) then
    RaiseLastOSError;
end;

function IsEmptyDir(const pDir: string): Boolean;
begin
  Result:= Length(TDirectory.GetFileSystemEntries(pDir)) = 0;
end;

{ Runs the emitter with the clone-guard override Ask-Report sets around the bundler,
  restoring the variable exactly (absent stays absent). }
function RunEmitter(const pEmitter: TChartEmitter; const pArgs: TQuestionArgs; const pDir: string): TChartResult;
begin
  if not pArgs.AllowLiveDb then
    Exit(pEmitter(pArgs, pDir));
  var Had:= GetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR) <> '';
  var Prev:= GetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR);
  Winapi.Windows.SetEnvironmentVariable(PChar(ALLOW_LIVE_DB_ENV_VAR), PChar('1'));
  try
    Result:= pEmitter(pArgs, pDir);
  finally
    if Had then
      Winapi.Windows.SetEnvironmentVariable(PChar(ALLOW_LIVE_DB_ENV_VAR), PChar(Prev))
    else
      Winapi.Windows.SetEnvironmentVariable(PChar(ALLOW_LIVE_DB_ENV_VAR), nil);
  end;
end;

function AskChartQuestion(const pArgs: TQuestionArgs): TAskAnswer;
var
  Emitter: TChartEmitter;
  Chart  : TChartResult;
  LeftLabel, RightLabel: string;
begin
  if not FindChartQuestion(pArgs.Question, Emitter) then
    raise EChartsQuestion.CreateFmt('%s is not ported to Delphi', [pArgs.Question]);
  QuestionVocab(pArgs.Question, LeftLabel, RightLabel);
  var Dir:= TPath.Combine(pArgs.OutRoot, pArgs.Question + '-' + BundleSlug(pArgs.Target));
  var DirWasNew:= not TDirectory.Exists(Dir);
  ForceDirectories(Dir);
  try
    Chart:= RunEmitter(Emitter, pArgs, Dir);
  except  // dl:ok bare-except@1755 -- REVIEWED 2026-10-13: removes the bundle folder this call made when it is still empty, then re-raises; the refusal is the answer
    if DirWasNew and TDirectory.Exists(Dir) and IsEmptyDir(Dir) then
      TDirectory.Delete(Dir);
    raise;
  end;
  MoveOver(Chart.Layout.Svg, TPath.Combine(Dir, GRAPH_SVG));
  MoveOver(Chart.Layout.Plain, TPath.Combine(Dir, GRAPH_PLAIN));
  MoveOver(Chart.Layout.Dot, TPath.Combine(Dir, GRAPH_DOT));
  MoveOver(Chart.Layout.Png, TPath.Combine(Dir, GRAPH_PNG));
  MoveOver(Chart.Layout.Pdf, TPath.Combine(Dir, GRAPH_PDF));

  var Generated:= FormatDateTime(ISO_UTC, TTimeZone.Local.ToUniversalTime(Now));
  var Regenerate:= RegenerateText(pArgs);
  TFile.WriteAllText(TPath.Combine(Dir, META_JSON), MetaJson(pArgs, Chart, LeftLabel, RightLabel, Generated, Regenerate),
    TEncoding.ASCII);
  var SvgPath:= TPath.Combine(Dir, GRAPH_SVG);
  if not TFile.Exists(SvgPath) then
    raise EChartsQuestion.CreateFmt('%s drew no chart: %s is missing', [pArgs.Question, SvgPath]);
  var ShellPath:= ExpandFileName(TPath.Combine(Dir, SHELL_HTML));
  TFile.WriteAllBytes(ShellPath, TEncoding.UTF8.GetBytes(ShellHtml(pArgs, Chart, LeftLabel, RightLabel, Generated, SvgPath)));
  TFile.WriteAllBytes(TPath.Combine(Dir, XREF_TXT), TEncoding.ASCII.GetBytes(XrefText(pArgs, ShellPath, Generated, Regenerate)));

  var ToRoutine:= pArgs.Command.Get('To');
  var SentTarget:= if ToRoutine <> '' then pArgs.Target + ' -> ' + ToRoutine else pArgs.Target;
  var Lines: TArray<string>:= [
    Format('%s (drag-lint report %s) for %s, asked on %s, engine %s.', [QuestionPhrase(pArgs.Question), pArgs.Question,
      SentTarget, FormatDateTime(ASKED_ON, pArgs.AskedOn), pArgs.EngineVersion]),
    ReportCommandText(pArgs.Command),
    'BUNDLE ' + Dir,
    'INDEX ' + pArgs.DbPath,
    Format('CHART %s %s -- %d %s / %d %s', [pArgs.Question, SentTarget, Chart.LeftCount, LeftLabel, Chart.RightCount, RightLabel])];
  var DotPath:= TPath.Combine(Dir, GRAPH_DOT);
  var DotLines: TArray<string>:= [];
  if TFile.Exists(DotPath) then
    DotLines:= TFile.ReadAllLines(DotPath, TEncoding.UTF8);
  Result.Lines:= Lines + DotAnswerRows(DotLines, Regenerate, pArgs.MaxRows, DotPath, ShellPath);
  Result.BundleDir:= Dir;
end;

end.
