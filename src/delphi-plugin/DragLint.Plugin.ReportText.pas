unit DragLint.Plugin.ReportText;

{ The IDE-free half of the drag-lint > Reports submenu.

  WHY IT IS ITS OWN UNIT. DragLint.Plugin.Reports builds the menu, reads the
  caret and runs charts\src\Ask-Report.ps1; all of that is ToolsAPI-bound and
  cannot be compiled into a console test. Everything that decides WHAT is sent
  and WHAT the user is handed back lives here instead, with no ToolsAPI and no
  VCL, so tests\reportstext\ReportTextTests.dpr (DUnitX) can pin it:

    the question catalog -- every question the chart pipeline accepts, with
      a human caption and the kind of selection it is asked of;
    the DocInsight formatter -- the stdout answer as a /// <remarks> block
      that is strict 7-bit ASCII, wrapped, and NEVER carries the autodoc
      provenance marker (autodoc keeps unmarked content byte-for-byte, so a
      pasted answer survives Auto Doc runs only while it stays unmarked);
    the small parsers -- typeat JSON, a DFM root object line, Ask-Report's
      refusal reason and its stale-index reindex commands. }

interface

uses
  System.SysUtils;

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

  /// <summary>One question of charts\src\Ask-Report.ps1 as the menu offers it.</summary>
  TReportQuestion = record
    /// <summary>The -Question value, e.g. 'who-writes'.</summary>
    Id     : string;
    /// <summary>The menu caption: a human phrase ending in '...'.</summary>
    Caption: string;
    /// <summary>What the user selects for this question.</summary>
    Kind   : TReportTargetKind;
  end;

  /// <summary>The two incremental reindex shapes Ask-Report.ps1 prints for a
  /// stale index.</summary>
  TReindexKind = (
    rikProject,   { index --project '<x.dproj>' --db '<db>' }
    rikSection);  { index --all --only <Section> }

  /// <summary>One reindex command parsed from Ask-Report's stale-index
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
  /// <summary>Longest line FormatReportAsDocInsight emits, '/// ' included.
  /// Well under the 120-column ceiling so a pasted block never needs
  /// re-wrapping in an indented declaration.</summary>
  REPORT_DOC_MAX_LINE = 100;

  /// <summary>Number of questions in REPORT_QUESTIONS.</summary>
  REPORT_QUESTION_COUNT = 25;

  /// <summary>Every question of charts\src\New-DiagramArtifact.ps1's
  /// ValidateSet, in menu order within each group. Grouping follows the "You
  /// select" section of docs\wiki\ask-&lt;question&gt;.md.</summary>
  /// <remarks>tests\plugin\run_reports_text.ps1 compares this list two-way
  /// against the ValidateSet, so the two cannot drift silently.</remarks>
  REPORT_QUESTIONS: array[0..REPORT_QUESTION_COUNT - 1] of TReportQuestion = (
    (Id: 'butterfly'       ; Caption: 'Callers and callees (butterfly chart)...'              ; Kind: rtkRoutine),
    (Id: 'who-calls'       ; Caption: 'Who calls this routine...'                             ; Kind: rtkRoutine),
    (Id: 'what-it-calls'   ; Caption: 'What this routine calls...'                            ; Kind: rtkRoutine),
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

/// <summary>Turns an Ask-Report.ps1 stdout answer into a DocInsight remarks
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
/// pipe. An answer with nothing left says so in a sentence.</remarks>
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

/// <summary>Whether a typed target may be sent at all.</summary>
/// <param name="pTarget">The target from the prompt.</param>
/// <returns>False for an empty or blank target and for one containing a double
/// quote, which would break the quoted command-line argument.</returns>
function IsValidReportTarget(const pTarget: string): Boolean;

/// <summary>The command line that runs one question through Ask-Report.ps1.</summary>
/// <param name="pPwsh">Full path to pwsh.exe.</param>
/// <param name="pScript">Full path to Ask-Report.ps1.</param>
/// <param name="pQuestionId">The -Question value.</param>
/// <param name="pTarget">The -Target value; must pass IsValidReportTarget.</param>
/// <param name="pInFile">The active file, passed as -In so the script resolves
/// the project index itself.</param>
/// <param name="pEngine">The drag-lint.exe the plugin uses, passed as -Engine.</param>
/// <returns>A quoted command line ending in -Open, so a chart opens in the
/// browser.</returns>
function BuildAskReportCmdLine(const pPwsh, pScript, pQuestionId, pTarget, pInFile, pEngine: string): string;

/// <summary>The reason Ask-Report.ps1 gave for a non-zero exit.</summary>
/// <param name="pOutput">The captured stdout+stderr.</param>
/// <returns>Everything from the first 'ask-report:' line on, with that prefix
/// removed; the trimmed output when there is no such line.</returns>
function AskReportReason(const pOutput: string): string;

/// <summary>The incremental reindex commands in a stale-index message.</summary>
/// <param name="pOutput">The captured output of a run that exited 3.</param>
/// <returns>One entry per recognised command, in order.</returns>
/// <remarks>Accepts exactly the two shapes Ask-Report.ps1 prints -- `index
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
  DOC_PREFIX = '/// ';
  DOC_EMPTY = '///';
  CRLF = #13#10;
  { The autodoc provenance marker, assembled so this unit's own source never
    contains it as one literal. }
  AUTODOC_MARKER = 'drag-lint' + ':auto';
  AUTODOC_MARKER_SAFE = 'drag-lint auto';
  ASK_PREFIX = 'ask-report:';
  { leading spaces above which a trace line is a continuation of the one above }
  CONTINUATION_INDENT = 2;
  WRAP_INDENT = '  ';
  ROW_INDENT = '  ';
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

{ ---- formatter helpers ---- }

type
  TCharSubst = record
    Code: Char;
    Text: string;
  end;

const
  { The non-ASCII characters an answer is known to carry (the chart labels and
    the trace use dashes, arrows and typographic quotes), each with a readable
    ASCII stand-in. Anything else outside 7-bit becomes '?'. }
  CHAR_SUBSTS: array[0..19] of TCharSubst = (
    (Code: #$00A0; Text: ' '  ), (Code: #$00B7; Text: '*'  ), (Code: #$2022; Text: '*'  ),
    (Code: #$00D7; Text: 'x'  ), (Code: #$2010; Text: '-'  ), (Code: #$2011; Text: '-'  ),
    (Code: #$2012; Text: '--' ), (Code: #$2013; Text: '--' ), (Code: #$2014; Text: '--' ),
    (Code: #$2015; Text: '--' ), (Code: #$2018; Text: '''' ), (Code: #$2019; Text: '''' ),
    (Code: #$201A; Text: '''' ), (Code: #$201C; Text: '"'  ), (Code: #$201D; Text: '"'  ),
    (Code: #$201E; Text: '"'  ), (Code: #$2026; Text: '...'), (Code: #$2190; Text: '<-' ),
    (Code: #$2192; Text: '->' ), (Code: #$21D2; Text: '=>' ));

function ScrubChar(pC: Char): string;
begin
  if (pC >= ' ') and (pC <= '~') then Exit(pC);
  if pC < ' ' then Exit(' '); { tab and any other control character }
  for var S: TCharSubst in CHAR_SUBSTS do
    if S.Code = pC then Exit(S.Text);
  Result:= '?';
end;

{ One line at a time, so the caller never has to think about CR/LF here. }
function ScrubLine(const pLine: string): string;
var
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    for var C: Char in pLine do SB.Append(ScrubChar(C));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function RemoveAutodocMarker(const pText: string): string;
begin
  Result:= pText;
  while ContainsText(Result, AUTODOC_MARKER) do
    Result:= StringReplace(Result, AUTODOC_MARKER, AUTODOC_MARKER_SAFE, [rfReplaceAll, rfIgnoreCase]);
end;

function XmlEscape(const pText: string): string;
begin
  Result:= StringReplace(pText , '&', '&amp;', [rfReplaceAll]);
  Result:= StringReplace(Result, '<', '&lt;' , [rfReplaceAll]);
end;

{ ' @File.pas:12' -> ' (File.pas:12)'; only a token that looks like a file. }
function RenderAnchors(const pLine: string): string;
begin
  Result:= TRegEx.Replace(pLine, '(^|\s)@([^\s@]+\.[A-Za-z0-9]+(?::\d+)?)(?=$|[\s,;])', '$1($2)');
end;

function LeadingSpaces(const pLine: string): Integer;
begin
  Result:= 0;
  while (Result < Length(pLine)) and (pLine[Result + 1] = ' ') do Inc(Result);
end;

function SplitLines(const pText: string): TArray<string>;
begin
  Result:= StringReplace(StringReplace(pText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]).Split([#10]);
end;

{ Word-wraps one logical line into /// lines no longer than REPORT_DOC_MAX_LINE.
  Continuation lines get two more spaces of indent; a token longer than the
  room left is cut, never dropped. }
procedure EmitWrapped(pOut: TStringBuilder; const pIndent, pText: string);
var
  Room   : Integer;
  Current: string;
  Lead   : string;

  procedure Flush;
  begin
    pOut.Append(DOC_PREFIX).Append(Lead).Append(Current).Append(CRLF);
    Current:= '';
    Lead:= pIndent + WRAP_INDENT;
  end;

begin
  Lead:= pIndent;
  Current:= '';
  for var Word0: string in pText.Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    var Word: string:= Word0;
    repeat
      Room:= REPORT_DOC_MAX_LINE - Length(DOC_PREFIX) - Length(Lead);
      if Current = '' then
      begin
        if Length(Word) <= Room then
        begin
          Current:= Word;
          Word:= '';
        end
        else
        begin
          Current:= Copy(Word, 1, Room);
          Word:= Copy(Word, Room + 1, MaxInt);
          Flush;
        end;
      end
      else if Length(Current) + 1 + Length(Word) <= Room then
      begin
        Current:= Current + ' ' + Word;
        Word:= '';
      end
      else Flush;
    until Word = '';
  end;
  if Current <> '' then Flush;
end;

{ One answer line -> the text to emit for it, its indent, and whether it is
  kept at all. }
function RenderAnswerLine(const pRaw: string; out pIndent, pText: string): Boolean;
var
  Trimmed: string;
begin
  pIndent:= '';
  pText:= '';
  Trimmed:= Trim(pRaw);
  Result:= False;
  if StartsText(ASK_PREFIX, Trimmed) or StartsText('WARNING:', Trimmed) then Exit;
  { top-level BUNDLE / INDEX lines name Ask-Report's own temp folder and the
    databases -- provenance for a terminal, noise in a doc comment. A trace's
    OWN '  INDEX <names> AS OF' line is indented, and kept. }
  if StartsStr('BUNDLE ', pRaw) or StartsStr('INDEX ', pRaw) then Exit;
  if StartsStr('REGENERATE ', Trimmed) then Exit;
  if StartsStr('CHART ', pRaw) then
  begin
    var P: Integer:= Pos(' -- ', pRaw);
    if P = 0 then Exit;
    pText:= 'Totals: ' + Trim(Copy(pRaw, P + Length(' -- '), MaxInt)) + '.';
    Exit(True);
  end;
  if StartsStr('TARGET ', Trimmed) then
    pText:= 'Selected: ' + RenderAnchors(Trim(Copy(Trimmed, Length('TARGET ') + 1, MaxInt)))
  else
    pText:= RenderAnchors(Trimmed);
  if LeadingSpaces(pRaw) > CONTINUATION_INDENT then pIndent:= ROW_INDENT;
  Result:= pText <> '';
end;

function FormatReportAsDocInsight(const pQuestionId, pTarget: string; pDate: TDateTime; const pAnswer: string): string;
var
  SB       : TStringBuilder;
  Q        : TReportQuestion;
  Phrase   : string;
  Indent   : string;
  Text     : string;
  Findings : Integer;
  PendBreak: Boolean;
begin
  if FindReportQuestion(pQuestionId, Q) then Phrase:= Q.Caption.TrimRight(['.'])
  else Phrase:= 'Report';
  SB:= TStringBuilder.Create;
  try
    SB.Append(DOC_PREFIX).Append('<remarks>').Append(CRLF);
    EmitWrapped(SB, '', XmlEscape(ScrubLine(Format('%s (drag-lint report %s) for %s, asked on %s.',
      [Phrase, pQuestionId, pTarget, FormatDateTime('yyyy-mm-dd', pDate)]))));
    Findings:= 0;
    PendBreak:= True;
    for var Raw: string in SplitLines(pAnswer) do
    begin
      var Line: string:= ScrubLine(TrimRight(Raw));
      if Trim(Line) = '' then
      begin
        PendBreak:= True;
        Continue;
      end;
      if not RenderAnswerLine(Line, Indent, Text) then Continue;
      if PendBreak then SB.Append(DOC_EMPTY).Append(CRLF);
      PendBreak:= False;
      EmitWrapped(SB, Indent, XmlEscape(Text));
      Inc(Findings);
    end;
    if Findings = 0 then
    begin
      SB.Append(DOC_EMPTY).Append(CRLF);
      EmitWrapped(SB, '', 'The report returned no findings.');
    end;
    SB.Append(DOC_PREFIX).Append('</remarks>').Append(CRLF);
    Result:= RemoveAutodocMarker(SB.ToString);
  finally
    SB.Free;
  end;
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

function IsValidReportTarget(const pTarget: string): Boolean;
begin
  Result:= (Trim(pTarget) <> '') and (Pos('"', pTarget) = 0);
end;

function BuildAskReportCmdLine(const pPwsh, pScript, pQuestionId, pTarget, pInFile, pEngine: string): string;
begin
  Result:= Format('"%s" -NoProfile -NonInteractive -File "%s" -Question %s -Target "%s" -In "%s" -Engine "%s" -Open',
                  [pPwsh, pScript, pQuestionId, Trim(pTarget), pInFile, pEngine]);
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
