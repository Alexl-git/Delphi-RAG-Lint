unit DRagLint.Charts.ReportHeader;

{ The header contract of a dl-charts answer (spec H1-H4): the sentence line
    <Phrase> (drag-lint report <id>) for <target>, asked on <yyyy-MM-dd HH:mm>, engine <v>.
  and the COMMAND line that names the exact question that produced it
    COMMAND <id> [--target "v"] [--to "v"] (--project "v" | --in "v") [--depth n] ...
  (CLI style, what BuildCommandLine prints since 1.56; the PowerShell style written before it,
    COMMAND <id> [-Target "v"] [-To "v"] (-Project "v" | -In "v") [-Depth n] ...
  is still READ by ParseCommandLine, and both styles parse to the same TReportCommand)
  in both the plain form (Ask-Report.ps1 -Plain) and the DocInsight form
  (DRagLint.Charts.DocInsight, `drag-lint ask`), plus the legacy header that has no time, engine
  or COMMAND. Pure string work: no IO, no VCL, no engine dependency. }

interface

type
  /// <summary>Which shape an answer's lines are in.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.Adapter.Text.BuildLogical (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.Adapter.Text.DetectFormOf (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.Adapter.Text.ReportItems (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.Adapter.Text.ReportLogicalLines (DRagLint.Charts.Adapter.Text.pas) (+4 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TReportForm = (rfUnknown, rfPlain, rfDocInsight);

  /// <summary>One argument of a COMMAND line.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Charts.ReportHeader.pas), DRagLint.Charts.AskVerb.AddArg (DRagLint.Charts.AskVerb.pas), DRagLint.Charts.Compare.SetArg (DRagLint.Charts.Compare.pas), DRagLint.Charts.ReportHeader.ArgIndex (DRagLint.Charts.ReportHeader.pas), DRagLint.Charts.ReportHeader.ParseCommandLine (DRagLint.Charts.ReportHeader.pas)</para>
  /// <para>Used in units: DRagLint.Charts.AskVerb, DRagLint.Charts.Compare, DRagLint.Charts.ReportHeader</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCommandArg = record
    /// <summary>Argument name WITHOUT the leading '-' or '--'. A known argument carries its
    /// canonical spelling whatever style it was written in ('-target', '--target' and
    /// '-Target' all give 'Target'; '--surface-cap' gives 'SurfaceCap'); an unknown one is
    /// kept as written.</summary>
    Name : string;
    /// <summary>Argument value, quotes removed; '' for a name with no value.</summary>
    Value: string;
  end;

  /// <summary>A parsed COMMAND line: the question id and its explicit arguments.</summary>
  /// <remarks>
  /// Names compare case-insensitively and ignore '-' inside the name, so the
  /// PowerShell spelling and the CLI spelling of one argument are one name ('SurfaceCap' =
  /// 'surface-cap' = 'surfacecap'). PS trap handled: PowerShell parameter names and -eq are
  /// case-insensitive, so '-target' and '-Target' are one argument here too. Args never
  /// holds two entries with the same name.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Charts.AskVerb.AskCommandOf (DRagLint.Charts.AskVerb.pas), DRagLint.Charts.Compare.ChooseCommand (DRagLint.Charts.Compare.pas), DRagLint.Charts.Compare.ProduceNewSide (DRagLint.Charts.Compare.pas), DRagLint.Charts.ReportHeader.ParseCommandLine (DRagLint.Charts.ReportHeader.pas), DRagLint.CLI.Compare.CompareBuildCommand (DRagLint.CLI.Compare.pas) (+26 more)</para>
  /// <para>Used in units: DRagLint.Charts.Ask, DRagLint.Charts.AskVerb, DRagLint.Charts.Compare, DRagLint.Charts.Producer, DRagLint.Charts.Producer.Delphi, DRagLint.Charts.Question, DRagLint.Charts.Render, DRagLint.Charts.ReportHeader, DRagLint.CLI.Compare</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TReportCommand = record
    /// <summary>The question id (first token), e.g. 'who-writes'.</summary>
    Question: string;
    /// <summary>The arguments in the order they were written.</summary>
    Args    : TArray<TCommandArg>;
    /// <summary>Whether an argument of this name is present.</summary>
    /// <param name="pName">Name without the leading '-' / '--', in either spelling
    /// ('SurfaceCap' or 'surface-cap'); case and inner '-' are ignored.</param>
    /// <returns>True when present (even with an empty value).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Ask.ReportCommandText (DRagLint.Charts.Ask.pas), DRagLint.Charts.Compare.TargetWithTo (DRagLint.Charts.Compare.pas), DRagLint.Charts.Producer.Delphi.NumArg (DRagLint.Charts.Producer.Delphi.pas), DRagLint.Charts.ReportHeader.BuildCommandLine (DRagLint.Charts.ReportHeader.pas), DRagLint.CLI.Compare.CompareTargetOf (DRagLint.CLI.Compare.pas)</para>
    /// <para>Calls: DRagLint.Charts.ReportHeader.ArgIndex</para>
    /// <para>Returns: ArgIndex(Args, pName) &lt;&gt; NOT_FOUND</para>
    /// <para>Reads: Args</para>
    /// <seealso cref="DRagLint.Charts.ReportHeader.ArgIndex"/>
    /// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.Get"/>
    /// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.IsEmpty"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Has(const pName: string): Boolean;
    /// <summary>The value of the named argument.</summary>
    /// <param name="pName">Name without the leading '-' / '--', in either spelling
    /// ('SurfaceCap' or 'surface-cap'); case and inner '-' are ignored.</param>
    /// <returns>The value, or '' when the argument is absent.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Ask.AskChartQuestion (DRagLint.Charts.Ask.pas), DRagLint.Charts.Ask.MetaJson (DRagLint.Charts.Ask.pas), DRagLint.Charts.Ask.RegenerateText (DRagLint.Charts.Ask.pas), DRagLint.CLI.Compare.CompareIsSnapshotOnly (DRagLint.CLI.Compare.pas), DRagLint.CLI.Compare.CompareTargetOf (DRagLint.CLI.Compare.pas) (+14 more)</para>
    /// <para>Calls: DRagLint.Charts.ReportHeader.ArgIndex</para>
    /// <para>Returns: if I = NOT_FOUND then ''</para>
    /// <para>Reads: Args</para>
    /// <seealso cref="DRagLint.Charts.ReportHeader.ArgIndex"/>
    /// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.Has"/>
    /// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.IsEmpty"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Get(const pName: string): string;
    /// <summary>Whether this is the empty command (no question).</summary>
    /// <returns>True when Question is ''.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Compare.ChooseCommand (DRagLint.Charts.Compare.pas), DRagLint.Charts.Compare.LoadAutoSnapshotSide (DRagLint.Charts.Compare.pas), DRagLint.Charts.Compare.TakeGivenCommand (DRagLint.Charts.Compare.pas), DRagLint.CLI.Compare.CompareIsSnapshotOnly (DRagLint.CLI.Compare.pas), DRagLint.CLI.Compare.CompareUsageProblem (DRagLint.CLI.Compare.pas) (+2 more)</para>
    /// <para>Returns: Question = ''</para>
    /// <para>Reads: Question</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.Get"/>
    /// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.Has"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsEmpty: Boolean;
  end;

  /// <summary>Which argument style a COMMAND line is written in.</summary>
  /// <remarks>
  /// csNone: no argument name at all (or no question). csPowerShell: every name has
  /// ONE leading '-' (what the engine printed up to 1.55). csCli: every name has TWO
  /// (printed since 1.56). csMixed: both occur in one line -- nothing the engine ever
  /// printed, so a migration must leave such a line alone.
  /// </remarks>
  TCommandStyle = (csNone, csPowerShell, csCli, csMixed);

  /// <summary>The parsed header of an answer.</summary>
  /// <remarks>
  /// A legacy header (no time, engine or COMMAND) parses with AskedOn as a date
  /// only, EngineVersion '' and an empty Command.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Charts.Compare.pas) ?, declaration (DRagLint.Charts.Remarks.pas) ?, DRagLint.Charts.Adapter.Text.HeaderRange (DRagLint.Charts.Adapter.Text.pas) ?, DRagLint.Charts.Compare.HeaderOf (DRagLint.Charts.Compare.pas), DRagLint.Charts.ReportHeader.ParseReportHeader (DRagLint.Charts.ReportHeader.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.Charts.Adapter.Text, DRagLint.Charts.Compare, DRagLint.Charts.Remarks, DRagLint.Charts.Render, DRagLint.Charts.ReportHeader</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DRagLint.Charts.ReportHeader.TReportCommand.IsEmpty</para>
    /// <para>Returns: not Command.IsEmpty</para>
    /// <para>Reads: Command</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.IsEmpty"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function HasCommand: Boolean;
  end;

