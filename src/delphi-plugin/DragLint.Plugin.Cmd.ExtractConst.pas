unit DragLint.Plugin.Cmd.ExtractConst;

{ 1.52 command stub, owned by lane XCONST: Extract the literal at the cursor into a named constant and replace every occurrence in the unit (ruling B4-2, PLAN D6).

  Registered HIDDEN in the 1.52 command table (DragLint.Plugin.Cmd152) by the
  initialization section below. The owning lane implements InvokeExtractConst and
  sets Visible to True in THIS unit; DragLint.Plugin.Editor is not edited. }

interface

implementation

uses
  DragLint.Plugin.Cmd152;

const
  COMMAND_ID = 'extract-constant';

procedure InvokeExtractConst(Sender: TObject);
begin
  Cmd152NotYetAvailable(COMMAND_ID);
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
  Command.Visible:= False;
  Command.Click:= InvokeExtractConst;
  Command.Surfaces:= [csMainMenu, csEditorContext];
  Command.Needs:= cnNothing;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.