unit DRagLint.Charts.ReportHeader;

{ The header contract of a dl-charts answer (spec H1-H4): the sentence line
    <Phrase> (drag-lint report <id>) for <target>, asked on <yyyy-MM-dd HH:mm>, engine <v>.
  and the COMMAND line that names the exact question that produced it
    COMMAND <id> [-Target "v"] [-To "v"] (-Project "v" | -In "v") [-Depth n] ...
  in both the plain form (Ask-Report.ps1 -Plain) and the DocInsight form
  (DRagLint.Charts.DocInsight, `drag-lint ask`), plus the legacy header that has no time, engine
  or COMMAND. Pure string work: no IO, no VCL, no engine dependency. }

interface

type
  /// <summary>Which shape an answer's lines are in.</summary>
  TReportForm = (rfUnknown, rfPlain, rfDocInsight);

  /// <summary>One argument of a COMMAND line.</summary>
  TCommandArg = record
    /// <summary>Argument name WITHOUT the leading '-', as written.</summary>
    Name : string;
    /// <summary>Argument value, quotes removed; '' for a name with no value.</summary>
    Value: string;
  end;

  /// <summary>A parsed COMMAND line: the question id and its explicit arguments.</summary>
  /// <remarks>Names compare case-insensitively (SameText). PS trap handled: PowerShell
  /// parameter names and -eq are case-insensitive, so '-target' and '-Target' are one
  /// argument here too. Args never holds two entries with the same name.</remarks>
  TReportCommand = record
    /// <summary>The question id (first token), e.g. 'who-writes'.</summary>
    Question: string;
    /// <summary>The arguments in the order they were written.</summary>
    Args    : TArray<TCommandArg>;
    /// <summary>Whether an argument of this name is present.</summary>
    /// <param name="pName">Name without '-'; compared with SameText.</param>
    /// <returns>True when present (even with an empty value).</returns>
    function Has(const pName: string): Boolean;
    /// <summary>The value of the named argument.</summary>
    /// <param name="pName">Name without '-'; compared with SameText.</param>
    /// <returns>The value, or '' when the argument is absent.</returns>
    function Get(const pName: string): string;
    /// <summary>Whether this is the empty command (no question).</summary>
    /// <returns>True when Question is ''.</returns>
    function IsEmpty: Boolean;
  end;

  /// <summary>The parsed header of an answer.</summary>
  /// <remarks>A legacy header (no time, engine or COMMAND) parses with AskedOn as a date
  /// only, EngineVersion '' and an empty Command.</remarks>
  TReportHeader = record
    /// <summary>Plain or DocInsight.</summary>
    Form         : TReportForm;
    /// <summary>The caption phrase before ' (drag-lint report ...)'.</summary>
    Phrase       : string;
    /// <summary>The question id inside the parentheses.</summary>
    QuestionId   : string;
    /// <summary>The target; 'A -> B' for the path question.</summary>
    Target       : string;
    /// <summary>'yyyy-MM-dd' or 'yyyy-MM-dd HH:mm', exactly as written.</summary>
    AskedOn      : string;
    /// <summary>The engine version; '' on a legacy header.</summary>
    EngineVersion: string;
    /// <summary>The COMMAND line; empty on a legacy header.</summary>
    Command      : TReportCommand;
    /// <summary>Physical lines consumed: the sentence, its continuation lines and the
    /// COMMAND line with its continuations. Leading blank lines and the DocInsight
    /// '&lt;remarks&gt;' line are NOT counted.</summary>
    HeaderLines  : Integer;
    /// <summary>Whether a COMMAND line was parsed.</summary>
    /// <returns>True when Command is not empty.</returns>
    function HasCommand: Boolean;
  end;

/// <summary>Parses the header at the top of an answer, plain or DocInsight.</summary>
/// <param name="pLines">The answer's lines, line ends removed; a stray trailing CR or
/// trailing spaces on a line are tolerated.</param>
/// <param name="pHeader">The header; Default(TReportHeader) when the result is False.</param>
/// <returns>False when the first non-blank line (after a DocInsight '&lt;remarks&gt;')
/// is not a header sentence.</returns>
/// <remarks>DocInsight continuation lines (body indented two spaces more than the line
/// they continue) are joined with a single space, for the sentence and for the COMMAND
/// line alike (a wiki or mail client may re-wrap the COMMAND line). The DocInsight
/// COMMAND line is XML-unescaped before parsing. A COMMAND line that does not parse
/// leaves Command empty and is not counted in HeaderLines. Pure; thread-safe.</remarks>
function ParseReportHeader(const pLines: TArray<string>; out pHeader: TReportHeader): Boolean;