/// <summary>Parses the header at the top of an answer, plain or DocInsight.</summary>
/// <param name="pLines">The answer's lines, line ends removed; a stray trailing CR or
/// trailing spaces on a line are tolerated.</param>
/// <param name="pHeader">The header; Default(TReportHeader) when the result is False.</param>
/// <returns>False when the first non-blank line (after a DocInsight '&lt;remarks&gt;')
/// is not a header sentence.</returns>
/// <remarks>
/// DocInsight continuation lines (body indented two spaces more than the line
/// they continue) are joined with a single space, for the sentence and for the COMMAND
/// line alike (a wiki or mail client may re-wrap the COMMAND line). The DocInsight
/// COMMAND line is XML-unescaped before parsing. A COMMAND line that does not parse
/// leaves Command empty and is not counted in HeaderLines. Pure; thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Adapter.Text.HeaderRange (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.Compare.HeaderOf (DRagLint.Charts.Compare.pas), DRagLint.Charts.Remarks.RemarksBlockIsReport (DRagLint.Charts.Remarks.pas)</para>
/// <para>Calls: Default, DRagLint.Charts.ReportHeader.BodyAt, DRagLint.Charts.ReportHeader.IsContinuation, DRagLint.Charts.ReportHeader.LeadingSpaces, DRagLint.Charts.ReportHeader.ParseCommandLine, DRagLint.Charts.ReportHeader.StripDocPrefix, DRagLint.Charts.ReportHeader.XmlUnescape</para>
/// <para>Returns: False; True</para>
/// <para>Complexity: 21 (cyclomatic, outer body), 55 lines (full implementation)</para>
/// <para>Mutates: pHeader (out)</para>
/// <seealso cref="DRagLint.Charts.ReportHeader.BodyAt"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.IsContinuation"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.LeadingSpaces"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.ParseCommandLine"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.StripDocPrefix"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseReportHeader(const pLines: TArray<string>; out pHeader: TReportHeader): Boolean;

