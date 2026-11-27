unit ChbSender;

interface

procedure SendBoth;

implementation

uses
  ChbCmds, uPipeChb;

procedure SendBoth;
begin
  SendPipe(cmdOne);
  SendPipe(cmdTwo);
end;

end.
