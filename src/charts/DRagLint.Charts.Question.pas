unit DRagLint.Charts.Question;

(* The shared shape of a ported chart question (spec s11, P1-P5): what an in-process
  emitter is given, what it hands back, and the registry the Delphi producer answers from.

  The PowerShell side splits one question over three scripts: Ask-Report.ps1 (the plain
  answer), New-DiagramArtifact.ps1 (the bundle) and one Emit-<Question>.ps1 (the chart).
  The Delphi side keeps the same split: DRagLint.Charts.Ask ports the first two once for
  every chart question, and one DRagLint.Charts.Q.<Question> unit per question ports the
  emitter and registers it here from its initialization section. A question id that is
  not registered is not ported, and the producer hands it to PowerShell.

  The two tables below are copied from the scripts and must change with them:
  QUESTION_CAPTIONS is the IDE plugin's REPORT_QUESTIONS captions (the phrase of the
  header sentence) and QUESTION_VOCAB is New-DiagramArtifact.ps1's $vocab (the two
  labelled counts of the CHART line and meta.json). *)

interface

uses
  System.SysUtils, DRagLint.Charts.ReportHeader, DRagLint.Charts.Dot;

const
  /// <summary>New-DiagramArtifact.ps1's -Cap default.</summary>
  DEFAULT_CAP = 20;
  /// <summary>New-DiagramArtifact.ps1's -Depth default.</summary>
  DEFAULT_DEPTH = 2;
  /// <summary>New-DiagramArtifact.ps1's -SurfaceCap default.</summary>
  DEFAULT_SURFACE_CAP = 12;
  /// <summary>Ask-Report.ps1's -MaxRows default.</summary>
  DEFAULT_MAX_ROWS = 80;
  /// <summary>Ask-Report's exit code for a refused or failed question.</summary>
  ASK_EXIT_REFUSED = 1;

