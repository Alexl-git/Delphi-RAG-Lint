unit DragLint.Plugin.Cmd.CheckInit;

{ 1.52 command stub, owned by lane HBIDE: check-init --at <file>:<line>:<col> --json: verdict, writer list and witness hops as Messages lines (ruling HB1).

  Registered HIDDEN in the 1.52 command table (DragLint.Plugin.Cmd152) by the
  initialization section below. The owning lane implements InvokeCheckInit and
  sets Visible to True in THIS unit; DragLint.Plugin.Editor is not edited. }

interface

implementation

uses
  DragLint.Plugin.Cmd152;

const
  COMMAND_ID = 'check-init';

procedure InvokeCheckInit(Sender: TObject);
begin
  Cmd152NotYetAvailable(COMMAND_ID);
end;

procedure RegisterCommand;
var
  Command: TCmd152Command;
begin
  Command.Id:= COMMAND_ID;
  Command.OwnerLane:= 'HBIDE';
  Command.ParentPath:= 'Analyze';
  Command.AfterCaption:= '';
  Command.Caption:= 'Check Initialization of Identifier at Cursor...';
  Command.Visible:= False;
  Command.Click:= InvokeCheckInit;
  Command.Surfaces:= [csMainMenu, csEditorContext];
  Command.Needs:= cnSymbol;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.