unit DragLint.Plugin.Cmd.FieldRepo;

{ 1.52 command stub, owned by lane TTIDE: TableTools migration M10-M11: the Field repository submenu that replaces the TableTools Tables menu.

  Registered HIDDEN in the 1.52 command table (DragLint.Plugin.Cmd152) by the
  initialization section below. The owning lane implements InvokeFieldRepo and
  sets Visible to True in THIS unit; DragLint.Plugin.Editor is not edited. }

interface

implementation

uses
  DragLint.Plugin.Cmd152;

const
  COMMAND_ID = 'field-repository';

procedure InvokeFieldRepo(Sender: TObject);
begin
  Cmd152NotYetAvailable(COMMAND_ID);
end;

procedure RegisterCommand;
var
  Command: TCmd152Command;
begin
  Command.Id:= COMMAND_ID;
  Command.OwnerLane:= 'TTIDE';
  Command.ParentPath:= 'Field Repository';
  Command.AfterCaption:= '';
  Command.Caption:= 'Open Field Repository Editor...';
  Command.Visible:= False;
  Command.Click:= InvokeFieldRepo;
  Command.Surfaces:= [csMainMenu];
  Command.Needs:= cnNothing;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.