/// <summary>Parses a COMMAND line.</summary>
/// <param name="pText">The line, with or without the 'COMMAND ' prefix (ordinal).</param>
/// <param name="pCmd">The command; empty when the result is False.</param>
/// <returns>False when there is no question token.</returns>
/// <remarks>Tokens split on spaces outside double quotes; quotes are removed and have no
/// escape. An unquoted token of '-' followed by a letter is a name; its value is the next
/// token unless that is itself a name (value ''). A quoted token is always a value, and
/// '-3' is a value. A repeated name keeps its first position and takes the last value; a
/// value with no name before it is ignored.</remarks>
function ParseCommandLine(const pText: string; out pCmd: TReportCommand): Boolean;

/// <summary>Builds the canonical COMMAND line, WITHOUT the 'COMMAND ' prefix.</summary>
/// <param name="pCmd">The command.</param>
/// <returns>The question id, then the known arguments in the order Target, To, Project,
/// In, Depth, Cap, SurfaceCap, Control, Mode, MaxRows with their canonical spelling, then
/// unknown arguments in input order with their own spelling.</returns>
/// <remarks>Target, To, Project, In and Control are always double-quoted; the other known
/// values are bare. An unknown value is quoted when it holds a space or starts with '-'
/// (so it re-parses as a value); an unknown name with an empty value is written alone.
/// Values never contain '"' (IsValidReportTarget), so no escaping is done.</remarks>
function BuildCommandLine(const pCmd: TReportCommand): string;

/// <summary>Whether two commands ask the same question (H4).</summary>
/// <param name="pA">The old answer's command.</param>
/// <param name="pB">The new answer's command.</param>
/// <param name="pDiffering">One 'Name: a vs b' per differing argument, '(absent)' for a
/// missing side, sorted by name (case-insensitive); known names in canonical spelling.
/// Question ids are compared but never listed here.</param>
/// <returns>True when the ids are equal (SameText) and every argument matches.</returns>
/// <remarks>Order and quoting never matter. Names compare case-insensitively; two values
/// that both parse as integers compare numerically ('03' = '3'), any other pair with
/// SameText (targets are Delphi identifiers, projects are Windows paths). An explicit
/// argument against an absent one IS a difference. PS trap handled: PowerShell -eq is
/// case-insensitive and coerces '03' -eq 3; both behaviours are kept.</remarks>
function SameQuestion(const pA, pB: TReportCommand; out pDiffering: TArray<string>): Boolean;

/// <summary>Strips a DocInsight '///' prefix.</summary>
/// <param name="pLine">A source line; leading whitespace before '///' is allowed.</param>
/// <param name="pBody">The text after '///' and ONE following space, trailing whitespace
/// removed; continuation indentation is kept ('///   x' gives '  x').</param>
/// <returns>False (pBody '') for a line that is not a '///' comment ('////' is not).</returns>
function StripDocPrefix(const pLine: string; out pBody: string): Boolean;

/// <summary>Reverses the XML escaping of a DocInsight line.</summary>
/// <param name="pText">Escaped text.</param>
/// <returns>pText with &amp;lt; &amp;gt; &amp;amp; &amp;quot; decoded in one left-to-right
/// pass ('&amp;amp;lt;' gives '&amp;lt;'); any other '&amp;' is kept as is.</returns>
function XmlUnescape(const pText: string): string;

implementation

uses
  System.SysUtils, System.Character, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions;

