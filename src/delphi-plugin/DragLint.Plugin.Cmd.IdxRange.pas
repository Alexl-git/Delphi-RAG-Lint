unit DragLint.Plugin.Cmd.IdxRange;

{ 1.52 command stub, owned by lane IDXRANGE2: index-possibly-out-of-range: verify all callers (dl:ok-range, PLAN D2) and insert a range check (rulings C1-C3).

  Registered HIDDEN in the 1.52 command table (DragLint.Plugin.Cmd152) by the
  initialization section below. The owning lane implements InvokeIdxRange and
  sets Visible to True in THIS unit; DragLint.Plugin.Editor is not edited. }

interface

implementation

uses
  DragLint.Plugin.Cmd152;

const
  COMMAND_ID = 'idx-range';

procedure InvokeIdxRange(Sender: TObject);
begin
  Cmd152NotYetAvailable(COMMAND_ID);
end;

procedure RegisterCommand;
var
  Command: TCmd152Command;
begin
  Command.Id:= COMMAND_ID;
  Command.OwnerLane:= 'IDXRANGE2';
  Command.ParentPath:= 'Code Quality';
  Command.AfterCaption:= '';
  Command.Caption:= 'Verify All Callers Pass an In-Range Index...';
  Command.Visible:= False;
  Command.Click:= InvokeIdxRange;
  RegisterCmd152(Command);
end;

initialization
  RegisterCommand;

end.