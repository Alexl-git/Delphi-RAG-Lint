unit DragLint.Plugin.Cmd.CheckInit;

{ 1.52 command, owned by lane HBIDE (ruling HB1): "Check Initialization of
  Identifier at Cursor..." in the drag-lint main menu (submenu Analyze) and in
  the code editor's right-click menu (submenu drag-lint).

  The click saves nothing and edits nothing: it shells
  `drag-lint check-init --at "<file>:<line>:<col>" --db "<db>" --json` off the
  main thread and posts the answer to the IDE Messages window -- a title line
  with the verdict, one clickable line per judged use, its witness hops
  indented under it, one clickable line per writer, and the limits.

  The pure parts (command line, JSON -> message lines) are public and free of
  ToolsAPI, so tests\plugin\run_v152_HBIDE_menu.ps1 compiles this unit into a
  console program; the IDE parts sit behind a not-CONSOLE conditional.
  DragLint.Plugin.Editor is not edited. }

interface

type
  /// <summary>How one check-init message line is posted.</summary>
  /// <remarks>cmTitle = IOTAMessageServices.AddTitleMessage (no location);
  /// cmTool = AddToolMessage, clickable when FileName is not ''.</remarks>
  TCheckInitMsgKind = (cmTitle, cmTool);

  /// <summary>One line for the IDE Messages window.</summary>
  TCheckInitMsg = record
    /// <summary>Title or tool line.</summary>
    Kind: TCheckInitMsgKind;
    /// <summary>The file a double-click opens; '' = not navigable.</summary>
    FileName: string;
    /// <summary>The message text.</summary>
    Text: string;
    /// <summary>1-based line; 0 when FileName is ''.</summary>
    Line: Integer;
    /// <summary>1-based column; 0 when unknown.</summary>
    Col: Integer;
  end;

/// <summary>The engine command line that judges the use under the caret.</summary>
/// <param name="pExe">Full path of the engine exe; quoted in the result.</param>
/// <param name="pFileName">The editor file; quoted together with line and col.</param>
/// <param name="pDb">The project index; quoted in the result.</param>
/// <param name="pLine">1-based caret line.</param>
/// <param name="pCol">1-based caret column.</param>
/// <returns>'"exe" check-init --at "file:line:col" --db "db" --json'.</returns>
/// <remarks>Pure. No QName is passed: check-init resolves the identifier at
/// --at itself and judges that use at its real column.</remarks>
function CheckInitCommandLine(const pExe, pFileName, pDb: string; pLine, pCol: Integer): string;  // dl:ok unused-public-symbol@067d -- test seam: run_v152_HBIDE_menu.ps1 calls it from a console build outside the plugin index

/// <summary>Turns the engine's check-init answer into Messages lines.</summary>
/// <param name="pOutput">The engine's stdout (the --json document, or an
/// error text).</param>
/// <param name="pExitCode">The engine's exit code: 0 all SET, 1 some use not
/// SET, anything else an error.</param>
/// <returns>Never empty. Element 0 is the title (cmTitle):
/// 'check-init QName: VERDICT' plus ' -- summary' when there is one. Then, for
/// the verdict UNKNOWN-CALLEE, one unlocated hint line on how to answer the
/// callee; one clickable line per use ('use in Routine: VERDICT [reasons] --
/// why'), each followed by its witness hops ('  step. Routine: note');
/// one clickable line per writer ('writer Routine (how[, fired by X][,
/// unresolved][, not counted]), N caller(s)'); one unlocated line per limit
/// ('limit: text'). A verdict the plugin does not know is shown verbatim.
/// When the exit code is not 0 or 1, or the output holds no JSON object, the
/// single title 'check-init failed (exit N): first line of output'.</returns>
/// <remarks>Pure; tolerant of missing keys (a missing string is '', a missing
/// number 0).</remarks>
function CheckInitMessages(const pOutput: string; pExitCode: Integer): TArray<TCheckInitMsg>;  // dl:ok unused-public-symbol@4c77 -- test seam: run_v152_HBIDE_menu.ps1 calls it from a console build outside the plugin index

implementation

uses
  System.SysUtils,
  System.JSON,
  {$IFNDEF CONSOLE}
  System.Classes,
  Vcl.Dialogs,
  ToolsAPI,
  DragLint.Plugin.ExeResolver,
  DragLint.Plugin.ProcRun,
  DragLint.Plugin.Editor,
  {$ENDIF}
  DragLint.Plugin.Cmd152;

const
  COMMAND_ID = 'check-init';
  VERDICT_UNKNOWN_CALLEE = 'UNKNOWN-CALLEE';
  { How to answer an unresolved callee (lane HBTAIL H-CONFIG). }
  UNKNOWN_CALLEE_HINT = VERDICT_UNKNOWN_CALLEE + ': a call the index cannot resolve may set it; answer the callee in '
    + '<project>\_D-RAG\drag-lint-project.json "checkInit": {"callees": {"<Name>": "sets" or "reads"}}';
  { Exit codes of an answer; anything else is an error. }
  EXIT_ALL_SET = 0;
  EXIT_NOT_ALL_SET = 1;

