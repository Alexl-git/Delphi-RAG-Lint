unit RF2Service;

interface

uses
  Vcl.SvcMgr;

type
  TRf2Worker = class(TService)
    procedure ServiceExecute(Sender: TService);
  end;

implementation

procedure TRf2Worker.ServiceExecute(Sender: TService);
var
  Tmp: Integer;
begin
  try
    Tmp:= 1 div Sender.ThreadCount;
  except
    Tmp:= 0;
  end;
end;

end.
