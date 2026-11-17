unit DragLint.Plugin.Cmd.FixMarker;

{ 1.52 command, owned by lane VSFIX: RAD Studio parity of the LSP "Fix with drag-lint" code action: apply the autofix of the finding at the cursor.

  Registered in the 1.52 command table (DragLint.Plugin.Cmd152) by the initialization
  section below; DragLint.Plugin.Editor is not edited. The command reads the finding the
  diagnostics cache holds for the caret's line (a Problems / marker entry), asks Yes = apply /
  No = preview, and runs the engine's own fixer: `lint --in <file> --fix --fix-line <n> --fix-rule <rule> [--apply]`.
  Same engine call as the CLI and the LSP quick-fix, so the three produce the same bytes. }

interface

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,
  DragLint.Plugin.Cmd152,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.ExeResolver,
  DragLint.Plugin.ProcRun,
  DragLint.Plugin.Editor;

const
  COMMAND_ID = 'fix-marker';
  { One finding, one line: a fix that needs longer than this is hung. }
  FIX_TIMEOUT_MS = 60000;
  { The engine's answer is shown in a dialog, so only its head. }
  OUTPUT_SHOW_MAX = 800;

{ The caret's file and 0-based line in the top editor; False when no editor is open. }
function CaretPosition(out pFileName: string; out pLine0: Integer): Boolean;
var
  ESS: IOTAEditorServices;
  EV : IOTAEditView      ;
begin
  Result:= False;
  pFileName:= '';
  pLine0:= 0;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EV:= ESS.TopView;
  if (EV = nil) or (EV.Buffer = nil) then Exit;
  pFileName:= EV.Buffer.FileName;
  pLine0:= EV.Position.Row - 1; { the diagnostics cache is 0-based }
  Result:= pFileName <> '';
end;

{ The drag-lint rule the cache holds for the line: the first diagnostic from drag-lint with a code
  (compiler findings carry a dcc source and are not fixed here). '' when the line has none. }
function RuleAtLine(const pFileName: string; pLine0: Integer): string;
begin
  Result:= '';
  for var D: TDragLintDiagnostic in Cache.GetForLine(pFileName, pLine0) do
    if (D.Code <> '') and StartsText('drag-lint', D.Source) then Exit(D.Code);
end;

{ The engine command for the fix of one rule on one line; pApply False = a dry-run preview. }
function FixCommandLine(const pExe, pFileName, pDb, pRule: string; pLine1: Integer; pApply: Boolean): string;
begin
  Result:= Format('"%s" lint --in "%s" --db "%s" --fix --fix-line %d --fix-rule "%s"%s',
    [pExe, pFileName, pDb, pLine1, pRule, IfThen(pApply, ' --apply', '')]);
end;

procedure InvokeFixMarker(Sender: TObject);
var
  FileName: string ;
  Line0   : Integer;
  Rule    : string ;
  Db      : string ;
  Exe     : string ;
  Apply   : Boolean;
  Cmd     : string ;
begin
  if not CaretPosition(FileName, Line0) then
  begin
    ShowMessage('drag-lint: put the caret on the finding''s line in an editor first.');
    Exit;
  end;
  Rule:= RuleAtLine(FileName, Line0);
  if Rule = '' then
  begin
    ShowMessage(Format('drag-lint: no drag-lint finding on line %d.', [Line0 + 1]));
    Exit;
  end;
  Exe:= EngineExeOrEmpty;
  Db := ResolvePrimaryIndexDb;
  if (Exe = '') or (Db = '') then
  begin
    ShowMessage('drag-lint: no engine or no project index.');
    Exit;
  end;
  case MessageDlg(Format('Fix %s on line %d with drag-lint?', [Rule, Line0 + 1]) + sLineBreak + sLineBreak +
                  'Yes = apply now (the engine keeps a backup copy)' + sLineBreak +
                  'No  = preview only (nothing is changed)', mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes: Apply:= True;
    mrNo : Apply:= False;
  else
    Exit;
  end;
  if Apply then
  begin
    var MS: IOTAModuleServices;
    if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll; { the engine edits the file on disk }
  end;
  Cmd:= FixCommandLine(Exe, FileName, Db, Rule, Line0 + 1, Apply);
  { Off the main thread: the engine may take seconds. Only the process run is in the worker; the dialog runs back on the main thread (Synchronize, not Queue: nothing stays queued if the package unloads). }
  TThread.CreateAnonymousThread(
    procedure
    var
      Output: string;
    begin
      Output:= '';
      try
        RunCaptureStdout(Cmd, Output, FIX_TIMEOUT_MS);
      except
        on E: Exception do Output:= 'drag-lint: command failed: ' + E.ClassName + ': ' + E.Message;
      end;
      if Trim(Output) = '' then Output:= '(no output -- the engine produced nothing)';
      TThread.Synchronize(TThread.CurrentThread,
        procedure
        begin
          ShowMessage(Copy(Output, 1, OUTPUT_SHOW_MAX));
        end);
    end).Start;
end;

procedure RegisterCommand;
var
  Command: TCmd152Command;
begin
  Command.Id:= COMMAND_ID;
  Command.OwnerLane:= 'VSFIX';
  Command.ParentPath:= 'Code Quality';
  Command.AfterCaption:= '';
  Command.Caption:= 'Fix with drag-lint (finding at cursor)';
  Command.Visible:= True;
  Command.Click:= InvokeFixMarker;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.