function CheckInitCommandLine(const pExe, pFileName, pDb: string; pLine, pCol: Integer): string;
begin
  Result:= Format('"%s" check-init --at "%s:%d:%d" --db "%s" --json', [pExe, pFileName, pLine, pCol, pDb]);
end;

function Msg(pKind: TCheckInitMsgKind; const pFileName, pText: string; pLine, pCol: Integer): TCheckInitMsg;
begin
  Result.Kind:= pKind;
  Result.FileName:= pFileName;
  Result.Text:= pText;
  Result.Line:= pLine;
  Result.Col:= pCol;
end;

{ A tool line located at the site fields (file, line, col) of pObj. }
function SiteMsg(pObj: TJSONObject; const pText: string): TCheckInitMsg;
begin
  Result:= Msg(cmTool, pObj.GetValue<string>('file', ''), pText,
    pObj.GetValue<Integer>('line', 0), pObj.GetValue<Integer>('col', 0));
end;

{ The array under pKey, or nil when absent or not an array. }
function ArrayOf(pObj: TJSONObject; const pKey: string): TJSONArray;
begin
  Result:= nil;
  var V: TJSONValue:= pObj.GetValue(pKey);
  if V is TJSONArray then Result:= TJSONArray(V);
end;

{ The string items of pArr joined with ', '. }
function JoinStrings(pArr: TJSONArray): string;
begin
  var Items: TArray<string>:= nil;
  if pArr <> nil then
    for var V in pArr do Items:= Items + [V.Value];
  Result:= string.Join(', ', Items);
end;

