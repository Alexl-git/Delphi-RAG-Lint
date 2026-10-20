unit DragLint.Plugin.ReportText;

{ The IDE-free half of the drag-lint > Reports submenu.

  WHY IT IS ITS OWN UNIT. DragLint.Plugin.Reports builds the menu, reads the
  caret and runs `drag-lint ask`; all of that is ToolsAPI-bound and
  cannot be compiled into a console test. Everything that decides WHAT is sent
  and WHAT the user is handed back lives here instead, with no ToolsAPI and no
  VCL, so tests\reportstext\ReportTextTests.dpr (DUnitX) can pin it:

    the question catalog -- every question the chart pipeline accepts, with
      a human caption and the kind of selection it is asked of;
    the DocInsight formatter -- the stdout answer as a /// <remarks> block
      that is strict 7-bit ASCII, wrapped, and NEVER carries the autodoc
      provenance marker (autodoc keeps unmarked content byte-for-byte, so a
      pasted answer survives Auto Doc runs only while it stays unmarked).
      The formatter itself lives in src\charts\DRagLint.Charts.DocInsight
      (the engine must not link a plugin unit); this unit only adds the
      catalog caption and forwards;
    the small parsers -- typeat JSON, a DFM root object line, the ask verb's
      refusal reason and its stale-index reindex commands. }

interface

uses
  System.SysUtils
  , DRagLint.Charts.DocInsight
  ;

type
  /// <summary>What the user has to select before a report question can be
  /// asked. It decides how the menu groups the question and where the target
  /// comes from.</summary>
  TReportTargetKind = (
    rtkRoutine,   { the routine at the caret }
    rtkMember,    { the field, property or DFM control at the caret }
    rtkType,      { the type at the caret }
    rtkUnit,      { the active unit }
    rtkProject,   { the whole project: no target to choose }
    rtkName);     { a typed table or column name }

  /// <summary>One question of `drag-lint ask` as the menu offers it.</summary>
  TReportQuestion = record
    /// <summary>The -Question value, e.g. 'who-writes'.</summary>
    Id     : string;
    /// <summary>The menu caption: a human phrase ending in '...'.</summary>
    Caption: string;
    /// <summary>What the user selects for this question.</summary>
    Kind   : TReportTargetKind;
  end;

  /// <summary>The two incremental reindex shapes `drag-lint ask` prints for a
  /// stale index.</summary>
  TReindexKind = (
    rikProject,   { index --project '<x.dproj>' --db '<db>' }
    rikSection);  { index --all --only <Section> }

  /// <summary>One reindex command parsed from the ask verb's stale-index
  /// message (exit 3).</summary>
  TReindexCommand = record
    /// <summary>Which of the two shapes it is.</summary>
    Kind       : TReindexKind;
    /// <summary>The project file, for rikProject.</summary>
    ProjectFile: string;
    /// <summary>The index database, for rikProject.</summary>
    Db         : string;
    /// <summary>The manifest section name, for rikSection.</summary>
    Section    : string;
  end;

