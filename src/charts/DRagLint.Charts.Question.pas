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
  QUESTION_CAPTIONS is Report.DocInsight.ps1's $script:ReportCaptions (the phrase of the
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
    /// <summary>Where the bundle folder is made (Ask-Report -OutRoot).</summary>
    OutRoot      : string;
    /// <summary>The repo's charts folder: the clone root is &lt;ChartsRoot&gt;\scratch\db.</summary>
    ChartsRoot   : string;
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
    /// <summary>dot.exe: DotExe when set, else the Resolve-GraphvizDot walk from ChartsRoot.</summary>
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
  end;

  /// <summary>What a ported chart emitter hands back (the PS emitter's result object).</summary>
  TChartResult = record
    /// <summary>The files of the one dot layout run, and the SVG anchor count.</summary>
    Layout      : TDotLayout;
    /// <summary>The count the question's vocabulary names first (e.g. Reads).</summary>
    LeftCount   : Int64;
    /// <summary>The count the question's vocabulary names second (e.g. Writes).</summary>
    RightCount  : Int64;
    /// <summary>The emitter's ClickTargets.</summary>
    ClickTargets: Integer;
    /// <summary>The emitter's AllClickable.</summary>
    AllClickable: Boolean;
    /// <summary>Every emitter property except the file paths, in the PS object's order.</summary>
    Fields      : TArray<TMetaField>;
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

/// <summary>The two count labels of a question (New-DiagramArtifact's $vocab).</summary>
/// <param name="pId">The question id.</param>
/// <param name="pLeft">The first label, e.g. 'tables read'.</param>
/// <param name="pRight">The second label, e.g. 'tables written'.</param>
/// <returns>False for an unknown id (both labels '').</returns>
function QuestionVocab(const pId: string; out pLeft, pRight: string): Boolean;

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

const
  CLONE_SUBDIR = 'scratch\db';
  SCRIPTS_SUBDIR = 'src';
  UNKNOWN_PHRASE = 'Report';
  HEX_WIDTH = 4;
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
  Result:= ResolveGraphvizDot('', DragLintSettingsPath, ChartsRoot, TPath.Combine(ChartsRoot, SCRIPTS_SUBDIR), SHARED_DOT_DEFAULT);
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

initialization

finalization
  GRegistry.Free;

end.