function FailedMsg(pExitCode: Integer; const pOutput: string): TCheckInitMsg;
begin
  var First: string:= Trim(pOutput);
  var Eol: Integer:= First.IndexOfAny([#13, #10]);
  if Eol >= 0 then First:= Trim(First.Substring(0, Eol));
  if First = '' then First:= 'no output';
  Result:= Msg(cmTitle, '', Format('check-init failed (exit %d): %s', [pExitCode, First]), 0, 0);
end;

procedure AddUse(pUse: TJSONObject; var pMsgs: TArray<TCheckInitMsg>);
begin
  var Text: string:= 'use in ' + pUse.GetValue<string>('routine', '') + ': ' + pUse.GetValue<string>('verdict', '');
  var Reasons: string:= JoinStrings(ArrayOf(pUse, 'reasons'));
  if Reasons <> '' then Text:= Text + ' [' + Reasons + ']';
  var Why: string:= pUse.GetValue<string>('why', '');
  if Why <> '' then Text:= Text + ' -- ' + Why;
  pMsgs:= pMsgs + [SiteMsg(pUse, Text)];
  var Witness: TJSONArray:= ArrayOf(pUse, 'witness');
  if Witness = nil then Exit;
  for var V in Witness do
    if V is TJSONObject then
    begin
      var Hop: TJSONObject:= TJSONObject(V);
      var HopText: string:= Format('  %d. %s', [Hop.GetValue<Integer>('step', 0), Hop.GetValue<string>('routine', '')]);
      var Note: string:= Hop.GetValue<string>('note', '');
      if Note <> '' then HopText:= HopText + ': ' + Note;
      pMsgs:= pMsgs + [SiteMsg(Hop, HopText)];
    end;
end;

function WriterText(pWriter: TJSONObject): string;
begin
  Result:= 'writer ' + pWriter.GetValue<string>('routine', '') + ' (' + pWriter.GetValue<string>('how', '');
  var FiredBy: string:= pWriter.GetValue<string>('fired_by', '');
  if FiredBy <> '' then Result:= Result + ', fired by ' + FiredBy;
  if not pWriter.GetValue<Boolean>('resolved', True) then Result:= Result + ', unresolved';
  if not pWriter.GetValue<Boolean>('counts', True) then Result:= Result + ', not counted';
  var Callers: Integer:= 0;
  var CallersObj: TJSONValue:= pWriter.GetValue('callers');
  if CallersObj is TJSONObject then Callers:= TJSONObject(CallersObj).GetValue<Integer>('count', 0);
  Result:= Result + Format('), %d caller(s)', [Callers]);
end;

{ The Messages lines of a parsed answer. }
function AnswerMsgs(pDoc: TJSONObject): TArray<TCheckInitMsg>;
begin
  var QName: string:= '';
  var Target: TJSONValue:= pDoc.GetValue('target');
  if Target is TJSONObject then QName:= TJSONObject(Target).GetValue<string>('qname', '');
  var Verdict: string:= pDoc.GetValue<string>('verdict', '');
  var Title: string:= 'check-init ' + QName + ': ' + Verdict;
  var Summary: string:= pDoc.GetValue<string>('summary', '');
  if Summary <> '' then Title:= Title + ' -- ' + Summary;
  Result:= [Msg(cmTitle, '', Title, 0, 0)];
  if Verdict = VERDICT_UNKNOWN_CALLEE then Result:= Result + [Msg(cmTool, '', UNKNOWN_CALLEE_HINT, 0, 0)];
  var Arr: TJSONArray:= ArrayOf(pDoc, 'uses');
  if Arr <> nil then
    for var V in Arr do
      if V is TJSONObject then AddUse(TJSONObject(V), Result);
  Arr:= ArrayOf(pDoc, 'writers');
  if Arr <> nil then
    for var V in Arr do
      if V is TJSONObject then Result:= Result + [SiteMsg(TJSONObject(V), WriterText(TJSONObject(V)))];
  Arr:= ArrayOf(pDoc, 'limits');
  if Arr <> nil then
    for var V in Arr do Result:= Result + [Msg(cmTool, '', 'limit: ' + V.Value, 0, 0)];
end;

function CheckInitMessages(const pOutput: string; pExitCode: Integer): TArray<TCheckInitMsg>;
begin
  Result:= [FailedMsg(pExitCode, pOutput)];
  if (pExitCode <> EXIT_ALL_SET) and (pExitCode <> EXIT_NOT_ALL_SET) then Exit;
  { The engine writes one JSON document; anything before its first brace is not part of it. }
  var Start: Integer:= pOutput.IndexOf('{');
  if Start < 0 then Exit;
  var Doc: TJSONValue:= TJSONObject.ParseJSONValue(pOutput.Substring(Start));
  try
    if Doc is TJSONObject then Result:= AnswerMsgs(TJSONObject(Doc));
  finally
    Doc.Free;
  end;
end;

{$IFNDEF CONSOLE}

{ One check-init run must not outlive a click by much; a hung engine is killed. }
const
  CHECK_TIMEOUT_MS = 120000;

{ The caret's file, 1-based line and 1-based column in the top editor; False when no editor is open. }
function CaretAt(out pFileName: string; out pLine, pCol: Integer): Boolean;
var
  ESS: IOTAEditorServices;
  EV : IOTAEditView;
begin
  Result:= False;
  pFileName:= '';
  pLine:= 0;
  pCol:= 0;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then Exit;
  pFileName:= EV.Buffer.FileName;
  pLine:= EV.CursorPos.Line;
  pCol:= EV.CursorPos.Col;
  Result:= pFileName <> '';
end;

procedure PostMessages(const pMsgs: TArray<TCheckInitMsg>);
var
  MS: IOTAMessageServices;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, MS) then Exit;
  for var M in pMsgs do
    if M.Kind = cmTitle then MS.AddTitleMessage(M.Text)
    else MS.AddToolMessage(M.FileName, M.Text, 'drag-lint', M.Line, M.Col);
end;

procedure InvokeCheckInit(Sender: TObject);
var
  FileName: string;
  Line    : Integer;
  Col     : Integer;
begin
  if not CaretAt(FileName, Line, Col) then
  begin
    ShowMessage('drag-lint: put the caret on a variable or field in an editor first.');
    Exit;
  end;
  var Exe: string:= EngineExeOrEmpty;
  var Db : string:= ResolvePrimaryIndexDb;
  if (Exe = '') or (Db = '') then
  begin
    ShowMessage('drag-lint: no engine or no project index.');
    Exit;
  end;
  var Cmd: string:= CheckInitCommandLine(Exe, FileName, Db, Line, Col);
  { Off the main thread; Synchronize, not Queue: nothing stays queued if the package unloads. }
  TThread.CreateAnonymousThread(
    procedure
    var
      Output  : string;
      ExitCode: Integer;
    begin
      Output:= '';
      try
        ExitCode:= RunCaptureStdout(Cmd, Output, CHECK_TIMEOUT_MS);
      except
        on E: Exception do
        begin
          ExitCode:= -1;
          Output:= E.ClassName + ': ' + E.Message;
        end;
      end;
      var Msgs: TArray<TCheckInitMsg>:= CheckInitMessages(Output, ExitCode);
      TThread.Synchronize(TThread.CurrentThread,
        procedure
        begin
          PostMessages(Msgs);
        end);
    end).Start;
end;

{$ELSE}

procedure InvokeCheckInit(Sender: TObject);
begin
  Cmd152NotYetAvailable(COMMAND_ID);
end;

{$ENDIF}

procedure RegisterCommand;
var
  Command: TCmd152Command;
begin
  Command.Id:= COMMAND_ID;
  Command.OwnerLane:= 'HBIDE';
  Command.ParentPath:= 'Analyze';
  Command.AfterCaption:= '';
  Command.Caption:= 'Check Initialization of Identifier at Cursor...';
  Command.Visible:= True;
  Command.Click:= InvokeCheckInit;
  Command.Surfaces:= [csMainMenu, csEditorContext];
  Command.Needs:= cnSymbol;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.