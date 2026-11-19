unit DragLint.Plugin.Cmd.ExtractConst;

{ 1.52 command, owned by lane XCONST: Extract the literal at the cursor into a named constant and
  replace every occurrence in the unit (ruling B4-2, PLAN D6).

  Registered in the 1.52 command table (DragLint.Plugin.Cmd152) by the initialization section
  below; DragLint.Plugin.Editor is not edited. The command saves the editors (the engine edits the
  file on disk), asks the engine for the PLAN of the literal under the caret -- a preview of the
  on-demand rule extract-constant: `lint --in <file> --db <db> --enable extract-constant --fix
  --fix-rule extract-constant --fix-line <n> --col <c>` -- and shows a name prompt pre-filled with
  the engine's proposal. OK runs the same command with --name <ident> --apply. Same engine call as
  the CLI, so the two produce the same bytes. Manual only: there is no "all literals" variant. }

interface

implementation

uses
  System.SysUtils,
  System.Classes,
  System.RegularExpressions,
  Vcl.Dialogs,
  ToolsAPI,
  DragLint.Plugin.Cmd152,
  DragLint.Plugin.ExeResolver,
  DragLint.Plugin.ProcRun,
  DragLint.Plugin.Editor;

const
  COMMAND_ID = 'extract-constant';
  { One literal, one unit: a plan that needs longer than this is hung. }
  PLAN_TIMEOUT_MS = 60000;
  { The engine's answer is shown in a dialog, so only its head. }
  OUTPUT_SHOW_MAX = 1200;
  { The engine's plan line: `extract-constant: name <Name> = <literal> (...)`. }
  PLAN_NAME_PATTERN = 'extract-constant: name (\S+) = ';

{ The caret's file, 1-based line and 1-based column in the top editor; False when no editor is open. }
function CaretAt(out pFileName: string; out pLine, pCol: Integer): Boolean;
var
  ESS: IOTAEditorServices;
  EV : IOTAEditView      ;
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

{ The engine command for the plan (pName = '', pApply False) or the applied extraction. }
function ExtractCommandLine(const pExe, pFileName, pDb, pName: string; pLine, pCol: Integer; pApply: Boolean): string;
begin
  Result:= Format('"%s" lint --in "%s" --db "%s" --enable %s --fix --fix-rule %s --fix-line %d --col %d',
    [pExe, pFileName, pDb, COMMAND_ID, COMMAND_ID, pLine, pCol]);
  if pName <> '' then Result:= Result + ' --name "' + pName + '"';
  if pApply then Result:= Result + ' --apply';
end;

{ Runs pCmd off the main thread and hands its output to pDone back on the main thread
  (Synchronize, not Queue: nothing stays queued if the package unloads). }
procedure RunThen(const pCmd: string; const pDone: TProc<string>);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Output: string;
    begin
      Output:= '';
      try
        RunCaptureStdout(pCmd, Output, PLAN_TIMEOUT_MS);
      except
        on E: Exception do Output:= 'drag-lint: command failed: ' + E.ClassName + ': ' + E.Message;
      end;
      if Trim(Output) = '' then Output:= '(no output -- the engine produced nothing)';
      TThread.Synchronize(TThread.CurrentThread,
        procedure
        begin
          pDone(Output);
        end);
    end).Start;
end;

procedure InvokeExtractConst(Sender: TObject);
var
  FileName: string ;
  Line    : Integer;
  Col     : Integer;
  Db      : string ;
  Exe     : string ;
begin
  if not CaretAt(FileName, Line, Col) then
  begin
    ShowMessage('drag-lint: put the caret on a number or string literal in an editor first.');
    Exit;
  end;
  Exe:= EngineExeOrEmpty;
  Db := ResolvePrimaryIndexDb;
  if (Exe = '') or (Db = '') then
  begin
    ShowMessage('drag-lint: no engine or no project index.');
    Exit;
  end;
  var MS: IOTAModuleServices;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll; { the engine reads and edits the file on disk }
  RunThen(ExtractCommandLine(Exe, FileName, Db, '', Line, Col, False),
    procedure(pPlan: string)
    begin
      var M: TMatch:= TRegEx.Match(pPlan, PLAN_NAME_PATTERN);
      if not M.Success then
      begin
        ShowMessage(Copy(pPlan, 1, OUTPUT_SHOW_MAX));
        Exit;
      end;
      var Name: string:= M.Groups[1].Value;
      if not InputQuery('drag-lint: Extract Constant',
        'Constant name (every occurrence of the literal in the unit is replaced):', Name) then Exit;
      Name:= Trim(Name);
      if Name = '' then Exit;
      RunThen(ExtractCommandLine(Exe, FileName, Db, Name, Line, Col, True),
        procedure(pResult: string)
        begin
          ShowMessage(Copy(pResult, 1, OUTPUT_SHOW_MAX));
        end);
    end);
end;

procedure RegisterCommand;
var
  Command: TCmd152Command;
begin
  Command.Id:= COMMAND_ID;
  Command.OwnerLane:= 'XCONST';
  Command.ParentPath:= '';
  Command.AfterCaption:= 'Extract Method (selection)... (Ctrl+Alt+M)';
  Command.Caption:= 'Extract Constant (literal at cursor)...';
  Command.Visible:= True;
  Command.Click:= InvokeExtractConst;
  Command.Surfaces:= [csMainMenu, csEditorContext];
  Command.Needs:= cnNothing;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.
