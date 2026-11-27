unit uPipeChb;

interface

uses
  ChbCmds;

procedure SendPipe(pCmd: TChbCmd);

implementation

procedure SendPipe(pCmd: TChbCmd);
begin
  if pCmd = cmdThree then
    Exit;
end;

end.