const
  NOT_FOUND = -1;
  DOC_PREFIX = '///';
  COMMAND_PREFIX = 'COMMAND ';
  REMARKS_OPEN = '<remarks>';
  ABSENT = '(absent)';
  QUOTE = '"';
  NAME_MARK = '-';
  /// EmitWrapped indents a continuation line two spaces more than the line it continues.
  CONTINUATION_INDENT = 2;
  SENTENCE_PATTERN = '^(.*?) \(drag-lint report ([a-z0-9-]+)\) for (.+?), asked on ' +
    '(\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2})?)(?:, engine (\S+?))?\.$';
  GROUP_PHRASE = 1;
  GROUP_ID = 2;
  GROUP_TARGET = 3;
  GROUP_ASKED = 4;
  GROUP_ENGINE = 5;
  /// Canonical order and spelling of the COMMAND arguments (header contract).
  KNOWN_NAMES: array[0..9] of string = ('Target', 'To', 'Project', 'In', 'Depth', 'Cap',
    'SurfaceCap', 'Control', 'Mode', 'MaxRows');
  /// The known arguments whose value is always double-quoted.
  QUOTED_NAMES: array[0..4] of string = ('Target', 'To', 'Project', 'In', 'Control');
  ENTITIES: array[0..3] of string = ('&lt;', '&gt;', '&amp;', '&quot;');
  ENTITY_CHARS: array[0..3] of Char = ('<', '>', '&', '"');

type
  TToken = record
    Text  : string;
    Quoted: Boolean;
  end;

function IndexOfName(const pNames: array of string; const pName: string): Integer;
begin
  for var I:= Low(pNames) to High(pNames) do
    if SameText(pNames[I], pName) then
      Exit(I);
  Result:= NOT_FOUND;
end;

{ PS trap handled: hashtable keys and parameter names are case-insensitive in PowerShell,
  so the lookup is SameText, never '='. }
function ArgIndex(const pArgs: TArray<TCommandArg>; const pName: string): Integer;
begin
  for var I:= 0 to High(pArgs) do
    if SameText(pArgs[I].Name, pName) then
      Exit(I);
  Result:= NOT_FOUND;
end;

function DisplayName(const pName: string): string;
begin
  var K:= IndexOfName(KNOWN_NAMES, pName);
  Result:= if K = NOT_FOUND then pName else KNOWN_NAMES[K];
end;

function LeadingSpaces(const pText: string): Integer;
begin
  Result:= 0;
  while (Result < Length(pText)) and (pText[Result + 1] = ' ') do
    Inc(Result);
end;

function LooksLikeName(const pText: string): Boolean;
begin
  Result:= (Length(pText) >= 2) and (pText[1] = NAME_MARK) and pText[2].IsLetter;
end;

function IsName(const pToken: TToken): Boolean;
begin
  Result:= not pToken.Quoted and LooksLikeName(pToken.Text);
end;

{ A value that would not re-parse as one value when written bare. }
function NeedsQuotes(const pValue: string): Boolean;
begin
  Result:= pValue.Contains(' ') or LooksLikeName(pValue);
end;

function Tokenise(const pText: string): TArray<TToken>;
var
  List   : TList<TToken>;
  Current: TToken;
  Started: Boolean;

  procedure Flush;
  begin
    if Started then
      List.Add(Current);
    Current:= Default(TToken);
    Started:= False;
  end;