/// <summary>Parses a COMMAND line in either style: CLI ('--target "t" --surface-cap 40',
/// printed since 1.56) or PowerShell ('-Target "t" -SurfaceCap 40', printed before).</summary>
/// <param name="pText">The line, with or without the 'COMMAND ' prefix (ordinal).</param>
/// <param name="pCmd">The command; empty when the result is False.</param>
/// <returns>False when there is no question token.</returns>
/// <remarks>
/// Both styles give the SAME command: a known argument is stored under its canonical
/// name (Target, To, Project, In, Depth, Cap, SurfaceCap, Control, Mode, MaxRows) whichever
/// way it was spelled; an unknown name is stored as written, without its dashes. A line
/// that mixes the styles parses too (DetectCommandStyle tells them apart).
/// Tokens split on spaces outside double quotes; quotes are removed and have no
/// escape. An unquoted token of '-' or '--' followed by a letter is a name; its value is
/// the next token unless that is itself a name (value ''). A quoted token is always a
/// value, and '-3' is a value. A repeated name (in any spelling) keeps its first position
/// and takes the last value; a value with no name before it is ignored.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.ReportHeader.ParseReportHeader (DRagLint.Charts.ReportHeader.pas), DRagLint.CLI.Compare.CompareBuildCommand (DRagLint.CLI.Compare.pas)</para>
/// <para>Calls: Default, DRagLint.Charts.ReportHeader.ArgIndex, DRagLint.Charts.ReportHeader.IsName, DRagLint.Charts.ReportHeader.Tokenise</para>
/// <para>Returns: False; True</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 43 lines (full implementation)</para>
/// <para>Mutates: pCmd (out)</para>
/// <seealso cref="DRagLint.Charts.ReportHeader.ArgIndex"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.IsName"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.Tokenise"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseCommandLine(const pText: string; out pCmd: TReportCommand): Boolean;

