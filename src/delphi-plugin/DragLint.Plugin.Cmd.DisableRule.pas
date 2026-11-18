unit DragLint.Plugin.Cmd.DisableRule;

{ 1.52 command, owned by lane DISRULE: "Disable Rule..." for the finding at the cursor --
  this line, this unit or this project (ruling B4-3, PLAN section 5 D1).

  Registered in the 1.52 command table (DragLint.Plugin.Cmd152) by the initialization
  section below; DragLint.Plugin.Editor is not edited. The command reads the rule the
  diagnostics cache holds for the caret's line, asks for the scope (three command links,
  in the D1 order) and a one-line reason, and runs the engine's own verb:
    rules disable --rule <id> --scope line|unit|project --in <F> --line <N> --reason "..." [--project <P>]
  Same engine call as the CLI, so the marker / config entry is byte-identical.
  Line scope writes a dl:ok marker into the source (all editors are saved first);
  unit and project scope write the active project's drag-lint-lint.json only.
  `rules enable` (CLI) undoes any of the three; the Lint Options dock shows the config entries. }

interface

implementation

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Vcl.Dialogs,
  ToolsAPI,  // dl:ok used-unit-not-resolvable@2cd2 -- REVIEWED 2026-11-17: v152 DISRULE: ToolsAPI is the IDE's design-time unit (source\ToolsAPI), outside the library index; same finding on Cmd.FixMarker; index gap logged
  DragLint.Plugin.Cmd152,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.ExeResolver,
  DragLint.Plugin.ProcRun;

const
  COMMAND_ID = 'disable-rule';
  { A config edit or one marker: anything longer than this is hung. }
  RUN_TIMEOUT_MS = 60000;
  { The engine's answer is shown in a dialog, so only its head. }
  OUTPUT_SHOW_MAX = 800;
  { TTaskDialog command-link ids, one per scope (D1 order). }
  ID_LINE    = 101;
  ID_UNIT    = 102;
  ID_PROJECT = 103;

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

{ The first drag-lint rule the cache holds for the line; '' when the line has none. }
function RuleAtLine(const pFileName: string; pLine0: Integer): string;
begin
  Result:= '';
  for var D: TDragLintDiagnostic in Cache.GetForLine(pFileName, pLine0) do
    if (D.Code <> '') and SameText(Copy(D.Source, 1, Length('drag-lint')), 'drag-lint') then Exit(D.Code);
end;

{ The active project's .dproj; '' when none (the engine then walks up from the file). }
function ActiveProjectFile: string;
begin
  var P: IOTAProject:= GetActiveProject;
  Result:= if P <> nil then P.FileName else '';
end;

{ One command link on the task dialog. }
procedure AddLink(pDialog: TTaskDialog; const pCaption, pHint: string; pId: Integer);
begin
  var B: TTaskDialogButtonItem:= TTaskDialogButtonItem(pDialog.Buttons.Add);
  B.Caption:= pCaption;
  B.CommandLinkHint:= pHint;
  B.ModalResult:= pId;
end;

{ Asks for the scope with three command links; '' when cancelled. }
function AskScope(const pRule: string; pLine1: Integer; const pFileName: string): string;
begin
  Result:= '';
  var TD: TTaskDialog:= TTaskDialog.Create(nil);
  try
    TD.Caption:= 'drag-lint: Disable Rule';
    TD.Title:= Format('Disable %s', [pRule]);
    TD.Text:= Format('Finding on line %d of %s. Where should the rule stay silent?', [pLine1, ExtractFileName(pFileName)]);
    TD.Flags:= [tfUseCommandLinks, tfAllowDialogCancellation];
    TD.CommonButtons:= [tcbCancel];
    AddLink(TD, 'Disable here (this line)', 'Writes a dl:ok marker with your reason on this line.', ID_LINE);
    AddLink(TD, 'Disable in this unit',
      'Adds this unit to the rule''s exclude_units in the project lint config. The source is not changed.', ID_UNIT);
    AddLink(TD, 'Disable in this project',
      'Turns the rule off in the project lint config (the file the Lint Options dock saves).', ID_PROJECT);
    if not TD.Execute then Exit;
    case TD.ModalResult of
      ID_LINE   : Result:= 'line';
      ID_UNIT   : Result:= 'unit';
      ID_PROJECT: Result:= 'project';
    end;
  finally
    TD.Free;
  end;
end;

{ The engine command; a '"' in the reason becomes '''' so the quoted argument stays one argument. }
function DisableCommandLine(const pExe, pRule, pScope, pFileName: string; pLine1: Integer;
  const pReason, pProject: string): string;
begin
  Result:= Format('"%s" rules disable --rule "%s" --scope %s --in "%s" --line %d --reason "%s"',
    [pExe, pRule, pScope, pFileName, pLine1, StringReplace(pReason, '"', '''', [rfReplaceAll])]);
  if pProject <> '' then Result:= Result + Format(' --project "%s"', [pProject]);
end;

procedure InvokeDisableRule(Sender: TObject);
var
  FileName, Rule, Scope, Reason, Exe, Problem: string;
  Line0: Integer;
begin
  Problem:= '';
  Rule:= '';
  Exe:= EngineExeOrEmpty;
  if not CaretPosition(FileName, Line0) then Problem:= 'put the caret on the finding''s line in an editor first.'
  else
  begin
    Rule:= RuleAtLine(FileName, Line0);
    if Rule = '' then Problem:= Format('no drag-lint finding on line %d.', [Line0 + 1])
    else if Exe = '' then Problem:= 'no engine found.';
  end;
  if Problem <> '' then
  begin
    ShowMessage('drag-lint: ' + Problem);
    Exit;
  end;
  Scope:= AskScope(Rule, Line0 + 1, FileName);
  if Scope = '' then Exit;
  Reason:= '';
  if not InputQuery('drag-lint: Disable ' + Rule, 'One-line reason (stored with the entry and today''s date):', Reason) then Exit;
  if Trim(Reason) = '' then
  begin
    ShowMessage('drag-lint: a reason is required; nothing was changed.');
    Exit;
  end;
  if Scope = 'line' then
  begin
    var MS: IOTAModuleServices;
    if Supports(BorlandIDEServices, IOTAModuleServices, MS) then MS.SaveAll; { the engine edits the file on disk }
  end;
  var Cmd: string:= DisableCommandLine(Exe, Rule, Scope, FileName, Line0 + 1, Trim(Reason), ActiveProjectFile);
  { Off the main thread: the engine may take a second. The dialog runs back on the main thread
    (Synchronize, not Queue: nothing stays queued if the package unloads). }
  TThread.CreateAnonymousThread(
    procedure
    var
      Output: string;
    begin
      Output:= '';
      try
        RunCaptureStdout(Cmd, Output, RUN_TIMEOUT_MS);
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
  Command.OwnerLane:= 'DISRULE';
  Command.ParentPath:= 'Code Quality';
  Command.AfterCaption:= 'Allow a Finding on This Line...';
  Command.Caption:= 'Disable Rule...';
  Command.Visible:= True;
  Command.Click:= InvokeDisableRule;
  Command.Surfaces:= [csMainMenu, csEditorContext];
  Command.Needs:= cnFinding;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.