begin
  List:= TList<TToken>.Create;
  try
    Current:= Default(TToken);
    Started:= False;
    var InQuote:= False;
    for var C in pText do
      if C = QUOTE then
      begin
        InQuote:= not InQuote;
        Current.Quoted:= True;
        Started:= True;
      end
      else if ((C = ' ') or (C = #9)) and not InQuote then
        Flush
      else
      begin
        Current.Text:= Current.Text + C;
        Started:= True;
      end;
    Flush;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

function ValuesMatch(const pA, pB: string): Boolean;
begin
  var IA, IB: Integer;
  // PS trap handled: '03' -eq 3 is True in PowerShell; two integers compare numerically.
  if TryStrToInt(pA, IA) and TryStrToInt(pB, IB) then
    Result:= IA = IB
  else
    Result:= SameText(pA, pB);
end;

function BodyAt(const pLines: TArray<string>; pIndex: Integer; pForm: TReportForm;
  out pBody: string): Boolean;
begin
  pBody:= '';
  if (pIndex < 0) or (pIndex >= Length(pLines)) then
    Exit(False);
  if pForm = rfDocInsight then
    Exit(StripDocPrefix(pLines[pIndex], pBody));
  pBody:= pLines[pIndex].TrimRight;
  Result:= True;
end;

function IsContinuation(const pBody: string; pBaseIndent: Integer): Boolean;
begin
  Result:= (pBody.Trim <> '') and (LeadingSpaces(pBody) >= pBaseIndent + CONTINUATION_INDENT);
end;

{ TReportCommand }

function TReportCommand.Has(const pName: string): Boolean;
begin
  Result:= ArgIndex(Args, pName) <> NOT_FOUND;
end;

function TReportCommand.Get(const pName: string): string;
begin
  var I:= ArgIndex(Args, pName);
  Result:= if I = NOT_FOUND then '' else Args[I].Value;
end;

function TReportCommand.IsEmpty: Boolean;
begin
  Result:= Question = '';
end;

{ TReportHeader }

function TReportHeader.HasCommand: Boolean;
begin
  Result:= not Command.IsEmpty;
end;

{ functions }

function StripDocPrefix(const pLine: string; out pBody: string): Boolean;
begin
  pBody:= '';
  var S:= pLine.TrimLeft;
  Result:= S.StartsWith(DOC_PREFIX) and not S.StartsWith(DOC_PREFIX + '/');
  if not Result then
    Exit;
  // TrimRight also drops the CR a CRLF file leaves when split on LF alone.
  S:= S.Substring(Length(DOC_PREFIX)).TrimRight;
  pBody:= if S.StartsWith(' ') then S.Substring(1) else S;
end;

function XmlUnescape(const pText: string): string;
begin
  var SB:= TStringBuilder.Create(Length(pText));
  try
    var I:= 1;
    while I <= Length(pText) do
    begin
      var Matched:= False;
      if pText[I] = '&' then
        for var K:= Low(ENTITIES) to High(ENTITIES) do
          if Copy(pText, I, Length(ENTITIES[K])) = ENTITIES[K] then
          begin
            SB.Append(ENTITY_CHARS[K]);
            Inc(I, Length(ENTITIES[K]));
            Matched:= True;
            Break;
          end;
      if not Matched then
      begin
        SB.Append(pText[I]);
        Inc(I);
      end;
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function ParseCommandLine(const pText: string; out pCmd: TReportCommand): Boolean;
begin
  pCmd:= Default(TReportCommand);
  var S:= pText.Trim;
  if S.StartsWith(COMMAND_PREFIX) then
    S:= S.Substring(Length(COMMAND_PREFIX))
  else if S = COMMAND_PREFIX.TrimRight then
    S:= '';
  var Tokens:= Tokenise(S);
  if (Length(Tokens) = 0) or IsName(Tokens[0]) or (Tokens[0].Text = '') then
    Exit(False);
  pCmd.Question:= Tokens[0].Text;
  var Args:= TList<TCommandArg>.Create;
  try
    var I:= 1;
    while I < Length(Tokens) do
    begin
      if IsName(Tokens[I]) then
      begin
        var Arg: TCommandArg;
        Arg.Name:= Tokens[I].Text.Substring(1);
        Arg.Value:= '';
        if (I + 1 < Length(Tokens)) and not IsName(Tokens[I + 1]) then
        begin
          Arg.Value:= Tokens[I + 1].Text;
          Inc(I);
        end;
        var Existing:= ArgIndex(Args.ToArray, Arg.Name);
        if Existing = NOT_FOUND then
          Args.Add(Arg)
        else
        begin
          Arg.Name:= Args[Existing].Name;
          Args[Existing]:= Arg;
        end;
      end;
      Inc(I);
    end;
    pCmd.Args:= Args.ToArray;
  finally
    Args.Free;
  end;
  Result:= True;
end;

function BuildCommandLine(const pCmd: TReportCommand): string;
begin
  var SB:= TStringBuilder.Create(pCmd.Question);
  try
    for var Known in KNOWN_NAMES do
      if pCmd.Has(Known) then
      begin
        var V:= pCmd.Get(Known);
        SB.Append(' ').Append(NAME_MARK).Append(Known);
        if (IndexOfName(QUOTED_NAMES, Known) <> NOT_FOUND) or NeedsQuotes(V) then
          SB.Append(' ').Append(QUOTE).Append(V).Append(QUOTE)
        else if V <> '' then
          SB.Append(' ').Append(V);
      end;
    for var Arg in pCmd.Args do
      if IndexOfName(KNOWN_NAMES, Arg.Name) = NOT_FOUND then
      begin
        SB.Append(' ').Append(NAME_MARK).Append(Arg.Name);
        if NeedsQuotes(Arg.Value) then
          SB.Append(' ').Append(QUOTE).Append(Arg.Value).Append(QUOTE)
        else if Arg.Value <> '' then
          SB.Append(' ').Append(Arg.Value);
      end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function SameQuestion(const pA, pB: TReportCommand; out pDiffering: TArray<string>): Boolean;
begin
  pDiffering:= nil;
  var InA: TDictionary<string, string>:= nil;
  var InB: TDictionary<string, string>:= nil;
  var Names: TList<string>:= nil;
  var Diff: TList<string>:= nil;
  try
    // PS trap handled: hashtable keys are case-insensitive, so the maps and the name list are too.
    InA:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
    InB:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
    Names:= TList<string>.Create(TIStringComparer.Ordinal);
    Diff:= TList<string>.Create;
    for var Arg in pA.Args do
    begin
      InA.AddOrSetValue(Arg.Name, Arg.Value);
      if not Names.Contains(Arg.Name) then
        Names.Add(Arg.Name);
    end;
    for var Arg in pB.Args do
    begin
      InB.AddOrSetValue(Arg.Name, Arg.Value);
      if not Names.Contains(Arg.Name) then
        Names.Add(Arg.Name);
    end;
    Names.Sort;
    for var N in Names do
    begin
      var VA, VB: string;
      var HasA:= InA.TryGetValue(N, VA);
      var HasB:= InB.TryGetValue(N, VB);
      if HasA and HasB and ValuesMatch(VA, VB) then
        Continue;
      Diff.Add(DisplayName(N) + ': ' + (if HasA then VA else ABSENT) + ' vs ' + (if HasB then VB else ABSENT));
    end;
    pDiffering:= Diff.ToArray;
    Result:= SameText(pA.Question, pB.Question) and (Diff.Count = 0);
  finally
    Diff.Free;
    Names.Free;
    InB.Free;
    InA.Free;
  end;
end;

function ParseReportHeader(const pLines: TArray<string>; out pHeader: TReportHeader): Boolean;
begin
  pHeader:= Default(TReportHeader);
  Result:= False;
  var I:= 0;
  while (I < Length(pLines)) and (pLines[I].Trim = '') do
    Inc(I);
  if I >= Length(pLines) then
    Exit;
  var Body: string;
  var Form:= if StripDocPrefix(pLines[I], Body) then rfDocInsight else rfPlain;
  if (Form = rfDocInsight) and (Body.Trim = REMARKS_OPEN) then
    Inc(I);
  var First:= I;
  if not BodyAt(pLines, I, Form, Body) then
    Exit;
  var Indent:= LeadingSpaces(Body);
  var Sentence:= Body.Trim;
  Inc(I);
  while (Form = rfDocInsight) and not Sentence.EndsWith('.') and BodyAt(pLines, I, Form, Body)
    and IsContinuation(Body, Indent) do
  begin
    Sentence:= Sentence + ' ' + Body.Trim;
    Inc(I);
  end;
  var M:= TRegEx.Match(Sentence, SENTENCE_PATTERN);
  if not M.Success then
    Exit;
  pHeader.Form:= Form;
  pHeader.Phrase:= M.Groups[GROUP_PHRASE].Value;
  pHeader.QuestionId:= M.Groups[GROUP_ID].Value;
  pHeader.Target:= M.Groups[GROUP_TARGET].Value;
  pHeader.AskedOn:= M.Groups[GROUP_ASKED].Value;
  // A trailing optional group that did not take part is missing from Groups, not empty.
  pHeader.EngineVersion:= if M.Groups.Count > GROUP_ENGINE then M.Groups[GROUP_ENGINE].Value else '';
  pHeader.HeaderLines:= I - First;
  if BodyAt(pLines, I, Form, Body) and Body.StartsWith(COMMAND_PREFIX) then
  begin
    var Text:= Body;
    var J:= I + 1;
    while (Form = rfDocInsight) and BodyAt(pLines, J, Form, Body) and IsContinuation(Body, 0) do
    begin
      Text:= Text + ' ' + Body.Trim;
      Inc(J);
    end;
    if Form = rfDocInsight then
      Text:= XmlUnescape(Text);
    var Cmd: TReportCommand;
    if ParseCommandLine(Text, Cmd) then
    begin
      pHeader.Command:= Cmd;
      Inc(pHeader.HeaderLines, J - I);
    end;
  end;
  Result:= True;
end;

end.
