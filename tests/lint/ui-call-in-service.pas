unit UiCallService;

interface

uses
  Vcl.SvcMgr, Vcl.Dialogs;

type
  TWorker = class(TService)
    procedure ServiceExecute(Sender: TService);
  end;

  TOtherThing = class(TObject)
    procedure Ask;
  end;

implementation

procedure TWorker.ServiceExecute(Sender: TService);
begin
  ShowMessage('connection lost');
end;

procedure TOtherThing.Ask;
begin
  ShowMessage('fine here');
end;

end.