const
  /// <summary>Longest line FormatReportAsDocInsight emits, '/// ' included --
  /// except a report header's COMMAND line, which is never wrapped. An alias of
  /// DRagLint.Charts.DocInsight.DOCINSIGHT_MAX_LINE, kept for existing callers.</summary>
  REPORT_DOC_MAX_LINE = DOCINSIGHT_MAX_LINE;

  /// <summary>Number of questions in REPORT_QUESTIONS.</summary>
  REPORT_QUESTION_COUNT = 26;

  /// <summary>Every question of charts\src\New-DiagramArtifact.ps1's
  /// ValidateSet, in menu order within each group. Grouping follows the "You
  /// select" section of docs\wiki\ask-&lt;question&gt;.md.</summary>
  /// <remarks>tests\plugin\run_reports_text.ps1 compares this list two-way
  /// against the ValidateSet, so the two cannot drift silently.</remarks>
  REPORT_QUESTIONS: array[0..REPORT_QUESTION_COUNT - 1] of TReportQuestion = (
    (Id: 'butterfly'       ; Caption: 'Callers and callees (butterfly chart)...'              ; Kind: rtkRoutine),
    (Id: 'who-calls'       ; Caption: 'Who calls this routine...'                             ; Kind: rtkRoutine),
    (Id: 'what-it-calls'   ; Caption: 'What this routine calls...'                            ; Kind: rtkRoutine),
    (Id: 'path'            ; Caption: 'Call path from this routine to another...'             ; Kind: rtkRoutine),
    (Id: 'effects'         ; Caption: 'What this routine changes (side effects)...'           ; Kind: rtkRoutine),
    (Id: 'touches-tables'  ; Caption: 'Which tables this routine touches...'                  ; Kind: rtkRoutine),
    (Id: 'exception-paths' ; Caption: 'Which exceptions escape this routine...'               ; Kind: rtkRoutine),
    (Id: 'crosses-boundary'; Caption: 'Does this routine leave the process...'                ; Kind: rtkRoutine),
    (Id: 'protocol-trace'  ; Caption: 'Where this protocol command travels...'                ; Kind: rtkRoutine),
    (Id: 'change-impact'   ; Caption: 'What a change here would break...'                     ; Kind: rtkRoutine),
    (Id: 'tested-by'       ; Caption: 'Which tests reach this code...'                        ; Kind: rtkRoutine),
    (Id: 'who-writes'      ; Caption: 'Who writes this field...'                              ; Kind: rtkMember ),
    (Id: 'who-reads'       ; Caption: 'Who reads this field...'                               ; Kind: rtkMember ),
    (Id: 'feeds-from'      ; Caption: 'What feeds this control (back to the column)...'       ; Kind: rtkMember ),
    (Id: 'lands-where'     ; Caption: 'Where this field lands in the database...'             ; Kind: rtkMember ),
    (Id: 'round-trip'      ; Caption: 'Field round-trip (grid -> server -> SQL)...'           ; Kind: rtkMember ),
    (Id: 'class-surface'   ; Caption: 'What this type exposes (class surface)...'             ; Kind: rtkType   ),
    (Id: 'hierarchy'       ; Caption: 'Ancestors and descendants (hierarchy)...'              ; Kind: rtkType   ),
    (Id: 'wiring'          ; Caption: 'Who registers and resolves this interface...'          ; Kind: rtkType   ),
    (Id: 'event-wiring'    ; Caption: 'Which handler runs on which event (form)...'           ; Kind: rtkType   ),
    (Id: 'lifecycle'       ; Caption: 'Form lifecycle (create -> show -> destroy)...'         ; Kind: rtkType   ),
    (Id: 'deps'            ; Caption: 'Dependencies of this unit...'                          ; Kind: rtkUnit   ),
    (Id: 'architecture'    ; Caption: 'Project architecture (layered zones)...'               ; Kind: rtkProject),
    (Id: 'cycles'          ; Caption: 'Circular unit dependencies...'                         ; Kind: rtkProject),
    (Id: 'consumers'       ; Caption: 'Who uses this table or column...'                      ; Kind: rtkName   ),
    (Id: 'shown-where'     ; Caption: 'Where this database column is shown...'                ; Kind: rtkName   ));

/// <summary>The section header the menu shows above a group of questions.</summary>
/// <param name="pKind">The selection kind the group is asked of.</param>
/// <returns>A non-empty, human header such as 'Routine at the cursor'.</returns>
function ReportGroupCaption(pKind: TReportTargetKind): string;

/// <summary>Looks a question up by its -Question id.</summary>
/// <param name="pId">The id, e.g. 'round-trip'; compared case-insensitively.</param>
/// <param name="pQuestion">Receives the catalog entry; a default record when
/// not found.</param>
/// <returns>True when the id is in REPORT_QUESTIONS.</returns>
function FindReportQuestion(const pId: string; out pQuestion: TReportQuestion): Boolean;