/// <summary>Builds the canonical COMMAND line in CLI style, WITHOUT the 'COMMAND '
/// prefix: the one grammar every carrier prints (report header, ask output, doc-comment
/// embed, compare's JSON).</summary>
/// <param name="pCmd">The command.</param>
/// <returns>The question id, then the known arguments in the order --target, --to,
/// --project, --in, --depth, --cap, --surface-cap, --control, --mode, --max-rows (the flag
/// names of `drag-lint ask`), then unknown arguments in input order as '--' + their name in
/// lower-case kebab form ('FooBar' gives '--foo-bar').</returns>
/// <remarks>
/// --target, --to, --project, --in and --control are always double-quoted; the other
/// known values are bare. An unknown value is quoted when it holds a space or starts with
/// '-' (so it re-parses as a value); an unknown name with an empty value is written alone.
/// Values never contain '"' (IsValidReportTarget), so no escaping is done. The output
/// re-parses (ParseCommandLine) to a command SameQuestion calls equal to pCmd, and building
/// that again gives the same text. The PowerShell style is never written.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Render.CommandText (DRagLint.Charts.Render.pas)</para>
/// <para>Calls: DRagLint.Charts.ReportHeader.IndexOfName, DRagLint.Charts.ReportHeader.NeedsQuotes, DRagLint.Charts.ReportHeader.TReportCommand.Get, DRagLint.Charts.ReportHeader.TReportCommand.Has</para>
/// <para>Returns: SB.ToString</para>
/// <seealso cref="DRagLint.Charts.ReportHeader.IndexOfName"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.NeedsQuotes"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.Get"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.TReportCommand.Has"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildCommandLine(const pCmd: TReportCommand): string;

/// <summary>Which argument style a COMMAND line is written in.</summary>
/// <param name="pText">The line, with or without the 'COMMAND ' prefix (ordinal).</param>
/// <returns>csPowerShell when every argument name has one leading '-', csCli when every
/// one has two, csMixed when both occur, csNone when the line names no argument.</returns>
/// <remarks>
/// Uses ParseCommandLine's own token rules, so a quoted token and '-3' are values,
/// never names. Pure; thread-safe.
/// </remarks>
function DetectCommandStyle(const pText: string): TCommandStyle;

/// <summary>Whether two commands ask the same question (H4).</summary>
/// <param name="pA">The old answer's command.</param>
/// <param name="pB">The new answer's command.</param>
/// <param name="pDiffering">One 'Name: a vs b' per differing argument, '(absent)' for a
/// missing side, sorted by name (case-insensitive); known names in canonical spelling.
/// Question ids are compared but never listed here.</param>
/// <returns>True when the ids are equal (SameText) and every argument matches.</returns>
/// <remarks>
/// Order, quoting and argument style never matter: a command read from a
/// PowerShell-style line equals the same command read from a CLI-style line. Names compare
/// case-insensitively and ignore '-' inside the name; two values
/// that both parse as integers compare numerically ('03' = '3'), any other pair with
/// SameText (targets are Delphi identifiers, projects are Windows paths). An explicit
/// argument against an absent one IS a difference. PS trap handled: PowerShell -eq is
/// case-insensitive and coerces '03' -eq 3; both behaviours are kept.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Compare.ChooseCommand (DRagLint.Charts.Compare.pas)</para>
/// <para>Calls: DRagLint.Charts.ReportHeader.DisplayName, DRagLint.Charts.ReportHeader.ValuesMatch, SameText</para>
/// <para>Returns: SameText(pA.Question, pB.Question) and (Diff.Count = 0)</para>
/// <para>Mutates: pDiffering (out)</para>
/// <seealso cref="DRagLint.Charts.ReportHeader.DisplayName"/>
/// <seealso cref="DRagLint.Charts.ReportHeader.ValuesMatch"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SameQuestion(const pA, pB: TReportCommand; out pDiffering: TArray<string>): Boolean;

/// <summary>Strips a DocInsight '///' prefix.</summary>
/// <param name="pLine">A source line; leading whitespace before '///' is allowed.</param>
/// <param name="pBody">The text after '///' and ONE following space, trailing whitespace
/// removed; continuation indentation is kept ('///   x' gives '  x').</param>
/// <returns>False (pBody '') for a line that is not a '///' comment ('////' is not).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Adapter.Text.CollectDocInsight (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.Adapter.Text.DetectFormOf (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.Adapter.Text.HeaderRange (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.ReportHeader.BodyAt (DRagLint.Charts.ReportHeader.pas), DRagLint.Charts.ReportHeader.ParseReportHeader (DRagLint.Charts.ReportHeader.pas)</para>
/// <para>Returns: S.StartsWith(DOC_PREFIX) and not S.StartsWith(DOC_PREFIX + '/')</para>
/// <para>Mutates: pBody (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function StripDocPrefix(const pLine: string; out pBody: string): Boolean;

