unit DragLint.Plugin.Cmd.FixMarker;

{ 1.52 command stub, owned by lane VSFIX: RAD Studio parity of the LSP "Fix with drag-lint" code action: apply the autofix of the finding at the cursor.

  Registered HIDDEN in the 1.52 command table (DragLint.Plugin.Cmd152) by the
  initialization section below. The owning lane implements InvokeFixMarker and
  sets Visible to True in THIS unit; DragLint.Plugin.Editor is not edited. }

interface

implementation

uses
  DragLint.Plugin.Cmd152;

const
  COMMAND_ID = 'fix-marker';

procedure InvokeFixMarker(Sender: TObject);
begin
  Cmd152NotYetAvailable(COMMAND_ID);
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
  Command.Visible:= False;
  Command.Click:= InvokeFixMarker;
  Command.Surfaces:= [csMainMenu, csEditorContext];
  Command.Needs:= cnFinding;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.