/// <summary>Turns a `drag-lint ask --plain` stdout answer into a DocInsight remarks
/// block ready to paste above a declaration.</summary>
/// <param name="pQuestionId">The question that was asked.</param>
/// <param name="pTarget">The target that was sent.</param>
/// <param name="pDate">When it was asked; only the date part is printed.</param>
/// <param name="pAnswer">The captured output of a run that exited 0.</param>
/// <returns>CRLF-separated lines, each starting with '///', opening with
/// '/// &lt;remarks&gt;' and closing with '/// &lt;/remarks&gt;'. The first
/// sentence names the question, the target and the date.</returns>
/// <remarks>Guarantees, each pinned by a test: strict 7-bit ASCII (dashes and
/// arrows become -- and ->, anything else unknown becomes '?'); no line longer
/// than REPORT_DOC_MAX_LINE (an over-long token is split); the autodoc
/// provenance marker never appears; '&lt;' and '&amp;' are XML-escaped; a
/// row's '@File.pas:line' anchor is rendered '(File.pas:line)'; the
/// '... +N more ... not shown' disclosure is kept. Dropped: the BUNDLE and
/// top-level INDEX header lines, a trace's REGENERATE line, and any
/// 'ask-report:' or 'WARNING:' line that reached the shared stdout/stderr
/// pipe. An answer with nothing left says so in a sentence.
/// An answer whose first line is the report header sentence
/// (charts\src\Ask-Report.ps1, spec section 3) keeps it, and its COMMAND line is
/// emitted on ONE line, unwrapped -- the only line allowed past
/// REPORT_DOC_MAX_LINE, because the line must rerun as typed.
/// A thin forwarder: looks pQuestionId's caption up in REPORT_QUESTIONS
/// (case-insensitive) and calls DRagLint.Charts.DocInsight.FormatAnswerAsDocInsight,
/// which owns the format.</remarks>
function FormatReportAsDocInsight(const pQuestionId, pTarget: string; pDate: TDateTime; const pAnswer: string): string;

/// <summary>Reads the "resolved" field of `drag-lint typeat --format json`.</summary>
/// <param name="pOutput">The captured output; notes printed before or after
/// the JSON document are tolerated.</param>
/// <returns>The resolved qualified name, or '' when there is none.</returns>
function ParseTypeAtResolved(const pOutput: string): string;

/// <summary>Parses the first line of a text DFM ('object frmX: TfrmX').</summary>
/// <param name="pFirstLine">The line; 'object', 'inherited' and 'inline' are
/// accepted.</param>
/// <param name="pName">Receives the root component (form instance) name.</param>
/// <param name="pClass">Receives the root class name.</param>
/// <returns>False for anything else, including a binary DFM.</returns>
function ParseDfmRootObject(const pFirstLine: string; out pName, pClass: string): Boolean;

/// <summary>Rewrites a typeat answer for a DFM control into the
/// &lt;FormInstance&gt;.&lt;Control&gt; form the control questions take.</summary>
/// <param name="pQName">Typically Unit.TForm.Control, as typeat resolves a
/// component field.</param>
/// <param name="pRootName">The DFM root instance name, '' when unknown.</param>
/// <param name="pRootClass">The DFM root class name, '' when unknown.</param>
/// <returns>pRootName + '.' + Control when the owning class equals pRootClass
/// (case-insensitive); otherwise pQName unchanged.</returns>
/// <remarks>Measured 2026-10-05 on the frozen ORM3 clones: feeds-from and
/// lands-where refuse Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName (exit
/// 1) and answer frmBlueprint4.dxDBGrid1OperationVName (exit 0); round-trip
/// accepts both. An ORM property (uCAUSFAIL.TmcCAUSFAIL.REASON) is not on the
/// form's class and is left alone.</remarks>
function FormControlTarget(const pQName, pRootName, pRootClass: string): string;

/// <summary>The unit part of a member qualified name -- where its DFM is.</summary>
/// <param name="pQName">Unit.Class.Member; the unit name may itself be dotted.</param>
/// <returns>Everything before the last two parts, or '' when the name has
/// fewer than three parts (an instance target such as frmX.Edit1 names no
/// unit).</returns>
function QNameUnitName(const pQName: string): string;