type
  /// <summary>A question was refused, failed, or is not ported.</summary>
  EChartsQuestion = class(Exception);

  /// <summary>Everything one chart question is asked with.</summary>
  /// <remarks>The values Ask-Report and New-DiagramArtifact would hold after resolution:
  /// full index path, defaults applied. A value record; nothing in it is owned.</remarks>
  TQuestionArgs = record
    /// <summary>The question id, lower case (Ask-Report R13).</summary>
    Question     : string;
    /// <summary>The selection, as given.</summary>
    Target       : string;
    /// <summary>The project index, full path.</summary>
    DbPath       : string;
    /// <summary>crosses-boundary's other half (-CounterpartDb), full path; '' = not given.</summary>
    CounterpartDb: string;
    /// <summary>The SERVER index (-ServerDbPath), full path; '' = not given. Carried only for a
    /// question that reads it (QuestionReadsServerIndex); the emitter handles '' as its
    /// Emit-*.ps1 handles the omitted parameter.</summary>
    ServerDbPath : string;
    /// <summary>The SQL-script index (-SqlDbPath), full path; '' = not given. Carried only for a
    /// question that reads it (QuestionReadsSqlIndex); the emitter handles '' as its
    /// Emit-*.ps1 handles the omitted parameter.</summary>
    SqlDbPath    : string;
    /// <summary>Where the bundle folder is made (Ask-Report -OutRoot).</summary>
    OutRoot      : string;
    /// <summary>The repo's charts folder: the clone root is &lt;ChartsRoot&gt;\scratch\db.</summary>
    ChartsRoot   : string;
    /// <summary>The folder the chart scripts (Ask-Report.ps1) were found in; '' = &lt;ChartsRoot&gt;\src,
    /// the repository layout. An installed copy keeps them beside the engine ({app}\bin), so
    /// the producer sets this and the dot lookup starts there.</summary>
    ScriptDir    : string;
    /// <summary>The resolved dot.exe.</summary>
    DotExe       : string;
    /// <summary>The effective -Cap.</summary>
    Cap          : Integer;
    /// <summary>The effective -Depth.</summary>
    Depth        : Integer;
    /// <summary>The effective -SurfaceCap.</summary>
    SurfaceCap   : Integer;
    /// <summary>The effective -MaxRows of the printed answer.</summary>
    MaxRows      : Integer;
    /// <summary>The question and its EXPLICIT arguments, as the COMMAND line names them.</summary>
    Command      : TReportCommand;
    /// <summary>Lets a non-clone index through the clone guard for the emitter call, exactly
    /// as Ask-Report sets DRAGLINT_CHARTS_ALLOW_LIVE_DB=1 around the bundler.</summary>
    AllowLiveDb  : Boolean;
    /// <summary>When the question was asked (local time).</summary>
    AskedOn      : TDateTime;
    /// <summary>The engine version the header names.</summary>
    EngineVersion: string;
    /// <summary>The clone folder &lt;ChartsRoot&gt;\scratch\db.</summary>
    /// <returns>The folder path.</returns>
    function CloneRoot: string;
    /// <summary>dot.exe: DotExe when set, else the Resolve-GraphvizDot walk from ScriptDir (or ChartsRoot\src).</summary>
    /// <returns>The full path of dot.exe.</returns>
    /// <remarks>Called where the PS emitter's Invoke-DotRun resolves it: after the .dot text is built.
    /// ResolveGraphvizDot raises EChartsTool, naming every place looked, when no dot.exe is found.</remarks>
    function Dot: string;
    /// <summary>The index path through the clone guard (Get-CloneDb), as the PS emitters open it.</summary>
    /// <returns>The full path.</returns>
    /// <exception cref="EChartsTool">A blank, missing, non-.sqlite or (without the override) non-clone path.</exception>
    function GuardedDb: string;
  end;

  /// <summary>One emitter count for meta.json's "emitter" object, already JSON-encoded.</summary>
  TMetaField = record
    /// <summary>The PS property name, e.g. 'Reads'.</summary>
    Name: string;
    /// <summary>The value as a JSON literal: 4, true, "text".</summary>
    Json: string;
    /// <summary>An integer field.</summary>
    /// <param name="pName">Property name.</param>
    /// <param name="pValue">Value.</param>
    /// <returns>The field.</returns>
    class function Int(const pName: string; pValue: Int64): TMetaField; static;
    /// <summary>A Boolean field.</summary>
    /// <param name="pName">Property name.</param>
    /// <param name="pValue">Value.</param>
    /// <returns>The field.</returns>
    class function Bool(const pName: string; pValue: Boolean): TMetaField; static;
    /// <summary>A string field.</summary>
    /// <param name="pName">Property name.</param>
    /// <param name="pValue">Value; escaped as ConvertTo-Json escapes it.</param>
    /// <returns>The field.</returns>
    class function Str(const pName, pValue: string): TMetaField; static;
    /// <summary>A double field, as ConvertTo-Json writes a [double] (Measure-Object -Sum).</summary>
    /// <param name="pName">Property name.</param>
    /// <param name="pValue">Value.</param>
    /// <returns>The field: a whole number keeps a '.0' suffix (24.0), any other prints round-trip.</returns>
    class function Real(const pName: string; pValue: Double): TMetaField; static;
    /// <summary>A JSON null: the PS wrote $null -- the value was not asked, not measured empty.</summary>
    /// <param name="pName">Property name.</param>
    /// <returns>The field, Json 'null' (never 0, which would read as a measured absence).</returns>
    class function Null(const pName: string): TMetaField; static;
    /// <summary>A nested object field (an [ordered] dictionary of the emitter result).</summary>
    /// <param name="pName">Property name.</param>
    /// <param name="pFields">The members, in order, already JSON-encoded.</param>
    /// <returns>The field, indented for the emitter object of meta.json (members at six
    /// spaces, the closing brace at four); '{}' when pFields is empty.</returns>
    class function Obj(const pName: string; const pFields: TArray<TMetaField>): TMetaField; static;
    /// <summary>A string-array field, as ConvertTo-Json -Depth 4 writes a [string[]] inside the emitter object.</summary>
    /// <param name="pName">Property name.</param>
    /// <param name="pValues">The elements, in order; each is escaped as ConvertTo-Json escapes a string.</param>
    /// <returns>The field: elements at six spaces one per line, the closing bracket at four; '[]' when pValues is empty.</returns>
    /// <remarks>Elements at six spaces one per line (PsJsonString), the closing bracket at four; '[]' when pValues is
    /// empty; a one-element array stays an array (measured 2026-10-17 under pwsh 7). Mirrors Obj's indentation.</remarks>
    class function StrList(const pName: string; const pValues: TArray<string>): TMetaField; static;
    /// <summary>A double encoded as ConvertTo-Json writes it.</summary>
    /// <param name="pValue">Value.</param>
    /// <returns>'24.0' for a whole number, else the shortest round-trip text with '.' as decimal point.</returns>
    class function RealJson(pValue: Double): string; static;
  end;

  /// <summary>One leaf -> full path pair of a text question's link table.</summary>
  TAnchorPath = record
    /// <summary>The file leaf as an anchor writes it (e.g. 'Blueprint4.pas'); matched case-insensitively.</summary>
    Leaf: string;
    /// <summary>The ONE full path the indexes hold for the leaf.</summary>
    Path: string;
  end;

  /// <summary>What a ported chart emitter hands back (the PS emitter's result object).</summary>
  TChartResult = record
    /// <summary>The files of the one dot layout run, and the SVG anchor count.</summary>
    Layout      : TDotLayout;
    /// <summary>The count the question's vocabulary names first (e.g. Reads).</summary>
    LeftCount   : Int64;
    /// <summary>The count the question's vocabulary names second (e.g. Writes).</summary>
    RightCount  : Int64;
    /// <summary>meta.json's leftCount literal when the PS value is not an integer (e.g. a
    /// Measure-Object sum, '24.0'); '' writes LeftCount.</summary>
    LeftJson    : string;
    /// <summary>meta.json's rightCount literal when the PS value is not an integer; '' writes RightCount.</summary>
    RightJson   : string;
    /// <summary>The emitter's own wording for the first count, New-DiagramArtifact's '&lt;Count&gt;Label'
    /// property (:239-245); '' keeps QuestionVocab's label. Only who-writes / who-reads set one.</summary>
    LeftLabel   : string;
    /// <summary>The emitter's own wording for the second count; '' keeps QuestionVocab's label.
    /// Only who-writes / who-reads set one.</summary>
    RightLabel  : string;
    /// <summary>The emitter's ClickTargets.</summary>
    ClickTargets: Integer;
    /// <summary>The emitter's AllClickable.</summary>
    AllClickable: Boolean;
    /// <summary>Every emitter property except the file paths, in the PS object's order.</summary>
    Fields      : TArray<TMetaField>;
    /// <summary>The emitter's Trace: the Form A document it wrote (a file path); '' for a chart question.
    /// A non-empty value makes AskChartQuestion bundle the question as a TEXT question: the file becomes
    /// trace.dlgraph and the shell page quotes it instead of drawing only a chart.</summary>
    TracePath   : string;
    /// <summary>Why the chart could not be drawn, '' when it was; a text question only. The text is still
    /// delivered, with a line saying the chart is missing.</summary>
    ChartError  : string;
    /// <summary>The emitter's AnchorPaths: leaf -> the ONE full path the indexes hold; a text question only.
    /// An anchor whose leaf is absent stays plain text on the shell page.</summary>
    AnchorPaths : TArray<TAnchorPath>;
  end;

  /// <summary>A ported chart emitter.</summary>
  /// <param name="pArgs">The question.</param>
  /// <param name="pOutDir">The bundle folder the layout files go to (they are renamed after).</param>
  /// <returns>The chart.</returns>
  /// <remarks>Raises EChartsQuestion (or any exception) to refuse: the message is the answer.</remarks>
  TChartEmitter = reference to function(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;

/// <summary>Registers a ported chart emitter; called from a Q unit's initialization.</summary>
/// <param name="pId">The question id (lower case).</param>
/// <param name="pEmitter">The emitter.</param>
procedure RegisterChartQuestion(const pId: string; const pEmitter: TChartEmitter);

/// <summary>Finds the ported emitter of a question.</summary>
/// <param name="pId">The question id; compared case-insensitively.</param>
/// <param name="pEmitter">The emitter, or nil.</param>
/// <returns>True when the question is ported.</returns>
function FindChartQuestion(const pId: string; out pEmitter: TChartEmitter): Boolean;

/// <summary>The ids of every ported question, sorted ordinally.</summary>
/// <returns>The ids.</returns>
function PortedQuestionIds: TArray<string>;

/// <summary>The phrase of the header sentence for a question id.</summary>
/// <param name="pId">The question id.</param>
/// <returns>Its menu caption without the trailing dots, or 'Report' for an unknown id.</returns>
function QuestionPhrase(const pId: string): string;

/// <summary>Every question id the chart pipeline accepts (New-DiagramArtifact.ps1's
/// ValidateSet), in the menu-caption order of the header-phrase table.</summary>
/// <returns>The 26 ids, lower case.</returns>
function QuestionIds: TArray<string>;

/// <summary>The two count labels of a question (New-DiagramArtifact's $vocab).</summary>
/// <param name="pId">The question id.</param>
/// <param name="pLeft">The first label, e.g. 'tables read'.</param>
/// <param name="pRight">The second label, e.g. 'tables written'.</param>
/// <returns>False for an unknown id (both labels '').</returns>
function QuestionVocab(const pId: string; out pLeft, pRight: string): Boolean;

/// <summary>Whether a question reads the SERVER index (Ask-Report's $needServer).</summary>
/// <param name="pId">The question id; compared case-insensitively.</param>
/// <returns>True for round-trip and lands-where.</returns>
/// <remarks>The same list decides New-DiagramArtifact's regenerate -ServerDbPath and
/// Ask-Report's 'INDEX ... (server)' line.</remarks>
function QuestionReadsServerIndex(const pId: string): Boolean;

/// <summary>Whether a question reads the SQL-script index (Ask-Report's $needSql).</summary>
/// <param name="pId">The question id; compared case-insensitively.</param>
/// <returns>True for round-trip, lands-where, consumers and feeds-from.</returns>
/// <remarks>The same list decides New-DiagramArtifact's regenerate -SqlDbPath and
/// Ask-Report's 'INDEX ... (sql)' line.</remarks>
function QuestionReadsSqlIndex(const pId: string): Boolean;

/// <summary>The -Depth a question walks when none is given (New-DiagramArtifact's $EffDepth).</summary>
/// <param name="pId">The question id; compared case-insensitively.</param>
/// <returns>3 for exception-paths, 4 for round-trip, else DEFAULT_DEPTH.</returns>
/// <remarks>The value the emitter walks, meta.json's depth and the regenerate line's -Depth.</remarks>
function QuestionDefaultDepth(const pId: string): Integer;

/// <summary>Encodes a string as ConvertTo-Json writes it.</summary>
/// <param name="pValue">The text.</param>
/// <returns>The quoted JSON string: '"' and '\' escaped, control characters as \b \f \n \r \t
/// or \u00XX; everything else verbatim (Newtonsoft StringEscapeHandling.Default).</returns>
function PsJsonString(const pValue: string): string;

implementation

uses
  System.Generics.Collections, System.Generics.Defaults, System.IOUtils
  , DRagLint.Charts.Tools // dl:unit DRagLint.Charts.Tools accepted -- the shared dot.exe default travels with the dot walk (ResolveGraphvizDot) it feeds
  ;

type
  { one row of DEFAULT_DEPTHS }
  TDepthDefault = record
    Id   : string;
    Depth: Integer;
  end;

const
  CLONE_SUBDIR = 'scratch\db';
  SCRIPTS_SUBDIR = 'src';
  UNKNOWN_PHRASE = 'Report';
  HEX_WIDTH = 4;
  { below this a whole double prints exactly as an integer }
  EXACT_DOUBLE_LIMIT = 1E15;
  { Ask-Report.ps1's $needServer and $needSql }
  READS_SERVER: array[0..1] of string = ('round-trip', 'lands-where');
  READS_SQL: array[0..3] of string = ('round-trip', 'lands-where', 'consumers', 'feeds-from');
  { New-DiagramArtifact's $EffDepth: the questions whose -Depth default is not DEFAULT_DEPTH }
  DEFAULT_DEPTHS: array[0..1] of TDepthDefault = (
    (Id: 'exception-paths'; Depth: 3),
    (Id: 'round-trip'; Depth: 4));
  QUESTION_CAPTIONS: array[0..25] of array[0..1] of string = (
    ('butterfly', 'Callers and callees (butterfly chart)...'),
    ('who-calls', 'Who calls this routine...'),
    ('what-it-calls', 'What this routine calls...'),
    ('path', 'Call path from this routine to another...'),
    ('effects', 'What this routine changes (side effects)...'),
    ('touches-tables', 'Which tables this routine touches...'),
    ('exception-paths', 'Which exceptions escape this routine...'),
    ('crosses-boundary', 'Does this routine leave the process...'),
    ('protocol-trace', 'Where this protocol command travels...'),
    ('change-impact', 'What a change here would break...'),
    ('tested-by', 'Which tests reach this code...'),
    ('who-writes', 'Who writes this field...'),
    ('who-reads', 'Who reads this field...'),
    ('feeds-from', 'What feeds this control (back to the column)...'),
    ('lands-where', 'Where this field lands in the database...'),
    ('round-trip', 'Field round-trip (grid -> server -> SQL)...'),
    ('class-surface', 'What this type exposes (class surface)...'),
    ('hierarchy', 'Ancestors and descendants (hierarchy)...'),
    ('wiring', 'Who registers and resolves this interface...'),
    ('event-wiring', 'Which handler runs on which event (form)...'),
    ('lifecycle', 'Form lifecycle (create -> show -> destroy)...'),
    ('deps', 'Dependencies of this unit...'),
    ('architecture', 'Project architecture (layered zones)...'),
    ('cycles', 'Circular unit dependencies...'),
    ('consumers', 'Who uses this table or column...'),
    ('shown-where', 'Where this database column is shown...'));
  QUESTION_VOCAB: array[0..25] of array[0..2] of string = (
    ('butterfly', 'callers', 'callees'),
    ('deps', 'used by', 'uses'),
    ('who-calls', 'call sites', 'cycle rows'),
    ('what-it-calls', 'call sites', 'cycle rows'),
    ('who-writes', 'write sites', 'routines'),
    ('who-reads', 'read sites', 'routines'),
    ('hierarchy', 'ancestors', 'descendants'),
    ('class-surface', 'members', 'shown'),
    ('event-wiring', 'events', 'handlers'),
    ('touches-tables', 'tables read', 'tables written'),
    ('lifecycle', 'stages wired', 'implemented, not wired'),
    ('cycles', 'groups', 'uses edges'),
    ('wiring', 'registrations', 'resolution sites'),
    ('effects', 'effects', 'unclassified tokens'),
    ('architecture', 'project units', 'back-edges'),
    ('protocol-trace', 'references', 'zones'),
    ('crosses-boundary', 'commands', 'transport calls'),
    ('shown-where', 'data bindings', 'forms'),
    ('change-impact', 'routines affected', 'units'),
    ('tested-by', 'covering tests', 'fixtures'),
    ('exception-paths', 'raise sites', 'handler clauses in body'),
    ('consumers', 'reading routines', 'writing routines'),
    ('feeds-from', 'chain rows', 'controls in the index that resolve to one table'),
    ('lands-where', 'server DataService rows', 'triggers touching the column'),
    ('round-trip', 'steps', 'unresolved'),
    ('path', 'shortest paths', 'calls on each path'));

var
  GRegistry: TDictionary<string, TChartEmitter>;

function TQuestionArgs.CloneRoot: string;
begin
  Result:= TPath.Combine(ChartsRoot, CLONE_SUBDIR);
end;

function TQuestionArgs.Dot: string;
begin
  if DotExe <> '' then
    Exit(DotExe);
  var Scripts:= if ScriptDir <> '' then ScriptDir else TPath.Combine(ChartsRoot, SCRIPTS_SUBDIR);
  Result:= ResolveGraphvizDot('', DragLintSettingsPath, ChartsRoot, Scripts, SHARED_DOT_DEFAULT);
end;

function TQuestionArgs.GuardedDb: string;
var
  Note: string;
begin
  Result:= CloneDb(DbPath, CloneRoot, Note);
end;

function PsJsonString(const pValue: string): string;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append('"');
    for var C in pValue do
      case C of
        '"' : SB.Append('\"');
        '\' : SB.Append('\\');
        #8  : SB.Append('\b');
        #9  : SB.Append('\t');
        #10 : SB.Append('\n');
        #12 : SB.Append('\f');
        #13 : SB.Append('\r');
        #0..#7, #11, #14..#31: SB.Append('\u').Append(IntToHex(Ord(C), HEX_WIDTH).ToLower);
      else
        SB.Append(C);
      end;
    SB.Append('"');
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TMetaField.Int(const pName: string; pValue: Int64): TMetaField;
begin
  Result.Name:= pName;
  Result.Json:= IntToStr(pValue);
end;

class function TMetaField.Bool(const pName: string; pValue: Boolean): TMetaField;
begin
  Result.Name:= pName;
  Result.Json:= if pValue then 'true' else 'false';
end;

class function TMetaField.Str(const pName, pValue: string): TMetaField;
begin
  Result.Name:= pName;
  Result.Json:= PsJsonString(pValue);
end;

class function TMetaField.RealJson(pValue: Double): string;
begin
  if (Frac(pValue) = 0) and (Abs(pValue) < EXACT_DOUBLE_LIMIT) then
    Exit(IntToStr(Trunc(pValue)) + '.0');
  Result:= FloatToStr(pValue, TFormatSettings.Invariant);
end;

class function TMetaField.Real(const pName: string; pValue: Double): TMetaField;
begin
  Result.Name:= pName;
  Result.Json:= RealJson(pValue);
end;

class function TMetaField.Null(const pName: string): TMetaField;
begin
  Result.Name:= pName;
  Result.Json:= 'null';
end;

class function TMetaField.Obj(const pName: string; const pFields: TArray<TMetaField>): TMetaField;
const
  MEMBER_INDENT = '      ';
  CLOSE_INDENT = '    ';
begin
  Result.Name:= pName;
  if Length(pFields) = 0 then
  begin
    Result.Json:= '{}';
    Exit;
  end;
  var SB:= TStringBuilder.Create;
  try
    SB.Append('{').Append(sLineBreak);
    for var K:= 0 to High(pFields) do
    begin
      SB.Append(MEMBER_INDENT).Append(PsJsonString(pFields[K].Name)).Append(': ').Append(pFields[K].Json);
      if K < High(pFields) then
        SB.Append(',');
      SB.Append(sLineBreak);
    end;
    SB.Append(CLOSE_INDENT).Append('}');
    Result.Json:= SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TMetaField.StrList(const pName: string; const pValues: TArray<string>): TMetaField;  // dl:ok duplicate-code@d745 -- REVIEWED 2026-10-17: the string-array twin of Obj, deliberately the same indentation scheme (H14); sharing the loop would cost a callback for six lines
const
  ELEMENT_INDENT = '      ';
  CLOSE_INDENT = '    ';
begin
  Result.Name:= pName;
  if Length(pValues) = 0 then
  begin
    Result.Json:= '[]';
    Exit;
  end;
  var SB:= TStringBuilder.Create;
  try
    SB.Append('[').Append(sLineBreak);
    for var K:= 0 to High(pValues) do
    begin
      SB.Append(ELEMENT_INDENT).Append(PsJsonString(pValues[K]));
      if K < High(pValues) then
        SB.Append(',');
      SB.Append(sLineBreak);
    end;
    SB.Append(CLOSE_INDENT).Append(']');
    Result.Json:= SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure RegisterChartQuestion(const pId: string; const pEmitter: TChartEmitter);
begin
  if GRegistry = nil then
    GRegistry:= TDictionary<string, TChartEmitter>.Create(TIStringComparer.Ordinal);
  GRegistry.AddOrSetValue(pId, pEmitter);
end;

function FindChartQuestion(const pId: string; out pEmitter: TChartEmitter): Boolean;
begin
  pEmitter:= nil;
  Result:= (GRegistry <> nil) and GRegistry.TryGetValue(pId, pEmitter);
end;

function PortedQuestionIds: TArray<string>;
begin
  if GRegistry = nil then
    Exit(nil);
  Result:= GRegistry.Keys.ToArray;
  TArray.Sort<string>(Result, TStringComparer.Ordinal);
end;

function QuestionPhrase(const pId: string): string;
begin
  for var K:= Low(QUESTION_CAPTIONS) to High(QUESTION_CAPTIONS) do
    if SameText(QUESTION_CAPTIONS[K, 0], pId) then
    begin
      Result:= QUESTION_CAPTIONS[K, 1];
      while Result.EndsWith('.') do
        Result:= Result.Substring(0, Result.Length - 1);
      Exit;
    end;
  Result:= UNKNOWN_PHRASE;
end;

function QuestionIds: TArray<string>;
begin
  SetLength(Result, Length(QUESTION_CAPTIONS));
  for var K:= Low(QUESTION_CAPTIONS) to High(QUESTION_CAPTIONS) do
    Result[K]:= QUESTION_CAPTIONS[K, 0];
end;

function QuestionVocab(const pId: string; out pLeft, pRight: string): Boolean;
begin
  for var K:= Low(QUESTION_VOCAB) to High(QUESTION_VOCAB) do
    if SameText(QUESTION_VOCAB[K, 0], pId) then
    begin
      pLeft:= QUESTION_VOCAB[K, 1];
      pRight:= QUESTION_VOCAB[K, 2];
      Exit(True);
    end;
  pLeft:= '';
  pRight:= '';
  Result:= False;
end;

function QuestionReadsServerIndex(const pId: string): Boolean;
begin
  Result:= False;
  for var Id in READS_SERVER do
    if SameText(Id, pId) then
      Exit(True);
end;

function QuestionReadsSqlIndex(const pId: string): Boolean;
begin
  Result:= False;
  for var Id in READS_SQL do
    if SameText(Id, pId) then
      Exit(True);
end;

function QuestionDefaultDepth(const pId: string): Integer;
begin
  Result:= DEFAULT_DEPTH;
  for var D in DEFAULT_DEPTHS do
    if SameText(D.Id, pId) then
      Exit(D.Depth);
end;

initialization

finalization
  GRegistry.Free;

end.