/// <summary>Reverses the XML escaping of a DocInsight line.</summary>
/// <param name="pText">Escaped text.</param>
/// <returns>pText with &amp;lt; &amp;gt; &amp;amp; &amp;quot; decoded in one left-to-right
/// pass ('&amp;amp;lt;' gives '&amp;lt;'); any other '&amp;' is kept as is.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Adapter.Text.CollectDocInsight (DRagLint.Charts.Adapter.Text.pas), DRagLint.Charts.ReportHeader.ParseReportHeader (DRagLint.Charts.ReportHeader.pas)</para>
/// <para>Calls: Copy</para>
/// <para>Returns: SB.ToString</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
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
  /// What BuildCommandLine writes before a name (CLI style).
  CLI_NAME_MARK = '--';
  /// Leading marks of a PowerShell-style name ('-Target') and of a CLI-style one ('--target').
  MARKS_NONE = 0;
  MARKS_POWERSHELL = 1;
  MARKS_CLI = 2;
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
  KNOWN_NAMES: array[0..11] of string = ('Target', 'To', 'Project', 'In', 'Depth', 'Cap',
    'SurfaceCap', 'Control', 'Mode', 'MaxRows', 'Since', 'MinSupport'); { v156 G46: the last two }
  /// The CLI spelling of KNOWN_NAMES, index for index: the flag names of `drag-lint ask`.
  KNOWN_CLI_NAMES: array[0..11] of string = ('target', 'to', 'project', 'in', 'depth', 'cap',
    'surface-cap', 'control', 'mode', 'max-rows', 'since', 'min-support');
  /// The known arguments whose value is always double-quoted.
  QUOTED_NAMES: array[0..4] of string = ('Target', 'To', 'Project', 'In', 'Control');
  ENTITIES: array[0..3] of string = ('&lt;', '&gt;', '&amp;', '&quot;');
  ENTITY_CHARS: array[0..3] of Char = ('<', '>', '&', '"');

type
  TToken = record
    Text  : string;
    Quoted: Boolean;
  end;

{ What two spellings of one argument name share: 'SurfaceCap', 'surface-cap' and 'SURFACECAP'
  all give 'surfacecap'. PS trap handled: hashtable keys and parameter names are
  case-insensitive in PowerShell, so the key is lower-cased, never compared with '='. }
function NameKey(const pName: string): string;
begin
  Result:= pName.Replace(NAME_MARK, '').ToLowerInvariant;
end;

function SameName(const pA, pB: string): Boolean;
begin
  Result:= NameKey(pA) = NameKey(pB);
end;

function IndexOfName(const pNames: array of string; const pName: string): Integer;
begin
  for var I:= Low(pNames) to High(pNames) do
    if SameName(pNames[I], pName) then
      Exit(I);
  Result:= NOT_FOUND;
end;

function ArgIndex(const pArgs: TArray<TCommandArg>; const pName: string): Integer;
begin
  for var I:= 0 to High(pArgs) do
    if SameName(pArgs[I].Name, pName) then
      Exit(I);
  Result:= NOT_FOUND;
end;

{ 'FooBar' -> 'foo-bar', 'foo-bar' -> 'foo-bar', 'ABC' -> 'abc': a '-' goes before an upper-case
  letter that follows a lower-case letter or a digit. }
function KebabOf(const pName: string): string;
begin
  var SB:= TStringBuilder.Create(Length(pName) + Length(pName) div 2);
  try
    for var I:= 1 to Length(pName) do
    begin
      var C:= pName[I];
      if C.IsUpper and (I > 1) and (pName[I - 1].IsLower or pName[I - 1].IsDigit) then
        SB.Append(NAME_MARK);
      SB.Append(C.ToLower);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ The CLI spelling a name is written with: the `drag-lint ask` flag for a known one. }