/// <summary>True for the questions whose target is a form control and so
/// should go through FormControlTarget.</summary>
/// <param name="pQuestionId">The question id.</param>
/// <returns>True for feeds-from, lands-where and round-trip.</returns>
function QuestionTakesFormControl(const pQuestionId: string): Boolean;

/// <summary>True for the questions that need a second routine (-To) besides
/// the target.</summary>
/// <param name="pQuestionId">The question id.</param>
/// <returns>True for path (routine A is the target, routine B is -To).</returns>
/// <remarks>The caret supplies routine A only; the menu prompts for B.</remarks>
function QuestionTakesSecondRoutine(const pQuestionId: string): Boolean;

/// <summary>Whether a typed target may be sent at all.</summary>
/// <param name="pTarget">The target from the prompt.</param>
/// <returns>False for an empty or blank target and for one containing a double
/// quote, which would break the quoted command-line argument.</returns>
function IsValidReportTarget(const pTarget: string): Boolean;

/// <summary>The command line that runs one question through the engine's `ask` verb.</summary>
/// <param name="pEngine">The drag-lint.exe the plugin uses.</param>
/// <param name="pQuestionId">The question id, e.g. 'who-writes'.</param>
/// <param name="pTarget">The --target value; must pass IsValidReportTarget.</param>
/// <param name="pInFile">The active file, passed as --in so the engine resolves the
/// project index itself.</param>
/// <param name="pTo">Routine B for a question that takes one (see
/// QuestionTakesSecondRoutine), passed as --to; '' omits --to. Must pass
/// IsValidReportTarget when given.</param>
/// <returns>"engine" ask &lt;id&gt; --target "t" [--to "b"] --in "f" --plain --open, so a
/// chart opens in the browser. Every value is quoted the way CommandLineToArgvW splits it (an
/// embedded quote becomes \", backslashes before a quote or the closing quote are doubled), so
/// the engine receives each value exactly.</returns>
/// <remarks>--plain is load-bearing: HandleReportDone wraps the answer in its
/// own DocInsight block (FormatReportAsDocInsight), and without --plain the
/// verb would print a block of its own, wrapped twice. No pwsh and no
/// Ask-Report.ps1 are needed here: the engine answers every question
/// in-process (all 26 since the CHARTS port).</remarks>
function BuildAskCmdLine(const pEngine, pQuestionId, pTarget, pInFile: string; const pTo: string = ''): string;
/// <summary>The reason `drag-lint ask` gave for a non-zero exit.</summary>
/// <param name="pOutput">The captured stdout+stderr.</param>
/// <returns>Everything from the first 'ask-report:' line on, with that prefix
/// removed; the trimmed output when there is no such line.</returns>
function AskReportReason(const pOutput: string): string;
/// <summary>The message for an engine that predates the `ask` verb.</summary>
/// <param name="pExit">The exit code of the ask run.</param>
/// <param name="pOutput">The captured stdout+stderr.</param>
/// <returns>'The drag-lint engine is too old for the Reports menu (no "ask" command) --
/// update the engine.' when pExit is 2 and a line of pOutput reads 'unknown command: ask'
/// (any case, any prefix such as 'ERROR: '); '' otherwise.</returns>
/// <remarks>An old engine answers `ask` with that line followed by its whole help banner,
/// which AskReportReason would otherwise put into the dialog.</remarks>
function AskEngineTooOldMessage(pExit: Integer; const pOutput: string): string;

/// <summary>The incremental reindex commands in a stale-index message.</summary>
/// <param name="pOutput">The captured output of a run that exited 3.</param>
/// <returns>One entry per recognised command, in order.</returns>
/// <remarks>Accepts exactly the two shapes `drag-lint ask` prints -- `index
/// --project '&lt;p&gt;' --db '&lt;db&gt;'` and `index --all --only
/// &lt;Section&gt;` -- and nothing else: a folder target (which would widen a
/// project DB into a directory DB) and a --rebuild are never returned.</remarks>
function ParseReindexCommands(const pOutput: string): TArray<TReindexCommand>;

implementation

uses
  System.Classes
  , System.StrUtils
  , System.JSON
  , System.RegularExpressions
  ;

