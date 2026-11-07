unit uLhUse;

interface

uses
  uLhBase;

type
  TWorker = class(TBaseWorker)
  public
    procedure Execute; override;
  end;

  TUser = class(TLogThread)
  public
    procedure Execute; override;
  end;

procedure UseNet;
procedure UseLocks(T: TThread);

implementation

procedure DoWork;
begin
end;

procedure TWorker.Execute; // TRIGGER-LH-THREAD
begin
  DoWork;
end;

procedure TUser.Execute; // CONTROL-LH-THREAD
begin
  DoWork;
end;

procedure UseNet;
var
  H: TMyHttp;
  K: TMyHttp;
begin
  H := TMyHttp.Create(nil); // TRIGGER-LH-NET
  K := TMyHttp.Create(nil); // CONTROL-LH-NET
  K.ReadTimeout := 5000;
end;

procedure UseLocks(T: TThread);
var
  CS : TCriticalSection;
  Sem: TSemaphore;
begin
  CS.Enter;
  T.WaitFor; // TRIGGER-LH-LOCK
  CS.Leave;
  Sem.Acquire;
  T.WaitFor; // CONTROL-LH-LOCK
  Sem.Release;
end;

end.
