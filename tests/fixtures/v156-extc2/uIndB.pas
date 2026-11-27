unit uIndB;

{ 1.56 EXT-C2 fixture: an EVENT bound through a property from another unit, and a routine passed
  as a CALLBACK ARGUMENT. Pinned by tests\autotest\run_v156_EXTC2_indirect.ps1 -- append only. }

interface

uses
  uIndA;

type
  TListener = class
  private
    FEmitter: TEmitter;
    procedure HandleEvt(Sender: TObject);
    procedure NotAHandler(Sender: TObject);
  public
    procedure Wire;
    procedure Unwire;
  end;

procedure RunCb(ACb: TPlainProc);
procedure RunNoCall(ACb: TPlainProc);
procedure UseCb;

implementation

procedure RunCb(ACb: TPlainProc);
begin
  ACb(2);
end;

procedure RunNoCall(ACb: TPlainProc);
begin
  GHook:= ACb;
end;

procedure UseCb;
begin
  RunCb(PlainOther);
  RunCb(@PlainTarget);
end;

procedure TListener.HandleEvt(Sender: TObject);
begin
end;

procedure TListener.NotAHandler(Sender: TObject);
begin
end;

procedure TListener.Wire;
begin
  FEmitter.OnChange:= HandleEvt;
end;

procedure TListener.Unwire;
begin
  FEmitter.OnChange:= nil;
end;

end.