const
  CRLF = #13#10;
  ASK_PREFIX = 'ask-report:';
  { Unit + Class + Member: the fewest dotted parts a member qname has }
  QNAME_MEMBER_PARTS = 3;

function ReportGroupCaption(pKind: TReportTargetKind): string;
begin
  case pKind of
    rtkRoutine: Result:= 'Routine at the cursor';
    rtkMember : Result:= 'Field, property or grid column at the cursor';
    rtkType   : Result:= 'Type at the cursor';
    rtkUnit   : Result:= 'This unit';
    rtkProject: Result:= 'This project';
  else
    Result:= 'Table or column (typed name)';
  end;
end;

function FindReportQuestion(const pId: string; out pQuestion: TReportQuestion): Boolean;
begin
  pQuestion:= Default(TReportQuestion);
  for var Q: TReportQuestion in REPORT_QUESTIONS do
    if SameText(Q.Id, pId) then
    begin
      pQuestion:= Q;
      Exit(True);
    end;
  Result:= False;
end;

{ ---- formatter: forwards to DRagLint.Charts.DocInsight ---- }

function SplitLines(const pText: string): TArray<string>;
begin
  Result:= StringReplace(StringReplace(pText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]).Split([#10]);
end;

function FormatReportAsDocInsight(const pQuestionId, pTarget: string; pDate: TDateTime; const pAnswer: string): string;
var
  Q     : TReportQuestion;
  Phrase: string;
begin
  Phrase:= '';
  if FindReportQuestion(pQuestionId, Q) then Phrase:= Q.Caption.TrimRight(['.']);
  Result:= FormatAnswerAsDocInsight(Phrase, pQuestionId, pTarget, pDate, pAnswer);
end;

{ ---- glue parsers ---- }

function ParseTypeAtResolved(const pOutput: string): string;
var
  B, E: Integer;
  V   : TJSONValue;
begin
  Result:= '';
  B:= Pos('{', pOutput);
  E:= LastDelimiter('}', pOutput);
  if (B = 0) or (E <= B) then Exit;
  V:= TJSONObject.ParseJSONValue(Copy(pOutput, B, E - B + 1));
  if V = nil then Exit;
  try
    if V is TJSONObject then Result:= Trim(TJSONObject(V).GetValue<string>('resolved', ''));
  finally
    V.Free;
  end;
end;

function ParseDfmRootObject(const pFirstLine: string; out pName, pClass: string): Boolean;
var
  M: TMatch;
begin
  pName:= '';
  pClass:= '';
  M:= TRegEx.Match(pFirstLine, '^\s*(?:object|inherited|inline)\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.]*)', [roIgnoreCase]);
  Result:= M.Success;
  if Result then
  begin
    pName:= M.Groups[1].Value;
    pClass:= M.Groups[2].Value;
  end;
end;

function FormControlTarget(const pQName, pRootName, pRootClass: string): string;
var
  Parts: TArray<string>;
begin
  Result:= pQName;
  if (pRootName = '') or (pRootClass = '') then Exit;
  Parts:= pQName.Split(['.']);
  { Unit.TForm.Control at least: the owning class is the second-to-last part }
  if Length(Parts) < QNAME_MEMBER_PARTS then Exit;
  if SameText(Parts[High(Parts) - 1], pRootClass) then
    Result:= pRootName + '.' + Parts[High(Parts)];
end;

function QNameUnitName(const pQName: string): string;
var
  Parts: TArray<string>;
begin
  Result:= '';
  Parts:= pQName.Split(['.']);
  if Length(Parts) >= QNAME_MEMBER_PARTS then
    Result:= string.Join('.', Parts, 0, Length(Parts) - (QNAME_MEMBER_PARTS - 1));
end;

function QuestionTakesFormControl(const pQuestionId: string): Boolean;
begin
  Result:= MatchText(pQuestionId, ['feeds-from', 'lands-where', 'round-trip']);
end;

function QuestionTakesSecondRoutine(const pQuestionId: string): Boolean;
begin
  Result:= SameText(pQuestionId, 'path');
end;

function IsValidReportTarget(const pTarget: string): Boolean;
begin
  Result:= (Trim(pTarget) <> '') and (Pos('"', pTarget) = 0);
end;

{ Quotes one argument for CreateProcess the way CommandLineToArgvW splits it: n backslashes
  before an embedded quote become 2n+1, n before the closing quote become 2n, others stay.
  REFERENCE: the engine's QuoteArg in src\charts\DRagLint.Charts.Process.pas --
  same rules, reproduced here because the plugin BPL does not link the charts units. }
function QuoteCmdArg(const pValue: string): string;
const
  QUOTE: Char = '"';
  BACKSLASH: Char = '\';
var
  Slashes: Integer;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append(QUOTE);
    Slashes:= 0;
    for var C in pValue do
    begin
      if C = BACKSLASH then
        Inc(Slashes)
      else
      begin
        if C = QUOTE then SB.Append(BACKSLASH, Slashes * 2 + 1)
        else SB.Append(BACKSLASH, Slashes);
        Slashes:= 0;
        SB.Append(C);
      end;
    end;
    SB.Append(BACKSLASH, Slashes * 2);
    SB.Append(QUOTE);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function BuildAskCmdLine(const pEngine, pQuestionId, pTarget, pInFile: string; const pTo: string = ''): string;
begin
  var ToArg: string:= if Trim(pTo) = '' then '' else ' --to ' + QuoteCmdArg(Trim(pTo));
  Result:= Format('%s ask %s --target %s%s --in %s --plain --open',
    [QuoteCmdArg(pEngine), pQuestionId, QuoteCmdArg(Trim(pTarget)), ToArg, QuoteCmdArg(pInFile)]);
end;
function AskReportReason(const pOutput: string): string;
var
  SB     : TStringBuilder;
  Started: Boolean;
begin
  SB:= TStringBuilder.Create;
  try
    Started:= False;
    for var Line: string in SplitLines(pOutput) do
    begin
      var T: string:= TrimLeft(Line);
      if StartsText(ASK_PREFIX, T) then
      begin
        Started:= True;
        if SB.Length > 0 then SB.Append(CRLF);
        SB.Append(Trim(Copy(T, Length(ASK_PREFIX) + 1, MaxInt)));
      end
      else if Started and (Trim(Line) <> '') then
        SB.Append(CRLF).Append(TrimRight(Line));
    end;
    if Started then Result:= SB.ToString else Result:= Trim(pOutput);
  finally
    SB.Free;
  end;
end;

function AskEngineTooOldMessage(pExit: Integer; const pOutput: string): string;
const
  UNKNOWN_ASK = 'unknown command: ask';
  EXIT_SETUP = 2;  { the engine's exit code for an unknown command }
begin
  Result:= '';
  if pExit <> EXIT_SETUP then
    Exit;
  for var Line: string in SplitLines(pOutput) do
    if EndsText(UNKNOWN_ASK, Trim(Line)) then
      Exit('The drag-lint engine is too old for the Reports menu (no "ask" command) -- update the engine.');
end;

function ParseReindexCommands(const pOutput: string): TArray<TReindexCommand>;
var
  M  : TMatch;
  Cmd: TReindexCommand;
begin
  Result:= nil;
  for var Line: string in SplitLines(pOutput) do
  begin
    Cmd:= Default(TReindexCommand);
    M:= TRegEx.Match(Line, '\sindex\s+--project\s+''([^'']+)''\s+--db\s+''([^'']+)''\s*$');
    if M.Success then
    begin
      Cmd.Kind:= rikProject;
      Cmd.ProjectFile:= M.Groups[1].Value;
      Cmd.Db:= M.Groups[2].Value;
    end
    else
    begin
      M:= TRegEx.Match(Line, '\sindex\s+--all\s+--only\s+([A-Za-z0-9_.\-]+)\s*$');
      if not M.Success then Continue;
      Cmd.Kind:= rikSection;
      Cmd.Section:= M.Groups[1].Value;
    end;
    Result:= Result + [Cmd];
  end;
end;

end.
