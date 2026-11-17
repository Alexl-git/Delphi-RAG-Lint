unit DragLint.Plugin.Cmd.DisableRule;

{ 1.52 command stub, owned by lane DISRULE: Disable the rule of the finding at the cursor for this line, this unit or this project (ruling B4-3, PLAN D1).

  Registered HIDDEN in the 1.52 command table (DragLint.Plugin.Cmd152) by the
  initialization section below. The owning lane implements InvokeDisableRule and
  sets Visible to True in THIS unit; DragLint.Plugin.Editor is not edited. }

interface

implementation

uses
  DragLint.Plugin.Cmd152;

const
  COMMAND_ID = 'disable-rule';

procedure InvokeDisableRule(Sender: TObject);
begin
  Cmd152NotYetAvailable(COMMAND_ID);
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
  Command.Visible:= False;
  Command.Click:= InvokeDisableRule;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.