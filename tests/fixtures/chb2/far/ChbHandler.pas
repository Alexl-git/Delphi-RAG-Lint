unit ChbHandler;

interface

uses
  ChbCmds;

procedure Handle(pCmd: TChbCmd);

implementation

procedure Handle(pCmd: TChbCmd);
begin
  case pCmd of
    cmdOne: Writeln('one');
  end;
end;

end.