function CliName(const pName: string): string;
begin
  var K:= IndexOfName(KNOWN_NAMES, pName);
  Result:= if K = NOT_FOUND then KebabOf(pName) else KNOWN_CLI_NAMES[K];
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

{ How many '-' open a name: MARKS_POWERSHELL for '-Target', MARKS_CLI for '--target',
  MARKS_NONE for anything that is not a name ('-3', '---x', 'x', '-'). }
function NameMarks(const pText: string): Integer;
begin
  Result:= MARKS_NONE;
  while (Result < MARKS_CLI) and (Result < Length(pText)) and (pText[Result + 1] = NAME_MARK) do
    Inc(Result);
  if (Result >= Length(pText)) or not pText[Result + 1].IsLetter then
    Result:= MARKS_NONE;
end;

function LooksLikeName(const pText: string): Boolean;
begin
  Result:= NameMarks(pText) <> MARKS_NONE;
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
  Result:= if TryStrToInt(pA, IA) and TryStrToInt(pB, IB) then IA = IB else SameText(pA, pB);
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

{ The tokens after the optional 'COMMAND ' prefix. }
function CommandTokens(const pText: string): TArray<TToken>;
begin
  var S:= pText.Trim;
  if S.StartsWith(COMMAND_PREFIX) then
    S:= S.Substring(Length(COMMAND_PREFIX))
  else if S = COMMAND_PREFIX.TrimRight then
    S:= '';
  Result:= Tokenise(S);
end;

function DetectCommandStyle(const pText: string): TCommandStyle;
begin
  var Tokens:= CommandTokens(pText);
  var Seen: array[MARKS_POWERSHELL..MARKS_CLI] of Boolean;
  Seen[MARKS_POWERSHELL]:= False;
  Seen[MARKS_CLI]:= False;
  for var I:= 1 to High(Tokens) do
    if IsName(Tokens[I]) then
      Seen[NameMarks(Tokens[I].Text)]:= True;
  if Seen[MARKS_POWERSHELL] and Seen[MARKS_CLI] then
    Result:= csMixed
  else if Seen[MARKS_CLI] then
    Result:= csCli
  else if Seen[MARKS_POWERSHELL] then
    Result:= csPowerShell
  else
    Result:= csNone;
end;

function ParseCommandLine(const pText: string; out pCmd: TReportCommand): Boolean;
begin
  pCmd:= Default(TReportCommand);
  var Tokens:= CommandTokens(pText);
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
        Arg.Name:= DisplayName(Tokens[I].Text.Substring(NameMarks(Tokens[I].Text)));
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
        SB.Append(' ').Append(CLI_NAME_MARK).Append(CliName(Known));
        if (IndexOfName(QUOTED_NAMES, Known) <> NOT_FOUND) or NeedsQuotes(V) then
          SB.Append(' ').Append(QUOTE).Append(V).Append(QUOTE)
        else if V <> '' then
          SB.Append(' ').Append(V);
      end;
    for var Arg in pCmd.Args do
      if IndexOfName(KNOWN_NAMES, Arg.Name) = NOT_FOUND then
      begin
        SB.Append(' ').Append(CLI_NAME_MARK).Append(CliName(Arg.Name));
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
    // PS trap handled: hashtable keys are case-insensitive, so the maps are keyed by NameKey (which
    // also makes 'SurfaceCap' and 'surface-cap' one name) and the name list sorts without case.
    InA:= TDictionary<string, string>.Create;
    InB:= TDictionary<string, string>.Create;
    Names:= TList<string>.Create(TIStringComparer.Ordinal);
    Diff:= TList<string>.Create;
    for var Arg in pA.Args do
    begin
      if not InA.ContainsKey(NameKey(Arg.Name)) then
        Names.Add(Arg.Name);
      InA.AddOrSetValue(NameKey(Arg.Name), Arg.Value);
    end;
    for var Arg in pB.Args do
    begin
      if not InA.ContainsKey(NameKey(Arg.Name)) and not InB.ContainsKey(NameKey(Arg.Name)) then
        Names.Add(Arg.Name);
      InB.AddOrSetValue(NameKey(Arg.Name), Arg.Value);
    end;
    Names.Sort;
    for var N in Names do
    begin
      var VA, VB: string;
      var HasA:= InA.TryGetValue(NameKey(N), VA);
      var HasB:= InB.TryGetValue(NameKey(N), VB);
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
